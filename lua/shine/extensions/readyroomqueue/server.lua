local Shine = Shine
local StringFormat = string.format

local Plugin = Plugin
Plugin.Version = "1.0"

Plugin.HasConfig = false

function Plugin:Initialise()
    self.Enabled = true

    self.PlayerQueue = Queue()
    self.ReservedQueue = Queue() -- for players with reserved slots
    self.PlayerSet = Shine.Set()

    return true
end

function Plugin:ClientDisconnect( Client )
    if not Client or Client:GetIsVirtual() then return end

    if Client:GetIsSpectator() then
        self:Dequeue( Client )
    else
        self:Pop()
    end
end

function Plugin:GetFreePlayerSlots()
    local NumPlayers = Server.GetNumPlayersTotal()
    local NumRes = Server.GetReservedSlotLimit()
    local MaxPlayers = Server.GetMaxPlayers()

    local Enabled, ResPlugin = Shine:IsExtensionEnabled("reservedslots")
    if not Enabled or ResPlugin.Config.SlotType == Plugin.SlotType.PLAYABLE then
        return MaxPlayers - NumRes - NumPlayers, MaxPlayers - NumPlayers
    end

    local MaxSpecSlot = Server.GetMaxSpectators

end

function Plugin:JoinTeam( Gamerules, Player, _, NewTeam)
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam)
    if NewTeam ~= kSpectatorIndex then return end

    self:Pop()
end

function Plugin:Enqueue( Client )
    local SteamID = Client:GetUserID()

    if not SteamID or SteamID < 1 then return end

    if self.PlayerSet:Contains( SteamID ) then return end

    self.PlayerSet:Add( SteamID )
    self.PlayerQueue:Add(SteamID)

    if GetHasReservedSlotAccess( SteamID ) then
        self.ReservedQueue.Add(SteamID)
    end
end

function Plugin:Dequeue( Client )
    if not Client then return end

    local SteamID = Client:GetUserID()

    if not self.PlayerSet:Contains( SteamID ) then return end

    local i = 0
    local removed = false

    for id in self.PlayerQueue:Iterate() do
        i = i + 1

        if removed then

            local Client = Shine.GetClientByNS2ID( id )
            if Client then
                self:SendTranslatedNotify(Client, "QUEUE_CHANGED", {
                    Position = i
                })
            end

        elseif id == SteamID then

            self.PlayerSet:Remove( SteamID )
            self.PlayerQueue:Remove( self.PlayerQueue.CurrentNode.Previous )
            removed = true

        end
    end

end

function Plugin:GetFirst(Pop)
    local First = self.PlayerQueue:Peek()

    if not First then return end --empty queue

    local Client = Shine.GetClientByNS2ID( First )

    -- Let's try to cover up for corrupted data
    while not Client and self.PlayerQueue:Peek() do
        self.PlayerQueue:Pop()
        self.PlayerSet:Remove( First )

        First = self.PlayerQueue:Peek()
        Client = Shine.GetClientByNS2ID( First )
    end

    if Pop then
        self.PlayerQueue:Pop()
        self.PlayerSet:Remove( First )
    end

    return First
end

function Plugin:Pop()
    local Gamerules = GetGameRules()
    if not Gamerules then -- abort mission
        -- Todo Print error
        return
    end

    local First = self:GetFirst( true )
    if not First then return end --empty queue

    local Client = Shine.GetClientByNS2ID( First )

    if not Client then return end

    Gamerules:JoinTeam( Client:GetControllingPlayer(), kTeamReadyRoom )
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    local i = 0
    for id in self.PlayerQueue:Iterate() do
        i = i + 1

        local Client = Shine.GetClientByNS2ID( id )
        if Client then
            self:SendTranslatedNotify(Client, "QUEUE_CHANGED", {
                Position = i
            })
        end
    end
end

function Plugin:NotifyPlayersAboutChnage()

end

function Plugin:CreateCommands()
    local function EnqueuPlayer( Client )
        if not Client then return end

    end
    local Enqueue = self:BindCommand( "sh_rr_enqueue", "rr_enqueue", EnqueuPlayer, true )
    Enqueue:Help()

    local function DequeuePlayer( Client )

        if not self:Dequeue(SteamId) then
            self:NotifyTranslatedError( Client, "DEQUEUE_FAILED") -- Better handling?
        end


        self:SendTranslatedNotify( Client, "DEQUEUE_SUCCESS")
    end

    local Dequeue = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Dequeue:Help()

    local function DisplayPosition( Client )
    end
    local Position = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Position:Help()
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )
    self.Enabled = false
end