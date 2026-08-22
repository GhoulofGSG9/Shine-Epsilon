local Notify = Shared.Message

local TableConcat = table.concat

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

Plugin.QueueHistoryFile = "config://shine/temp/rr_queue_history.json"
Plugin.QueueWaitTimeHistoryFile = "config://shine/temp/rr_queue_wait_time_history.json"

-- How often we look for free player slots that nobody claimed and for expired ready room grace periods.
Plugin.TickInterval = 1

function Plugin:Initialise()
    self.Enabled = true

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

function Plugin:DebugPrint( Message, ... )
    if not self.Config.Debug then return end

    self:Print( Message, true, ... )
end

function Plugin:LoadWaitTimeHistory()
    local WaitTimeHistory = Shine.LoadJSONFile( self.QueueWaitTimeHistoryFile ) or {
        AVGWaitTime = 0,
        SampleSize = 0
    }

    self.AVGWaitTime = WaitTimeHistory.AVGWaitTime
    self.AVGWaitTimeSampleSize = WaitTimeHistory.SampleSize
end

function Plugin:UpdateWaitTimeHistory( WaitTime )
    local SumWaitTimes = self.AVGWaitTime * self.AVGWaitTimeSampleSize + WaitTime
    self.AVGWaitTimeSampleSize = self.AVGWaitTimeSampleSize + 1
    self.AVGWaitTime = math.round( SumWaitTimes / self.AVGWaitTimeSampleSize )

    local WaitTimeHistory = {
        AVGWaitTime = self.AVGWaitTime,
        SampleSize = self.AVGWaitTimeSampleSize
    }
    Shine.SaveJSONFile( WaitTimeHistory, self.QueueWaitTimeHistoryFile )
end

function Plugin:LoadQueueHistory()
    self.HistoricPlayers = Shine.Set()

    if not self.Config.RestoreQueueAfterMapchange then return end

    local QueueHistory = Shine.LoadJSONFile( self.QueueHistoryFile ) or {}

    local now = Shared.GetSystemTime()

    local TimeStamp = QueueHistory.TimeStamp
    if not TimeStamp or tonumber( TimeStamp ) + self.Config.QueueHistoryLifeTime < now then
        return
    end

    if QueueHistory.PlayerQueue then
        for i = 1, #QueueHistory.PlayerQueue do
            local SteamId = QueueHistory.PlayerQueue[i]
            self:InsertIntoQueue(self.PlayerQueue, SteamId, i )
            self.HistoricPlayers:Add( SteamId )
        end
    end

    if QueueHistory.ReservedQueue then
        for i = 1, #QueueHistory.ReservedQueue do
            local SteamId = QueueHistory.ReservedQueue[i]
            self:InsertIntoQueue(self.ReservedQueue, SteamId, i )
        end
    end

    local function ClearHistory()
        self.HistoricPlayers = Shine.Set()

        self:UpdateQueuePositions( self.PlayerQueue )
        self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
    end

    self:SimpleTimer( self.Config.QueuePositionMaxReservationTime, ClearHistory )
end

function Plugin:SaveQueueHistory()
    local QueueHistory = {
        PlayerQueue = self.PlayerQueue:GetKeys(),
        ReservedQueue = self.ReservedQueue:GetKeys(),
        TimeStamp = Shared.GetSystemTime()
    }
    Shine.SaveJSONFile( QueueHistory, self.QueueHistoryFile )
end

function Plugin:OnFirstThink()
    Shine.Hook.SetupClassHook( "Gamerules", "GetCanJoinPlayingTeam", "OnGetCanJoinPlayingTeam", function(OldFunc, gamerules, player, skipHook )
        local result = OldFunc( gamerules, player )

        if not skipHook then
            local HookResult = { Shine.Hook.Call( "OnGetCanJoinPlayingTeam", gamerules, player, result ) }
            if HookResult[ 1 ] ~= nil then
                return unpack( HookResult )
            end
        end

        return result
    end )

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

    -- Their player slot is free now. Ignore them while counting, Shine may not have dropped them from
    -- Shine.GameIDs yet depending on hook ordering.
    self:Pop( Client )
end

