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

function Plugin:ScheduleSeedUpdate( Delay )
    self:CreateTimer( "SeedUpdate", Delay, 1, function()
        self:SeedUpdate()
    end )
end

--[[
    Sends the heartbeat. The coordinator knows this server by the request's source address and the port in the
    body, it only answers servers that Steam's server list shows at that address.
]]
function Plugin:SeedUpdate()
    -- Also the timeout callback, which gets no arguments.
    local function OnReply( Body, _, _, Status )
        if not self.Enabled then return end

        local Data
        if type( Body ) == "string" and Body ~= "" then
            local Ok, Decoded = pcall( json.decode, Body )
            Data = Ok and type( Decoded ) == "table" and Decoded or nil
        end

        -- Only ns2-engine builds pass the HTTP status, the retail engine passes the body alone.
        Status = tonumber( Status )

        if Data and ( Status == 200 or not Status and tonumber( Data.next ) ) then
            self.SeedOnline = true
            self:ScheduleSeedUpdate( Min( Max( tonumber( Data.next ) or IDLE_DELAY, 1 ), 60 ) )
            self:HandleSeedReply( Data )
            return
        end

        self:DebugPrint( "Seed queue heartbeat failed with HTTP %s.", tostring( Status ) )

        -- 403 or a detail body: this address is not a listed NS2 server (yet), or it is rate limited.
        local Refused
        if Status then
            Refused = Status == 403 or Status == 429
        else
            Refused = Data ~= nil and type( Data.detail ) == "string"
        end

        self:ScheduleSeedUpdate( Refused and FORBIDDEN_DELAY or ERROR_DELAY )
    end

    Shine.TimedHTTPRequest( self.SeedURL.."/seedqueue/heartbeat", "POST",
        { data = json.encode( self:BuildSeedHeartbeat() ) }, OnReply, OnReply, REQUEST_TIMEOUT )
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
        port = Server.GetPort(),
        players = NumPlayers,
        maxPlayers = MaxPlayers,
        reserved = NumReserved,
        matching = Config.MatchingTarget,
        queue = Queue
    }
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

    -- The coordinator takes heartbeats for this server from anything behind its IP, so a commit alone never
    -- moves a player who did not agree here.
    local Players = GetPlayerList( Commit )
    for i = 1, #Players do
        local SteamID = Players[ i ]
        local Answer = self.SeedAnswers[ SteamID ]
        local Agreed = self.SeedPrefs[ SteamID ] == "always"
            or ( Answer ~= nil and Answer.offer == ID and Answer.accept )

        if Agreed and not Decision.Dispatched[ SteamID ] then
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
