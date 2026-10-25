--[[
    Offline tests for the readyroomqueue plugin.

    Run from the repository root:
        RunQueueTests.bat
    or
        C:/Git/ns2-engine/utils/lua/luajit.exe test/readyroomqueue/run.lua
]]

local Mocks = assert( loadfile( "test/readyroomqueue/mocks.lua" ) )()

local Passed, Failed = 0, 0
local FailureLines = {}
local CurrentWorld

local function Fail( Message )
    error( Message, 2 )
end

local function AssertTrue( Value, Message )
    if not Value then
        Fail( ( Message or "expected a truthy value" ) .. ", got " .. tostring( Value ) )
    end
end

local function AssertFalse( Value, Message )
    if Value then
        Fail( ( Message or "expected a falsy value" ) .. ", got " .. tostring( Value ) )
    end
end

local function AssertEquals( Expected, Actual, Message )
    if Expected ~= Actual then
        Fail( ( Message or "value mismatch" ) .. ": expected " .. tostring( Expected )
            .. ", got " .. tostring( Actual ) )
    end
end

local function AssertList( Expected, Actual, Message )
    local function Render( List )
        local Parts = {}
        for i = 1, #List do Parts[ i ] = tostring( List[ i ] ) end
        return "{" .. table.concat( Parts, ", " ) .. "}"
    end

    if #Expected ~= #Actual then
        Fail( ( Message or "list mismatch" ) .. ": expected " .. Render( Expected )
            .. ", got " .. Render( Actual ) )
    end

    for i = 1, #Expected do
        if Expected[ i ] ~= Actual[ i ] then
            Fail( ( Message or "list mismatch" ) .. ": expected " .. Render( Expected )
                .. ", got " .. Render( Actual ) )
        end
    end
end

local Registered = {}