function Plugin:OnGetCanJoinPlayingTeam( _, Player, Allowed )
    -- Anyone that is not flagged as a spectator already occupies a player slot, so the queue has no
    -- business blocking them. This is what keeps the plugin from locking everyone out of the teams.
    if not Player:GetIsSpectator() then return end

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

    -- A player slot is free. Work out whether somebody ahead of them in the queue could actually take it,
    -- taking into account which kind of slot became free.
    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()

    local AheadID
    if NumPlayers < MaxPlayers - NumReserved then
        _, AheadID = self:GetFirstServableClient( self.PlayerQueue, SteamID )
    end

    if not AheadID and NumPlayers < MaxPlayers then
        _, AheadID = self:GetFirstServableClient( self.ReservedQueue, SteamID, true )
    end

    -- Nobody is waiting that could use this slot, so let them have it. Never hold a slot hostage.
    if not AheadID then return end

    self:Enqueue( Client )

    if self.Popping then return end

    self.Popping = true
    local Ok, Granted = pcall( self.Pop, self )
    self.Popping = nil

    if not Ok then
        error( Granted, 0 )
    end

    -- The pop may have handed the slot to this very player.
    if not Client:GetIsSpectator() then return end

    if Granted then
        self:DebugPrint( "Blocked %s[%s] from skipping the queue, the free slot went to %s.",
            Shine.GetClientName( Client ), SteamID, AheadID )
        return false
    end

    -- Nobody could be served after all, so do not stand in this player's way.
    return
end

function Plugin:CanClientQueue( Client )
    if not Client then return false end

    -- Only clients using a spectator slot can gain anything from the queue. A client sitting in the ready
    -- room already holds a player slot, queueing them would only stall the queue for everybody else.
    return Client:GetIsSpectator() == true
end

function Plugin:GetQueuePosition( Client )
    local SteamId = Client:GetUserId()

    return self.PlayerQueue:Get(SteamId)
end

function Plugin:PostJoinTeam( _, Player, OldTeam, NewTeam )
    local Client = Player:GetClient()

    if NewTeam ~= kSpectatorIndex then

        -- Make sure clients don't stay in the queue if they get moved to a playing slot
        self:Dequeue(Client)

        self:UpdateReadyRoomGrace( Client, OldTeam, NewTeam )

        return
    end

    if Client then
        local SteamID = Client:GetUserId()
        if SteamID then
            self.GraceExpiries[ SteamID ] = nil
        end
    end

    local SteamId = Player:GetSteamId()

    local position = 0
    if SteamId and self.HistoricPlayers:Contains( SteamId ) then
        self.HistoricPlayers:Remove( SteamId )
        position = self.PlayerQueue:Get( SteamId ) or 0
    end

    self:Pop()

    if not self:GetCanJoinPlayingTeam( Player ) then
        if Client then
            if position == 0 then
                self:SendTranslatedNotify(Client, "QUEUE_INFORM", {
                    Position = self.PlayerQueue:GetCount()
                })
            else
                self:SendTranslatedNotify(Client, "QUEUE_WELCOME_BACK", {
                    Position = position
                })
            end
        end
    end
end

-- Allows to insert new key to a specific position in the Maps Keys array
-- Also position is the value to add for given key in the map
function Plugin:InsertIntoQueue( Queue, Key, Position, UpdateMessageName )
    if Key == nil then return end -- ensure Key is not nil

    local NumMembers = Queue.NumMembers + 1
    if Position > NumMembers then return end -- ensure we are not inserting to an invalid position

    Position = Position or NumMembers -- set position to end of map if not specified otherwise

    -- Key allready exists in map, abort mission!
    if Queue.MemberLookup[ Key ] ~= nil then
        Queue.MemberLookup[ Key ] = Position
        return
    end

    Queue.NumMembers = NumMembers
    table.insert(Queue.Keys, Position, Key)
    Queue.MemberLookup[ Key ] = Position

    if UpdateMessageName and Position < NumMembers then
        self:UpdateQueuePositions(Queue, UpdateMessageName)
    end
end

function Plugin:GetQueueInsertPosition( Queue, Client )
    local VIPPlayersEnabled = self.Config.VIPPlayers.Enabled
    local PermissionString = self.Config.VIPPlayers.PermissionString
    if VIPPlayersEnabled and Shine:HasAccess(Client, PermissionString) then

        local position = 1
        for SteamID in Queue:Iterate() do
            local c = Shine.GetClientByNS2ID(SteamID)
            if c then
                if Shine:HasAccess(c, PermissionString) then
                    position = position + 1
                else
                    break
                end
            end
        end

        return position
    end

    return Queue:GetCount() + 1
end

