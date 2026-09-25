local Max = math.max
local Min = math.min
local StringFormat = string.format
local TableEmpty = table.Empty
local TableQuickCopy = table.QuickCopy

local Plugin = ...
Plugin.PrintName = "Ready Room Queue"

Plugin.HasConfig = true

Plugin.ConfigName = "ReadRoomQueue.json"
Plugin.DefaultConfig = {
    RestoreQueueAfterMapchange = true,
    Debug = false,
    QueuePositionMaxReservationTime = 300, -- how long we reserve a queue position after a map change.
    QueueHistoryLifeTime = 300, -- max amount of time the queue history is preserved after a mapchange. Increase/decrease this value based on server loading time
    ReadyRoomGracePeriod = {
        -- Players that leave a playing team keep holding on to their player slot. While others are waiting
        -- in the queue they only keep it for Time seconds, after that the slot is handed to the queue.
        Enabled = true,
        Time = 90,
        EnqueueOnExpiry = true -- add them to the queue rather than dropping them out of it entirely
    },
    VIPPlayers = {
        Enabled = false,
        PermissionString = "sh_vip"
    }
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = true

Plugin.QueueHistoryFile = "config://shine/temp/rr_queue_history.json"
Plugin.QueueWaitTimeHistoryFile = "config://shine/temp/rr_queue_wait_time_history.json"

-- How often we look for free player slots that nobody claimed and for expired ready room grace periods.
Plugin.TickInterval = 1

Plugin.MaxWaitTimeSamples = 20

function Plugin:Initialise()
    -- Using Map instead of Set because Set doesn't provide any easy way to get a value's current position
    -- and Queue doesn't allow to insert at a specific position without iterating over the all elements
    self.PlayerQueue = Shine.Map()
    self.ReservedQueue = Shine.Map() -- for players with reserved slots

    -- SteamID -> time at which the player loses the player slot they are holding on to in the ready room.
    -- Kept plugin side rather than on the client so it can never survive a map change.
    self.GraceExpiries = {}

    self:LoadQueueHistory()

    self:LoadWaitTimeHistory()

    self:CreateCommands()

    self:CreateTimer( "RRQueueTick", self.TickInterval, -1, function()
        self:OnTick()
    end )

    return true
end

-- Shine's recursive check walks the old value after replacing a mistyped table, so fix the top level first.
function Plugin:TypeCheckConfig( Config )
    local Edited = Shine.TypeCheckConfig( self.__Name, Config, self.DefaultConfig )
    return Shine.TypeCheckConfig( self.__Name, Config, self.DefaultConfig, true ) or Edited
end

function Plugin:DebugPrint( Message, ... )
    if not self.Config.Debug then return end

    self:Print( Message, true, ... )
end

function Plugin:LoadWaitTimeHistory()
    local WaitTimeHistory = Shine.LoadJSONFile( self.QueueWaitTimeHistoryFile ) or {}

    self.AVGWaitTime = tonumber( WaitTimeHistory.AVGWaitTime ) or 0
    self.AVGWaitTimeSampleSize = Max( tonumber( WaitTimeHistory.SampleSize ) or 0, 0 )
end

function Plugin:UpdateWaitTimeHistory( WaitTime )
    local SampleSize = Min( self.AVGWaitTimeSampleSize + 1, self.MaxWaitTimeSamples )

    self.AVGWaitTime = self.AVGWaitTime + ( WaitTime - self.AVGWaitTime ) / SampleSize
    self.AVGWaitTimeSampleSize = SampleSize

    Shine.SaveJSONFile( {
        AVGWaitTime = self.AVGWaitTime,
        SampleSize = self.AVGWaitTimeSampleSize
    }, self.QueueWaitTimeHistoryFile )
end

function Plugin:LoadQueueHistory()
    self.HistoricPlayers = Shine.Set()

    if not self.Config.RestoreQueueAfterMapchange then return end

    local QueueHistory = Shine.LoadJSONFile( self.QueueHistoryFile ) or {}

    local TimeStamp = tonumber( QueueHistory.TimeStamp )
    if not TimeStamp or TimeStamp + self.Config.QueueHistoryLifeTime < Shared.GetSystemTime() then
        return
    end

    Shine.SaveJSONFile( {}, self.QueueHistoryFile )

    local PlayerQueue = QueueHistory.PlayerQueue or {}
    for i = 1, #PlayerQueue do
        local SteamID = PlayerQueue[ i ]
        self.PlayerQueue:Add( SteamID, self.PlayerQueue:GetCount() + 1 )
        self.HistoricPlayers:Add( SteamID )
    end

    local ReservedQueue = QueueHistory.ReservedQueue or {}
    for i = 1, #ReservedQueue do
        self.ReservedQueue:Add( ReservedQueue[ i ], self.ReservedQueue:GetCount() + 1 )
    end

    self:SimpleTimer( self.Config.QueuePositionMaxReservationTime, function()
        self.HistoricPlayers = Shine.Set()
        self:UpdateAllQueuePositions()
    end )
end

-- Players the grace period queued while idle have no spot to carry over to the next map.
local function GetRestorableKeys( Queue )
    local Keys = {}

    for SteamID in Queue:Iterate() do
        local QueuedClient = Shine.GetClientByNS2ID( SteamID )
        if not ( QueuedClient and QueuedClient.RRReclaimed ) then
            Keys[ #Keys + 1 ] = SteamID
        end
    end

    return Keys
end

function Plugin:SaveQueueHistory()
    local QueueHistory = {
        PlayerQueue = GetRestorableKeys( self.PlayerQueue ),
        ReservedQueue = GetRestorableKeys( self.ReservedQueue ),
        TimeStamp = Shared.GetSystemTime()
    }
    Shine.SaveJSONFile( QueueHistory, self.QueueHistoryFile )
end

function Plugin:OnFirstThink()
    Shine.Hook.SetupClassHook( "Gamerules", "GetCanJoinPlayingTeam", "OnGetCanJoinPlayingTeam",
        function( OldFunc, Gamerules, Player )
            local Allowed = OldFunc( Gamerules, Player )

            local Result = Shine.Hook.Call( "OnGetCanJoinPlayingTeam", Gamerules, Player, Allowed )
            if Result ~= nil then
                return Result
            end

            return Allowed
        end )

    -- Vanilla's GetCanJoinPlayingTeam never sees ShineForce, so remember which player a Shine admin move is
    -- for. A plain hook at top priority, because shuffles force their moves through a top priority hook that
    -- stops plugin hooks from running.
    Shine.Hook.Add( "JoinTeam", "RRQueueAdminTeamMove", function( _, Player, NewTeam, _, ShineForce )
        self.AdminTeamMove = ShineForce and NewTeam ~= kSpectatorIndex and Player or nil
    end, Shine.Hook.MAX_PRIORITY )

    -- At the end of a round the gamerules move every single player back into the ready room. Those moves
    -- must never start a grace period, otherwise the whole server would end up in the spectator slots.
    Shine.Hook.SetupClassHook( "NS2Gamerules", "UpdateToReadyRoom", "OnRRQueueUpdateToReadyRoom",
        function( OldFunc, gamerules, force )
            self.InRoundEndMove = true

            local Success, Result = pcall( OldFunc, gamerules, force )

            self.InRoundEndMove = nil

            if not Success then
                error( Result, 0 )
            end

            return Result
        end )
end

function Plugin:ClientConnect( Client )
    if Client:GetIsVirtual() then return end

    if Client:GetIsSpectator() then
        self:OnSpectatorJoined( Client )
        return
    end

    local SteamID = Client:GetUserId()
    if not self.HistoricPlayers:Contains( SteamID ) then return end

    -- Joining the ready room on connect does not go through JoinTeam, nothing else would drop this entry.
    self.HistoricPlayers:Remove( SteamID )
    self:Dequeue( Client )
end

function Plugin:ClientDisconnect( Client )
    if not Client or Client:GetIsVirtual() then return end

    local SteamID = Client:GetUserId()
    if SteamID then
        self.GraceExpiries[ SteamID ] = nil
    end

    local WasSpectator = Client:GetIsSpectator()

    self:Dequeue( Client )

    -- A spectator was not holding a player slot, so nothing frees up by them leaving.
    if WasSpectator then return end

    -- The engine may still count them while this hook runs.
    self:SimpleTimer( 0, function()
        self:Pop()
    end )
end

function Plugin:OnGetCanJoinPlayingTeam( _, Player, Allowed )
    local AdminTeamMove = self.AdminTeamMove == Player
    self.AdminTeamMove = nil

    -- Anyone that is not flagged as a spectator already occupies a player slot, so the queue has no
    -- business blocking them. This is what keeps the plugin from locking everyone out of the teams.
    if not Player:GetIsSpectator() or AdminTeamMove then return end

    local Client = Player:GetClient()
    if not Client then return end

    local SteamID = Client:GetUserId()
    if not SteamID or SteamID < 1 then return end

    if not Allowed then
        -- The server has no room for them, let the vanilla rejection stand and queue them up.
        self:DebugPrint( "Denied join for %s[%s], adding them to the queue.",
            Shine.GetClientName( Client ), SteamID )
        self:Enqueue( Client )
        return
    end

    -- Vanilla only knows the engine's count, which can still miss a slot the plugin just handed out.
    if not self:GetCanTakePlayerSlot( Client ) then
        self:Enqueue( Client )
        return false
    end

    -- A player slot is free. Work out whether somebody ahead of them in the queue could actually take it,
    -- taking into account which kind of slot became free.
    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()

    local Queue, AheadID, AheadIndex
    if NumPlayers < MaxPlayers - NumReserved then
        Queue = self.PlayerQueue
        _, AheadID, AheadIndex = self:GetFirstServableClient( Queue, SteamID, false, true )
    end

    if not AheadID and NumPlayers < MaxPlayers then
        Queue = self.ReservedQueue
        _, AheadID, AheadIndex = self:GetFirstServableClient( Queue, SteamID, true, true )
    end

    -- Nobody is waiting that could use this slot, so let them have it. Never hold a slot hostage.
    if not AheadID then return end

    -- A VIP the queue would put in front of everybody that could take the slot gets it straight away.
    if not Queue:Get( SteamID ) and self:GetQueueInsertPosition( Queue, Client ) <= AheadIndex then return end

    self:Enqueue( Client )

    if self.Popping then
        self:DebugPrint( "Blocked %s[%s] from skipping the queue, a pop is already running.",
            Shine.GetClientName( Client ), SteamID )
        return false
    end

    self.Popping = true
    local Ok, Granted = pcall( self.Pop, self )
    self.Popping = nil

    if not Ok then
        error( Granted, 0 )
    end

    -- The pop handed the slot to this very player and already replaced their entity with a ready room one,
    -- vanilla must not carry on with the old entity.
    if not Client:GetIsSpectator() then return false end

    if Granted then
        self:DebugPrint( "Blocked %s[%s] from skipping the queue, the free slot went to %s.",
            Shine.GetClientName( Client ), SteamID, AheadID )
        return false
    end

    -- Nobody could be served after all, so do not stand in this player's way.
    return
end

function Plugin:PostJoinTeam( _, Player, OldTeam, NewTeam )
    local Client = Player:GetClient()

    if NewTeam ~= kSpectatorIndex then
        -- Make sure clients don't stay in the queue if they get moved to a playing slot
        self:Dequeue( Client )

        self:UpdateReadyRoomGrace( Client, OldTeam, NewTeam )

        return
    end

    local SteamID = Client and Client:GetUserId()
    if not SteamID then return end

    self.GraceExpiries[ SteamID ] = nil

    -- Vanilla moves connecting spectators here before Shine knows the client, which would make the pop drop
    -- their restored queue entry and the client could not receive any message yet. ClientConnect takes over.
    if not Shine:IsValidClient( Client ) then return end

    self:OnSpectatorJoined( Client )
end

function Plugin:OnSpectatorJoined( Client )
    local SteamID = Client:GetUserId()

    local Position = 0
    if self.HistoricPlayers:Contains( SteamID ) then
        self.HistoricPlayers:Remove( SteamID )
        Position = self.PlayerQueue:Get( SteamID ) or 0
    end

    self:Pop()

    -- A reclaim moves them here on purpose and tells them their real position right afterwards.
    if SteamID == self.ReclaimingSteamID then return end

    if self:GetCanTakePlayerSlot( Client ) then return end

    if Position == 0 then
        self:SendTranslatedNotify( Client, "QUEUE_INFORM", {
            Position = self.PlayerQueue:GetCount()
        } )
    else
        self:SendTranslatedNotify( Client, "QUEUE_WELCOME_BACK", {
            Position = Position
        } )
    end
end

-- Shine.Map has no positional insert, so this reaches into its internals.
function Plugin:InsertIntoQueue( Queue, Key, Position, UpdateMessageName )
    if Queue:Get( Key ) then return end

    Queue.NumMembers = Queue.NumMembers + 1
    table.insert( Queue.Keys, Position, Key )
    Queue.MemberLookup[ Key ] = Position

    if Position < Queue.NumMembers then
        self:UpdateQueuePositions( Queue, UpdateMessageName )
    end
end

function Plugin:GetQueueInsertPosition( Queue, Client )
    local VIPConfig = self.Config.VIPPlayers
    if not VIPConfig.Enabled or Client.RRReclaimed or not Shine:HasAccess( Client, VIPConfig.PermissionString ) then
        return Queue:GetCount() + 1
    end

    -- A connected non-VIP that was not connected when an earlier VIP queued can sit in front of that VIP,
    -- so behind the last VIP as well as in front of the first non-VIP.
    local Keys = Queue:GetKeys()
    local FirstNonVIP, LastVIP

    for i = 1, #Keys do
        local QueuedClient = Shine.GetClientByNS2ID( Keys[ i ] )
        if QueuedClient then
            if not QueuedClient.RRReclaimed and Shine:HasAccess( QueuedClient, VIPConfig.PermissionString ) then
                LastVIP = i
            elseif not FirstNonVIP then
                FirstNonVIP = i
            end
        end
    end

    return Max( FirstNonVIP or #Keys + 1, ( LastVIP or 0 ) + 1 )
end

function Plugin:SendWaitTime( Client )
    if self.AVGWaitTimeSampleSize == 0 then return end

    self:SendTranslatedNotify( Client, "QUEUE_WAITTIME", {
        Time = math.round( self.AVGWaitTime )
    } )
end

function Plugin:SendQueuePosition( Client, Position )
    self:SendTranslatedNotify( Client, "QUEUE_POSITION", {
        Position = Position
    } )

    local ReservedPosition = self.ReservedQueue:Get( Client:GetUserId() )
    if ReservedPosition then
        self:SendTranslatedNotify( Client, "PRIORITY_QUEUE_POSITION", {
            Position = ReservedPosition
        } )
    end

    self:SendWaitTime( Client )
end

--[[
    Adds a spectator to the queue. Reclaimed marks players the grace period queued rather than players that
    asked to play: they get no VIP jump and create no demand for further reclaims.

    Output: false when they cannot queue, otherwise true plus their position if they were queued already.
]]
function Plugin:Enqueue( Client, Reclaimed )
    if not Client:GetIsSpectator() then
        self:NotifyTranslatedError( Client, "ENQUEUE_ERROR_PLAYER" )
        return false
    end

    local SteamID = Client:GetUserId()

    if not SteamID or SteamID < 1 then return false end

    -- Only time spent waiting by choice counts towards the average wait time.
    if Reclaimed or Client.RRReclaimed then
        Client.RRQueueJoinTime = not Reclaimed and Shared.GetTime() or nil
    end

    Client.RRReclaimed = Reclaimed or nil

    local Position = self.PlayerQueue:Get( SteamID )
    if Position then
        return true, Position
    end

    Position = self:GetQueueInsertPosition( self.PlayerQueue, Client )
    self:InsertIntoQueue( self.PlayerQueue, SteamID, Position, "QUEUE_CHANGED_VIP" )
    self:SendTranslatedNotify( Client, "QUEUE_ADDED", {
        Position = Position
    } )

    self:SendWaitTime( Client )

    if GetHasReservedSlotAccess( SteamID ) then
        Position = self:GetQueueInsertPosition( self.ReservedQueue, Client )
        self:InsertIntoQueue( self.ReservedQueue, SteamID, Position, "PRIORITY_QUEUE_CHANGED_VIP" )
        self:SendTranslatedNotify( Client, "PRIORITY_QUEUE_ADDED", {
            Position = Position
        } )
    end

    if not Reclaimed then
        Client.RRQueueJoinTime = Shared.GetTime()
    end

    return true
end

function Plugin:UpdateQueuePositions( Queue, Message )
    Message = Message or "QUEUE_CHANGED"

    local i = 1
    for SteamID, Position in Queue:Iterate() do
        local Client = Shine.GetClientByNS2ID( SteamID )
        if Client then

            if Position ~= i then
                Queue:Add( SteamID, i )
                self:SendTranslatedNotify( Client, Message, {
                    Position = i
                })
            end
            i = i + 1

        -- Historic player entry
        elseif self.HistoricPlayers:Contains( SteamID ) then

            Queue:Add( SteamID, i )
            i = i + 1

        -- player disconnected but somehow wasn't removed
        else
            Queue:Remove( SteamID )
        end
    end
end

function Plugin:UpdateAllQueuePositions()
    self:UpdateQueuePositions( self.PlayerQueue )
    self:UpdateQueuePositions( self.ReservedQueue, "PRIORITY_QUEUE_CHANGED" )
end

function Plugin:Dequeue( Client )
    if not Client then return end

    local SteamId = Client:GetUserId()
    Client.RRReclaimed = nil

    local Removed = false

    if self.ReservedQueue:Remove( SteamId ) ~= nil then
        self:UpdateQueuePositions( self.ReservedQueue, "PRIORITY_QUEUE_CHANGED" )
        Removed = true
    end

    if self.PlayerQueue:Remove( SteamId ) ~= nil then
        self:UpdateQueuePositions( self.PlayerQueue )
        Removed = true
    end

    return Removed
end

--[[
    Counts how many player slots are currently taken.

    Vanilla's count includes clients still loading into a player slot, the spectator flags of connected
    clients include a flag the plugin flipped a moment ago even if the engine's counter lags behind. Any slot
    either of them still sees as taken is never handed out, a stale count only delays a pop until the tick.

    Output: number of used player slots, the player slot limit, how many of those slots are reserved.
]]
function Plugin:GetSlotCounts()
    local NumFlagged = 0

    local Clients = Shine.GameIDs:GetKeys()
    for i = 1, #Clients do
        local Client = Clients[ i ]
        if not Client:GetIsVirtual() and not Client:GetIsSpectator() then
            NumFlagged = NumFlagged + 1
        end
    end

    local NumPlayers = Max( Server.GetNumClientsTotal() - Server.GetNumSpectators(), NumFlagged )

    local MaxPlayers = Server.GetMaxPlayers()
    local NumReserved = Server.GetReservedSlotLimit() or 0
    if NumReserved > MaxPlayers then
        NumReserved = MaxPlayers
    end

    return NumPlayers, MaxPlayers, NumReserved
end

-- Checked locally rather than through the gamerules, which would pop a "server full" error at them.
function Plugin:GetCanTakePlayerSlot( Client )
    if not Client:GetIsSpectator() then return true end

    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()
    if NumPlayers < MaxPlayers - NumReserved then return true end

    return NumPlayers < MaxPlayers and GetHasReservedSlotAccess( Client:GetUserId() )
end

--[[
    Returns the first client in the given queue that could be given a player slot right now, looking only
    at the entries ahead of BeforeSteamID. The key order of the map is the queue order.

    Output: the client, their SteamID and their index in the queue's keys.
]]
function Plugin:GetFirstServableClient( Queue, BeforeSteamID, RequireReservedAccess, SkipReclaimed )
    local Keys = Queue:GetKeys()

    for i = 1, #Keys do
        local SteamID = Keys[ i ]

        if SteamID == BeforeSteamID then break end

        if not self.HistoricPlayers:Contains( SteamID ) then
            local QueuedClient = Shine.GetClientByNS2ID( SteamID )

            if QueuedClient and QueuedClient:GetIsSpectator()
            and not ( SkipReclaimed and QueuedClient.RRReclaimed )
            and ( not RequireReservedAccess or GetHasReservedSlotAccess( SteamID ) ) then
                return QueuedClient, SteamID, i
            end
        end
    end
end

function Plugin:RemoveFromQueues( SteamID )
    local Removed = self.PlayerQueue:Remove( SteamID ) ~= nil
    Removed = self.ReservedQueue:Remove( SteamID ) ~= nil or Removed

    if Removed then
        self.QueuesDirty = true
    end

    return Removed
end

--[[
    Hands a player slot to the given client.

    Clearing the spectator flag is what actually claims the player slot, the move into the ready room is
    only there to get them out of the spectator team. That move has to be forced: without it JoinTeam
    returns false for anyone already sitting in the ready room, and the rookie only check would veto it.
    It also needs ShineForce, or the readyroom plugin refuses it for a while after it assigned them a team.
    Joining an actual playing team afterwards still goes through all the usual vanilla checks.
]]
function Plugin:GrantPlayerSlot( Client )
    if not Client then return false end

    local Gamerules = GetGamerules()
    if not Gamerules then return false end

    local Player = Client:GetControllingPlayer()
    if not Player then return false end

    local WasSpectator = Client:GetIsSpectator()
    if WasSpectator then
        Client:SetIsSpectator( false )
    end

    if Player:GetTeamNumber() ~= kTeamReadyRoom then
        if not Gamerules:JoinTeam( Player, kTeamReadyRoom, true, true ) then
            if WasSpectator then
                Client:SetIsSpectator( true )
            end

            return false
        end
    end

    Player = Client:GetControllingPlayer() or Player
    if Player.SetCameraDistance then
        Player:SetCameraDistance( 0 )
    end

    return true
end

function Plugin:OnSlotGranted( Client, SteamID )
    self.PlayerQueue:Remove( SteamID )
    self.ReservedQueue:Remove( SteamID )
    self.GraceExpiries[ SteamID ] = nil

    self:SendNetworkMessage( Client, "QueueLeft", {}, true )

    if Client.RRQueueJoinTime then
        self:UpdateWaitTimeHistory( Shared.GetTime() - Client.RRQueueJoinTime )
    end

    Client.RRQueueJoinTime = nil
    Client.RRReclaimed = nil

    self.QueuesDirty = nil

    self:UpdateAllQueuePositions()
end

--[[
    Walks the given queue in order and gives the free player slot to the first candidate that can take it.

    A candidate that cannot be served is skipped, never returned on. Giving up on the first failure is what
    used to freeze the entire queue behind a single client that could not be moved. Players the grace period
    queued are only served once nobody else can take the slot.
]]
function Plugin:PopQueue( Queue, RequireReservedAccess )
    -- Snapshot the keys, the map's iterator uses a shared cursor and entries get removed below.
    local Candidates = TableQuickCopy( Queue:GetKeys() )

    for Pass = 1, 2 do
        local WantReclaimed = Pass == 2

        for i = 1, #Candidates do
            local SteamID = Candidates[ i ]

            -- Skip entries that were removed while working through the snapshot.
            if Queue:Get( SteamID ) then
                local QueuedClient = Shine.GetClientByNS2ID( SteamID )

                if not QueuedClient then
                    -- Restored entries keep their position until their reservation runs out, drop the rest.
                    if not self.HistoricPlayers:Contains( SteamID ) then
                        self:DebugPrint( "Dropping queue entry %s, the client is gone.", SteamID )
                        self:RemoveFromQueues( SteamID )
                    end
                elseif not QueuedClient:GetIsSpectator() then
                    -- They already hold a player slot, the queue has nothing left to give them.
                    self:DebugPrint( "Dropping %s from the queue, they already hold a player slot.", SteamID )
                    self:RemoveFromQueues( SteamID )
                elseif ( QueuedClient.RRReclaimed == true ) ~= WantReclaimed then
                    -- Handled by the other pass.
                elseif self.HistoricPlayers:Contains( SteamID ) then
                    self:DebugPrint( "Skipping %s, waiting for them to reconnect after the map change.", SteamID )
                elseif RequireReservedAccess and not GetHasReservedSlotAccess( SteamID ) then
                    self:DebugPrint( "Skipping %s, only a reserved slot is free and they have no access.", SteamID )
                elseif self:GrantPlayerSlot( QueuedClient ) then
                    self:DebugPrint( "Gave a player slot to %s.", SteamID )
                    self:OnSlotGranted( QueuedClient, SteamID )

                    return true
                else
                    self:DebugPrint( "Could not move %s into the ready room, trying the next player.", SteamID )
                end
            end
        end
    end

    return false
end

--[[
    Hands one free player slot over to the queue, if there is one to hand out.

    Output: true when a client was given a player slot.
]]
function Plugin:Pop()
    if not GetGamerules() then -- abort mission
        return false
    end

    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()

    self:DebugPrint( "Pop: %s/%s player slots used (%s reserved), %s queued, %s in the reserved queue.",
        NumPlayers, MaxPlayers, NumReserved, self.PlayerQueue:GetCount(), self.ReservedQueue:GetCount() )

    local Granted = false

    if NumPlayers < MaxPlayers then
        -- Ordinary slots go to the normal queue. Whatever is left over are reserved slots and only players
        -- with reserved slot access may take those.
        if NumPlayers < MaxPlayers - NumReserved then
            Granted = self:PopQueue( self.PlayerQueue, false )
        end

        if not Granted then
            Granted = self:PopQueue( self.ReservedQueue, true )
        end
    end

    if self.QueuesDirty then
        self.QueuesDirty = nil

        self:UpdateAllQueuePositions()
    end

    return Granted
end

--[[
    True while freeing one more player slot would let somebody in the queue in. Players the grace period
    itself queued do not count, or every reclaim would create the demand for the next one.
]]
function Plugin:HasWaitingClient()
    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()
    NumPlayers = NumPlayers - 1

    if NumPlayers < MaxPlayers - NumReserved
    and self:GetFirstServableClient( self.PlayerQueue, nil, false, true ) then
        return true
    end

    return NumPlayers < MaxPlayers
        and self:GetFirstServableClient( self.ReservedQueue, nil, true, true ) ~= nil
end

-- Callers are responsible for making sure somebody is actually waiting for the slot.
function Plugin:StartReadyRoomGrace( Client, SteamID )
    local Config = self.Config.ReadyRoomGracePeriod
    if not Config.Enabled then return false end

    if self.GraceExpiries[ SteamID ] then return false end

    -- Never touch bots, the round end move that drops the whole server into the ready room, or the pre
    -- game ready room where everybody is meant to be sitting around anyway.
    if Client:GetIsVirtual() or self.InRoundEndMove then return false end

    local Gamerules = GetGamerules()
    if not Gamerules or not Gamerules:GetGameStarted() then return false end

    self.GraceExpiries[ SteamID ] = Shared.GetTime() + Config.Time

    self:SendTranslatedNotify( Client, "RR_GRACE_WARNING", {
        Time = Config.Time
    })

    return true
end

--[[
    Starts or clears the grace period of a client that just moved to a new team.
]]
function Plugin:UpdateReadyRoomGrace( Client, OldTeam, NewTeam )
    if not Client then return end

    local SteamID = Client:GetUserId()
    if not SteamID or SteamID < 1 then return end

    if NewTeam ~= kTeamReadyRoom then
        -- They are playing again, so there is nothing to reclaim.
        self.GraceExpiries[ SteamID ] = nil
        return
    end

    -- Only players giving up a playing team slot go on the clock right here. Anybody else sitting in the
    -- ready room on a player slot is picked up by the tick as soon as somebody starts waiting.
    if OldTeam ~= kTeam1Index and OldTeam ~= kTeam2Index then return end

    -- Nobody is waiting, so let them keep their slot for as long as they like.
    if not self:HasWaitingClient() then return end

    self:StartReadyRoomGrace( Client, SteamID )
end

function Plugin:StartPendingReadyRoomGraces()
    if not self.Config.ReadyRoomGracePeriod.Enabled then return end
    if not self:HasWaitingClient() then return end

    local Clients = Shine.GameIDs:GetKeys()
    for i = 1, #Clients do
        local Client = Clients[ i ]

        if not Client:GetIsVirtual() and not Client:GetIsSpectator() then
            local SteamID = Client:GetUserId()

            if SteamID and SteamID > 0 and not self.GraceExpiries[ SteamID ] then
                local Player = Client:GetControllingPlayer()

                if Player and Player:GetTeamNumber() == kTeamReadyRoom then
                    self:StartReadyRoomGrace( Client, SteamID )
                end
            end
        end
    end
end

function Plugin:CheckReadyRoomGrace()
    local Config = self.Config.ReadyRoomGracePeriod
    if not Config.Enabled then return end
    if not next( self.GraceExpiries ) then return end

    local Gamerules = GetGamerules()
    if not Gamerules or not Gamerules:GetGameStarted() then
        TableEmpty( self.GraceExpiries )
        return
    end

    local Now = Shared.GetTime()

    -- Snapshot first: reclaiming a slot pops the queue, which clears grace entries of other clients,
    -- and clearing a key other than the current one during a pairs() walk is undefined behaviour.
    local Expired = {}
    local Stale = {}

    for SteamID, Expiry in pairs( self.GraceExpiries ) do
        local Client = Shine.GetClientByNS2ID( SteamID )
        local Player = Client and Client:GetControllingPlayer()

        if not Client or not Player or Client:GetIsSpectator()
        or Player:GetTeamNumber() ~= kTeamReadyRoom then
            -- No longer sitting in the ready room on a player slot.
            Stale[ #Stale + 1 ] = SteamID
        elseif Now >= Expiry then
            Expired[ #Expired + 1 ] = SteamID
        end
    end

    for i = 1, #Stale do
        self.GraceExpiries[ Stale[ i ] ] = nil
    end

    for i = 1, #Expired do
        local SteamID = Expired[ i ]
        local Client = Shine.GetClientByNS2ID( SteamID )
        local Player = Client and Client:GetControllingPlayer()

        -- The entry is left in place so a failed move is retried next tick instead of starting a fresh grace
        -- period. One reclaim per tick: until the slot counts catch up with it, the waiter it was for still
        -- looks like they are waiting and would justify reclaiming the next expired player as well.
        if Client and Player and not Client:GetIsSpectator()
        and Player:GetTeamNumber() == kTeamReadyRoom
        and self:ReclaimPlayerSlot( Client, Player ) then
            return
        end
    end
end

function Plugin:ReclaimPlayerSlot( Client, Player )
    local SteamID = Client:GetUserId()

    -- Only take the slot back if it is actually going to be used by somebody.
    if not self:HasWaitingClient() then
        self.GraceExpiries[ SteamID ] = nil
        return false
    end

    local Gamerules = GetGamerules()
    if not Gamerules then return false end

    -- PostJoinTeam fires mid-move and would report a queue position that does not include them yet.
    self.ReclaimingSteamID = SteamID

    -- Without ShineForce, plugins that restrict spectating (norookies, hiveteamrestriction) veto every retry.
    local Ok, Moved = pcall( Gamerules.JoinTeam, Gamerules, Player, kSpectatorIndex, true, true )

    self.ReclaimingSteamID = nil

    if not Ok then
        error( Moved, 0 )
    end

    if not Moved then
        self:DebugPrint( "Could not move %s out of the ready room to reclaim their player slot.", SteamID )
        return false
    end

    self:DebugPrint( "Reclaimed the player slot of %s, their ready room grace period ran out.", SteamID )

    self:NotifyTranslated( Client, "RR_GRACE_EXPIRED" )

    if self.Config.ReadyRoomGracePeriod.EnqueueOnExpiry then
        self:Enqueue( Client, true )
    else
        self:SendTranslatedNotify( Client, "QUEUE_INFORM", {
            Position = self.PlayerQueue:GetCount()
        } )
    end

    -- The move to the spectator team already popped the queue, this only covers the case where it did not.
    self:Pop()

    return true
end

function Plugin:OnTick()
    if self.PlayerQueue:GetCount() > 0 or self.ReservedQueue:GetCount() > 0 then
        -- Pick up player slots that were freed by something the plugin does not hook.
        local NumPlayers, MaxPlayers = self:GetSlotCounts()
        if NumPlayers < MaxPlayers then
            self:Pop()
        end
    end

    -- After the pop, so nobody is reclaimed or warned over a waiting player that a free slot serves anyway.
    self:CheckReadyRoomGrace()
    self:StartPendingReadyRoomGraces()
end

function Plugin:PrintQueue( Client )
    local function PrintEntries( Title, Queue )
        if Queue:GetCount() == 0 then
            Shine.PrintToConsole( Client, Title .. " is empty." )
            return
        end

        Shine.PrintToConsole( Client, Title .. ":" )

        for SteamID, Position in Queue:Iterate() do
            local QueuedClient = Shine.GetClientByNS2ID( SteamID )

            Shine.PrintToConsole( Client, StringFormat( "%d - %s[%d]%s", Position,
                QueuedClient and Shine.GetClientName( QueuedClient ) or "Unknown", SteamID,
                QueuedClient and QueuedClient.RRReclaimed and " (reclaimed)" or "" ) )
        end
    end

    PrintEntries( "Player Slot Queue", self.PlayerQueue )
    PrintEntries( "Reserved Slot Queue", self.ReservedQueue )

    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()
    Shine.PrintToConsole( Client, StringFormat( "%d/%d player slots used, %d of them reserved.",
        NumPlayers, MaxPlayers, NumReserved ) )
end

function Plugin:CreateCommands()
    local function EnqueuePlayer( Client )
        if not Client then return end

        local _, Position = self:Enqueue( Client )
        if Position then
            self:SendQueuePosition( Client, Position )
        end
    end
    local Enqueue = self:BindCommand( "sh_rr_enqueue", "rr_enqueue", EnqueuePlayer, true )
    Enqueue:Help( "Enter the queue for a player slot" )

    local function DequeuePlayer( Client )
        if not Client then return end

        if not self:Dequeue( Client ) then
            self:NotifyTranslatedError( Client, "DEQUEUE_FAILED" )
            return
        end

        self:NotifyTranslated( Client, "DEQUEUE_SUCCESS" )
    end
    local Dequeue = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Dequeue:Help( "Leave the player slot queue" )

    local function DisplayPosition( Client )
        if not Client then return end

        local Position = self.PlayerQueue:Get( Client:GetUserId() )
        if not Position then
            self:NotifyTranslatedError( Client, "QUEUE_POSITION_UNKNOWN" )
            return
        end

        self:SendQueuePosition( Client, Position )
    end
    local Position = self:BindCommand( "sh_rr_position", "rr_position", DisplayPosition, true )
    Position:Help( "Returns your current position in the player slot queue" )

    local PrintQueue = self:BindCommand( "sh_rr_printqueue", nil, function( Client )
        self:PrintQueue( Client )
    end )
    PrintQueue:Help( "Prints both player slot queues and the current slot usage" )

    local ListClients = self:BindCommand( "sh_rr_listclients", nil, function( Client )
        local Clients, Count = Shine.GetAllClients()
        for i = 1, Count do
            local Target = Clients[ i ]
            local ClientPlayer = Target:GetControllingPlayer()

            Shine.PrintToConsole( Client, StringFormat( "%s - spectator: %s - team: %s",
                Shine.GetClientInfo( Target ), tostring( Target:GetIsSpectator() ),
                tostring( ClientPlayer and ClientPlayer:GetTeamNumber() ) ) )
        end
    end )
    ListClients:Help( "Lists every client with its spectator flag and team" )
end

function Plugin:MapChange()
    if not self.Config.RestoreQueueAfterMapchange then return end

    self:SaveQueueHistory()
end
