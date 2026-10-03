--[[
    Global seed queue: reports the queue to the seed coordinator and sends players that accepted a seed
    offer to its target. The coordinator contract is ns2-economy api/docs/dev/SEED_QUEUE.md.
]]

local Plugin = ...

local Floor = math.floor
local Max = math.max
local Min = math.min
local StringFormat = string.format
local StringUTF8Sub = string.UTF8Sub
local TableCount = table.Count

local Prefs = { ask = true, always = true, never = true }

local REQUEST_TIMEOUT = 15
local IDLE_DELAY = 10
local ERROR_DELAY = 30
local FORBIDDEN_DELAY = 120
local ENROL_DELAY = 60
local CHALLENGE_PREFIX = "td_chal="
local CHALLENGE_LIFETIME = 170
local MIN_FIRST_POLL = 15
local COMPLETE_DELAYS = { 10, 15, 20, 20 }
local TOKEN_REFRESH_LEEWAY = 120
-- The coordinator repeats a decision for 60 s.
local DECISION_MEMORY = 120
local MAX_SCORES = 16
local MAX_QUEUE = 128
local MAX_NAME = 100

function Plugin:InitialiseGlobalQueue()
    local Config = self.Config.GlobalQueue
    if not Config.Enabled then return end

    self.SeedEnabled = true
    self.SeedURL = Config.URL:gsub( "/+$", "" )

    self.SeedPrefs = {}
    self.SeedScores = {}
    self.SeedAnswers = {}
    -- SteamID -> id of the offer they were shown.
    self.SeedOffered = {}
    -- Offer id -> { At, Dispatched = { [ SteamID ] = true } } for every commit or abort handled.
    self.SeedDecided = {}
    -- SteamID -> time until which a disconnect keeps their queue entry, armed when they are sent away.
    self.HopReturns = {}
    self.SeedActiveClients = {}

    self:ScheduleSeedUpdate( 1 )
end

function Plugin:DisableGlobalQueue()
    self.SeedEnabled = false
    self.SeedOnline = false

    for Client in pairs( self.SeedActiveClients ) do
        self:SendNetworkMessage( Client, "SeedActive", { URL = "" }, true )
    end
    self.SeedActiveClients = {}
end

function Plugin:ScheduleSeedUpdate( Delay )
    self:CreateTimer( "SeedUpdate", Delay, 1, function()
        self:SeedUpdate()
    end )
end

--[[
    Sends a form POST to the coordinator. Callback receives the decoded JSON body (or nil) and the HTTP status.
]]
function Plugin:SeedRequest( Path, Payload, Headers, Callback )
    local function OnReply( Body, _, _, Status )
        if not self.SeedEnabled then return end

        local Data
        if type( Body ) == "string" and Body ~= "" then
            local Ok, Decoded = pcall( json.decode, Body )
            Data = Ok and Decoded or nil
        end

        Callback( Data, tonumber( Status ) or 0 )
    end

    local Ok, RequestID = pcall( Shared.SendHTTPRequest, self.SeedURL..Path, "POST",
        { data = json.encode( Payload ) }, OnReply, { timeout = REQUEST_TIMEOUT, headers = Headers } )

    if not Ok then
        self:Print( "Disabling the global seed queue, this server cannot send HTTP headers: %s", true,
            tostring( RequestID ) )
        self:DisableGlobalQueue()
        return
    end

    -- Refused because the engine's request queue is full, the callback will never run.
    if RequestID == nil then
        self:ScheduleSeedUpdate( ERROR_DELAY )
    end
end

function Plugin:SeedUpdate()
    if not self.SeedEnabled then return end

    if self.SeedChallenge then
        self:CompleteSeedEnrolment()
        return
    end

    local Config = self.Config.GlobalQueue
    local Now = Shared.GetSystemTime()

    local CanRefresh = Config.RefreshToken ~= ""
        and not ( Config.RefreshTokenExpiresAt > 0 and Config.RefreshTokenExpiresAt <= Now )

    if Config.ServerId == "" or ( Config.Token == "" and not CanRefresh ) then
        self:StartSeedEnrolment()
        return
    end

    if CanRefresh and ( Config.Token == ""
    or ( Config.TokenExpiresAt > 0 and Config.TokenExpiresAt - TOKEN_REFRESH_LEEWAY <= Now ) ) then
        self:RefreshSeedToken()
        return
    end

    self:SendSeedHeartbeat()