function Plugin:SendQueuePosition( Client, Position )
    self:SendTranslatedNotify(Client, "QUEUE_POSITION", {
        Position = Position
    })

    if self.AVGWaitTimeSampleSize > 0 then
        self:SendNetworkMessage( Client, "WaitTime", { Time = self.AVGWaitTime }, true )
    end
end

function Plugin:Enqueue( Client )
    if not self:CanClientQueue( Client ) then
        self:NotifyTranslatedError( Client, "ENQUEUE_ERROR_PLAYER" )
        return false
    end

    local SteamID = Client:GetUserId()

    if not SteamID or SteamID < 1 then return false end

    local position = self.PlayerQueue:Get( SteamID )
    if position then
        self:SendQueuePosition( Client, position )
        return true
    end

    position = self:GetQueueInsertPosition(self.PlayerQueue, Client)
    self:InsertIntoQueue(self.PlayerQueue, SteamID, position, "QUEUE_CHANGED_VIP")
    self:SendTranslatedNotify( Client, "QUEUE_ADDED", {
        Position = position
    })

    if self.AVGWaitTimeSampleSize > 0 then
        self:SendNetworkMessage( Client, "WaitTime", { Time = self.AVGWaitTime }, true)
    end

    if GetHasReservedSlotAccess( SteamID ) then
        position = self:GetQueueInsertPosition(self.ReservedQueue, Client)
        self:InsertIntoQueue(self.ReservedQueue, SteamID, position, "PIORITY_QUEUE_CHANGED_VIP")
        self:SendTranslatedNotify(Client, "PIORITY_QUEUE_ADDED", {
            Position = position
        })
    end

    -- Save join time for later
    Client.RRQueueJoinTime = Shared.GetTime()

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

function Plugin:Dequeue( Client )
    if not Client then return end

    local SteamId = Client:GetUserId()

    local position = self.PlayerQueue:Remove( SteamId )

    if self.ReservedQueue:Remove( SteamId ) then
        self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
    end

    if not position then return false end

    self:UpdateQueuePositions( self.PlayerQueue )

    return true
end

function Plugin:GetFirstClient( Queue )
    for SteamId in Queue:Iterate() do
        if not self.HistoricPlayers:Contains( SteamId ) then
            local QueuedClient = Shine.GetClientByNS2ID( SteamId )
            if QueuedClient then
                return QueuedClient, SteamId
            end
        end
    end
end

--[[
    Counts how many player slots are currently taken.

    Bots never carry the spectator flag and do not use up a player slot from the server's point of view, so
    they must not be counted here. IgnoreClient can be used to skip a client that is on its way out.

    Output: number of used player slots, the player slot limit, how many of those slots are reserved.
]]
function Plugin:GetSlotCounts( IgnoreClient )
    local NumPlayers = 0

    local Clients = Shine.GameIDs:GetKeys()
    for i = 1, #Clients do
        local Client = Clients[ i ]
        if Client ~= IgnoreClient and not Client:GetIsVirtual() and not Client:GetIsSpectator() then
            NumPlayers = NumPlayers + 1
        end
    end

    local MaxPlayers = Server.GetMaxPlayers()
    local NumReserved = Server.GetReservedSlotLimit() or 0
    if NumReserved > MaxPlayers then
        NumReserved = MaxPlayers
    end

    return NumPlayers, MaxPlayers, NumReserved
end

-- Confirm we don't end up with too many players due to a bugged spectator counter.
function Plugin:GetCanJoinPlayingTeam( Player )
    if not Player:GetIsSpectator() then return true end

    local Gamerules = GetGamerules()
    if not Gamerules then
        return false
    end

    local NumPlayers, MaxPlayers = self:GetSlotCounts()
    if NumPlayers >= MaxPlayers then return false end

    return Gamerules:GetCanJoinPlayingTeam( Player, true )
end

--[[
    Returns the first client in the given queue that could be given a player slot right now, looking only
    at the entries ahead of BeforeSteamID. The key order of the map is the queue order.
]]
function Plugin:GetFirstServableClient( Queue, BeforeSteamID, RequireReservedAccess )
    local Keys = Queue:GetKeys()

    for i = 1, #Keys do
        local SteamID = Keys[ i ]

        if SteamID == BeforeSteamID then break end

        if not self.HistoricPlayers:Contains( SteamID ) then
            local QueuedClient = Shine.GetClientByNS2ID( SteamID )

            if QueuedClient and QueuedClient:GetIsSpectator()
            and ( not RequireReservedAccess or GetHasReservedSlotAccess( SteamID ) ) then
                return QueuedClient, SteamID
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
        if not Gamerules:JoinTeam( Player, kTeamReadyRoom, true ) then
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
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    if Client.RRQueueJoinTime then
        self:UpdateWaitTimeHistory( Shared.GetTime() - Client.RRQueueJoinTime )
        Client.RRQueueJoinTime = nil
    end

    self.QueuesDirty = nil

    self:UpdateQueuePositions( self.PlayerQueue )
    self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
