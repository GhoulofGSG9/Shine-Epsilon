--[[
    Shine No Rookies - Server
]]
local Shine = Shine
local Plugin = Plugin

Plugin.Version = "1.0"

Plugin.ConfigName = "RookiesOnly.json"
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
    WaitMessage = "Please wait while we fetch your stats.",
    ShowSwitchAtBlock = false
}

Plugin.Name = "Rookies Only"
Plugin.DisconnectReason = "You are not a rookie anymore"

function Plugin:CheckForSteamTime() --This plugin does not use steam times at all
end

function Plugin:BuildBlockMessage()
    self.BlockMessage = self.Config.BlockMessage
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
