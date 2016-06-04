--[[
    Shine BotManager
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "0.1"

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "AllowPlayersToReplaceComBots", true )
end

Shine.Hook.SetupClassHook("GameInfo", "GetRookieMode", "GetRookieMode", "ActivePre")

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:GetRookieMode(GameInfo, ShineForce)
	if not ShineForce and self.dt.AllowPlayersToReplaceComBots ~= GameInfo.rookieMode then
		return true
	end
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

Shine:RegisterExtension( "botmanager", Plugin )
