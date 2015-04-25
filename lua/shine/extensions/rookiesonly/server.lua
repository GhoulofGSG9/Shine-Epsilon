--[[
    Shine No Rookies - Server
]]
local Shine = Shine
local Plugin = Plugin

Plugin.Version = "1.0"
Plugin.HasConfig = true

Plugin.ConfigName = "rookiesonly.json"
Plugin.DefaultConfig =
{
    Mode = 1, -- 1: Level 2: Playtime
    MaxPlaytime = 20,
    MaxLevel = 5,
    ShowInform = false,
    InformMessage = "This server is rookies only",
    AllowSpectating = true,
    BlockMessage = "This server is rookies only",
    Kick = true,
    Kicktime = 20,
    KickMessage = "You will be kicked in %s seconds",
    WaitMessage = "Please wait while your data is retrieved",
    ShowSwitchAtBlock = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Name = "Rookies Only"
Plugin.DisconnectReason = "You are not a rookie anymore"

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" then
        return false, string.format( "The rookie-only plugin does not work with %s.", Gamemode )
    end

    self.Enabled = true

    self.BlockMessage = self.Config.BlockMessage
    self.Config.Mode = math.Clamp( self.Config.Mode, 1, 2 )

    return true
end

function Plugin:CheckValues( Playerdata )
    if self.Mode == 1 then
        if self.Config.MaxLevel > 0 and Playerdata.level <= self.Config.MaxLevel then
            return true
        end
    elseif self.Config.MaxPlaytime > 0 or Playerdata.playTime <= self.Config.MaxPlaytime * 3600 then
        return true
    end

	return false
end
