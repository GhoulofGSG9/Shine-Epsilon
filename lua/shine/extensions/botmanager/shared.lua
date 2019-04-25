--[[
    Shine BotManager
]]
local Plugin = Shine.Plugin( ... )
Plugin.Version = "0.2"

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "AllowPlayersToReplaceComBots", true )
	self:AddDTVar( "boolean", "LoginCommanderBotAtLogout", false )
end

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:OnFirstThink()
	if Server then
		Shine.Hook.SetupClassHook("NS2Gamerules", "OnCommanderLogout", "PreOnCommanderLogout", "PassivePre")
		Shine.Hook.SetupClassHook("NS2Gamerules", "OnCommanderLogin", "PreOnCommanderLogi", "PassivePre")
	end

	Shine.Hook.SetupClassHook("GameInfo", "GetRookieMode", "GetRookieMode", "ActivePre")
	Shine.Hook.SetupClassHook("GameInfo", "GetRookieMode", "PostGetRookieMode", "PassivePost")
end

function Plugin:PreOnCommanderLogin()
	self.OverrideRookieMode = true
end

function Plugin:PreOnCommanderLogout()
	self.OverrideRookieMode = self.dt.LoginCommanderBotAtLogout
end

function Plugin:GetRookieMode(GameInfo)
	if self.OverrideRookieMode and self.dt.AllowPlayersToReplaceComBots ~= GameInfo.rookieMode then
		return true
	end
end

function Plugin:PostGetRookieMode()
	self.OverrideRookieMode = false
end

return Plugin
