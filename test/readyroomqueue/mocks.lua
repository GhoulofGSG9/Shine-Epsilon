--[[
    Mock world for the readyroomqueue plugin tests.

    The Gamerules mock is a transcription of the real server side code so the tests fail for the same
    reasons a live server would:
      * Gamerules:GetCanJoinPlayingTeam - C:/Git/ns2/ns2/lua/Gamerules.lua:136
      * NS2Gamerules:GetCanJoinTeamNumber - C:/Git/ns2/ns2/lua/NS2Gamerules.lua:1388
      * NS2Gamerules:JoinTeam - C:/Git/ns2/ns2/lua/NS2Gamerules.lua:1455
      * Player:SetIsSpectator - C:/Git/ns2/ns2/lua/Player_Server.lua:41
      * ServerGame::SetIsSpectator - C:/Git/ns2-engine/Source/Spark_Server/ServerGame.cpp:1066
      * Shine JoinTeam class hook - C:/Git/Shine/lua/shine/core/shared/hook.lua:1089
]]

local Mocks = {}

local SHINE_LIB = "C:/Git/Shine/lua/shine/"
-- Overridable so the suite can be pointed at an older revision of the plugin to check that these
-- tests actually catch the bugs they are meant to cover.
local PLUGIN_FILE = os.getenv( "RRQUEUE_PLUGIN_FILE" ) or "lua/shine/extensions/readyroomqueue/server.lua"
local PLUGIN_DIR = PLUGIN_FILE:match( "^(.*[/\\])" ) or ""
local NS2_JSON = "C:/Git/ns2/core/lua/dkjson.lua"

Mocks.PluginDir = PLUGIN_DIR

-- Set by the suite to rerun scenarios with the global seed queue on and its coordinator unreachable.
Mocks.CoordinatorDown = false

-- NS2 globals the plugin and the mocks rely on.
kTeamReadyRoom = 0
kTeam1Index = 1
kTeam2Index = 2
kSpectatorIndex = 3
kRookieMaxSkillTier = 3

function math.round( Value, DecimalPlaces )
    local Mult = 10 ^ ( DecimalPlaces or 0 )
    return math.floor( Value * Mult + 0.5 ) / Mult
end

--[[
    Loads the real Shine Map and Set implementations. The plugin reaches into Map internals
    ( NumMembers, MemberLookup, Keys ) so a hand written stub would hide bugs.
]]
local function LoadShineObjects()
    if Shine and Shine.Map and Shine.Set then return end

    Shine = Shine or {}
    Shared = Shared or { GetTime = function() return 0 end, GetSystemTime = function() return 0 end,
        Message = print }
    Server = Server or { GetMaxPlayers = function() return 24 end,
        GetMaxSpectators = function() return 4 end }

    package.path = "C:/Git/Shine/lua/?.lua;" .. package.path

    json = json or assert( loadfile( NS2_JSON ) )()

    local Files = {
        "lib/debug.lua", "lib/table.lua", "lib/math.lua", "lib/string.lua", "lib/class.lua",
        "lib/objects.lua", "lib/objects/stream.lua", "lib/objects/map.lua", "lib/objects/set.lua",
        "lib/objects/version.lua", "lib/utf8.lua", "core/shared/config.lua"
    }

    for i = 1, #Files do
        local Chunk, Err = loadfile( SHINE_LIB .. Files[ i ] )
        if not Chunk then
            error( "Unable to load " .. Files[ i ] .. ": " .. tostring( Err ) )
        end
        -- Some of these files trail off into server only code, everything the objects need is defined
        -- before that point so a partial load is fine.
        pcall( Chunk )
    end

    if not Shine.Map or not Shine.Set then
        error( "Shine.Map/Shine.Set are unavailable, is C:/Git/Shine checked out?" )
    end
end

local function DeepCopy( Value )
    if type( Value ) ~= "table" then return Value end

    local Copy = {}
    for Key, Sub in pairs( Value ) do
        Copy[ Key ] = DeepCopy( Sub )
    end
    return Copy
end

Mocks.DeepCopy = DeepCopy

