local Plugin = Plugin

Plugin.HasConfig = true
Plugin.ConfigName = "BotManager.json"
Plugin.DefaultConfig =
{
	MaxBots = 12,
	CommanderBots = false,
	AllowPlayersToReplaceComBots = true
}
Plugin.CheckConfig = true

do
	Shine.Hook.SetupClassHook("NS2Gamerules", "GetCanJoinTeamNumber", "PostGetCanJoinTeamNumber", function (OldFunc, ...)
		local a, b = OldFunc( ... )

		local Hook = Shine.Hook.Call("PostActiveGetCanJoinTeamNumber", a, b)

		return Hook or a, b
	end)
end

function Plugin:Initialise()
	self.Enabled = true

	self.MaxBots = self.Config.MaxBots
	self.CommanderBots = self.Config.CommanderBots

	self.dt.AllowPlayersToReplaceComBots = self.Config.AllowPlayersToReplaceComBots

	self:CreateCommands()

	return true
end

function Plugin:OnFirstThink()
	self:SetMaxBots(self.MaxBots, self.CommanderBots)
end

function Plugin:SetMaxBots(bots, com)
	local Gamerules = GetGamerules()

	if not Gamerules or not Gamerules.SetMaxBots then return end

	Gamerules:SetMaxBots(bots, com)
end

function Plugin:PostActiveGetCanJoinTeamNumber( _, Reason )
	if self.dt.AllowPlayersToReplaceComBots and Reason then
		local rookieMode = GetGamerules().gameInfo:GetRookieMode(true)
		if Reason == 2 and not rookieMode then return true end
	end
end

function Plugin:CreateCommands()
	local function MaxBots( _, Number, SaveIntoConfig )
		self:SetMaxBots( Number, self.Config.CommanderBots )

		self.MaxBots = Number

		if SaveIntoConfig then
			self.Config.MaxBots = Number
			self:SaveConfig()
		end
	end
	local ShowNewsCommand = self:BindCommand( "sh_maxbots", "maxbots", MaxBots )
	ShowNewsCommand:AddParam{ Type = "number", Min = 0, Error = "Please specify the amount of bots you want to set.", Help = "Maximum number of bots"  }
	ShowNewsCommand:AddParam{ Type = "boolean", Default = false, Help = "true = save change", Optional = true  }
	ShowNewsCommand:Help( "Sets the maximum amount of bots currently allowed at this server." )

	local function MaxBots( _, Enable, SaveIntoConfig )
		self:SetMaxBots( self.Config.MaxBots, Enable )

		self.CommanderBots = Enable

		if SaveIntoConfig then
			self.Config.CommanderBots = Enable
			self:SaveConfig()
		end
	end
	local ShowNewsCommand = self:BindCommand( "sh_enablecombots", "enablecombots", MaxBots )
	ShowNewsCommand:AddParam{ Type = "boolean", Error = "Please specify if you want to enable commander bots", Help = "true = add commander bots"  }
	ShowNewsCommand:AddParam{ Type = "boolean", Default = false, Help = "true = save change", Optional = true  }
	ShowNewsCommand:Help( "Sets if teams should be filled with commander bots or not" )

end