local function Test( Name, Func )
    Registered[ #Registered + 1 ] = { Name = Name, Func = Func }
end

local function RunTest( Name, Func )
    CurrentWorld = nil

    local Ok, Err = pcall( Func )

    -- Every scenario must leave the engine spectator counter consistent with the client flags.
    if Ok and CurrentWorld then
        local Counted = CurrentWorld:CountFlaggedSpectators()
        if Server.GetNumSpectators() ~= Counted then
            Ok = false
            Err = "spectator counter leaked: engine says " .. tostring( Server.GetNumSpectators() )
                .. ", flags say " .. tostring( Counted )
        elseif CurrentWorld.SpectatorFlagUnderflow then
            Ok = false
            Err = "spectator counter underflowed"
        elseif CurrentWorld.CallbackErrors[ 1 ] then
            Ok = false
            Err = "a wrapped callback errored: " .. tostring( CurrentWorld.CallbackErrors[ 1 ] )
        end
    end

    if Ok then
        Passed = Passed + 1
        print( "  ok   " .. Name )
    else
        Failed = Failed + 1
        print( "  FAIL " .. Name )
        print( "         " .. tostring( Err ) )
        FailureLines[ #FailureLines + 1 ] = Name
    end
end

--[[
    Records what the plugin's GetCanJoinPlayingTeam hook returned, so tests can assert that the plugin
    never blocks a join it has no business blocking.
]]
local function SpyOnHook( World )
    local Plugin = World.Plugin
    local Original = Plugin.OnGetCanJoinPlayingTeam
    World.HookReturns = {}

    Plugin.OnGetCanJoinPlayingTeam = function( self, Gamerules, Player, Allowed )
        local Result = Original( self, Gamerules, Player, Allowed )
        World.HookReturns[ #World.HookReturns + 1 ] = {
            SteamID = Player:GetClient() and Player:GetClient().SteamID,
            Allowed = Allowed,
            Result = Result
        }
        return Result
    end
end

local function CountBlocks( World )
    local Count = 0
    for i = 1, #World.HookReturns do
        if World.HookReturns[ i ].Result == false then
            Count = Count + 1
        end
    end
    return Count
end

-- Removes a client without going through any hook, standing in for a slot that frees up by a path the
-- plugin does not know about.
local function SilentlyRemove( World, Target )
    for i = 1, #World.Clients do
        if World.Clients[ i ] == Target then
            table.remove( World.Clients, i )
            break
        end
    end
    Shine.GameIDs:Remove( Target )
end

local function FillTeams( World, Count )
    local Players = {}
    for i = 1, Count do
        Players[ i ] = World:AddPlayer{ Name = "P" .. i }
    end
    return Players
end

local function NotifiedWith( World, SteamID, Key )
    for i = 1, #World.Plugin.Notified do
        local Entry = World.Plugin.Notified[ i ]
        if Entry.SteamID == SteamID and Entry.Key == Key then
            return true
        end
    end
    return false
end

local function SentMessage( World, SteamID, Name )
    for i = 1, #World.Plugin.NetworkMessages do
        local Entry = World.Plugin.NetworkMessages[ i ]
        if Entry.SteamID == SteamID and Entry.Name == Name then
            return true
        end
    end
    return false
end

print( "readyroomqueue tests" )

-- --------------------------------------------------------------------------------------------------
Test( "full server: a spectator spamming F4 is queued and never gets in", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    FillTeams( World, 4 )
    local Spec = World:AddSpectator{ Name = "Spammer" }

    for _ = 1, 6 do
        World:PressF4( Spec )
    end

    AssertEquals( kSpectatorIndex, Spec:GetControllingPlayer():GetTeamNumber(),
        "the spammer must stay in the spectator team" )
    AssertTrue( Spec:GetIsSpectator(), "the spammer must stay on a spectator slot" )
    AssertList( { Spec.SteamID }, World:QueueIDs(), "the spammer must be queued exactly once" )
    AssertEquals( 4, World:CountPlayerSlotsUsed(), "no extra player slot may be used" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a freed slot goes to the head of the queue on disconnect", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local First = World:AddSpectator{ Name = "First" }
    local Second = World:AddSpectator{ Name = "Second" }

    World:PressF4( First )
    World:PressF4( Second )
    AssertList( { First.SteamID, Second.SteamID }, World:QueueIDs(), "both must be queued in order" )

    World:Disconnect( Players[ 1 ] )

    AssertEquals( kTeamReadyRoom, First:GetControllingPlayer():GetTeamNumber(),
        "the head of the queue must be moved into the ready room" )
    AssertFalse( First:GetIsSpectator(), "the head of the queue must hold a player slot now" )
    AssertList( { Second.SteamID }, World:QueueIDs(), "only the second player may still be queued" )
    AssertTrue( SentMessage( World, First.SteamID, "QueueLeft" ), "the head must be told they got a slot" )

    -- They can now actually play.
    AssertTrue( World:JoinPlayingTeam( First, kTeam1Index ), "the popped player must be able to join a team" )
    AssertEquals( kTeam1Index, First:GetControllingPlayer():GetTeamNumber(), "they must end up on team 1" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a slot freed by an unhooked path is picked up by the tick", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local Waiting = World:AddSpectator{ Name = "Waiting" }
    World:PressF4( Waiting )

    SilentlyRemove( World, Players[ 2 ] )
    AssertEquals( kSpectatorIndex, Waiting:GetControllingPlayer():GetTeamNumber(),
        "nothing should have happened yet" )

    World:Tick()

    AssertEquals( kTeamReadyRoom, Waiting:GetControllingPlayer():GetTeamNumber(),
        "the tick must hand the free slot to the queue" )
    AssertList( {}, World:QueueIDs(), "the queue must be empty afterwards" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "reserved slots: a reserved slot goes to the reserved queue, not to the plain queue", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4, ReservedSlots = 2 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local Plain = World:AddSpectator{ Name = "Plain" }
    local Reserved = World:AddSpectator{ Name = "Reserved", Reserved = true }

    World:PressF4( Plain )
    World:PressF4( Reserved )
    AssertList( { Plain.SteamID, Reserved.SteamID }, World:QueueIDs(), "both must be queued in order" )
    AssertEquals( 1, World.Plugin.ReservedQueue:GetCount(), "only the reserved player is in the reserved queue" )

    -- One slot free, and with 2 of 4 slots reserved it is a reserved one.
    World:Disconnect( Players[ 1 ] )

    AssertEquals( kTeamReadyRoom, Reserved:GetControllingPlayer():GetTeamNumber(),
        "the reserved player must get the reserved slot" )
    AssertEquals( kSpectatorIndex, Plain:GetControllingPlayer():GetTeamNumber(),
        "the plain player may not take a reserved slot" )
    AssertList( { Plain.SteamID }, World:QueueIDs(), "the plain player must stay queued" )

    -- Two of the four slots are reserved, so with two slots still in use there is no ordinary slot
    -- free yet. Vanilla denies the plain player here too, the plugin must agree with it.
    World:Disconnect( Players[ 2 ] )
    World:Tick()
    AssertEquals( kSpectatorIndex, Plain:GetControllingPlayer():GetTeamNumber(),
        "the plain player still has to wait while only reserved headroom is free" )

    World:Disconnect( Players[ 3 ] )
    World:Tick()
    AssertEquals( kSpectatorIndex, Plain:GetControllingPlayer():GetTeamNumber(),
        "two of four slots are reserved, so two players still fill the ordinary slots" )

    -- Now an ordinary slot really is free.
    World:Disconnect( Players[ 4 ] )
    AssertEquals( kTeamReadyRoom, Plain:GetControllingPlayer():GetTeamNumber(),
        "the plain player must get the ordinary slot" )
    AssertList( {}, World:QueueIDs(), "the queue must be empty afterwards" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a queue entry that already holds a player slot does not freeze the queue", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 3 )
    local Idler = World:AddClient{ Name = "Idler", Team = kTeamReadyRoom }
    local Waiting = World:AddSpectator{ Name = "Waiting" }

    -- Stale entry of the kind older versions of the plugin could create.
    World.Plugin:InsertIntoQueue( World.Plugin.PlayerQueue, Idler.SteamID, 1 )
    World.Plugin:InsertIntoQueue( World.Plugin.PlayerQueue, Waiting.SteamID, 2 )
    AssertList( { Idler.SteamID, Waiting.SteamID }, World:QueueIDs(), "both entries must be queued" )

    World:Disconnect( Players[ 1 ] )

    AssertEquals( kTeamReadyRoom, Waiting:GetControllingPlayer():GetTeamNumber(),
        "the waiting spectator must get the slot" )
    AssertList( {}, World:QueueIDs(), "the stale entry must be dropped, not left blocking the queue" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a ready room player cannot enqueue and stall the queue", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World

    FillTeams( World, 3 )
    local Idler = World:AddClient{ Name = "Idler", Team = kTeamReadyRoom }

    AssertFalse( World.Plugin:Enqueue( Idler ), "a ready room player must not be able to queue" )
    AssertList( {}, World:QueueIDs(), "the queue must stay empty" )
    AssertTrue( NotifiedWith( World, Idler.SteamID, "ENQUEUE_ERROR_PLAYER" ),
        "they must be told why they cannot queue" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "bots do not use up player slots as far as the queue is concerned", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    FillTeams( World, 2 )
    for _ = 1, 4 do
        World:AddBot()
    end

    local A = World:AddSpectator{ Name = "A" }
    local B = World:AddSpectator{ Name = "B" }

    AssertTrue( World.Plugin:Enqueue( A ), "a spectator must be able to queue" )
    AssertTrue( World.Plugin:Enqueue( B ), "a spectator must be able to queue" )

    World:Tick()
    AssertEquals( kTeamReadyRoom, A:GetControllingPlayer():GetTeamNumber(),
        "bots must not stop the queue from popping" )

    World:Tick()
    AssertEquals( kTeamReadyRoom, B:GetControllingPlayer():GetTeamNumber(),
        "the second spectator must be served too" )
    AssertList( {}, World:QueueIDs(), "the queue must be empty afterwards" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "rookie only server: the queue still hands out slots, vanilla still blocks the team join", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4, RookieOnly = true }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local Veteran = World:AddSpectator{ Name = "Veteran", SkillTier = 5 }

    World:PressF4( Veteran )
    AssertList( { Veteran.SteamID }, World:QueueIDs(), "the veteran must be queued" )

    World:Disconnect( Players[ 1 ] )

    AssertEquals( kTeamReadyRoom, Veteran:GetControllingPlayer():GetTeamNumber(),
        "the queue must still be able to move them into the ready room" )
    AssertFalse( Veteran:GetIsSpectator(), "they must hold a player slot now" )
    AssertList( {}, World:QueueIDs(), "the queue must not be left wedged" )

    -- The rookie rule is vanilla's job and must still apply.
    AssertFalse( World:JoinPlayingTeam( Veteran, kTeam1Index ),
        "a veteran must still not be able to join a team on a rookie only server" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "empty queue: nobody is blocked from joining a team", function()
    local World = Mocks.NewWorld{ MaxPlayers = 8 }
    CurrentWorld = World
    SpyOnHook( World )

    FillTeams( World, 2 )
    local Idler = World:AddClient{ Name = "Idler", Team = kTeamReadyRoom }
    local Spec = World:AddSpectator{ Name = "Spec" }

    AssertTrue( World:JoinPlayingTeam( Idler, kTeam2Index ), "a ready room player must be able to join" )

    World:PressF4( Spec )
    AssertEquals( kTeamReadyRoom, Spec:GetControllingPlayer():GetTeamNumber(),
        "a spectator must be able to reach the ready room when slots are free" )
    AssertTrue( World:JoinPlayingTeam( Spec, kTeam1Index ), "and must then be able to join a team" )

    AssertEquals( 0, CountBlocks( World ), "the plugin must never block a join while the queue is empty" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a queue nobody can be served from does not hold the free slot hostage", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    FillTeams( World, 3 )

    -- A restored queue entry whose owner has not reconnected.
    World.Plugin:InsertIntoQueue( World.Plugin.PlayerQueue, 424242, 1 )
    World.Plugin.HistoricPlayers:Add( 424242 )

    local Spec = World:AddSpectator{ Name = "Spec" }
    World:PressF4( Spec )

    AssertEquals( kTeamReadyRoom, Spec:GetControllingPlayer():GetTeamNumber(),
        "an absent queue entry must not block a present spectator" )
    AssertEquals( 0, CountBlocks( World ), "the plugin must not block when it cannot serve anybody" )
    AssertTrue( World.Plugin.PlayerQueue:Get( 424242 ) ~= nil,
        "the restored entry must keep its position" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "a reserved player is not blocked by a plain player who cannot use the reserved slot", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4, ReservedSlots = 1 }
    CurrentWorld = World
    SpyOnHook( World )

    FillTeams( World, 4 )
    local Plain = World:AddSpectator{ Name = "Plain" }
    World:PressF4( Plain )
    AssertList( { Plain.SteamID }, World:QueueIDs(), "the plain player must be queued" )

    -- One player leaves, leaving only the reserved slot free.
    local Extra = World.Clients[ 1 ]
    World:Disconnect( Extra )
    AssertEquals( kSpectatorIndex, Plain:GetControllingPlayer():GetTeamNumber(),
        "the plain player may not take the reserved slot" )

    local Reserved = World:AddSpectator{ Name = "Reserved", Reserved = true }
    World:PressF4( Reserved )

    AssertEquals( kTeamReadyRoom, Reserved:GetControllingPlayer():GetTeamNumber(),
        "the reserved player must be able to use their reserved slot" )
    AssertEquals( kSpectatorIndex, Plain:GetControllingPlayer():GetTeamNumber(),
        "the plain player must still be waiting" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "map change restore: absent entries hold their position without wedging the pop", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )

    World.Plugin:InsertIntoQueue( World.Plugin.PlayerQueue, 999001, 1 )
    World.Plugin.HistoricPlayers:Add( 999001 )

    local Present = World:AddSpectator{ Name = "Present" }
    World:PressF4( Present )
    AssertList( { 999001, Present.SteamID }, World:QueueIDs(), "the restored entry keeps position one" )

    World:Disconnect( Players[ 1 ] )

    AssertEquals( kTeamReadyRoom, Present:GetControllingPlayer():GetTeamNumber(),
        "the present spectator must be served" )
    AssertList( { 999001 }, World:QueueIDs(), "the restored entry must still be waiting" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: a ready room idler loses their slot to the queue", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4,
        Config = { ReadyRoomGracePeriod = { Enabled = true, Time = 10, EnqueueOnExpiry = true } } }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local First = World:AddSpectator{ Name = "First" }
    local Second = World:AddSpectator{ Name = "Second" }
    World:PressF4( First )
    World:PressF4( Second )

    World:PressF4( Players[ 1 ] )
    AssertEquals( kTeamReadyRoom, Players[ 1 ]:GetControllingPlayer():GetTeamNumber(),
        "F4 must still work for a player on a team" )
    AssertTrue( NotifiedWith( World, Players[ 1 ].SteamID, "RR_GRACE_WARNING" ),
        "they must be warned that their slot is on the clock" )

    World:Tick( 5 )
    AssertEquals( kTeamReadyRoom, Players[ 1 ]:GetControllingPlayer():GetTeamNumber(),
        "the slot must not be taken before the grace period runs out" )
    AssertEquals( kSpectatorIndex, First:GetControllingPlayer():GetTeamNumber(),
        "the queue must not be served early either" )

    World:Tick( 6 )

    AssertTrue( Players[ 1 ]:GetIsSpectator(), "the idler must be moved onto a spectator slot" )
    AssertEquals( kSpectatorIndex, Players[ 1 ]:GetControllingPlayer():GetTeamNumber(),
        "the idler must end up in the spectator team" )
    AssertEquals( kTeamReadyRoom, First:GetControllingPlayer():GetTeamNumber(),
        "the head of the queue must get the freed slot" )
    AssertList( { Second.SteamID, Players[ 1 ].SteamID }, World:QueueIDs(),
        "the idler must be put at the back of the queue" )
    AssertTrue( NotifiedWith( World, Players[ 1 ].SteamID, "RR_GRACE_EXPIRED" ),
        "the idler must be told what happened" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: rejoining a team before it expires keeps the slot", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4,
        Config = { ReadyRoomGracePeriod = { Enabled = true, Time = 10 } } }
    CurrentWorld = World

    local Players = FillTeams( World, 4 )
    local Waiting = World:AddSpectator{ Name = "Waiting" }
    World:PressF4( Waiting )

    World:PressF4( Players[ 1 ] )
    AssertTrue( next( World.Plugin.GraceExpiries ) ~= nil, "the grace period must be armed" )

    AssertTrue( World:JoinPlayingTeam( Players[ 1 ], kTeam2Index ), "they must be able to rejoin a team" )
    AssertTrue( next( World.Plugin.GraceExpiries ) == nil, "the grace period must be cleared" )

    World:Tick( 30 )
    AssertEquals( kTeam2Index, Players[ 1 ]:GetControllingPlayer():GetTeamNumber(),
        "they must keep playing" )
    AssertEquals( kSpectatorIndex, Waiting:GetControllingPlayer():GetTeamNumber(),
        "and the server is still full" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: the round end move never puts the server into spectator slots", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4,
        Config = { ReadyRoomGracePeriod = { Enabled = true, Time = 10 } } }
    CurrentWorld = World

    local Players = FillTeams( World, 4 )
    local Waiting = World:AddSpectator{ Name = "Waiting" }
    World:PressF4( Waiting )

    World:EndRound()

    for i = 1, #Players do
        AssertEquals( kTeamReadyRoom, Players[ i ]:GetControllingPlayer():GetTeamNumber(),
            "everybody ends up in the ready room at the end of a round" )
    end
    AssertTrue( next( World.Plugin.GraceExpiries ) == nil,
        "the round end move must not arm any grace period" )

    World:Tick( 60 )

    AssertEquals( 4, World:CountPlayerSlotsUsed(), "nobody may lose their player slot" )
    AssertEquals( kSpectatorIndex, Waiting:GetControllingPlayer():GetTeamNumber(),
        "and the queue stays where it is" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: the pre game ready room is left alone", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4, GameStarted = false,
        Config = { ReadyRoomGracePeriod = { Enabled = true, Time = 10 } } }
    CurrentWorld = World

    local Players = FillTeams( World, 4 )
    local Waiting = World:AddSpectator{ Name = "Waiting" }
    World:PressF4( Waiting )

    World:PressF4( Players[ 1 ] )
    AssertTrue( next( World.Plugin.GraceExpiries ) == nil,
        "no grace period before the game has started" )

    World:Tick( 60 )
    AssertEquals( 4, World:CountPlayerSlotsUsed(), "nobody may lose their player slot" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: disabled by config", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4,
        Config = { ReadyRoomGracePeriod = { Enabled = false, Time = 10 } } }
    CurrentWorld = World

    local Players = FillTeams( World, 4 )
    local Waiting = World:AddSpectator{ Name = "Waiting" }
    World:PressF4( Waiting )

    World:PressF4( Players[ 1 ] )
    World:Tick( 60 )

    AssertEquals( kTeamReadyRoom, Players[ 1 ]:GetControllingPlayer():GetTeamNumber(),
        "the idler keeps their slot when the grace period is off" )
    AssertEquals( kSpectatorIndex, Waiting:GetControllingPlayer():GetTeamNumber(),
        "so the queue keeps waiting" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "grace period: two idlers expiring in the same tick are reclaimed one tick apart", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4,
        Config = { ReadyRoomGracePeriod = { Enabled = true, Time = 10, EnqueueOnExpiry = true } } }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local First = World:AddSpectator{ Name = "First" }
    local Second = World:AddSpectator{ Name = "Second" }
    World:PressF4( First )
    World:PressF4( Second )

    World:PressF4( Players[ 1 ] )
    World:PressF4( Players[ 2 ] )
    AssertEquals( 10 + World.Time, World.Plugin.GraceExpiries[ Players[ 1 ].SteamID ],
        "the first idler must be on the clock" )
    AssertTrue( World.Plugin.GraceExpiries[ Players[ 2 ].SteamID ] ~= nil,
        "the second idler must be on the clock" )

    World:Tick( 11 )

    AssertTrue( Players[ 1 ]:GetIsSpectator(), "the first idler must lose their slot" )
    AssertEquals( kTeamReadyRoom, First:GetControllingPlayer():GetTeamNumber(),
        "the first queued player must be served" )
    AssertFalse( Players[ 2 ]:GetIsSpectator(), "only one player is reclaimed per tick" )
    AssertTrue( World.Plugin.GraceExpiries[ Players[ 2 ].SteamID ] ~= nil,
        "the second idler stays on the clock for the next tick" )

    World:Tick( 1 )

    AssertTrue( Players[ 2 ]:GetIsSpectator(), "the second idler must lose their slot on the next tick" )
    AssertEquals( kTeamReadyRoom, Second:GetControllingPlayer():GetTeamNumber(),
        "the second queued player must be served" )
    AssertList( { Players[ 1 ].SteamID, Players[ 2 ].SteamID }, World:QueueIDs(),
        "both idlers must end up at the back of the queue" )
    -- First sat in the ready room on a player slot while Second still waited, so First is on the clock now.
    AssertEquals( nil, World.Plugin.GraceExpiries[ Players[ 1 ].SteamID ], "no grace entry may be left behind" )
    AssertEquals( nil, World.Plugin.GraceExpiries[ Players[ 2 ].SteamID ], "no grace entry may be left behind" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "queue skipping: a spectator cannot take a slot the player ahead of them is owed", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World
    SpyOnHook( World )

    local Players = FillTeams( World, 4 )
    local Head = World:AddSpectator{ Name = "Head" }
    local Skipper = World:AddSpectator{ Name = "Skipper" }

    World:PressF4( Head )
    AssertList( { Head.SteamID }, World:QueueIDs(), "the head must be queued" )

    -- The slot frees up without the plugin being told, so it is still open when the skipper asks.
    SilentlyRemove( World, Players[ 1 ] )

    World:PressF4( Skipper )

    AssertEquals( kSpectatorIndex, Skipper:GetControllingPlayer():GetTeamNumber(),
        "the skipper must not get in ahead of the queue" )
    AssertEquals( kTeamReadyRoom, Head:GetControllingPlayer():GetTeamNumber(),
        "the slot must go to the head of the queue instead" )
    AssertList( { Skipper.SteamID }, World:QueueIDs(), "the skipper must be queued" )
    AssertEquals( 1, CountBlocks( World ), "exactly one join may be blocked" )
end )

local QueueTestCount = #Registered

-- ================================================================================================== seed queue

local function NewSeedWorld( Config, Options )
    local GlobalQueue = { Enabled = true }
    for Key, Value in pairs( Config or {} ) do
        GlobalQueue[ Key ] = Value
    end

    Options = Options or {}
    Options.MaxPlayers = 4
    Options.Config = { GlobalQueue = GlobalQueue }

    local World = Mocks.NewWorld( Options )
    CurrentWorld = World

    -- The tests drive the coordinator round trips themselves.
    World.Plugin.Timers.SeedUpdate = nil

    return World
end

-- Queued spectators whose clients reported the default preference, as they do once seeding is active.
local function QueueSpectators( World, Count )
    local Players = FillTeams( World, 4 )
    local Specs = {}
    for i = 1, Count do
        Specs[ i ] = World:AddSpectator{ Name = "S" .. i }
        World:PressF4( Specs[ i ] )
        World.Plugin:ReceiveSeedPref( Specs[ i ], { Pref = "ask" } )
    end
    return Specs, Players
end

-- Runs one heartbeat and answers it with Reply. Returns the decoded payload and the request.
local function Heartbeat( World, Reply )
    World.Plugin:SeedUpdate()
    local Request = World:Respond( 200, Reply or { next = 10 } )
    AssertTrue( Request.URL:find( "/seedqueue/heartbeat", 1, true ), "expected a heartbeat, got " .. Request.URL )
    World.Plugin.Timers.SeedUpdate = nil
    return json.decode( Request.Params.data ), Request
end

local function ClosedReasons( World, SteamID )
    local Out = {}
    for i = 1, #World.Plugin.NetworkMessages do
        local Entry = World.Plugin.NetworkMessages[ i ]
        if Entry.SteamID == SteamID and Entry.Name == "SeedClosed" then
            Out[ #Out + 1 ] = Entry.Data.Reason
        end
    end
    return Out
end

local function FindEntry( Payload, SteamID )
    for i = 1, #Payload.queue do
        if Payload.queue[ i ].id == SteamID then
            return Payload.queue[ i ]
        end
    end
end

local function CountMessages( World, SteamID, Name )
    local Count = 0
    for i = 1, #World.Plugin.NetworkMessages do
        local Entry = World.Plugin.NetworkMessages[ i ]
        if Entry.SteamID == SteamID and Entry.Name == Name then
            Count = Count + 1
        end
    end
    return Count
end

local function Connects( World, SteamID )
    local Out = {}
    for i = 1, #World.Plugin.NetworkMessages do
        local Entry = World.Plugin.NetworkMessages[ i ]
        if Entry.SteamID == SteamID and Entry.Name == "Shine_Command" and Entry.Data.Command:find( "^connect" ) then
            Out[ #Out + 1 ] = Entry.Data.Command
        end
    end
    return Out
end

-- --------------------------------------------------------------------------------------------------
Test( "seed: the heartbeat lists queued players with their scores and preferences", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 2 )
    World:AddBot()
    local Silent = World:AddSpectator{ Name = "Silent" }
    World:PressF4( Silent )

    Plugin:ReceiveSeedPref( Specs[ 1 ], { Pref = "always" } )
    Plugin:ReceiveSeedPref( Specs[ 2 ], { Pref = "bogus" } )
    Plugin:ReceiveSeedPref( Silent, { Pref = "bogus" } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "1.2.3.4:27015", Score = 1.23456, Version = "c-1" } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "5.6.7.8:27015", Score = 0, Version = "c-1" } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "connect evil", Score = 2, Version = "c-1" } )
    Plugin:ReceiveSeedScore( Specs[ 2 ], { Address = "1.2.3.4:27015", Score = 0 / 0, Version = "c-1" } )
    -- The coordinator would refuse the whole heartbeat over it.
    Plugin:ReceiveSeedScore( Specs[ 2 ], { Address = "5.6.7.8:27015", Score = 1e30, Version = "c-1" } )

    World:Tick( 10 )

    local Payload, Request = Heartbeat( World )
    AssertEquals( "POST", Request.Method, "the heartbeat is a form POST" )

    AssertEquals( 1, Payload.v, "contract version" )
    AssertEquals( "Mock Server", Payload.name, "server name" )
    AssertEquals( 27015, Payload.port, "the game port identifies this server" )
    AssertEquals( 4, Payload.players, "bots and spectators are not counted as players" )
    AssertEquals( 4, Payload.maxPlayers, "max players" )
    AssertEquals( true, Payload.matching, "matching follows the config" )

    AssertEquals( 2, #Payload.queue, "both players with a preference must be listed, the silent one not" )
    local First, Second = Payload.queue[ 1 ], Payload.queue[ 2 ]
    AssertEquals( Specs[ 1 ].SteamID, First.id, "queue order" )
    AssertEquals( Specs[ 2 ].SteamID, Second.id, "queue order" )
    AssertEquals( 10, First.wait, "wait time" )
    AssertEquals( "always", First.pref, "preference" )
    AssertEquals( "ask", Second.pref, "an invalid preference is ignored" )
    AssertEquals( nil, FindEntry( Payload, Silent.SteamID ), "a player that never reported a preference is left out" )

    Plugin:ReceiveSeedPref( Silent, { Pref = "never" } )
    Payload = Heartbeat( World )
    AssertEquals( "never", FindEntry( Payload, Silent.SteamID ).pref, "listed once the preference is known" )
    AssertEquals( 1.235, First.scores[ "1.2.3.4:27015" ], "scores are rounded to 3 decimals" )
    AssertEquals( nil, First.scores[ "5.6.7.8:27015" ], "zero scores are left out" )
    AssertEquals( nil, First.scores[ "connect evil" ], "a malformed address is ignored" )
    AssertEquals( nil, Second.scores, "a player without scores sends none" )
    AssertEquals( nil, First.answer, "no answer without an offer" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an offer prompts listed players, a commit sends only players that agreed and only once", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 4 )
    local A, B, C, D = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ], Specs[ 4 ]

    Plugin:ReceiveSeedPref( C, { Pref = "always" } )

    local Offer = { id = "o-1", target = "1.2.3.4:27015", name = "Target", count = 12, remaining = 18,
        players = { A.SteamID, B.SteamID, C.SteamID } }
    Heartbeat( World, { next = 3, offer = Offer } )
    Heartbeat( World, { next = 3, offer = Offer } )

    AssertEquals( 1, CountMessages( World, A.SteamID, "SeedOffer" ), "A is prompted once" )
    AssertEquals( 1, CountMessages( World, B.SteamID, "SeedOffer" ), "B is prompted once" )
    AssertEquals( 0, CountMessages( World, C.SteamID, "SeedOffer" ), "an always player is not prompted" )
    AssertEquals( 0, CountMessages( World, D.SteamID, "SeedOffer" ), "an unlisted player is not prompted" )

    World.Commands.sh_rr_seed( A, "yes" )
    Plugin:ReceiveSeedAnswer( B, { Accept = false } )
    World.Commands.sh_rr_seed( D, "yes" )
    AssertTrue( NotifiedWith( World, D.SteamID, "SEED_NO_OFFER" ), "answering without an offer is refused" )

    local Payload = Heartbeat( World, { next = 3, offer = Offer } )
    AssertEquals( "o-1", Payload.queue[ 1 ].answer.offer, "A's answer names the offer" )
    AssertEquals( true, Payload.queue[ 1 ].answer.accept, "A accepted" )
    AssertEquals( false, Payload.queue[ 2 ].answer.accept, "B declined" )
    AssertEquals( nil, Payload.queue[ 4 ].answer, "D has no answer" )

    local Commit = { id = "o-1", target = "1.2.3.4:27015", name = "Target",
        players = { A.SteamID, B.SteamID, C.SteamID, D.SteamID, 999999 } }
    Heartbeat( World, { next = 10, commit = Commit } )
    Heartbeat( World, { next = 10, commit = Commit } )

    AssertList( { "connect 1.2.3.4:27015" }, Connects( World, A.SteamID ), "A is sent exactly once" )
    AssertList( { "connect 1.2.3.4:27015" }, Connects( World, C.SteamID ), "C is sent exactly once" )
    AssertList( {}, Connects( World, B.SteamID ), "B declined, being listed does not send them" )
    AssertList( {}, Connects( World, D.SteamID ), "D was never offered, being listed does not send them" )
    AssertList( { "declined" }, ClosedReasons( World, B.SteamID ), "B's prompt is closed once, the seed went on" )
    AssertList( { "committed" }, ClosedReasons( World, A.SteamID ), "A's prompt is closed once, A is on the way" )
    AssertList( {}, ClosedReasons( World, D.SteamID ), "D was never prompted" )

    Heartbeat( World, { next = 10, offer = Offer } )
    AssertEquals( 1, CountMessages( World, B.SteamID, "SeedOffer" ), "a decided offer is never shown again" )

    local Malicious = { id = "o-2", target = "1.2.3.4:1; quit", players = { C.SteamID } }
    Heartbeat( World, { next = 10, commit = Malicious } )
    AssertList( { "connect 1.2.3.4:27015" }, Connects( World, C.SteamID ),
        "a malformed target is never sent to a client" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a commit for another offer or without an answer sends nobody but always players", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 3 )
    local A, B, C = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ]

    Plugin:ReceiveSeedPref( C, { Pref = "always" } )

    Heartbeat( World, { next = 3, offer = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID, B.SteamID } } } )
    Plugin:ReceiveSeedAnswer( A, { Accept = true } )

    -- A forged heartbeat can get the coordinator to commit an offer nobody here was shown.
    Heartbeat( World, { next = 10, commit = { id = "o-x", target = "6.6.6.6:27015",
        players = { A.SteamID, B.SteamID, C.SteamID } } } )
    AssertList( {}, Connects( World, A.SteamID ), "an accept for another offer does not count" )
    AssertList( {}, Connects( World, B.SteamID ), "B never answered" )
    AssertList( { "connect 6.6.6.6:27015" }, Connects( World, C.SteamID ), "an always player agreed to any seed" )

    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015",
        players = { A.SteamID, B.SteamID } } } )
    AssertList( { "connect 1.2.3.4:27015" }, Connects( World, A.SteamID ), "A accepted o-1" )
    AssertList( {}, Connects( World, B.SteamID ), "B still never answered" )
    AssertList( { "declined" }, ClosedReasons( World, B.SteamID ), "B's prompt is closed" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an always player who said no to this offer is not sent", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local A = QueueSpectators( World, 1 )[ 1 ]

    Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 3, offer = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World.Commands.sh_rr_seed( A, "no" )

    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    AssertList( {}, Connects( World, A.SteamID ), "an explicit no beats the always preference" )
    AssertList( { "declined" }, ClosedReasons( World, A.SteamID ), "A's offer is closed" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: the heartbeat stays under the coordinator's size limit", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 40 )

    -- Clients pick the addresses they score, the longest the network message carries.
    for i = 1, #Specs do
        for j = 1, 16 do
            local Address = string.format( "%s%02d:27015", string.rep( "a", 54 ), j )
            Plugin:ReceiveSeedScore( Specs[ i ], { Address = Address, Score = 1.5, Version = "c-1" } )
        end
    end

    local Payload, Request = Heartbeat( World )
    AssertTrue( #Payload.queue > 0 and #Payload.queue < #Specs, "the queue is cut, got " .. #Payload.queue )
    AssertTrue( #Request.Params.data + 32 * #Payload.queue <= 30000, "the heartbeat fits the coordinator's limit" )
    AssertEquals( Specs[ 1 ].SteamID, Payload.queue[ 1 ].id, "the front of the queue is kept" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a coordinator that goes down after being up stops activating clients", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 1 )

    Heartbeat( World )
    World:Tick( 1 )
    AssertEquals( 1, CountMessages( World, Specs[ 1 ].SteamID, "SeedActive" ), "S1 is activated while it is up" )

    Plugin:SeedUpdate()
    World:Respond( 500, { detail = "down" } )
    Plugin.Timers.SeedUpdate = nil

    local Late = World:AddSpectator{ Name = "Late" }
    World:PressF4( Late )
    World:Tick( 1 )
    AssertEquals( 0, CountMessages( World, Late.SteamID, "SeedActive" ), "a client queued while it is down waits" )

    Heartbeat( World )
    World:Tick( 1 )
    AssertEquals( 1, CountMessages( World, Late.SteamID, "SeedActive" ), "activated once a heartbeat gets through" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an abort closes the prompt, clears answers and keeps queue positions", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 3 )
    local A, B = Specs[ 1 ], Specs[ 2 ]
    local Before = World:QueueIDs()

    local Offer = { id = "o-9", target = "1.2.3.4:27015", name = "Target", count = 12, remaining = 18,
        players = { A.SteamID, B.SteamID } }
    Heartbeat( World, { next = 3, offer = Offer } )
    Plugin:ReceiveSeedAnswer( A, { Accept = true } )

    Heartbeat( World, { next = 10, abort = { id = "o-9" } } )
    Heartbeat( World, { next = 10, abort = { id = "o-9" } } )

    AssertList( { "aborted" }, ClosedReasons( World, A.SteamID ), "A is told once" )
    AssertList( { "aborted" }, ClosedReasons( World, B.SteamID ), "B is told once" )
    AssertList( {}, ClosedReasons( World, Specs[ 3 ].SteamID ), "others are not told" )
    AssertList( Before, World:QueueIDs(), "nobody moves in the queue" )
    AssertList( {}, Connects( World, A.SteamID ), "nobody is sent anywhere" )

    local Payload = Heartbeat( World )
    AssertEquals( nil, Payload.queue[ 1 ].answer, "the answer is cleared" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a player back from a seed within the hop return time gets their old position", function()
    local World = NewSeedWorld{ HopReturnTime = 180 }
    local Specs, Players = QueueSpectators( World, 3 )
    local A, B, C = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ]

    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )
    AssertList( { A.SteamID, B.SteamID, C.SteamID }, World:QueueIDs(), "A's entry is held" )

    World:Disconnect( C )
    AssertList( { A.SteamID, B.SteamID }, World:QueueIDs(), "a plain disconnect still leaves the queue" )

    World:Tick( 60 )
    local Back = World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }

    AssertList( { A.SteamID, B.SteamID }, World:QueueIDs(), "A is back at the front" )
    AssertTrue( NotifiedWith( World, A.SteamID, "QUEUE_WELCOME_BACK" ), "A is told their position is restored" )

    World:Disconnect( Players[ 1 ] )
    AssertEquals( kTeamReadyRoom, Back:GetControllingPlayer():GetTeamNumber(), "A gets the next free slot" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a player back after the hop return time queues from the back", function()
    local World = NewSeedWorld{ HopReturnTime = 180 }
    local Specs = QueueSpectators( World, 3 )
    local A, B, C = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ]

    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )

    World:Tick( 181 )
    AssertList( { B.SteamID, C.SteamID }, World:QueueIDs(), "the held entry is dropped once the time is up" )

    World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }
    AssertList( { B.SteamID, C.SteamID }, World:QueueIDs(), "A is not restored" )
    AssertTrue( NotifiedWith( World, A.SteamID, "QUEUE_INFORM" ), "A is told how to queue again" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: the heartbeat backs off on 403 and 429, errors and timeouts retry sooner", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin

    local function NextUpdateAfter( Status )
        Plugin.Timers.SeedUpdate = nil
        Plugin:SeedUpdate()
        if Status then
            World:Respond( Status, { detail = "error" } )
        else
            World:Tick( 15 )
        end
        return Plugin.Timers.SeedUpdate.Next - World.Time
    end

    AssertEquals( 120, NextUpdateAfter( 403 ), "a server Steam does not list backs off" )
    AssertEquals( 120, NextUpdateAfter( 429 ), "a rate limited server backs off" )
    AssertEquals( 120, NextUpdateAfter( 404 ), "a switched off coordinator backs off" )
    AssertEquals( 30, NextUpdateAfter( 500 ), "a server error is retried" )
    AssertEquals( 30, NextUpdateAfter( nil ), "a timed out request is retried" )

    World:Respond( 200, { next = 1 } )
    AssertEquals( 30, Plugin.Timers.SeedUpdate.Next - World.Time, "a reply after the timeout is ignored" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: without an HTTP status the reply body decides", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 1 )

    local function NextUpdateAfter( Body )
        Plugin.Timers.SeedUpdate = nil
        Plugin:SeedUpdate()
        World:Respond( nil, Body )
        return Plugin.Timers.SeedUpdate.Next - World.Time
    end

    AssertEquals( 7, NextUpdateAfter{ next = 7, offer = { id = "o-1", target = "1.2.3.4:27015",
        players = { Specs[ 1 ].SteamID } } }, "a reply with next is a success" )
    AssertEquals( 1, CountMessages( World, Specs[ 1 ].SteamID, "SeedOffer" ), "and is handled" )
    AssertEquals( 120, NextUpdateAfter{ detail = "not_listed" }, "an error detail backs off" )
    AssertEquals( 120, NextUpdateAfter{ detail = "Rate limit exceeded" }, "so does a rate limit" )
    AssertEquals( 30, NextUpdateAfter( "<html>502 Bad Gateway</html>" ), "an undecodable body is retried" )
    AssertEquals( 30, NextUpdateAfter( "" ), "an empty body is retried" )
    AssertEquals( 30, NextUpdateAfter{ queue = {} }, "a table without next or detail is retried" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a heartbeat that fails to build is retried", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin

    local Build = Plugin.BuildSeedHeartbeat
    Plugin.BuildSeedHeartbeat = function() error( "broken heartbeat" ) end
    Plugin:ScheduleSeedUpdate( 1 )
    World:Tick( 1 )
    Plugin.BuildSeedHeartbeat = Build

    AssertEquals( 1, #World.CallbackErrors, "the error is reported" )
    AssertTrue( tostring( World.CallbackErrors[ 1 ] ):find( "broken heartbeat", 1, true ), "with its message" )
    World.CallbackErrors = {}
    AssertEquals( 0, #World.HTTPRequests, "nothing was sent" )

    World:Tick( 29 )
    AssertEquals( 0, #World.HTTPRequests, "the retry waits for the error delay" )
    World:Tick( 1 )
    AssertEquals( 1, #World.HTTPRequests, "the heartbeat is retried" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a new candidate list replaces a player's scores, zeros are never stored", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local A = QueueSpectators( World, 1 )[ 1 ]

    local function Score( Address, Value, Version )
        Plugin:ReceiveSeedScore( A, { Address = Address, Score = Value, Version = Version } )
    end
    local function Scores()
        return FindEntry( Heartbeat( World ), A.SteamID ).scores or {}
    end
    local function Count( Table )
        local Total = 0
        for _ in pairs( Table ) do Total = Total + 1 end
        return Total
    end

    -- Blocked or unusable candidates arrive as 0 and must not use up the cap.
    for i = 1, 20 do
        Score( "10.0.0." .. i .. ":27015", 0, "c-1" )
    end
    for i = 1, 16 do
        Score( "10.0.1." .. i .. ":27015", 1, "c-1" )
    end
    Score( "10.0.2.1:27015", 1, "c-1" )

    local Current = Scores()
    AssertEquals( 16, Count( Current ), "at most 16 scores per candidate list" )
    AssertEquals( nil, Current[ "10.0.2.1:27015" ], "a 17th candidate of the same list is dropped" )

    Score( "10.0.2.1:27015", 2, "c-2" )
    Current = Scores()
    AssertEquals( 1, Count( Current ), "a new candidate list replaces the old scores" )
    AssertEquals( 2, Current[ "10.0.2.1:27015" ], "the new list's score is kept" )

    Score( "10.0.2.1:27015", 0, "c-2" )
    AssertEquals( 0, Count( Scores() ), "a 0 drops the candidate's score" )

    Score( "10.0.2.2:27015", 3, "c-2" )
    Score( "10.0.2.3:27015", 0, "c-3" )
    AssertEquals( 0, Count( Scores() ), "a 0 for a new list still replaces the old list's scores" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an offer only prompts members that are still waiting in the queue", function()
    local World = NewSeedWorld()
    local Specs, Players = QueueSpectators( World, 3 )
    local A, B, C = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ]

    -- The coordinator picked the members from an earlier heartbeat. A got a slot since, B left the queue.
    World:Disconnect( Players[ 1 ] )
    AssertFalse( A:GetIsSpectator(), "A holds a player slot now" )
    World.Commands.sh_rr_dequeue( B )

    local Offer = { id = "o-1", target = "1.2.3.4:27015", name = "Target", count = 12, remaining = 18,
        players = { A.SteamID, B.SteamID, C.SteamID } }
    Heartbeat( World, { next = 3, offer = Offer } )
    Heartbeat( World, { next = 3, offer = Offer } )

    AssertEquals( 0, CountMessages( World, A.SteamID, "SeedOffer" ), "a player with a slot is not prompted" )
    AssertEquals( 0, CountMessages( World, B.SteamID, "SeedOffer" ), "a player that left the queue is not prompted" )
    AssertEquals( 1, CountMessages( World, C.SteamID, "SeedOffer" ), "a queued spectator is prompted once" )

    World.Commands.sh_rr_seed( A, "yes" )
    AssertTrue( NotifiedWith( World, A.SteamID, "SEED_NO_OFFER" ), "A has no offer to answer" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: every prompted player gets exactly one close that says what happened", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs, Players = QueueSpectators( World, 4 )
    local E, A, B, C = Specs[ 1 ], Specs[ 2 ], Specs[ 3 ], Specs[ 4 ]

    Heartbeat( World, { next = 3, offer = { id = "o-1", target = "1.2.3.4:27015",
        players = { E.SteamID, A.SteamID, B.SteamID, C.SteamID } } } )
    Plugin:ReceiveSeedAnswer( E, { Accept = true } )
    Plugin:ReceiveSeedAnswer( A, { Accept = true } )
    Plugin:ReceiveSeedAnswer( B, { Accept = false } )

    World:Disconnect( Players[ 1 ] )
    AssertFalse( E:GetIsSpectator(), "E got a player slot after accepting" )

    local Commit = { id = "o-1", target = "1.2.3.4:27015", players = { E.SteamID, A.SteamID } }
    Heartbeat( World, { next = 10, commit = Commit } )
    Heartbeat( World, { next = 10, commit = Commit } )

    AssertList( { "committed" }, ClosedReasons( World, A.SteamID ), "A is told they are on the way" )
    AssertList( { "declined" }, ClosedReasons( World, B.SteamID ), "B declined, the seed went on without them" )
    AssertList( { "declined" }, ClosedReasons( World, C.SteamID ), "C never answered" )
    AssertList( { "declined" }, ClosedReasons( World, E.SteamID ), "E accepted but stays for the slot here" )
    AssertList( {}, Connects( World, E.SteamID ), "E is not sent" )

    local Closed, Connected
    for i = 1, #Plugin.NetworkMessages do
        local Entry = Plugin.NetworkMessages[ i ]
        if Entry.SteamID == A.SteamID then
            Closed = Entry.Name == "SeedClosed" and i or Closed
            Connected = Entry.Name == "Shine_Command" and i or Connected
        end
    end
    AssertTrue( Closed < Connected, "A's prompt is closed before the connect" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an offer's server name is cut to the message field on a character boundary", function()
    local World = NewSeedWorld()
    local A = QueueSpectators( World, 1 )[ 1 ]

    local function OfferedName( Name, ID )
        Heartbeat( World, { next = 3, offer = { id = ID, target = "1.2.3.4:27015", name = Name,
            players = { A.SteamID } } } )

        local Messages = World.Plugin.NetworkMessages
        for i = #Messages, 1, -1 do
            if Messages[ i ].Name == "SeedOffer" then
                return Messages[ i ].Data.Name
            end
        end
    end

    -- "string (128)" keeps 127 bytes.
    AssertEquals( ( "x" ):rep( 127 ), OfferedName( ( "x" ):rep( 200 ), "o-1" ), "ASCII is cut at 127 bytes" )
    AssertEquals( "ab" .. ( "é" ):rep( 62 ), OfferedName( "ab" .. ( "é" ):rep( 63 ), "o-2" ),
        "a 2 byte character across the limit is left out whole" )
    AssertEquals( ( "€" ):rep( 42 ), OfferedName( ( "€" ):rep( 50 ), "o-3" ), "so is a 3 byte one" )
    AssertEquals( "Täst", OfferedName( "Täst", "o-4" ), "a short name is untouched" )
end )

-- --------------------------------------------------------------------------------------------------
-- extensions.lua:730 UnloadExtension, then :619 EnableExtension with the edited config.
local function Reload( World, GlobalQueue )
    local Plugin = World.Plugin

    Plugin.Enabled = false
    Plugin:Cleanup()

    for Key, Value in pairs( GlobalQueue ) do
        Plugin.Config.GlobalQueue[ Key ] = Value
    end

    AssertTrue( Plugin:Initialise(), "the plugin loads again" )
    Plugin.Enabled = true
end

Test( "seed: reloading the plugin starts the seed queue over", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 2 )

    Heartbeat( World )
    World:Tick( 1 )
    AssertEquals( 1, CountMessages( World, Specs[ 1 ].SteamID, "SeedActive" ), "S1 is activated" )

    -- A heartbeat is in flight while the seed queue is switched off and the plugin reloaded.
    Plugin:SeedUpdate()
    Reload( World, { Enabled = false } )

    AssertEquals( nil, Plugin.SeedEnabled, "seeding is off" )
    AssertEquals( nil, Plugin.SeedOnline, "the coordinator is not known to be online" )
    AssertEquals( nil, Plugin.SeedURL, "there is no coordinator" )
    AssertEquals( nil, next( Plugin.SeedActiveClients ), "no client is active" )
    AssertEquals( nil, next( Plugin.SeedPrefs ), "no preference is kept" )

    -- The reload emptied the queue.
    World:PressF4( Specs[ 1 ] )
    World:PressF4( Specs[ 2 ] )

    World:Respond( 200, { next = 1, offer = { id = "o-1", target = "1.2.3.4:27015",
        players = { Specs[ 1 ].SteamID, Specs[ 2 ].SteamID } } } )
    AssertEquals( nil, Plugin.Timers.SeedUpdate, "the stale reply does not restart the heartbeat" )
    AssertEquals( 0, CountMessages( World, Specs[ 2 ].SteamID, "SeedOffer" ), "nor is it handled" )

    World:Tick( 1 )
    AssertEquals( 1, CountMessages( World, Specs[ 1 ].SteamID, "SeedActive" ), "the tick leaves clients alone" )

    Reload( World, { Enabled = true } )
    AssertEquals( nil, Plugin.SeedOnline, "online again only once a heartbeat gets through" )
    World:Tick( 1 )
    AssertEquals( 1, #World.HTTPRequests, "the heartbeat starts again" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a client that vanished without a disconnect is dropped from the active clients", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 2 )

    Heartbeat( World )
    World:Tick( 1 )
    AssertTrue( Plugin.SeedActiveClients[ Specs[ 1 ] ], "S1 is active" )

    -- The engine dropped the connection without the disconnect hook running.
    SilentlyRemove( World, Specs[ 1 ] )
    Specs[ 1 ]:SetIsSpectator( false )
    World:Tick( 1 )

    AssertEquals( nil, Plugin.SeedActiveClients[ Specs[ 1 ] ], "the stale client is dropped" )
    AssertEquals( 1, CountMessages( World, Specs[ 1 ].SteamID, "SeedActive" ), "and sent nothing" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "map change restore: a restored player keeps the time they already waited", function()
    local Old = NewSeedWorld()
    local Specs = QueueSpectators( Old, 2 )
    Old:Tick( 30 )
    local Late = Old:AddSpectator{ Name = "Late" }
    Old:PressF4( Late )
    Old:Tick( 70 )
    Old.Plugin:MapChange()

    -- The next map is up 20 s later, its game time starts over.
    local World = NewSeedWorld( nil, { Files = Old.Files, SystemTime = Old.SystemTime + Old.Time + 20 } )
    FillTeams( World, 4 )
    local Back = World:AddSpectator{ SteamID = Specs[ 1 ].SteamID, Name = "Back" }
    local LateBack = World:AddSpectator{ SteamID = Late.SteamID, Name = "LateBack" }
    World.Plugin:ReceiveSeedPref( Back, { Pref = "ask" } )
    World.Plugin:ReceiveSeedPref( LateBack, { Pref = "ask" } )
    AssertTrue( NotifiedWith( World, Back.SteamID, "QUEUE_WELCOME_BACK" ), "the position is restored" )

    World:Tick( 5 )
    local Payload = Heartbeat( World )
    AssertEquals( 125, FindEntry( Payload, Back.SteamID ).wait, "100 s before the map change, 20 s loading, 5 s since" )
    AssertEquals( 95, FindEntry( Payload, LateBack.SteamID ).wait, "Late queued 70 s before the map change" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a player back from a seed keeps the time they already waited", function()
    local World = NewSeedWorld{ HopReturnTime = 180 }
    local A = QueueSpectators( World, 2 )[ 1 ]

    World:Tick( 40 )
    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )

    World:Tick( 60 )
    local Back = World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }
    World.Plugin:ReceiveSeedPref( Back, { Pref = "ask" } )

    AssertEquals( 100, FindEntry( Heartbeat( World ), A.SteamID ).wait, "the wait carries on across the hop" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a hop hold outlives the map change reservation that runs out during it", function()
    local Old = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = Old
    FillTeams( Old, 4 )
    local Gone = Old:AddSpectator{ SteamID = 777001, Name = "Gone" }
    Old:PressF4( Gone )
    Old.Plugin:MapChange()

    local World = NewSeedWorld( { HopReturnTime = 180 },
        { Files = Old.Files, SystemTime = Old.SystemTime + Old.Time + 10 } )
    local Specs = QueueSpectators( World, 2 )
    local A, B = Specs[ 1 ], Specs[ 2 ]
    AssertList( { Gone.SteamID, A.SteamID, B.SteamID }, World:QueueIDs(), "Gone's restored entry is ahead" )

    World:Tick( 200 )
    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )

    -- 301 s: the map change reservation is over, A's hold runs until 380 s.
    World:Tick( 101 )
    AssertList( { A.SteamID, B.SteamID }, World:QueueIDs(), "Gone is dropped, A's entry is still held" )

    World:Tick( 49 )
    World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }
    AssertList( { A.SteamID, B.SteamID }, World:QueueIDs(), "A is back at the front" )
    AssertTrue( NotifiedWith( World, A.SteamID, "QUEUE_WELCOME_BACK" ), "A is told their position is restored" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a second hop is not cut short by the first hop's timer", function()
    local World = NewSeedWorld{ HopReturnTime = 180 }
    local Specs = QueueSpectators( World, 2 )
    local A, B = Specs[ 1 ], Specs[ 2 ]

    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )

    World:Tick( 60 )
    local Back = World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }
    World.Plugin:ReceiveSeedPref( Back, { Pref = "always" } )

    World:Tick( 40 )
    Heartbeat( World, { next = 10, commit = { id = "o-2", target = "5.6.7.8:27015", players = { A.SteamID } } } )
    AssertList( { "connect 1.2.3.4:27015", "connect 5.6.7.8:27015" }, Connects( World, A.SteamID ), "A hops twice" )
    World:Disconnect( Back )

    -- 181 s: the first hold would have run out, the second one runs until 280 s.
    World:Tick( 81 )
    AssertList( { A.SteamID, B.SteamID }, World:QueueIDs(), "the second hold is still on" )

    World:Tick( 100 )
    AssertList( { B.SteamID }, World:QueueIDs(), "the second hold runs out on its own time" )
end )

-- --------------------------------------------------------------------------------------------------
-- Also passes against develop's server.lua, which never times restored entries.
Test( "map change restore: a restored player's wait stays out of the average wait time", function()
    local Old = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = Old
    FillTeams( Old, 4 )
    local A = Old:AddSpectator{ SteamID = 777101, Name = "A" }
    Old:PressF4( A )
    Old:Tick( 100 )
    Old.Plugin:MapChange()

    local World = Mocks.NewWorld{ MaxPlayers = 4, Files = Old.Files, SystemTime = Old.SystemTime + Old.Time + 20 }
    CurrentWorld = World
    local Players = FillTeams( World, 4 )
    local Back = World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }
    World:Tick( 5 )
    World:Disconnect( Players[ 1 ] )

    AssertFalse( Back:GetIsSpectator(), "the restored player gets the slot" )
    AssertEquals( 0, World.Plugin.AVGWaitTimeSampleSize, "their wait is not sampled" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a player back from a seed stays out of the average wait time", function()
    local World = NewSeedWorld{ HopReturnTime = 180 }
    local Specs, Players = QueueSpectators( World, 2 )
    local A, B = Specs[ 1 ], Specs[ 2 ]

    World.Plugin:ReceiveSeedPref( A, { Pref = "always" } )
    Heartbeat( World, { next = 10, commit = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID } } } )
    World:Disconnect( A )
    World:Tick( 60 )
    local Back = World:AddSpectator{ SteamID = A.SteamID, Name = "Back" }

    World:Disconnect( Players[ 1 ] )
    AssertFalse( Back:GetIsSpectator(), "A gets the slot back at the front" )
    AssertEquals( 0, World.Plugin.AVGWaitTimeSampleSize, "the seed trip is not sampled" )

    World:Disconnect( Players[ 2 ] )
    AssertFalse( B:GetIsSpectator(), "B gets the next slot" )
    AssertEquals( 1, World.Plugin.AVGWaitTimeSampleSize, "B's wait is sampled as before" )
    AssertEquals( 60, World.Plugin.AVGWaitTime, "B waited 60 s" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: a new offer closes the one a player still has open", function()
    local World = NewSeedWorld()
    local Plugin = World.Plugin
    local Specs = QueueSpectators( World, 2 )
    local A, B = Specs[ 1 ], Specs[ 2 ]

    Heartbeat( World, { next = 3, offer = { id = "o-1", target = "1.2.3.4:27015", players = { A.SteamID, B.SteamID } } } )
    Plugin:ReceiveSeedAnswer( A, { Accept = true } )

    Heartbeat( World, { next = 3, offer = { id = "o-2", target = "5.6.7.8:27015", players = { A.SteamID } } } )
    AssertList( { "aborted" }, ClosedReasons( World, A.SteamID ), "A's first offer is closed" )
    AssertEquals( 2, CountMessages( World, A.SteamID, "SeedOffer" ), "before the second is shown" )
    AssertEquals( nil, FindEntry( Heartbeat( World ), A.SteamID ).answer, "the answer to the first is dropped" )

    Plugin:ReceiveSeedAnswer( A, { Accept = true } )
    Heartbeat( World, { next = 10, commit = { id = "o-2", target = "5.6.7.8:27015", players = { A.SteamID } } } )
    Heartbeat( World, { next = 10, abort = { id = "o-1" } } )

    AssertList( { "aborted", "committed" }, ClosedReasons( World, A.SteamID ), "one close per offer" )
    AssertList( { "aborted" }, ClosedReasons( World, B.SteamID ), "B's offer is closed by its own abort" )
end )

-- --------------------------------------------------------------------------------------------------
Test( "config: older configs migrate to the current version without validation errors", function()
    local World = Mocks.NewWorld()
    CurrentWorld = World
    local Plugin = World.Plugin

    local Versions = {
        { "1.0", { "Debug", "ReadyRoomGracePeriod", "GlobalQueue" } },
        { "1.1", { "GlobalQueue" } }
    }

    for i = 1, #Versions do
        local Version, Missing = Versions[ i ][ 1 ], Versions[ i ][ 2 ]
        local Config = Mocks.DeepCopy( Plugin.DefaultConfig )
        Config.__Version = Version
        for j = 1, #Missing do
            Config[ Missing[ j ] ] = nil
        end

        -- base_plugin/config.lua ValidateConfigAfterLoad: the migration, then both validator rules.
        Shine.ApplyConfigMigration( Config, {
            NewVersion = Plugin.Version,
            CurrentVersion = Shine.VersionHolder( Version ),
            MigrationSteps = Plugin.ConfigMigrationSteps
        } )
        AssertEquals( Plugin.Version, Config.__Version, Version .. ": the version is bumped" )
        AssertFalse( Shine.VerifyConfig( Config, Plugin.DefaultConfig, { __Version = true } ),
            Version .. ": the migration must leave nothing for validation to add or remove" )
        AssertFalse( Plugin:TypeCheckConfig( Config ), Version .. ": nothing may be mistyped" )
    end
end )

-- --------------------------------------------------------------------------------------------------
Test( "seed: an unreachable coordinator is retried and never activates clients", function()
    Mocks.CoordinatorDown = true
    local Ok, Err = pcall( function()
        local World = Mocks.NewWorld{ MaxPlayers = 4 }
        CurrentWorld = World
        local Specs, Players = QueueSpectators( World, 2 )

        for _ = 1, 70 do
            World:Tick( 1 )
        end
        AssertTrue( ( World.HTTPFailures or 0 ) >= 2, "the heartbeat keeps being retried" )
        AssertEquals( 0, CountMessages( World, Specs[ 1 ].SteamID, "SeedActive" ), "clients are not activated" )

        World:Disconnect( Players[ 1 ] )
        AssertEquals( kTeamReadyRoom, Specs[ 1 ]:GetControllingPlayer():GetTeamNumber(), "the queue still pops" )
    end )
    Mocks.CoordinatorDown = false
    if not Ok then error( Err, 0 ) end
end )

-- --------------------------------------------------------------------------------------------------
kRookieLevel = 10
kRookieOnlyLevel = 5

local function LoadClientPlugin()
    local VoteMenu, Validator = Shine.VoteMenu, Shine.Validator
    -- votemenu_gui.lua:331, EditPage on a page nobody added yet adds it.
    local Pages = {}
    local function AddPage( _, Name, Populate ) Pages[ Name ] = Populate end
    Shine.VoteMenu = { AddPage = AddPage, EditPage = AddPage, SetPage = function() end, Visible = true }
    Shine.Validator = function()
        return { AddFieldRule = function() end, InEnum = function() end }
    end

    local ClientPlugin = {}
    local Ok, Err = pcall( assert( loadfile( Mocks.PluginDir .. "client.lua" ) ), ClientPlugin )

    Shine.VoteMenu, Shine.Validator = VoteMenu, Validator
    if not Ok then error( Err, 0 ) end

    return ClientPlugin, Pages
end

-- Runs a vote menu page's populate function against a menu that records its buttons.
local function PopulatePage( Populate )
    local Menu = { Side = {}, Bottom = {} }
    function Menu:AddSideButton( Text, DoClick ) self.Side[ #self.Side + 1 ] = { Text = Text, DoClick = DoClick } end
    function Menu:AddBottomButton( Text, DoClick ) self.Bottom[ #self.Bottom + 1 ] = { Text = Text, DoClick = DoClick } end
    function Menu:SetPage( Name ) self.Page = Name end

    Populate( Menu )

    local Side = {}
    for i = 1, #Menu.Side do
        Side[ i ] = Menu.Side[ i ].Text
    end
    return Menu, Side
end

-- --------------------------------------------------------------------------------------------------
Test( "scoreboard: the queue order lists client IDs in queue order and is cut at an entry boundary", function()
    local World = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = World

    FillTeams( World, 4 )
    local First = World:AddSpectator{ Name = "First" }
    local Second = World:AddSpectator{ Name = "Second" }
    World:PressF4( First )
    World:PressF4( Second )
    World.Plugin.PlayerQueue:Add( 999999, 3 )

    World.Plugin:UpdateQueueOrder()
    local Full = First:GetId() .. "," .. Second:GetId() .. ",-"
    AssertEquals( Full, World.Plugin.dt.QueueOrder, "client IDs in queue order, '-' for an absent entry" )

    World.Plugin.MaxQueueOrderLength = #Full
    World.Plugin:UpdateQueueOrder()
    AssertEquals( First:GetId() .. "," .. Second:GetId(), World.Plugin.dt.QueueOrder,
        "the variable keeps one byte less than its size, the last entry does not fit" )

    World.Plugin.MaxQueueOrderLength = #Full - 1
    World.Plugin:UpdateQueueOrder()
    AssertEquals( First:GetId() .. "," .. Second:GetId(), World.Plugin.dt.QueueOrder,
        "a limit ending on an entry boundary keeps that entry" )

    World.Plugin.MaxQueueOrderLength = #tostring( First:GetId() ) + 2
    World.Plugin:UpdateQueueOrder()
    AssertEquals( tostring( First:GetId() ), World.Plugin.dt.QueueOrder, "a partial client ID is never sent" )
end )

Test( "afk guard: queued players are partially immune, cleanup restores afkkick", function()
    local Original = function( _, Client ) return Client.Immune == true end
    local AFKKick = { IsClientPartiallyImmune = Original }
    local World = Mocks.NewWorld{ MaxPlayers = 4, Plugins = { afkkick = AFKKick } }
    CurrentWorld = World

    FillTeams( World, 4 )
    local Queued = World:AddSpectator{ Name = "Queued" }
    local Idle = World:AddSpectator{ Name = "Idle" }
    World:PressF4( Queued )

    AssertTrue( AFKKick:IsClientPartiallyImmune( Queued ), "a queued player must be immune" )
    AssertFalse( AFKKick:IsClientPartiallyImmune( Idle ), "a player outside the queue must not be" )
    Idle.Immune = true
    AssertTrue( AFKKick:IsClientPartiallyImmune( Idle ), "afkkick's own immunity must still apply" )

    World.Plugin:Cleanup()
    AssertEquals( Original, AFKKick.IsClientPartiallyImmune, "cleanup must restore the original method" )

    local Late = Mocks.NewWorld{ MaxPlayers = 4 }
    CurrentWorld = Late
    local LateAFKKick = { IsClientPartiallyImmune = Original }
    Shine.Plugins.afkkick = LateAFKKick
    Late.Plugin:OnPluginLoad( "afkkick" )
    AssertTrue( LateAFKKick.IsClientPartiallyImmune ~= Original, "an afkkick loaded later must be patched as well" )

    local Off = Mocks.NewWorld{ MaxPlayers = 4, Plugins = { afkkick = { IsClientPartiallyImmune = Original } },
        Config = { ProtectQueuedFromAFKKick = false } }
    CurrentWorld = Off
    AssertEquals( Original, Shine.Plugins.afkkick.IsClientPartiallyImmune, "the config switch must disable the patch" )
end )

Test( "scoreboard client: ready room rows of queued players show their queue position", function()
    local Plugin = LoadClientPlugin()
    Plugin.dt = { QueueOrder = "7,-,9" }

    local function Row( ClientIndex )
        local Status = { Text = "" }
        function Status:SetText( Text ) self.Text = Text end
        return { ClientIndex = ClientIndex, Status = Status }
    end
    local Rows = { Row( 7 ), Row( 8 ), Row( 9 ) }

    Plugin:OnGUIScoreboardUpdateTeam( nil, { TeamNumber = kTeam1Index, PlayerList = Rows } )
    AssertEquals( "", Rows[ 1 ].Status.Text, "only the ready room is annotated" )

    Plugin:OnGUIScoreboardUpdateTeam( nil, { TeamNumber = kTeamReadyRoom, PlayerList = Rows } )
    AssertEquals( "Queue: 1", Rows[ 1 ].Status.Text, "first in the queue" )
    AssertEquals( "", Rows[ 2 ].Status.Text, "a player outside the queue is left alone" )
    AssertEquals( "Queue: 3", Rows[ 3 ].Status.Text, "an absent entry ahead still counts as a position" )
end )

-- Transcribed from ns2/lua/menu2/NavBar/Screens/ServerBrowser/GMSBEntry.lua UpdateServerRanking, with the
-- serverEntry and profile getters replaced by fields of e.
local function GMSBEntryRanking( e )
    local exp = math.exp
    local sqrt = math.sqrt
    local players = e.Players
    local maxplayer = e.MaxPlayers - e.Reserved

    local playerskill = e.PlayerSkill
    local playerlevel = e.PlayerLevel
    local playertier = e.PlayerTier

    local viability = 1/(1 + exp( -0.5 * (players - 12)))
    local dViability = (201.714 * exp(0.5 * players))/(403.429 + exp(0.5 * players))^2
    local player = 0.5 * viability + 0.5 * dViability *  math.max(0, math.min(maxplayer, 24) - players - 1)

    local ping = 1 / (1 + exp( 1/40 * (e.Ping - 150)))
    local skill = (players < 2 or playerskill == -1) and 1 or exp(- 0.1 * math.abs(e.ServerSkill - playerskill) * sqrt(players - 1) / 346.41)

    local perfscore = e.PerfScore * e.PerfQuality / 100
    local perf = 1/(1 + exp( - perfscore / 5 ))

    local empty = players > 0 and 1 or 0.5
    local fav = e.Favorite and 2 or 1
    local blocked = e.Blocked and 0.000001 or 1
    local full = players >= maxplayer and not e.Favorite and 0.5 or 1
    local joinable = (not e.Passworded or e.Favorite or e.Friends) and 1 or 0.02
    local friend = e.Friends and 1.2 or 1
    local ranked = e.Mode == "ns2" and e.Ranked and 1.5 or 1

    local rookieonly = joinable == 1 and 0.3 or 1
    if e.RookieOnly then
        if playerlevel == -1 or playerlevel < kRookieLevel or playertier <= kRookieMaxSkillTier then
            rookieonly = 1 + (1/exp(0.125*(playerlevel - kRookieOnlyLevel)))
        end
    else
        if playerlevel == -1 or playerlevel > kRookieOnlyLevel then
            rookieonly = 1
        end
    end

    local history = e.Historical and e.Now - e.LastConnect <= 600 and 0.5 or 1
    local arcade = e.Mode == "ns2" and 1.0 or 0.6

    return player * ping * perf * skill * full * joinable * empty * fav * blocked * friend * rookieonly * ranked * history * arcade
end

local function ScoreInputs( Overrides )
    local Inputs = {
        Players = 12, MaxPlayers = 24, Reserved = 2, Ping = 60, MaxPing = 150, PerfScore = 30, PerfQuality = 80,
        Mode = "ns2", Ranked = true, Passworded = false, Favorite = false, Blocked = false, Friends = false,
        RookieOnly = false, Historical = false, LastConnect = 0, Now = 10000,
        PlayerSkill = 1500, ServerSkill = 1200, PlayerLevel = 30, PlayerTier = 5
    }
    for Key, Value in pairs( Overrides or {} ) do
        Inputs[ Key ] = Value
    end
    return Inputs
end

Test( "seed: ScoreCandidate without seed adaptations matches GMSBEntry's ranking", function()
    local Score = LoadClientPlugin().ScoreCandidate

    local Cases = {
        {},
        { Players = 0 },
        { Players = 1, PlayerSkill = -1 },
        { Players = 24, MaxPlayers = 24, Reserved = 0 },
        { Players = 24, MaxPlayers = 24, Reserved = 0, Favorite = true },
        { Passworded = true },
        { Passworded = true, Friends = true },
        { Blocked = true },
        { Ping = 250, PerfScore = -20 },
        { Mode = "combat", Ranked = true },
        { Historical = true, LastConnect = 9500 },
        { Historical = true, LastConnect = 9000 },
        { RookieOnly = true, PlayerLevel = 3, PlayerTier = 1 },
        { RookieOnly = true, PlayerLevel = 40, PlayerTier = 6 },
        { PlayerLevel = 4 },
        { PlayerLevel = -1, Friends = true }
    }

    for i = 1, #Cases do
        local Inputs = ScoreInputs( Cases[ i ] )
        local Expected = GMSBEntryRanking( Inputs )
        local Actual = Score( Inputs )
        if math.abs( Expected - Actual ) > 1e-12 * math.max( 1, math.abs( Expected ) ) then
            Fail( "case " .. i .. ": expected " .. Expected .. ", got " .. Actual )
        end
    end
end )

Test( "seed: ScoreCandidate with seed adaptations gates and neutralises", function()
    local Score = LoadClientPlugin().ScoreCandidate

    AssertEquals( 0, Score( ScoreInputs{ Seed = true, Blocked = true } ), "a blocked server scores 0" )
    AssertEquals( 0, Score( ScoreInputs{ Seed = true, Passworded = true } ), "a passworded server scores 0" )
    AssertEquals( 0, Score( ScoreInputs{ Seed = true, Ping = 151 } ), "a ping over maxPing scores 0" )
    AssertTrue( Score( ScoreInputs{ Seed = true, Ping = 150 } ) > 0, "a ping at maxPing still counts" )

    -- With every population factor already neutral, the seed score must be the browser's score.
    local Neutral = { PlayerSkill = -1, PlayerLevel = -1 }
    local Raw = Score( ScoreInputs( Neutral ) )
    Neutral.Seed = true
    AssertTrue( math.abs( Raw - Score( ScoreInputs( Neutral ) ) ) < 1e-12, "seed and browser agree when neutral" )

    AssertTrue( Score( ScoreInputs{ Seed = true, Favorite = true } ) > Score( ScoreInputs{ Seed = true } ),
        "a favourite ranks higher" )
    AssertTrue( Score( ScoreInputs{ Seed = true, Historical = true, LastConnect = 9500 } )
        < Score( ScoreInputs{ Seed = true } ), "a server left minutes ago ranks lower" )
end )

-- The client plugin with the parts of the Shine plugin surface the seed code uses.
local function NewClientPlugin()
    local Plugin, Pages = LoadClientPlugin()
    Plugin.Config = { SeedPref = Plugin.SeedPrefType.ASK }
    Plugin.Sent, Plugin.Notes, Plugin.Timers = {}, {}, {}

    function Plugin:SendNetworkMessage( Name, Data ) self.Sent[ #self.Sent + 1 ] = { Name = Name, Data = Data } end
    function Plugin:GetPhrase( Key ) return Key end
    function Plugin:GetInterpolatedPhrase( Key ) return Key end
    function Plugin:Notify( Message ) self.Notes[ #self.Notes + 1 ] = Message end
    function Plugin:CreateTimer( Name ) self.Timers[ Name ] = true end
    function Plugin:DestroyTimer( Name ) self.Timers[ Name ] = nil end

    return Plugin, Pages
end

-- Engine globals that only exist on the client, set for the duration of Func.
local function WithClientGlobals( Globals, Func )
    local Saved = {}
    for Key, Value in pairs( Globals ) do
        Saved[ Key ] = rawget( _G, Key )
        _G[ Key ] = Value
    end

    local Ok, Err = pcall( Func )

    for Key in pairs( Globals ) do
        _G[ Key ] = Saved[ Key ]
    end

    if not Ok then error( Err, 0 ) end
end

Test( "seed client: an offer is ignored while seeding is off or the preference is never", function()
    local Plugin = NewClientPlugin()
    local Shown = 0
    Shine.ScreenText = { Add = function() Shown = Shown + 1 end, Remove = function() end }

    WithClientGlobals( { Client = { WindowNeedsAttention = function() end } }, function()
        local Offer = { Name = "Target", Address = "1.2.3.4:27015", Count = 12, Time = 18 }

        Plugin:ReceiveSeedOffer( Offer )
        AssertEquals( nil, Plugin.SeedOffer, "no offer while seeding is off" )

        Plugin.SeedURL = "https://coordinator"
        Plugin.Config.SeedPref = Plugin.SeedPrefType.NEVER
        Plugin:ReceiveSeedOffer( Offer )
        AssertEquals( nil, Plugin.SeedOffer, "no offer for a never player" )
        AssertEquals( 0, Shown, "nothing was shown" )

        Plugin.Config.SeedPref = Plugin.SeedPrefType.ASK
        Plugin:ReceiveSeedOffer( Offer )
        AssertEquals( Offer, Plugin.SeedOffer, "an ask player is shown the offer" )
        AssertEquals( 1, Shown, "on screen" )

        Plugin:ReceiveSeedClosed{ Reason = "declined" }
        AssertEquals( nil, Plugin.SeedOffer, "a close removes the offer" )
        AssertList( { "SEED_CLOSED_DECLINED" }, Plugin.Notes, "with the reason's phrase" )
    end )

    local File = assert( io.open( "locale/shine/extensions/readyroomqueue/enGB.json" ) )
    local Locale = json.decode( File:read( "*a" ) )
    File:close()
    for _, Reason in ipairs{ "committed", "declined", "aborted" } do
        AssertTrue( Locale[ "SEED_CLOSED_" .. Reason:upper() ], Reason .. " needs a phrase" )
    end
end )

Test( "seed client: one main menu entry, the preference page stays reachable during an offer", function()
    local Plugin, Pages = NewClientPlugin()
    Plugin.Enabled = true

    local Main, Side = PopulatePage( Pages.Main )
    AssertList( {}, Side, "no entry while seeding is off" )

    Plugin.SeedURL = "https://coordinator"
    Main, Side = PopulatePage( Pages.Main )
    AssertList( { "SEED_PREF_BUTTON" }, Side, "the preference page without an offer" )
    Main.Side[ 1 ].DoClick()
    AssertEquals( "SeedPref", Main.Page, "which it opens" )

    Plugin.SeedOffer = { Name = "Target", Address = "1.2.3.4:27015", Count = 12, Time = 18 }
    Main, Side = PopulatePage( Pages.Main )
    AssertList( { "SEED_OFFER_BUTTON" }, Side, "the offer while one is open" )
    AssertEquals( 0, #Main.Bottom, "the bottom slot is left to other plugins" )

    local Offer
    Offer, Side = PopulatePage( Pages.SeedOffer )
    AssertList( { "SEED_YES", "SEED_NO", "SEED_PREF_BUTTON" }, Side, "the offer page answers and links on" )
    Offer.Side[ 3 ].DoClick()
    AssertEquals( "SeedPref", Offer.Page, "to the preference page" )

    Plugin.SeedOffer.Answered = true
    Offer, Side = PopulatePage( Pages.SeedOffer )
    AssertList( { "SEED_PREF_BUTTON" }, Side, "an answered offer only links on" )
end )

Test( "seed client: candidates without a score are refreshed again, a new list starts over", function()
    local World = Mocks.NewWorld()
    CurrentWorld = World
    local Plugin = NewClientPlugin()
    Plugin.SeedURL = "https://coordinator"

    local Refreshes = {}
    local Info = { ping = 50, maxPlayers = 24, numReservedSlots = 2, performanceScore = 30,
        performanceQuality = 80, mode = "ns2" }

    local function Refresh( Version )
        Refreshes = {}
        Plugin:RefreshSeedCandidates()
        -- The retail engine's callback gets the body alone.
        World:Respond( nil, { version = Version, groupSize = 12, maxPing = 150, candidates = {
            { address = "1.1.1.1:27015" }, { address = "2.2.2.2:27015" }, { address = "3.3.3.3:27015" }
        } } )

        local Addresses = {}
        for i = 1, #Refreshes do
            Addresses[ i ] = Refreshes[ i ].Address
        end
        return Addresses
    end

    WithClientGlobals( {
        Client = {
            -- The engine never calls back when the query fails.
            RefreshServer = function( Address, Callback )
                Refreshes[ #Refreshes + 1 ] = { Address = Address, Callback = Callback }
            end
        },
        LoadConfigFile = function( Name )
            if Name == "BlockedServers.json" then
                return { { address = "3.3.3.3:27015" } }
            end
        end
    }, function()
        AssertList( { "1.1.1.1:27015", "2.2.2.2:27015" }, Refresh( "c-1" ), "the usable candidates are refreshed" )
        local FirstList = Refreshes
        FirstList[ 1 ].Callback( Info )

        AssertList( { "2.2.2.2:27015" }, Refresh( "c-1" ), "the same list refreshes only the unscored candidate" )
        Refreshes[ 1 ].Callback( Info )
        AssertList( {}, Refresh( "c-1" ), "a fully scored list refreshes nothing" )

        AssertList( { "1.1.1.1:27015", "2.2.2.2:27015" }, Refresh( "c-2" ), "a new list is scored from scratch" )
        FirstList[ 2 ].Callback( Info )
    end )

    local Sent = {}
    for i = 1, #Plugin.Sent do
        local Data = Plugin.Sent[ i ].Data
        Sent[ i ] = Data.Address .. ( Data.Score > 0 and " + " or " 0 " ) .. Data.Version
    end
    AssertList( {
        "3.3.3.3:27015 0 c-1", "1.1.1.1:27015 + c-1", "2.2.2.2:27015 + c-1", "3.3.3.3:27015 0 c-2"
    }, Sent, "each candidate is scored once per list and a late answer for an old list is dropped" )
end )

-- --------------------------------------------------------------------------------------------------
for i = 1, #Registered do
    RunTest( Registered[ i ].Name, Registered[ i ].Func )
end

-- The queue must behave exactly the same with the global seed queue on and its coordinator unreachable.
Mocks.CoordinatorDown = true
for i = 1, QueueTestCount do
    RunTest( "[coordinator down] " .. Registered[ i ].Name, Registered[ i ].Func )
end
Mocks.CoordinatorDown = false

print( "" )
print( string.format( "%d passed, %d failed", Passed, Failed ) )

if Failed > 0 then
    for i = 1, #FailureLines do
        print( "failed: " .. FailureLines[ i ] )
    end
    os.exit( 1 )
end

os.exit( 0 )