end

--[[
    Walks the given queue in order and gives the free player slot to the first candidate that can take it.

    A candidate that cannot be served is skipped, never returned on. Giving up on the first failure is what
    used to freeze the entire queue behind a single client that could not be moved.
]]
function Plugin:PopQueue( Queue, RequireReservedAccess )
    -- Snapshot the keys, the map's iterator uses a shared cursor and entries get removed below.
    local Candidates = {}
    local Keys = Queue:GetKeys()
    for i = 1, #Keys do
        Candidates[ i ] = Keys[ i ]
    end

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
            elseif self.HistoricPlayers:Contains( SteamID ) then
                self:DebugPrint( "Skipping %s, waiting for them to reconnect after the map change.", SteamID )
            elseif not QueuedClient:GetIsSpectator() then
                -- They already hold a player slot, the queue has nothing left to give them.
                self:DebugPrint( "Dropping %s from the queue, they already hold a player slot.", SteamID )
                self:RemoveFromQueues( SteamID )
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

    return false
end

--[[
    Hands one free player slot over to the queue, if there is one to hand out.

    Output: true when a client was given a player slot.
]]
function Plugin:Pop( IgnoreClient )
    if not GetGamerules() then -- abort mission
        return false
    end

    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts( IgnoreClient )

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

        self:UpdateQueuePositions( self.PlayerQueue )
        self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
    end

    return Granted
end

-- Kept for backwards compatibility with anything calling into the plugin.
function Plugin:PopReserved()
    return self:PopQueue( self.ReservedQueue, true )
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

    local Config = self.Config.ReadyRoomGracePeriod
    if not Config.Enabled then return end

    -- Only players giving up a playing team slot are on the clock.
    if OldTeam ~= kTeam1Index and OldTeam ~= kTeam2Index then return end

    -- Never touch bots, the round end move that drops the whole server into the ready room, or the pre
    -- game ready room where everybody is meant to be sitting around anyway.
    if Client:GetIsVirtual() or self.InRoundEndMove then return end

    local Gamerules = GetGamerules()
    if not Gamerules or not Gamerules:GetGameStarted() then return end

    -- Nobody is waiting, so let them keep their slot for as long as they like.
    if not self:GetFirstServableClient( self.PlayerQueue )
    and not self:GetFirstServableClient( self.ReservedQueue, nil, true ) then
        return
    end

    if self.GraceExpiries[ SteamID ] then return end

    self.GraceExpiries[ SteamID ] = Shared.GetTime() + Config.Time

    self:SendTranslatedNotify( Client, "RR_GRACE_WARNING", {
        Time = Config.Time
    })
end

function Plugin:CheckReadyRoomGrace()
    local Config = self.Config.ReadyRoomGracePeriod
    if not Config.Enabled then return end
    if not next( self.GraceExpiries ) then return end

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
        self.GraceExpiries[ SteamID ] = nil

        local Client = Shine.GetClientByNS2ID( SteamID )
        local Player = Client and Client:GetControllingPlayer()

        -- Re-check, an earlier reclaim in this same pass may have changed things.
        if Client and Player and not Client:GetIsSpectator()
        and Player:GetTeamNumber() == kTeamReadyRoom then
            self:ReclaimPlayerSlot( Client, Player )
        end
    end
end

function Plugin:ReclaimPlayerSlot( Client, Player )
    -- Only take the slot back if it is actually going to be used by somebody.
    if not self:GetFirstServableClient( self.PlayerQueue )
    and not self:GetFirstServableClient( self.ReservedQueue, nil, true ) then
        return false
    end

    local Gamerules = GetGamerules()
    if not Gamerules then return false end

    if not Gamerules:JoinTeam( Player, kSpectatorIndex, true ) then
        self:DebugPrint( "Could not move %s out of the ready room to reclaim their player slot.",
            Client:GetUserId() )
        return false
    end

    self:DebugPrint( "Reclaimed the player slot of %s, their ready room grace period ran out.",
        Client:GetUserId() )

    self:NotifyTranslated( Client, "RR_GRACE_EXPIRED" )

    if self.Config.ReadyRoomGracePeriod.EnqueueOnExpiry then
        self:Enqueue( Client )
    end

    -- The move to the spectator team already popped the queue, this only covers the case where it did not.
    self:Pop()

    return true
