local Plugin = Plugin
local Shine = Shine

function Plugin:Initialise()
	self.Enabled = true

	self:CreateCommands()

	self.ClientConfigs = {}

	return true
end

function Plugin:GetClientConfig(Player)
	local id = Player:GetSteamId()

	if id == -1 then return end

	if not self.ClientConfigs[id] then
		self.ClientConfigs[id] = {
			Listen = {
				false,
				false,
				false,
				true
			},
			Speak = {
				false,
				false,
				false,
				true
			},
			Receive = {
				false,
				false,
				false,
				true
			},
			Send = {
				false,
				false,
				false,
				true
			},
		}
	end

	return self.ClientConfigs[id]
end

function Plugin:SetClientConfig( Player, Field, Team, Value)
	local id = Player:GetSteamId()
	local client = Player:GetClient()

	if id == -1 or not client then return end

	if self:GetClientConfig(Player) then
		self.ClientConfigs[id][Field][Team + 1] = Value

		local menuId = self.FieldToMenuOffset[Field] + Team + 1
		self:SendNetworkMessage( client, "MenuUpdate", { button = menuId, enabled = Value }, true )
	end
end

function Plugin:CanPlayerHearPlayer( Gamerules, Listener, Speaker )
	local listenerTeam = Listener:GetTeamNumber()
	local speakerTeam = Speaker:GetTeamNumber()

	local canhear

	if speakerTeam == kSpectatorIndex then
		local config = self:GetClientConfig(Speaker)

		if config then
			canhear = config.Speak[listenerTeam + 1]
		end
	end

	if listenerTeam == kSpectatorIndex then
		local config = self:GetClientConfig(Listener)

		if config then
			canhear = config.Listen[speakerTeam + 1]
		end
	end

	return canhear

end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	local Client = Player:GetClient()

	if not Client then return end

	local add = NewTeam == kSpectatorIndex
	self:SendNetworkMessage( Client, "Menu", {add = add}, true )
end

function Plugin:PlayerSay( Client, MessageTable )

	if not MessageTable.teamOnly then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local PlayerName = Player:GetName()
	local PlayerTeamNumber = Player:GetTeamNumber()

	local TeamColors = {
		{ 255, 255, 255 },
		{ 81, 194, 243 },
		{ 255, 192, 46 },
		{ 255, 255, 255 }
	}
	local colour = TeamColors[PlayerTeamNumber + 1]

	if PlayerTeamNumber ~= kSpectatorIndex then
		local function SendMessage(Player)
			local config = self:GetClientConfig(Player)

			if config and config.Receive[PlayerTeamNumber + 1] then
				Shine:NotifyDualColour(Player:GetClient(), colour[1], colour[2], colour[3], PlayerName,
					colour[1], colour[2], colour[3], string.format("(Team) %s", MessageTable.message))
			end
		end

		Gamerules:GetSpectatorTeam():ForEachPlayer(SendMessage)
	else
		local config = self:GetClientConfig(Player)

		if not config then return end

		local function SendMessage(Player)
			Shine:NotifyDualColour(Player:GetClient(), colour[1], colour[2], colour[3], PlayerName,
				colour[1], colour[2], colour[3], string.format("(Team) %s", MessageTable.message))
		end

		for i = 1, 3 do
			if config.Send[i] then
				local team = Gamerules:GetTeam( i-1 )
				if team then
					team:ForEachPlayer(SendMessage)
				end
			end
		end

		--We send team chat messages for specs manually ourself to take each players current
		--config into account.
		if config.Send[4] then
			local function SendMessageToSpec(Player)
				local config = self:GetClientConfig(Player)

				if config and config.Receive[4] then
					Shine:NotifyDualColour(Player:GetClient(), colour[1], colour[2], colour[3], PlayerName,
						colour[1], colour[2], colour[3], string.format("(Team) %s", MessageTable.message))
				end
			end

			Gamerules:GetSpectatorTeam():ForEachPlayer(SendMessageToSpec)
		end

		--Don't send the message to other spectators
		return ""
	end

end

function Plugin:CreateCommands()
	local Listen = self:BindCommand( "sh_spec_receive_voice", "spec_receive_voice" , function( Client, Channel, Enabled)
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		if Player:GetTeamNumber() ~= kSpectatorIndex then
			-- Inform about that only spec can use this
		end

		local Config = self:GetClientConfig(Player)
		local Change = Enabled == nil and not Config.Listen[Channel] or Enabled

		self:SetClientConfig(Player, "Listen", Channel, Change)
	end, true, true )
	Listen:AddParam{ Type = "number", Min = 0, Max = 3, Round = true, Help = "The team channel you want to en-/disable."}
	Listen:AddParam{ Type = "boolean", Optional = true, Help = "Determ if the channel should be en- or disabled." }
	Listen:Help( "Allows you to choose to which voice channels you want to listen as spectator." )

	local Speak = self:BindCommand( "sh_spec_send_voice", "spec_send_voice" , function( Client, Channel, Enabled)
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		if Player:GetTeamNumber() ~= kSpectatorIndex then
			-- Inform about that only spec can use this
		end

		local Config = self:GetClientConfig(Player)
		local Change = Enabled == nil and not Config.Speak[Channel] or Enabled

		self:SetClientConfig(Player, "Speak", Channel, Change)
	end, true, true )
	Speak:AddParam{ Type = "number", Min = 0, Max = 3, Round = true, Help = "The team channel you want to en-/disable."}
	Speak:AddParam{ Type = "boolean", Optional = true, Help = "Determ if the channel should be en- or disabled." }
	Speak:Help( "Allows you to choose to which voice channels you want to send to as spectator." )

	local Receive = self:BindCommand( "sh_spec_receive_chat", "spec_receive_chat" , function( Client, Channel, Enabled)
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		if Player:GetTeamNumber() ~= kSpectatorIndex then
			-- Inform about that only spec can use this
		end

		local Config = self:GetClientConfig(Player)
		local Change = Enabled == nil and not Config.Receive[Channel] or Enabled

		self:SetClientConfig(Player, "Receive", Channel, Change)
	end, true, true )

	Receive:AddParam{ Type = "number", Min = 0, Max = 3, Round = true, Help = "The team channel you want to en-/disable."}
	Receive:AddParam{ Type = "boolean", Optional = true, Help = "Determ if the channel should be en- or disabled." }
	Receive:Help( "Allows you to choose to which chat team channels you want to receive to as spectator." )

	local Send = self:BindCommand( "sh_spec_send_chat", "spec_send_chat" , function( Client, Channel, Enabled)
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		if Player:GetTeamNumber() ~= kSpectatorIndex then
			-- Inform about that only spec can use this
		end

		local Config = self:GetClientConfig(Player)
		local Change = Enabled == nil and not Config.Send[Channel] or Enabled

		self:SetClientConfig(Player, "Send", Channel, Change)
	end, true, true )

	Send:AddParam{ Type = "number", Min = 0, Max = 3, Round = true, Help = "The team channel you want to en-/disable."}
	Send:AddParam{ Type = "boolean", Optional = true, Help = "Determ if the channel should be en- or disabled." }
	Send:Help( "Allows you to choose to which chat team channels you want to send to as spectator." )
end

function Plugin:Cleanup()
	self.ClientConfigs = nil

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end

