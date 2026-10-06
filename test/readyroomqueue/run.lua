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

local function NewSeedWorld( Config )
    local GlobalQueue = { Enabled = true }
    for Key, Value in pairs( Config or {} ) do
        GlobalQueue[ Key ] = Value
    end

    local World = Mocks.NewWorld{ MaxPlayers = 4, Config = { GlobalQueue = GlobalQueue } }
    CurrentWorld = World

    -- The tests drive the coordinator round trips themselves.
    World.Plugin.Timers.SeedUpdate = nil

    return World
end

local function QueueSpectators( World, Count )
    local Players = FillTeams( World, 4 )
    local Specs = {}
    for i = 1, Count do
        Specs[ i ] = World:AddSpectator{ Name = "S" .. i }
        World:PressF4( Specs[ i ] )
    end
    return Specs, Players
end

-- Runs one heartbeat and answers it with Reply. Returns the decoded payload and the request.
local function Heartbeat( World, Reply )
    World.Plugin:SeedUpdate()
    local Request = World:Respond( 200, Reply or { next = 10 } )
    AssertTrue( Request.URL:find( "/seedqueue/heartbeat", 1, true ), "expected a heartbeat, got " .. Request.URL )
    return json.decode( Request.Params.data ), Request
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

    Plugin:ReceiveSeedPref( Specs[ 1 ], { Pref = "always" } )
    Plugin:ReceiveSeedPref( Specs[ 2 ], { Pref = "bogus" } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "1.2.3.4:27015", Score = 1.23456 } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "5.6.7.8:27015", Score = 0 } )
    Plugin:ReceiveSeedScore( Specs[ 1 ], { Address = "connect evil", Score = 2 } )
    Plugin:ReceiveSeedScore( Specs[ 2 ], { Address = "1.2.3.4:27015", Score = 0 / 0 } )

    World:Tick( 10 )

    local Payload, Request = Heartbeat( World )
    AssertEquals( "POST", Request.Method, "the heartbeat is a form POST" )

    AssertEquals( 1, Payload.v, "contract version" )
    AssertEquals( "Mock Server", Payload.name, "server name" )
    AssertEquals( 27015, Payload.port, "the game port identifies this server" )
    AssertEquals( 4, Payload.players, "bots and spectators are not counted as players" )
    AssertEquals( 4, Payload.maxPlayers, "max players" )
    AssertEquals( true, Payload.matching, "matching follows the config" )

    AssertEquals( 2, #Payload.queue, "both queued players must be listed" )
    local First, Second = Payload.queue[ 1 ], Payload.queue[ 2 ]
    AssertEquals( Specs[ 1 ].SteamID, First.id, "queue order" )
    AssertEquals( Specs[ 2 ].SteamID, Second.id, "queue order" )
    AssertEquals( 10, First.wait, "wait time" )
    AssertEquals( "always", First.pref, "preference" )
    AssertEquals( "ask", Second.pref, "an invalid preference is ignored" )
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
    AssertEquals( 1, CountMessages( World, B.SteamID, "SeedAbort" ), "B's prompt is closed" )
    AssertEquals( 0, CountMessages( World, A.SteamID, "SeedAbort" ), "A is on the way, not aborted" )

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
    AssertEquals( 1, CountMessages( World, B.SteamID, "SeedAbort" ), "B's prompt is closed" )
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

    AssertEquals( 1, CountMessages( World, A.SteamID, "SeedAbort" ), "A is told once" )
    AssertEquals( 1, CountMessages( World, B.SteamID, "SeedAbort" ), "B is told once" )
    AssertEquals( 0, CountMessages( World, Specs[ 3 ].SteamID, "SeedAbort" ), "others are not told" )
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
    Shine.VoteMenu = { AddPage = function() end, EditPage = function() end }
    Shine.Validator = function()
        return { AddFieldRule = function() end, InEnum = function() end }
    end

    local ClientPlugin = {}
    local Ok, Err = pcall( assert( loadfile( Mocks.PluginDir .. "client.lua" ) ), ClientPlugin )

    Shine.VoteMenu, Shine.Validator = VoteMenu, Validator
    if not Ok then error( Err, 0 ) end

    return ClientPlugin
end

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
