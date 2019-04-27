local Shine = Shine

local Notify = Shared.Message

local TableConcat = table.concat

local Plugin = ...
Plugin.PrintName = "Ready Room Queue"

Plugin.HasConfig = false

function Plugin:Initialise()
    self.Enabled = true

    self.PlayerQueue = Shine.Map()
    self.ReservedQueue = Shine.Map() -- for players with reserved slots

    self:CreateCommands()

    return true
end

function Plugin:OnFirstThink()
    Shine.Hook.SetupClassHook( "Gamerules", "GetCanJoinPlayingTeam", "OnGetCanJoinPlayingTeam", function( OldFunc, self, player, skipHook )
        local result = OldFunc( self, player )

        if not skipHook then
            Shine.Hook.Call( "OnGetCanJoinPlayingTeam", self, player, result )
        end

        return result
    end )
end

function Plugin:ClientDisconnect( Client )
    if not Client or Client:GetIsVirtual() then return end

    if Client:GetIsSpectator() then
        self:Dequeue( Client )
    else
        Client:SetIsSpectator(true)
        self:Pop()
    end
end

function Plugin:OnGetCanJoinPlayingTeam( _, Player, Allowed)
    if not Allowed and Player:GetIsSpectator() then
        local Client = Player:GetClient()
        if Client then
            self:Enqueue(Client)
        end
    end
end

function Plugin:GetQueuePosition(Client)
    local SteamId = Client:GetUserId()

    return self.PlayerQueue:Get(SteamId)
end

function Plugin:PostJoinTeam( _, _, _, NewTeam)
    if NewTeam ~= kSpectatorIndex then return end

    self:Pop()
end

function Plugin:Enqueue( Client )
    if not Client:GetIsSpectator() then
        self:NotifyTranslatedError("ENQUEUE_ERROR_PLAYER")
    end

    local SteamID = Client:GetUserId()

    if not SteamID or SteamID < 1 then return end

    local position = self.PlayerQueue:Get( SteamID )
    if position then
        self:SendTranslatedNotify(Client, "QUEUE_POSITION", {
            Position = position
        })

        return
    end

    position = self.PlayerQueue:GetCount() + 1
    self.PlayerQueue:Add(SteamID, position)
    self:SendTranslatedNotify(Client, "QUEUE_ADDED", {
        Position = position
    })
    if GetHasReservedSlotAccess( SteamID ) then
        position = self.ReservedQueue:GetCount() + 1
        self.ReservedQueue:Add(SteamID, position)
        self:SendTranslatedNotify(Client, "PIORITY_QUEUE_ADDED", {
            Position = position
        })
    end
end

function Plugin:UpdateQueuePositions(queue, message)
    message = message or "QUEUE_CHANGED"

    local i = 1
    for SteamId, Position in queue:Iterate() do
        local Client = Shine.GetClientByNS2ID( SteamId )
        if Client then
            if Position ~= i then
                queue:Add(SteamId, i)
                self:SendTranslatedNotify(Client, message, {
                    Position = i
                })
            end

            i = i + 1
        else
            queue:Remove(SteamId)
        end
    end
end

function Plugin:Dequeue( Client )
    if not Client then return end

    local SteamID = Client:GetUserId()

    local position = self.PlayerQueue:Remove(SteamID)
    if not position then return false end

    self:UpdateQueuePositions(self.PlayerQueue)

    position = self.ReservedQueue:Remove(SteamID)
    if position then
        self:UpdateQueuePositions(self.ReservedQueue, "PIORITY_QUEUE_CHANGED")
    end

    return true
end

function Plugin.GetFirst(Queue)
    Queue:ResetPosition()
    return Queue:GetNext()
end

function Plugin:PopReserved()
    local Gamerules = GetGamerules()
    if not Gamerules then -- abort mission
        return
    end

    local First = self.GetFirst(self.ReservedQueue)
    if not First then return end --empty queue

    local Client = Shine.GetClientByNS2ID( First )
    assert(Client)

    local Player = Client:GetControllingPlayer()
    if not Player or Gamerules:GetCanJoinPlayingTeam(Player, true) then
        return false
    end

    if not Gamerules:JoinTeam(Player, kTeamReadyRoom ) then
        return false
    end

    self.ReservedQueue:Remove(First)
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    self:UpdateQueuePositions(self.ReservedQueue, "PIORITY_QUEUE_CHANGED")

    return true
end

function Plugin:Pop()
    local Gamerules = GetGamerules()
    if not Gamerules then -- abort mission
        return
    end

    local First = self.GetFirst(self.PlayerQueue)
    if not First then return end --empty queue

    local Client = Shine.GetClientByNS2ID( First )
    assert(Client)

    local Player = Client:GetControllingPlayer()

    if not Gamerules:GetCanJoinPlayingTeam(Player, true) then
        return self:PopReserved()
    end

    if not Gamerules:JoinTeam(Player, kTeamReadyRoom) then
        return false
    end

    self.PlayerQueue:Remove(First)
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    self:UpdateQueuePositions(self.PlayerQueue)

    return true
end

function Plugin:PrintQueue(Client)
    local Message = {
        "Player Slot Queue:"
    }

    for SteamId, Position in self.PlayerQueue:Iterate() do
        local ClientName = "Unknown"
        local QueuedClient = Shine.GetClientByNS2ID(SteamId)
        if QueuedClient then
            ClientName = Shine.GetClientName(QueuedClient)
        end

        Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
    end

    Message[#Message + 1] = "\n Reserved Slot Queue:"

    for SteamId, Position in self.ReservedQueue:Iterate() do
        local ClientName = "Unknown"
        local QueuedClient = Shine.GetClientByNS2ID(SteamId)
        if QueuedClient then
            ClientName = Shine.GetClientName(QueuedClient)
        end

        Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
    end

    if not Client then
        Notify( TableConcat( Message, "\n" ) )
    else
        for i = 1, #Message do
            ServerAdminPrint( Client, Message[ i ] )
        end
    end
end

function Plugin:CreateCommands()
    local function EnqueuPlayer( Client )
        if not Client then return end

        self:Enqueue(Client)
    end
    local Enqueue = self:BindCommand( "sh_rr_enqueue", "rr_enqueue", EnqueuPlayer, true )
    Enqueue:Help("Enter the queue for a player slot")

    local function DequeuePlayer( Client )

        if not self:Dequeue(Client) then
            self:NotifyTranslatedError( Client, "DEQUEUE_FAILED")
        end


        self:NotifyTranslated( Client, "DEQUEUE_SUCCESS")
    end

    local Dequeue = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Dequeue:Help("Leave the player slot queue")

    local function DisplayPosition( Client )
        local position = self:GetQueuePosition(Client)
        if not position then
            self:NotifyTranslatedError( Client, "QUEUE_POSITION_UNKNOWN")
            return
        end

        self:SendTranslatedNotify(Client, "QUEUE_POSITION", {
            Position = position
        })
    end
    local Position = self:BindCommand( "sh_rr_position", "rr_position", DisplayPosition, true )
    Position:Help("Returns your current position in the player slot queue")

    local function PrintQueue(Client)
        self:PrintQueue(Client)
    end
    local Print = self:BindCommand( "sh_rr_printqueue", nil , PrintQueue, true )
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )
    self.Enabled = false
end