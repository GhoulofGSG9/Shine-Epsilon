--[[
    Shine No Rookies - Server
]]
local Shine = Shine
local InfoHub = Shine.PlayerInfoHub
local Plugin = Plugin

Plugin.Version = "1.6"

Plugin.ConfigName = "norookies.json"
Plugin.DefaultConfig =
{
    UseSteamTime = true,
    MinPlayer = 0,
    DisableAfterRoundtime = 0,
    MinPlaytime = 8,
    MinComPlaytime = 8,
    ShowInform = true,
    InformMessage = "This server is not rookie friendly",
    BlockTeams = true,
    ShowSwitchAtBlock = false,
    BlockCC = false,
    AllowSpectating = false,
    BlockMessage = "This server is not rookie friendly",
    Kick = true,
    Kicktime = 20,
    KickMessage = "You will be kicked in %s seconds",
    WaitMessage = "Please wait while we fetch your stats.",
}

Plugin.Name = "No Rookies"
Plugin.DisconnectReason = "You didn't fit to the required playtime"

local Enabled = true --used to temp disable the plugin in case the given player limit is reached

function Plugin:CheckForSteamTime()
	if self.Config.UseSteamTime or self.Config.ForceSteamTime then
		InfoHub:Request( self.Name, "STEAMPLAYTIME" )
    end
end

function Plugin:BuildBlockMessage()
    self.BlockMessage = self.Config.BlockMessage
end

function Plugin:SetGameState( _, NewState )
    if NewState == kGameState.Started and self.Config.DisableAfterRoundtime and self.Config.DisableAfterRoundtime > 0 then        
        self:CreateTimer( "Disable", self.Config.DisableAfterRoundtime * 60 , 1, function() Enabled = false end )
    end
end

function Plugin:EndGame()
    self:DestroyTimer( "Disable" )
    Enabled = true
end

function Plugin:CheckCommLogin( _, Player )
    if not self.Config.BlockCC or not Player or not Player.GetClient or Shine.GetHumanPlayerCount() < self.Config.MinPlayer then return end

    return self:Check( Player, true )
end

function Plugin:CheckValues( Playerdata, SteamId, ComCheck )
    PROFILE("NoRookies:CheckValues()")
    if not Enabled then return end

    --check the config first if we should process check on players joining a team
    if not ComCheck then
	    if not self.Config.BlockTeams then return true end
	    if Shine.GetHumanPlayerCount() < self.Config.MinPlayer then return end
    end

    --check if Player fits to the PlayTime
    local Playtime = Playerdata.playTime
    if self.Config.UseSteamTime then
	    local SteamTime = InfoHub:GetSteamData( SteamId ).PlayTime
	    if SteamTime and SteamTime > Playtime then
		    Playtime = SteamTime
	    end
    end

	local Min = ComCheck and self.Config.MinComPlaytime or self.Config.MinPlaytime
    return Playtime >= Min * 3600
end