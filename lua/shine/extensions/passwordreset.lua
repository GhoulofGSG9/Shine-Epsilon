--[[
    Shine PasswordReset
]]
local Notify = Shared.Message

local Plugin = Shine.Plugin( ... )
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PasswordReset.json"
Plugin.DefaultConfig =
{
    MinPlayer = 0,
    ResetTime = 10,
    DefaultPassword = "",
    StartPassword = ""
}
Plugin.CheckConfig = true

function Plugin:Initialise()
    self.Enabled = true

    if self.Config.StartPassword ~= "" then
        Notify( "[PasswordReset] Set password to start one" )
        Server.SetPassword(tostring(self.Config.StartPassword))
    end

    return true
end


function Plugin:ClientConnect()
    self:DestroyAllTimers()
end

function Plugin:ClientDisconnect()
    if Shine.GetHumanPlayerCount() >= self.Config.MinPlayer then return end

    self:SimpleTimer( self.Config.ResetTime * 60, function()
	if Shine.GetHumanPlayerCount() >= self.Config.MinPlayer then return end
        Notify( "[PasswordReset] Reseting password to default one" )
        Server.SetPassword( tostring( self.Config.DefaultPassword ) or "" )
    end )
end

return Plugin