--[[
    Creates a fresh world. Options:
        MaxPlayers, MaxSpectators, ReservedSlots, RookieOnly, GameStarted, ReservedIDs, Config,
        Files (another world's Files, to carry them over a map change), SystemTime (system time at game time 0)
]]
function Mocks.NewWorld( Options )
    LoadShineObjects()

    Options = Options or {}

    local World = {
        MaxPlayers = Options.MaxPlayers or 8,
        MaxSpectators = Options.MaxSpectators or 4,
        ReservedSlots = Options.ReservedSlots or 0,
        RookieOnly = Options.RookieOnly or false,
        GameStarted = Options.GameStarted ~= false,
        ReservedIDs = Options.ReservedIDs or {},
        Time = 0,
        NextSteamID = 1000,
        Clients = {},
        SpectatorCount = 0,
        ClassHooks = {},
        PlainHooks = {},
        Notifications = {},
        ClassHookLog = {},
        Files = Options.Files or {},
        SystemTime = Options.SystemTime or 0,
        CallbackErrors = {}
    }

    -- ---------------------------------------------------------------- engine / NS2 globals

    -- Game time starts over with every map, system time does not.
    Shared.GetTime = function() return World.Time end
    Shared.GetSystemTime = function() return World.SystemTime + World.Time end
    Shared.Message = function() end
    Shared.GetCheatsEnabled = function() return false end
    Shared.GetDevMode = function() return false end
    Shared.GetThunderdomeEnabled = function() return false end

    Server.GetMaxPlayers = function() return World.MaxPlayers end
    Server.GetMaxSpectators = function() return World.MaxSpectators end
    Server.GetReservedSlotLimit = function() return World.ReservedSlots end
    Server.IsDedicated = function() return true end
    Server.GetConfigSetting = function() return false end
    Server.SendNetworkMessage = function() end
    Server.GetName = function() return "Mock Server" end
    Server.GetPort = function() return 27015 end

    --[[
        Outgoing HTTP, Bindings/Shared.txt:545 and the callback in Spark_Server/World.cpp:256. Requests are
        recorded for World:Respond, unless World.HTTPFail makes every request fail the way an unreachable host
        does.
    ]]
    World.HTTPRequests = {}
    Shared.SendHTTPRequest = function( URL, Method, Params, Callback, ... )
        assert( select( "#", ... ) == 0, "Shared.SendHTTPRequest takes at most 4 arguments" )

        if World.HTTPFail then
            World.HTTPFailures = ( World.HTTPFailures or 0 ) + 1
            Callback( "", "Couldn't connect to server", 7, 0 )
            return
        end

        World.HTTPRequests[ #World.HTTPRequests + 1 ] = {
            URL = URL, Method = Method, Params = Params, Callback = Callback
        }
    end

    -- shine/lib/query.lua:161, its Shine.Timer.Simple driven by World:RunDueTimers.
    Shine.TimedHTTPRequest = function( URL, Protocol, Params, OnResponse, OnTimeout, Timeout )
        local Succeeded

        Shared.SendHTTPRequest( URL, Protocol, Params, function( ... )
            if Succeeded ~= nil then return end
            Succeeded = true
            OnResponse( ... )
        end )

        World.HTTPTimeoutCount = ( World.HTTPTimeoutCount or 0 ) + 1
        World.Plugin.Timers[ "HTTPTimeout" .. World.HTTPTimeoutCount ] = {
            Reps = 1, Next = World.Time + ( Timeout or 5 ), Func = function()
                if Succeeded ~= nil then return end
                Succeeded = false
                OnTimeout()
            end
        }
    end

    -- Answers the oldest outstanding request. Without a status it answers like the retail engine, whose
    -- callback gets the body alone.
    function World:Respond( Status, Body )
        local Request = table.remove( World.HTTPRequests, 1 )
        assert( Request, "no HTTP request to respond to" )

        local Encoded = type( Body ) == "table" and json.encode( Body ) or Body or ""
        if Status then
            Request.Callback( Encoded, nil, 0, Status )
        else
            Request.Callback( Encoded )
        end

        return Request
    end

    -- The engine counts network connections, so bots are not part of this.
    Server.GetNumClientsTotal = function()
        local Count = 0
        for i = 1, #World.Clients do
            if not World.Clients[ i ].Virtual then
                Count = Count + 1
            end
        end
        return Count
    end

    -- Mirrors ServerGame::GetNumSpectators, a counter maintained by SetIsSpectator rather than a scan,
    -- so a leaked spectator flag shows up in the tests.
    Server.GetNumSpectators = function() return World.SpectatorCount end

    GetHasReservedSlotAccess = function( SteamID )
        return World.ReservedIDs[ SteamID ] == true
    end

    ServerAdminPrint = function() end

    -- ---------------------------------------------------------------- clients and players

    local ClientMeta = {}
    ClientMeta.__index = ClientMeta

    function ClientMeta:GetUserId() return self.SteamID end
    function ClientMeta:GetId() return self.ID end
    function ClientMeta:GetIsVirtual() return self.Virtual == true end
    function ClientMeta:GetIsSpectator() return self.Spectator == true end
    function ClientMeta:GetControllingPlayer() return self.Player end

    -- ServerGame::SetIsSpectator: no-op when unchanged, otherwise adjusts the server wide counter.
    function ClientMeta:SetIsSpectator( IsSpectator )
        IsSpectator = IsSpectator and true or false
        if self.Spectator == IsSpectator then return false end

        self.Spectator = IsSpectator
        World.SpectatorCount = World.SpectatorCount + ( IsSpectator and 1 or -1 )
        if World.SpectatorCount < 0 then
            World.SpectatorFlagUnderflow = true
            World.SpectatorCount = 0
        end

        return true
    end

    local PlayerMeta = {}
    PlayerMeta.__index = PlayerMeta

    function PlayerMeta:GetClient() return self.Client end
    function PlayerMeta:GetTeamNumber() return self.TeamNumber end
    function PlayerMeta:GetSteamId() return self.Client and self.Client.SteamID or -1 end
    function PlayerMeta:GetIsVirtual() return self.Client and self.Client:GetIsVirtual() end
    function PlayerMeta:GetSkillTier() return self.SkillTier or 0 end
    function PlayerMeta:SetCameraDistance() end
    function PlayerMeta:SetSpectatorMode() end
    function PlayerMeta:GetIsSpectator()
        return self.Client and self.Client:GetIsSpectator()
    end

    -- Player_Server.lua:41
    function PlayerMeta:SetIsSpectator( IsSpec )
        if type( IsSpec ) ~= "boolean" then return end
        if self:GetIsVirtual() then return end

        self.Client:SetIsSpectator( IsSpec )

        if not IsSpec then return end

        if World.Gamerules and self:GetTeamNumber() ~= kSpectatorIndex then
            World.Gamerules:JoinTeam( self, kSpectatorIndex, true )
        end
    end

    --[[
        Adds a client. Team defaults to the ready room, Spectator marks them as using a spectator slot
        the way a connection accepted into a spectator slot arrives.
    ]]
    function World:AddClient( Options )
        Options = Options or {}

        local SteamID = Options.SteamID
        if not SteamID then
            World.NextSteamID = World.NextSteamID + 1
            SteamID = World.NextSteamID
        end

        World.NextClientID = ( World.NextClientID or 0 ) + 1

        local NewClient = setmetatable( {
            ID = World.NextClientID,
            SteamID = SteamID,
            Name = Options.Name or ( "Player" .. SteamID ),
            Virtual = Options.Virtual or false,
            Spectator = false
        }, ClientMeta )

        local NewPlayer = setmetatable( {
            Client = NewClient,
            TeamNumber = Options.Team or kTeamReadyRoom,
            SkillTier = Options.SkillTier or 0
        }, PlayerMeta )

        NewClient.Player = NewPlayer

        World.Clients[ #World.Clients + 1 ] = NewClient

        if Options.Reserved then
            World.ReservedIDs[ SteamID ] = true
        end

        if Options.Spectator then
            -- The engine flags the connection before the world ever sees it, then NS2Gamerules:OnClientConnect
            -- (NS2Gamerules.lua:288) moves them onto the spectator team before Shine knows the client.
            NewClient:SetIsSpectator( true )
            World.Gamerules:JoinTeam( NewPlayer, kSpectatorIndex, true )
        end

        -- Shine's ClientConnect hook: GameIDs at MAX_PRIORITY (permissions.lua:420), then the plugins.
        Shine.GameIDs:Add( NewClient, #World.Clients )
        if World.Plugin.ClientConnect then
            World.Plugin:ClientConnect( NewClient )
        end

        return NewClient
    end

    function World:AddPlayer( Options )
        Options = Options or {}
        Options.Team = Options.Team or kTeam1Index
        return World:AddClient( Options )
    end

    function World:AddSpectator( Options )
        Options = Options or {}
        Options.Spectator = true
        return World:AddClient( Options )
    end

    function World:AddBot()
        return World:AddClient{ Virtual = true, Team = kTeam1Index }
    end

    function World:Disconnect( TargetClient )
        -- Shine removes the client from GameIDs at MAX_PRIORITY, before plugin hooks run. The engine still
        -- counts the connection while the hooks run.
        Shine.GameIDs:Remove( TargetClient )
        World.Plugin:ClientDisconnect( TargetClient )

        for i = 1, #World.Clients do
            if World.Clients[ i ] == TargetClient then
                table.remove( World.Clients, i )
                break
            end
        end
        TargetClient:SetIsSpectator( false )

        -- The next frame, where zero delay timers run.
        World:RunDueTimers()
    end

    -- ---------------------------------------------------------------- Shine surface

    Shine.GameIDs = Shine.Map()

    -- player.lua:453, which only knows clients in GameIDs.
    Shine.GetClientByNS2ID = function( SteamID )
        local Keys = Shine.GameIDs:GetKeys()
        for i = 1, #Keys do
            if Keys[ i ].SteamID == SteamID then
                return Keys[ i ]
            end
        end
    end

    -- player.lua:152
    function Shine:IsValidClient( Target )
        return Target and self.GameIDs:Get( Target ) ~= nil
    end

    Shine.GetClientName = function( TargetClient )
        return TargetClient and TargetClient.Name or "Unknown"
    end

    Shine.GetClientInfo = function( TargetClient )
        return Shine.GetClientName( TargetClient )
    end

    Shine.GetAllClients = function()
        local Out = {}
        for i = 1, #World.Clients do
            Out[ i ] = World.Clients[ i ]
        end
        return Out, #Out
    end

    Shine.SendNetworkMessage = function( TargetClient, Name, Data )
        World.Plugin.NetworkMessages[ #World.Plugin.NetworkMessages + 1 ] = {
            Client = TargetClient,
            Name = Name,
            Data = Data,
            SteamID = TargetClient and TargetClient.SteamID
        }
    end

    Shine.LoadPluginFile = function( _, Path, ... )
        local Chunk, Err = loadfile( PLUGIN_DIR .. Path )
        if not Chunk then
            error( "Unable to load " .. Path .. ": " .. tostring( Err ) )
        end
        return Chunk( ... )
    end

    -- config.lua:50 and :132, through a JSON round trip so only what JSON can hold survives.
    Shine.LoadJSONFile = function( Path )
        local Data = World.Files[ Path ]
        if not Data then return false, "file not found" end
        return json.decode( Data )
    end
    Shine.SaveJSONFile = function( Table, Path )
        World.Files[ Path ] = json.encode( Table )
        return true
    end
    Shine.HasAccess = function() return false end
    function Shine:IsExtensionEnabled() return false end
    -- extensions.lua:33, every loaded plugin by name.
    Shine.Plugins = Options.Plugins or {}

    Shine.Hook = {
        -- Faithful enough to hook.lua: the first non-nil result wins.
        Call = function( Event, ... )
            local Handler = World.Plugin and World.Plugin[ Event ]
            if not Handler then return end
            return Handler( World.Plugin, ... )
        end,
        SetupClassHook = function( ClassName, Method, HookName, Func )
            World.ClassHooks[ ClassName .. "." .. Method ] = Func
            World.ClassHookLog[ #World.ClassHookLog + 1 ] = ClassName .. "." .. Method
        end,
        Add = function( Event, Name, Func )
            World.PlainHooks[ Event ] = World.PlainHooks[ Event ] or {}
            World.PlainHooks[ Event ][ Name ] = Func
        end,
        MAX_PRIORITY = -20
    }

    -- ---------------------------------------------------------------- gamerules

    local Gamerules = {}
    World.Gamerules = Gamerules

    function Gamerules:GetGameStarted() return World.GameStarted end

    -- Gamerules.lua:136
    function Gamerules:VanillaGetCanJoinPlayingTeam( Player )
        if Player:GetIsSpectator() then
            local numClients = Server.GetNumClientsTotal()
            local numSpecs = Server.GetNumSpectators()

            local numPlayer = numClients - numSpecs
            local maxPlayers = Server.GetMaxPlayers()
            local numRes = Server.GetReservedSlotLimit()

            if numPlayer >= maxPlayers then
                return false
            end

            local hasReservedSlot = GetHasReservedSlotAccess( Player:GetSteamId() )
            if numPlayer >= ( maxPlayers - numRes ) and not hasReservedSlot then
                return false
            end
        end

        return true
    end

    -- Routed through the plugin's own class hook wrapper so the wrapper itself is under test.
    function Gamerules:GetCanJoinPlayingTeam( Player, SkipHook )
        local Wrapper = World.ClassHooks[ "Gamerules.GetCanJoinPlayingTeam" ]
        if not Wrapper then
            return Gamerules.VanillaGetCanJoinPlayingTeam( self, Player )
        end

        return Wrapper( Gamerules.VanillaGetCanJoinPlayingTeam, self, Player, SkipHook )
    end

    -- NS2Gamerules.lua:1388
    function Gamerules:GetCanJoinTeamNumber( Player, TeamNumber )
        if TeamNumber ~= kSpectatorIndex then
            if World.RookieOnly and Player:GetSkillTier() > kRookieMaxSkillTier then
                return false
            end
        end

        return true
    end

    -- NS2Gamerules.lua:1455, wrapped the way Shine's JoinTeam class hook wraps it.
    function Gamerules:JoinTeam( Player, NewTeamNumber, Force, ShineForce )
        for _, Hook in pairs( World.PlainHooks.JoinTeam or {} ) do
            if Hook( self, Player, NewTeamNumber, Force, ShineForce ) == false then
                return false, Player
            end
        end

        local TargetClient = Player:GetClient()
        if not TargetClient then return end

        if NewTeamNumber ~= kSpectatorIndex and not self:GetCanJoinPlayingTeam( Player ) then
            return false
        end

        if not Force and not self:GetCanJoinTeamNumber( Player, NewTeamNumber ) then
            return false
        end

        local OldTeamNumber = Player:GetTeamNumber()
        local Success = false

        if OldTeamNumber ~= NewTeamNumber or Force then
            Player.TeamNumber = NewTeamNumber
            Success = true

            if NewTeamNumber == kSpectatorIndex then
                Player:SetIsSpectator( true )
            elseif Player:GetIsSpectator() then
                Player:SetIsSpectator( false )
            end
        end

        -- hook.lua:1105 only broadcasts PostJoinTeam on success.
        if Success and World.Plugin and World.Plugin.PostJoinTeam then
            World.Plugin:PostJoinTeam( self, Player, OldTeamNumber, NewTeamNumber, Force, ShineForce )
        end

        return Success, Player
    end

    -- NS2Gamerules.lua:901 - the round end move that puts the whole server back in the ready room.
    function Gamerules:VanillaUpdateToReadyRoom()
        for i = 1, #World.Clients do
            local Target = World.Clients[ i ]
            local Player = Target:GetControllingPlayer()
            if Player and not Player:GetIsSpectator() then
                Gamerules:JoinTeam( Player, kTeamReadyRoom )
            end
        end
    end

    function World:EndRound()
        local Wrapper = World.ClassHooks[ "NS2Gamerules.UpdateToReadyRoom" ]
        if not Wrapper then
            return Gamerules:VanillaUpdateToReadyRoom()
        end

        return Wrapper( Gamerules.VanillaUpdateToReadyRoom, Gamerules, false )
    end

    GetGamerules = function() return Gamerules end

    -- ---------------------------------------------------------------- console commands

    -- NS2ConsoleCommands_Server.lua:46 - F4.
    function World:PressF4( TargetClient )
        local Player = TargetClient:GetControllingPlayer()
        if Player and Player:GetTeamNumber() ~= kTeamReadyRoom then
            return Gamerules:JoinTeam( Player, kTeamReadyRoom )
        end
    end

    -- NS2ConsoleCommands_Server.lua:16 - F1/F2, only reachable from the ready room.
    function World:JoinPlayingTeam( TargetClient, TeamNumber )
        local Player = TargetClient:GetControllingPlayer()
        if Player and Player:GetTeamNumber() == kTeamReadyRoom then
            return Gamerules:JoinTeam( Player, TeamNumber or kTeam1Index )
        end
        return false
    end

    -- NS2ConsoleCommands_Server.lua:61 - the spectate command / ready room portal.
    function World:Spectate( TargetClient )
        local Player = TargetClient:GetControllingPlayer()
        return Gamerules:JoinTeam( Player, kSpectatorIndex )
    end

    -- ---------------------------------------------------------------- plugin

    local Plugin = {
        BaseClass = {},
        Timers = {},
        Notified = {},
        NetworkMessages = {},
        Logs = {},
        dt = {}
    }
    World.Plugin = Plugin

    -- timers.lua:95, the base Cleanup destroys the plugin's timers. Shine.TimedHTTPRequest's are global.
    function Plugin.BaseClass.Cleanup()
        for Name in pairs( Plugin.Timers ) do
            if not Name:find( "^HTTPTimeout" ) then
                Plugin.Timers[ Name ] = nil
            end
        end
    end

    -- base_plugin.lua:156, for plugin revisions without a Cleanup of their own.
    function Plugin:Cleanup()
        return self.BaseClass.Cleanup( self )
    end

    -- base_plugin.lua:215, errors are reported rather than raised.
    local function UnwrapResults( Ok, ... )
        if not Ok then
            World.CallbackErrors[ #World.CallbackErrors + 1 ] = ( ... )
            return
        end
        return ...
    end

    function Plugin:WrapCallback( Callback )
        return function( ... )
            if not self.Enabled then return end
            return UnwrapResults( pcall( Callback, ... ) )
        end
    end

    function Plugin:Print( Message, _, ... )
        local Args = { ... }
        local Ok, Formatted = pcall( string.format, Message, unpack( Args ) )
        Plugin.Logs[ #Plugin.Logs + 1 ] = Ok and Formatted or Message
        if World.Verbose then
            print( "[plugin] " .. ( Ok and Formatted or Message ) )
        end
    end

    local function RecordNotify( TargetClient, Key, Data )
        Plugin.Notified[ #Plugin.Notified + 1 ] = {
            Client = TargetClient,
            Key = Key,
            Data = Data,
            SteamID = TargetClient and TargetClient.SteamID
        }
    end

    function Plugin:SendTranslatedNotify( TargetClient, Key, Data ) RecordNotify( TargetClient, Key, Data ) end
    function Plugin:NotifyTranslated( TargetClient, Key ) RecordNotify( TargetClient, Key ) end
    function Plugin:NotifyTranslatedError( TargetClient, Key ) RecordNotify( TargetClient, Key ) end

    function Plugin:SendNetworkMessage( TargetClient, Name, Data )
        Plugin.NetworkMessages[ #Plugin.NetworkMessages + 1 ] = {
            Client = TargetClient,
            Name = Name,
            Data = Data,
            SteamID = TargetClient and TargetClient.SteamID
        }
    end

    function Plugin:SimpleTimer( Delay, Func )
        World.SimpleTimerCount = ( World.SimpleTimerCount or 0 ) + 1
        Plugin.Timers[ "Simple" .. World.SimpleTimerCount ] = {
            Delay = Delay, Func = Func, Reps = 1, Next = World.Time + Delay
        }
    end

    -- timer.lua:83, creating a timer that exists edits it in place, even from inside its own function.
    function Plugin:CreateTimer( Name, Delay, Reps, Func )
        local Timer = Plugin.Timers[ Name ] or {}
        Timer.Delay, Timer.Reps, Timer.Func, Timer.Next = Delay, Reps, Func, World.Time + Delay
        Plugin.Timers[ Name ] = Timer
    end

    function Plugin:SaveConfig() end

    World.Commands = {}
    function Plugin:BindCommand( ConCommand, _, Func )
        local Command = { Help = function() end, AddParam = function() end }
        World.Commands[ ConCommand ] = Func
        return Command
    end

    -- Shine loads shared.lua first, server.lua then extends the plugin it created.
    Plugin.__Name = "readyroomqueue"
    local SharedChunk = loadfile( PLUGIN_DIR .. "shared.lua" )
    if SharedChunk then
        local ShinePlugin = Shine.Plugin
        Shine.Plugin = function() return Plugin end
        SharedChunk( Plugin.__Name )
        Shine.Plugin = ShinePlugin
    end

    local Chunk, Err = loadfile( PLUGIN_FILE )
    if not Chunk then
        error( "Unable to load the plugin: " .. tostring( Err ) )
    end
    Chunk( Plugin, Plugin.__Name )

    Plugin.Config = DeepCopy( Plugin.DefaultConfig )

    -- Plugin revisions without the global seed queue just rerun the plain queue tests.
    if Mocks.CoordinatorDown and Plugin.Config.GlobalQueue then
        World.HTTPFail = true
        Plugin.Config.GlobalQueue.Enabled = true
    end

    if Options.Config then
        for Key, Value in pairs( Options.Config ) do
            if type( Value ) == "table" and type( Plugin.Config[ Key ] ) == "table" then
                for SubKey, SubValue in pairs( Value ) do
                    Plugin.Config[ Key ][ SubKey ] = SubValue
                end
            else
                Plugin.Config[ Key ] = Value
            end
        end
    end

    Plugin:Initialise()
    -- extensions.lua:694
    Plugin.Enabled = true
    Plugin:OnFirstThink()

    --[[
        Advances time and runs the plugin's periodic work, the way the Shine timer would.
    ]]
    function World:Tick( Seconds )
        World.Time = World.Time + ( Seconds or Plugin.TickInterval )
        Plugin:OnTick()
        World:RunDueTimers()
    end

    --[[
        Runs every timer but the queue tick, which Tick drives itself. Like timer.lua:167 the repetition is used
        up before the function runs and a function that errors destroys its timer. The error is raised again
        here, so a test never passes over it.
    ]]
    function World:RunDueTimers()
        local Due = {}
        for Key, Timer in pairs( Plugin.Timers ) do
            if Key ~= "RRQueueTick" and Timer.Next and Timer.Next <= World.Time then
                Due[ #Due + 1 ] = { Key = Key, Timer = Timer }
            end
        end

        for i = 1, #Due do
            local Key, Timer = Due[ i ].Key, Due[ i ].Timer
            if Plugin.Timers[ Key ] == Timer then
                if Timer.Reps > 0 then
                    Timer.Reps = Timer.Reps - 1
                end

                local Ok, Err = pcall( Timer.Func, Timer )
                if not Ok or Timer.Reps == 0 then
                    if Plugin.Timers[ Key ] == Timer then
                        Plugin.Timers[ Key ] = nil
                    end
                else
                    Timer.Next = World.Time + Timer.Delay
                end

                if not Ok then
                    error( Err, 0 )
                end
            end
        end
    end

    function World:CountFlaggedSpectators()
        local Count = 0
        for i = 1, #World.Clients do
            if World.Clients[ i ]:GetIsSpectator() then
                Count = Count + 1
            end
        end
        return Count
    end

    function World:CountPlayerSlotsUsed()
        local Count = 0
        for i = 1, #World.Clients do
            local Target = World.Clients[ i ]
            if not Target.Virtual and not Target:GetIsSpectator() then
                Count = Count + 1
            end
        end
        return Count
    end

    function World:QueueIDs()
        local Out = {}
        local Keys = Plugin.PlayerQueue:GetKeys()
        for i = 1, #Keys do
            Out[ i ] = Keys[ i ]
        end
        return Out
    end

    return World
end

return Mocks
