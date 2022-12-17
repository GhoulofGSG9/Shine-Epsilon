--[[
	Shine No Rookies - Server
]]
local InfoHub = Shine.PlayerInfoHub
local Plugin = ...

Plugin.Version = "1.8"

Plugin.ConfigName = "NoRookies.json"
Plugin.DefaultConfig =
{
	UseSteamTime = true,
	MinPlayer = 0,
	MinPlayerCom = 0,
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
	Debug = false,
	UseHiveLevel = false,
	LastPluginVersion = "1.8"
}

Plugin.PrintName = "No Rookies"
Plugin.DisconnectReason = "You didn't fit to the required playtime"

Plugin.Conflicts = {
	DisableThem = {
		"rookiesonly"
	},
	DisableUs = {
		"hiveteamrestriction"
	}
}

local Enabled = true --used to temp disable the plugin in case the given player limit is reached

function Plugin:Initialise()
	self.Enabled = true

	--copy old minplayer setting to minplayercom
	if self.Config.LastPluginVersion ~= self.Version then
		self.Config.MinPlayerCom = self.Config.MinPlayer
		self.Config.LastPluginVersion = self.Version
		self:SaveConfig()
	end

	self:CheckForSteamTime()
	self:BuildBlockMessage()

	return true
end

function Plugin:OnFirstThink()
	if Server.DisableQuickPlay and self.Config.BlockTeams and self.Config.MinPlaytime > 0 then
		self:Print("Tagging Server as incompatible to the quickplay queue because a playtime restriction is not supported by it.")
		Server.DisableQuickPlay()
	end
end

function Plugin:CheckForSteamTime()
	if self.Config.UseSteamTime or self.Config.ForceSteamTime then
		InfoHub:Request( self.PrintName, "STEAMPLAYTIME" )
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

function Plugin:ValidateCommanderLogin( _, _, Player )
	if not self.Config.BlockCC or not Player
            or not Player.GetClient or Shine.GetHumanPlayerCount() < self.Config.MinPlayerCom then return end

	return self:Check( Player, true )
end

function Plugin:JoinTeam( _, Player, NewTeam, _, ShineForce )
	if not self.Config.BlockTeams then return end

	if ShineForce or self.Config.AllowSpectating and NewTeam == kSpectatorIndex or NewTeam == kTeamReadyRoom then
		self:DestroyTimer( string.format( "Kick_%s", Player:GetSteamId() ))
		return
	end

	return self:Check( Player )
end

function Plugin:CheckValues( Playerdata, SteamId, ComCheck )
	PROFILE("NoRookies:CheckValues()")
	if not Enabled then return end

	if not self.Passed then self.Passed = { [1] = {}, [2] = {} } end
	if self.Passed[ComCheck and 2 or 1][SteamId] ~= nil then return self.Passed[ComCheck and 2 or 1][SteamId] end

	--check the config first if we should process check on players joining a team
	if not ComCheck then
		if not self.Config.BlockTeams then
			self.Passed[1][SteamId] = true
			return true
		end
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

	if self.Config.UseHiveLevel then
		Playtime = Playerdata.level * 3600
	end

	local Min = ComCheck and self.Config.MinComPlaytime or self.Config.MinPlaytime
	local Check = Playtime >= Min * 3600

	if self.Config.Debug then
		Print(string.format("NoRookie Debug: %s of %s = %s, Passed Check %s? %s",
				self.Config.UseHiveLevel and "Level" or "Playtime", SteamId, Playtime, ComCheck and 2 or 1, Check))
	end

	self.Passed[ComCheck and 2 or 1][SteamId] = Check
	return Check
end