end

function Plugin:StoreSeedAuth( Data )
    if type( Data ) ~= "table" or type( Data.serverId ) ~= "string" or Data.serverId == ""
    or type( Data.accessToken ) ~= "string" or Data.accessToken == ""
    or type( Data.refreshToken ) ~= "string" or Data.refreshToken == "" then
        return false
    end

    local Config = self.Config.GlobalQueue
    Config.ServerId = Data.serverId
    Config.Token = Data.accessToken
    Config.TokenExpiresAt = tonumber( Data.accessTokenExpiresAt ) or 0
    Config.RefreshToken = Data.refreshToken
    Config.RefreshTokenExpiresAt = tonumber( Data.refreshTokenExpiresAt ) or 0
    self:SaveConfig( true )

    return true
end

function Plugin:ClearSeedAuth()
    local Config = self.Config.GlobalQueue
    Config.ServerId = ""
    Config.Token = ""
    Config.TokenExpiresAt = 0
    Config.RefreshToken = ""
    Config.RefreshTokenExpiresAt = 0
    self:SaveConfig( true )
end

-- The coordinator proves the enrolling server owns its address by finding this tag in Steam's server list.
function Plugin:SetChallengeTag( Tag )
    local Tags = {}
    Server.GetTags( Tags )

    for i = 1, #Tags do
        if Tags[ i ]:find( CHALLENGE_PREFIX, 1, true ) then
            Server.RemoveTag( Tags[ i ] )
        end
    end

    if Tag then
        Server.AddTag( Tag )
    end
end

function Plugin:StartSeedEnrolment()
    self:SeedRequest( "/servers/enroll/start", {
        gamePort = Server.GetPort(),
        serverName = Server.GetName()
    }, nil, function( Data, Status )
        if Status ~= 200 or type( Data ) ~= "table" or type( Data.challengeId ) ~= "string"
        or type( Data.challengeTag ) ~= "string" then
            if not self.SeedEnrolFailLogged then
                self.SeedEnrolFailLogged = true
                self:Print( "Global seed queue enrolment could not start (HTTP %s: %s), retrying in the background.",
                    true, Status, type( Data ) == "table" and tostring( Data.detail ) or "no reply" )
            end

            self:ScheduleSeedUpdate( Status == 403 and FORBIDDEN_DELAY or ENROL_DELAY )
            return
        end

        self:SetChallengeTag( Data.challengeTag )
        self.SeedChallenge = {
            ID = Data.challengeId,
            Tag = Data.challengeTag,
            Attempts = 0,
            ExpiresAt = Shared.GetTime() + CHALLENGE_LIFETIME
        }

        -- Steam needs a while before the server list shows the new tag.
        self:ScheduleSeedUpdate( Max( tonumber( Data.pollAfterSeconds ) or 0, MIN_FIRST_POLL ) )
    end )
end

function Plugin:AbandonSeedChallenge()
    self.SeedChallenge = nil
    self:SetChallengeTag( nil )
    self:ScheduleSeedUpdate( ENROL_DELAY )
end

function Plugin:CompleteSeedEnrolment()
    local Challenge = self.SeedChallenge
    if Shared.GetTime() > Challenge.ExpiresAt then
        self:AbandonSeedChallenge()
        return
    end

    Challenge.Attempts = Challenge.Attempts + 1

    self:SeedRequest( "/servers/enroll/complete", {
        challengeId = Challenge.ID,
        observedChallengeTag = Challenge.Tag
    }, nil, function( Data, Status )
        if Status == 200 and self:StoreSeedAuth( Data ) then
            self.SeedChallenge = nil
            self:SetChallengeTag( nil )
            self:Print( "Enrolled with the global seed queue as server %s.", true, Data.serverId )
            self:ScheduleSeedUpdate( 1 )
            return
        end

        -- 403 covers the tag not having reached Steam's list yet.
        local Transient = Status == 0 or Status == 403 or Status == 429 or Status >= 500
        local Delay = COMPLETE_DELAYS[ Challenge.Attempts ]
        if Transient and Delay then
            self:ScheduleSeedUpdate( Delay )
            return
        end

        self:DebugPrint( "Seed queue enrolment failed (HTTP %s), starting over.", Status )
        self:AbandonSeedChallenge()
    end )