end

function Plugin:OnTick()
    self:CheckReadyRoomGrace()

    if self.PlayerQueue:GetCount() == 0 and self.ReservedQueue:GetCount() == 0 then return end

    -- Pick up player slots that were freed by something the plugin does not hook.
    local NumPlayers, MaxPlayers = self:GetSlotCounts()
    if NumPlayers >= MaxPlayers then return end

    self:Pop()
end

function Plugin:PrintQueue( Client )
    local Message = {}

    if self.PlayerQueue:GetCount() == 0 then
        Message[1] = "Player Slot Queue is currently empty."
    else

        Message[#Message + 1] = "Player Slot Queue:"
        for SteamId, Position in self.PlayerQueue:Iterate() do
            local ClientName = "Unknown"
            local QueuedClient = Shine.GetClientByNS2ID( SteamId )
            if QueuedClient then
                ClientName = Shine.GetClientName( QueuedClient )
            end

            Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
        end

        if self.ReservedQueue:GetCount() > 0 then
            Message[#Message + 1] = "\n Reserved Slot Queue:"

            for SteamId, Position in self.ReservedQueue:Iterate() do
                local ClientName = "Unknown"
                local QueuedClient = Shine.GetClientByNS2ID( SteamId )
                if QueuedClient then
                    ClientName = Shine.GetClientName( QueuedClient )
                end

                Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
            end
        end

    end

    local NumPlayers, MaxPlayers, NumReserved = self:GetSlotCounts()
    Message[#Message + 1] = string.format("\n%d/%d player slots used, %d of them reserved.",
        NumPlayers, MaxPlayers, NumReserved)

    if not Client then
        Notify( TableConcat( Message, "\n" ) )
    else
        for i = 1, #Message do
            ServerAdminPrint( Client, Message[ i ] )
        end
    end
end

function Plugin:CreateCommands()
    local function EnqueuePlayer(Client )
        if not Client then return end

        self:Enqueue(Client)
    end
    local Enqueue = self:BindCommand( "sh_rr_enqueue", "rr_enqueue", EnqueuePlayer, true )
    Enqueue:Help("Enter the queue for a player slot")

    local function DequeuePlayer( Client )

        if not self:Dequeue(Client) then
            self:NotifyTranslatedError( Client, "DEQUEUE_FAILED")
            return
        end


        self:NotifyTranslated( Client, "DEQUEUE_SUCCESS")
    end

    local Dequeue = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Dequeue:Help("Leave the player slot queue")

    local function DisplayPosition( Client )
        local position = self:GetQueuePosition( Client )
        if not position then
            self:NotifyTranslatedError( Client, "QUEUE_POSITION_UNKNOWN")
            return
        end

        self:SendQueuePosition( Client, position )
    end
    local Position = self:BindCommand( "sh_rr_position", "rr_position", DisplayPosition, true )
    Position:Help("Returns your current position in the player slot queue")

    local function PrintQueue( Client )
        self:PrintQueue( Client )
    end
    self:BindCommand( "sh_rr_printqueue", nil , PrintQueue, true )

    local function ListClients( Client )
        local Message = {}

        local Clients, Count = Shine.GetAllClients()
        for i = 1, Count do
            local client = Clients[ i ]
            local ClientPlayer = client:GetControllingPlayer()
            Message[#Message + 1] = string.format("%s - spectator: %s - team: %s",
                Shine.GetClientInfo(client), tostring( client:GetIsSpectator() ),
                tostring( ClientPlayer and ClientPlayer:GetTeamNumber() ))
        end

        if not Client then
            Notify( TableConcat( Message, "\n" ) )
        else
            for i = 1, #Message do
                ServerAdminPrint( Client, Message[ i ] )
            end
        end
    end
    self:BindCommand( "sh_rr_listclients", nil , ListClients, true )
end

function Plugin:MapChange()
    if not self.Config.RestoreQueueAfterMapchange then return end

    self:SaveQueueHistory()
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )

    self.GraceExpiries = nil
    self.InRoundEndMove = nil
    self.Popping = nil
    self.QueuesDirty = nil
    self.connectionChecked = nil
    self.Enabled = false
end
