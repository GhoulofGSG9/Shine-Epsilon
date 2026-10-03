local Plugin = ...

local VoteMenu = Shine.VoteMenu

local Abs = math.abs
local Exp = math.exp
local Max = math.max
local Min = math.min
local Sqrt = math.sqrt

Plugin.SeedPrefType = table.AsEnum{
    "ASK", "ALWAYS", "NEVER"
}

Plugin.HasConfig = true
Plugin.ConfigName = "ReadyRoomQueue.json"
Plugin.DefaultConfig = {
    SeedPref = Plugin.SeedPrefType.ASK,
    SeedPrefAsked = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
    local Validator = Shine.Validator()
    Validator:AddFieldRule( "SeedPref", Validator.InEnum( Plugin.SeedPrefType, Plugin.DefaultConfig.SeedPref ) )
    Plugin.ConfigValidator = Validator
end

Plugin.SeedRescoreInterval = 60
Plugin.MaxSeedCandidates = 10

--[[
    Ranks a seed candidate. The formula is GMSBEntry.lua's UpdateServerRanking
    (ns2/lua/menu2/NavBar/Screens/ServerBrowser/GMSBEntry.lua), so a seed target ranks the way the server
    browser would rank it. With Seed set, the factors that judge the server's current population are
    neutral, because the whole group arrives together, and passworded, blocked or too distant servers score 0.
]]
function Plugin.ScoreCandidate( In )
    if In.Seed and ( In.Passworded or In.Blocked or In.Ping > In.MaxPing ) then
        return 0
    end

    local Players = In.Players
    local MaxPlayer = In.MaxPlayers - In.Reserved

    local Viability = 1 / ( 1 + Exp( -0.5 * ( Players - 12 ) ) )
    local DViability = ( 201.714 * Exp( 0.5 * Players ) ) / ( 403.429 + Exp( 0.5 * Players ) ) ^ 2
    local Player = 0.5 * Viability + 0.5 * DViability * Max( 0, Min( MaxPlayer, 24 ) - Players - 1 )

    local Ping = 1 / ( 1 + Exp( 1 / 40 * ( In.Ping - 150 ) ) )

    local PerfScore = In.PerfScore * In.PerfQuality / 100
    local Perf = 1 / ( 1 + Exp( -PerfScore / 5 ) )

    local Fav = In.Favorite and 2 or 1
    local Ranked = In.Mode == "ns2" and In.Ranked and 1.5 or 1
    local History = In.Historical and In.Now - In.LastConnect <= 600 and 0.5 or 1
    local Arcade = In.Mode == "ns2" and 1 or 0.6

    local Skill, Empty, Blocked, Full, Joinable, Friend, RookieOnly = 1, 1, 1, 1, 1, 1, 1

    if not In.Seed then
        Skill = ( Players < 2 or In.PlayerSkill == -1 ) and 1
            or Exp( -0.1 * Abs( In.ServerSkill - In.PlayerSkill ) * Sqrt( Players - 1 ) / 346.41 )
        Empty = Players > 0 and 1 or 0.5
        Blocked = In.Blocked and 0.000001 or 1
        Full = Players >= MaxPlayer and not In.Favorite and 0.5 or 1
        Joinable = ( not In.Passworded or In.Favorite or In.Friends ) and 1 or 0.02
        Friend = In.Friends and 1.2 or 1

        RookieOnly = Joinable == 1 and 0.3 or 1
        if In.RookieOnly then
            if In.PlayerLevel == -1 or In.PlayerLevel < kRookieLevel or In.PlayerTier <= kRookieMaxSkillTier then
                RookieOnly = 1 + ( 1 / Exp( 0.125 * ( In.PlayerLevel - kRookieOnlyLevel ) ) )
            end
        elseif In.PlayerLevel == -1 or In.PlayerLevel > kRookieOnlyLevel then
            RookieOnly = 1
        end
    end

    return Player * Ping * Perf * Skill * Full * Joinable * Empty * Fav * Blocked * Friend * RookieOnly
        * Ranked * History * Arcade
end

-- The server browser's own files: older versions stored a list of entries, newer ones an address set.
local function LoadAddressSet( FileName )
    local Loaded = LoadConfigFile( FileName ) or {}
    if #Loaded == 0 then return Loaded end

    local Set = {}
    for i = 1, #Loaded do
        if Loaded[ i ].address then
            Set[ Loaded[ i ].address ] = true
        end
    end

    return Set
end

local function LoadHistory()
    local History = {}
    local Loaded = LoadConfigFile( "HistoryServers.json" ) or {}

    for i = 1, #Loaded do
        local Entry = Loaded[ i ]
        if Entry.address and Entry.lastConnect then
            History[ Entry.address ] = Entry
        end
    end

    return History
end

function Plugin:Initialise()
    self:AddClientSetting( "SeedPref", "sh_seedpref", {
        Type = "Radio",
        Options = self.SeedPrefType,
        Description = "SEED_PREF_DESCRIPTION",
        CommandMessage = "Seed queue preference set to: %s",
        OnChange = function( self )
            self:SendSeedPref()
        end
    } )

    return true
end

function Plugin:SendSeedPref()
    if not self.SeedURL then return end

    self:SendNetworkMessage( "SeedPref", { Pref = self.Config.SeedPref:lower() }, true )
end

function Plugin:ReceiveSeedActive( Data )
    if Data.URL == "" then
        self.SeedURL = nil
        self:DestroyTimer( "SeedRescore" )
        self:CloseSeedOffer()
        return
    end

    self.SeedURL = Data.URL
    self.SeedVersion = nil
    self:SendSeedPref()

    if not self.Config.SeedPrefAsked then
        self.Config.SeedPrefAsked = true
        self:SaveConfig( true )
        self:Notify( self:GetPhrase( "SEED_PREF_ASK" ) )
    end

    self:RefreshSeedCandidates()
    self:CreateTimer( "SeedRescore", self.SeedRescoreInterval, -1, function()
        self:RefreshSeedCandidates()
    end )
end

function Plugin:RefreshSeedCandidates()
    local URL = self.SeedURL
    if not URL then return end

    Shared.SendHTTPRequest( URL.."/seedqueue/candidates", "GET", {}, function( Body )
        if self.SeedURL ~= URL or type( Body ) ~= "string" then return end

        local Ok, Data = pcall( json.decode, Body )
        if not Ok or type( Data ) ~= "table" or type( Data.candidates ) ~= "table" then return end

        if Data.version ~= nil and Data.version == self.SeedVersion then return end
        self.SeedVersion = Data.version

        self:ScoreSeedCandidates( Data )
    end )
end

function Plugin:ScoreSeedCandidates( Data )
    if not Client.RefreshServer then return end

    local URL = self.SeedURL
    local Favorites = LoadAddressSet( "FavoriteServers.json" )
    local Blocked = LoadAddressSet( "BlockedServers.json" )
    local History = LoadHistory()
    local GroupSize = tonumber( Data.groupSize ) or 12
    local MaxPing = tonumber( Data.maxPing ) or 150

    self.SeedPings = {}

    for i = 1, Min( #Data.candidates, self.MaxSeedCandidates ) do
        local Candidate = Data.candidates[ i ]
        local Address = type( Candidate ) == "table" and Candidate.address

        if type( Address ) == "string" then
            -- Always send a score, so one sent before the candidate became unusable gets replaced.
            if Blocked[ Address ] then
                self:SendNetworkMessage( "SeedScore", { Address = Address, Score = 0 }, true )
            else
                Client.RefreshServer( Address, function( Info )
                    if self.SeedURL ~= URL or type( Info ) ~= "table" then return end

                    self.SeedPings[ Address ] = Info.ping

                    local HistoryEntry = History[ Address ]
                    local Score = self.ScoreCandidate{
                        Seed = true,
                        Players = GroupSize,
                        MaxPlayers = tonumber( Candidate.maxPlayers ) or Info.maxPlayers or 0,
                        Reserved = tonumber( Candidate.reserved ) or Info.numReservedSlots or 0,
                        Ping = tonumber( Info.ping ) or 999,
                        MaxPing = MaxPing,
                        PerfScore = tonumber( Info.performanceScore ) or 0,
                        PerfQuality = tonumber( Info.performanceQuality ) or 0,
                        Mode = Info.mode,
                        Ranked = Candidate.ranked == true,
                        Passworded = Info.requiresPassword == true,
                        Favorite = Favorites[ Address ] == true,
                        Blocked = false,
                        Historical = HistoryEntry ~= nil,
                        LastConnect = HistoryEntry and tonumber( HistoryEntry.lastConnect ) or 0,
                        Now = Shared.GetSystemTime()
                    }

                    self:SendNetworkMessage( "SeedScore", { Address = Address, Score = Score }, true )
                end )
            end
        end
    end
end

function Plugin:CloseSeedOffer()
    self.SeedOffer = nil
    self:DestroyTimer( "SeedOfferExpire" )
    Shine.ScreenText.Remove( "SeedOffer" )
end

function Plugin:ReceiveSeedOffer( Data )
    self.SeedOffer = Data

    local Ping = self.SeedPings and self.SeedPings[ Data.Address ]
    local Text = self:GetInterpolatedPhrase( "SEED_OFFER", {
        Count = Data.Count,
        Name = Data.Name,
        Ping = Ping or "?"
    } )

    -- ScreenText formats the remaining time into the text.
    Shine.ScreenText.Add( "SeedOffer", {
        X = 0.5, Y = 0.3,
        Text = Text:gsub( "%%", "%%%%" ).." %s",
        Duration = Data.Time,
        R = 255, G = 160, B = 0,
        Alignment = 1,
        Size = 2,
        FadeIn = 0.5
    } )

    self:CreateTimer( "SeedOfferExpire", Data.Time + 15, 1, function()
        self:CloseSeedOffer()
    end )

    if not VoteMenu.Visible then
        Shine.OpenVoteMenu()
    end
    VoteMenu:SetPage( "SeedOffer" )

    Client.WindowNeedsAttention()
end

function Plugin:AnswerSeedOffer( Accept )
    if not self.SeedOffer or self.SeedOffer.Answered then return end

    self.SeedOffer.Answered = true
    Shine.ScreenText.Remove( "SeedOffer" )

    self:SendNetworkMessage( "SeedAnswer", { Accept = Accept }, true )
    self:Notify( self:GetPhrase( Accept and "SEED_ACCEPTED" or "SEED_DECLINED" ) )
end

function Plugin:ReceiveSeedAbort()
    if not self.SeedOffer then return end

    self:CloseSeedOffer()
    self:Notify( self:GetPhrase( "SEED_ABORT" ) )
end

function Plugin:Cleanup()
    Shine.ScreenText.Remove( "SeedOffer" )

    return self.BaseClass.Cleanup( self )
end

VoteMenu:AddPage( "SeedOffer", function( self )
    self:AddBottomButton( Plugin:GetPhrase( "BACK" ), function()
        self:SetPage( "Main" )
    end )

    if not Plugin.SeedOffer or Plugin.SeedOffer.Answered then return end

    self:AddSideButton( Plugin:GetPhrase( "SEED_YES" ), function()
        Plugin:AnswerSeedOffer( true )
        return true
    end )
    self:AddSideButton( Plugin:GetPhrase( "SEED_NO" ), function()
        Plugin:AnswerSeedOffer( false )
        return true
    end )
end )

VoteMenu:AddPage( "SeedPref", function( self )
    self:AddBottomButton( Plugin:GetPhrase( "BACK" ), function()
        self:SetPage( "Main" )
    end )

    for i = 1, #Plugin.SeedPrefType do
        local Pref = Plugin.SeedPrefType[ i ]
        self:AddSideButton( Plugin:GetPhrase( Pref ), function()
            Shared.ConsoleCommand( "sh_seedpref "..Pref )
            return true
        end )
    end
end )

VoteMenu:EditPage( "Main", function( self )
    if not Plugin.Enabled or not Plugin.SeedURL then return end

    if Plugin.SeedOffer and not Plugin.SeedOffer.Answered then
        self:AddBottomButton( Plugin:GetPhrase( "SEED_OFFER_BUTTON" ), function()
            self:SetPage( "SeedOffer" )
        end )
    end

    self:AddBottomButton( Plugin:GetPhrase( "SEED_PREF_BUTTON" ), function()
        self:SetPage( "SeedPref" )
    end )
end )

function Plugin:ReceiveQueueLeft()
    self:Notify( self:GetPhrase( "QUEUE_LEAVE" ) )

    Client.WindowNeedsAttention()
end