end

function Plugin:RefreshSeedToken()
    local Config = self.Config.GlobalQueue

    self:SeedRequest( "/servers/token/refresh", {
        serverId = Config.ServerId,
        refreshToken = Config.RefreshToken
    }, nil, function( Data, Status )
        if Status == 200 and self:StoreSeedAuth( Data ) then
            self:ScheduleSeedUpdate( 1 )
            return
        end

        -- Rejected refresh token or an identity the coordinator purged: only a new enrolment helps.
        if Status == 403 or Status == 409 or Status == 422 then
            self:ClearSeedAuth()
        end

        self:ScheduleSeedUpdate( ERROR_DELAY )
    end )
end

function Plugin:IsSeedQueued( SteamID )
    return self.PlayerQueue:Get( SteamID ) ~= nil or self.ReservedQueue:Get( SteamID ) ~= nil
end

function Plugin:BuildSeedHeartbeat()
    local Config = self.Config.GlobalQueue
    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()
    local Now = Shared.GetTime()

    local Queue = {}
    local Seen = {}

    local function AddEntries( Map )
        local Keys = Map:GetKeys()
        for i = 1, #Keys do
            local SteamID = Keys[ i ]
            local Client = not Seen[ SteamID ] and #Queue < MAX_QUEUE and Shine.GetClientByNS2ID( SteamID )

            if Client and Client:GetIsSpectator() then
                Seen[ SteamID ] = true

                local Entry = {
                    id = SteamID,
                    wait = Floor( Now - ( Client.RRQueueJoinTime or Now ) ),
                    pref = self.SeedPrefs[ SteamID ] or "ask",
                    answer = self.SeedAnswers[ SteamID ]
                }

                -- The coordinator stores the queue in a 30000 character table cell, keep it lean.
                local Scores = self.SeedScores[ SteamID ]
                if Scores then
                    for Address, Score in pairs( Scores ) do
                        local Rounded = Floor( Score * 1000 + 0.5 ) / 1000
                        if Rounded > 0 then
                            Entry.scores = Entry.scores or {}
                            Entry.scores[ Address ] = Rounded
                        end
                    end
                end

                Queue[ #Queue + 1 ] = Entry
            end
        end
    end

    AddEntries( self.PlayerQueue )
    AddEntries( self.ReservedQueue )

    return {
        v = 1,
        name = StringUTF8Sub( Server.GetName() or "", 1, MAX_NAME ),
        players = NumPlayers,
        maxPlayers = MaxPlayers,
        reserved = NumReserved,
        matching = Config.MatchingTarget,
        queue = Queue
    }
end

function Plugin:SendSeedHeartbeat()
    local Config = self.Config.GlobalQueue

    self:SeedRequest( "/seedqueue/heartbeat", self:BuildSeedHeartbeat(), {
        [ "X-Server-Id" ] = Config.ServerId,
        [ "X-Server-Token" ] = Config.Token
    }, function( Data, Status )
        if Status == 200 and type( Data ) == "table" then
            self.SeedOnline = true
            self:HandleSeedReply( Data )
            self:ScheduleSeedUpdate( Min( Max( tonumber( Data.next ) or IDLE_DELAY, 1 ), 60 ) )
            return
        end

        if Status == 401 then
            -- Refreshes the token next, or enrols again when there is nothing to refresh with.
            Config.Token = ""
            Config.TokenExpiresAt = 0
            self:ScheduleSeedUpdate( IDLE_DELAY )
            return
        end

        self:DebugPrint( "Seed queue heartbeat failed with HTTP %s.", Status )

        -- 403 means the coordinator has not activated this server (yet).
        self:ScheduleSeedUpdate( ( Status == 403 or Status == 429 ) and FORBIDDEN_DELAY or ERROR_DELAY )
    end )
end

local function GetPlayerList( Decision )
    return type( Decision.players ) == "table" and Decision.players or {}
end

function Plugin:HandleSeedReply( Reply )
    local Now = Shared.GetTime()

    for ID, Decision in pairs( self.SeedDecided ) do
        if Decision.At + DECISION_MEMORY < Now then
            self.SeedDecided[ ID ] = nil
        end
    end

    if type( Reply.commit ) == "table" then
        self:OnSeedCommit( Reply.commit )
    end

    if type( Reply.abort ) == "table" then
        self:OnSeedAbort( Reply.abort )
    end

    if type( Reply.offer ) == "table" then
        self:OnSeedOffer( Reply.offer )
    end
end

function Plugin:OnSeedOffer( Offer )
    local ID = tostring( Offer.id )
    if self.SeedDecided[ ID ] then return end

    local Target = tostring( Offer.target or "" ):sub( 1, 64 )
    if not Target:match( "^[%w%.%-]+:%d+$" ) then return end

    local Players = GetPlayerList( Offer )
    local Message = {
        Name = StringUTF8Sub( tostring( Offer.name or "" ), 1, MAX_NAME ),
        Address = Target,
        Count = Floor( tonumber( Offer.count ) or #Players ),
        Time = Floor( tonumber( Offer.remaining ) or self.Config.GlobalQueue.PromptTime )
    }

    for i = 1, #Players do
        local SteamID = Players[ i ]
        local Client = Shine.GetClientByNS2ID( SteamID )

        if Client and self.SeedOffered[ SteamID ] ~= ID then
            self.SeedOffered[ SteamID ] = ID

            -- Players set to always count as accepted without being asked.
            if self.SeedPrefs[ SteamID ] ~= "always" then
                self:SendNetworkMessage( Client, "SeedOffer", Message, true )
            end
        end
    end
end

function Plugin:CloseSeedOffer( ID, Dispatched )
    for SteamID, OfferID in pairs( self.SeedOffered ) do
        if OfferID == ID then
            self.SeedOffered[ SteamID ] = nil
            self.SeedAnswers[ SteamID ] = nil

            local Client = not Dispatched[ SteamID ] and Shine.GetClientByNS2ID( SteamID )
            if Client then
                self:SendNetworkMessage( Client, "SeedAbort", {}, true )
            end
        end
    end
end

function Plugin:OnSeedCommit( Commit )
    local ID = tostring( Commit.id )
    local Target = tostring( Commit.target or "" )

    -- Ends up in a console command on the client.
    if not Target:match( "^[%w%.%-]+:%d+$" ) then return end

    local Decision = self.SeedDecided[ ID ]
    if not Decision then
        Decision = { At = Shared.GetTime(), Dispatched = {} }
        self.SeedDecided[ ID ] = Decision
    end

    local Players = GetPlayerList( Commit )
    for i = 1, #Players do
        local SteamID = Players[ i ]

        if not Decision.Dispatched[ SteamID ] then
            Decision.Dispatched[ SteamID ] = true

            local Client = Shine.GetClientByNS2ID( SteamID )
            -- Someone that got a player slot here in the meantime stays.
            if Client and Client:GetIsSpectator() and self:IsSeedQueued( SteamID ) then
                self.HopReturns[ SteamID ] = Shared.GetTime() + self.Config.GlobalQueue.HopReturnTime

                Shine.SendNetworkMessage( Client, "Shine_Command", {
                    Command = StringFormat( "connect %s", Target )
                }, true )
            end
        end
    end

    self:CloseSeedOffer( ID, Decision.Dispatched )
end

function Plugin:OnSeedAbort( Abort )
    local ID = tostring( Abort.id )
    if self.SeedDecided[ ID ] then return end

    self.SeedDecided[ ID ] = { At = Shared.GetTime(), Dispatched = {} }
    self:CloseSeedOffer( ID, self.SeedDecided[ ID ].Dispatched )
end

--[[
    Keeps the queue entry of a player that just left for a seed, so they get their place back if the seed
    falls through. Output: true when the entry is being held.
]]
function Plugin:HoldHopReturn( SteamID )
    local Expiry = self.HopReturns and self.HopReturns[ SteamID ]
    if not Expiry then return false end

    self.HopReturns[ SteamID ] = nil

    if Expiry < Shared.GetTime() or not self:IsSeedQueued( SteamID ) then return false end

    self.HistoricPlayers:Add( SteamID )

    self:SimpleTimer( self.Config.GlobalQueue.HopReturnTime, function()
        if not self.HistoricPlayers:Contains( SteamID ) or Shine.GetClientByNS2ID( SteamID ) then return end

        self.HistoricPlayers:Remove( SteamID )
        self:RemoveFromQueues( SteamID )
        self:UpdateAllQueuePositions()
    end )

    return true
end

function Plugin:ForgetSeedClient( Client, SteamID )
    if not self.SeedEnabled then return end

    self.SeedActiveClients[ Client ] = nil

    if SteamID then
        self.SeedPrefs[ SteamID ] = nil
        self.SeedScores[ SteamID ] = nil
        self.SeedAnswers[ SteamID ] = nil
        self.SeedOffered[ SteamID ] = nil
    end
end

-- Tells clients when to start or stop scoring candidates, run from the plugin tick.
function Plugin:SyncSeedActive()
    if not self.SeedOnline then return end

    local Active = self.SeedActiveClients

    for Client in pairs( Active ) do
        if not ( Client:GetIsSpectator() and self:IsSeedQueued( Client:GetUserId() ) ) then
            Active[ Client ] = nil
            self:SendNetworkMessage( Client, "SeedActive", { URL = "" }, true )
        end
    end

    local function Activate( Map )
        local Keys = Map:GetKeys()
        for i = 1, #Keys do
            local Client = Shine.GetClientByNS2ID( Keys[ i ] )
            if Client and not Active[ Client ] and Client:GetIsSpectator() then
                Active[ Client ] = true
                self:SendNetworkMessage( Client, "SeedActive", { URL = self.SeedURL }, true )
            end
        end
    end

    Activate( self.PlayerQueue )
    Activate( self.ReservedQueue )
end

function Plugin:SetSeedAnswer( Client, Accept )
    local SteamID = Client:GetUserId()
    local OfferID = self.SeedOffered[ SteamID ]
    if not OfferID then return false end

    self.SeedAnswers[ SteamID ] = { offer = OfferID, accept = Accept == true }

    return true
end

function Plugin:ReceiveSeedAnswer( Client, Data )
    if not self.SeedEnabled then return end

    self:SetSeedAnswer( Client, Data.Accept )
end

function Plugin:ReceiveSeedPref( Client, Data )
    if not self.SeedEnabled or not Prefs[ Data.Pref ] then return end

    self.SeedPrefs[ Client:GetUserId() ] = Data.Pref
end

function Plugin:ReceiveSeedScore( Client, Data )
    if not self.SeedEnabled then return end

    local Score = tonumber( Data.Score )
    if not Score or Score ~= Score or Score < 0 or Score == math.huge then return end
    if not Data.Address:match( "^[%w%.%-]+:%d+$" ) then return end

    local SteamID = Client:GetUserId()
    local Scores = self.SeedScores[ SteamID ]
    if not Scores then
        Scores = {}
        self.SeedScores[ SteamID ] = Scores
    end

    if not Scores[ Data.Address ] and TableCount( Scores ) >= MAX_SCORES then return end

    Scores[ Data.Address ] = Score
end

function Plugin:CreateSeedCommands()
    if not self.SeedEnabled then return end

    local function Answer( Client, Value )
        if not Client then return end

        Value = Value:lower()
        if Value ~= "yes" and Value ~= "no" then
            self:NotifyTranslatedError( Client, "SEED_ANSWER_USAGE" )
            return
        end

        if not self:SetSeedAnswer( Client, Value == "yes" ) then
            self:NotifyTranslatedError( Client, "SEED_NO_OFFER" )
        end
    end
    local AnswerCommand = self:BindCommand( "sh_rr_seed", "seed", Answer, true )
    AnswerCommand:AddParam{ Type = "string", Optional = true, Default = "" }
    AnswerCommand:Help( "Answers the current seed offer with yes or no" )

    -- The preference lives in the client's config, so hand it to the client's own setting command.
    local function SetPref( Client, Value )
        if not Client then return end

        Value = Value:lower()
        if not Prefs[ Value ] then
            self:NotifyTranslatedError( Client, "SEED_PREF_USAGE" )
            return
        end

        self.SeedPrefs[ Client:GetUserId() ] = Value
        Shine.SendNetworkMessage( Client, "Shine_Command", { Command = "sh_seedpref "..Value:upper() }, true )
    end
    local PrefCommand = self:BindCommand( "sh_rr_seedpref", "seedpref", SetPref, true )
    PrefCommand:AddParam{ Type = "string", Optional = true, Default = "" }
    PrefCommand:Help( "Sets whether you get asked (ask), always join (always) or never join (never) seeds" )
end
