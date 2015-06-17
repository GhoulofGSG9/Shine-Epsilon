local Plugin = {}
local Shine = Shine
local InfoHub = Shine.PlayerInfoHub

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "FakeServerIp.json"
Plugin.DefaultConfig =
{
	MaxRookieTime = 8,
	Kick = false,
	Ban = false,
	Bantime = 30,
	UseSteamPlayTime = true
}
Plugin.CheckConfig = true

Shine.Hook.SetupClassHook("Player", "SetRookieMode", "OnSetRookie", "Halt")

function Plugin:Initialise()
	self.Enabled = true
	self.PlayTimes = {}

	self.Config.MaxRookieTime = math.min(8, self.Config.MaxRookieTime)

	if self.Config.UseSteamPlayTime then
		InfoHub:Request( self.Name, "STEAMPLAYTIME" )
	end

	return true
end

function Plugin:OnReceiveSteamData( Client, Data )
	local SteamId = Client:GetUserID()

	if not self.Playtimes[SteamId] then self.Playtimes[SteamId] = -1 end

	if Data.PlayTime > self.Playtimes[SteamId] then
		self.Playtimes[SteamId] = Data.PlayTime
	end
end

function Plugin:OnReceiveHiveData( Client, Data )
	local SteamId = Client:GetUserID()

	if not self.Playtimes[SteamId] then self.Playtimes[SteamId] = -1 end

	if Data and Data.playTime > self.Playtimes[SteamId] then
		self.Playtimes[SteamId] = Data.playTime
	end
end

function Plugin:OnSetRookie( Player, Mode, Force )
	if Force then return end

	if not Mode then return end

	return self:CheckPlayer(Player, Mode)
end

function Plugin:CheckPlayer( Player, Mode )
	local Client = Player:GetClient()
	local SteamId = Client and Player:GetSteamId()

	if not SteamId or SteamId < 1 then return end
	if not InfoHub:GetIsRequestFinished( SteamId ) then return end

	if self.PlayTimes[SteamId] <= self.Config.MaxRookieTime then return end --Real Rookies or Timeouts

	if Player:GetIsRookie() or Mode then --Player tried to fake Rookie
		Player:SetRookie(false, true)
		if self.Config.Ban then
			local bancommand = string.format("sh_banid %s %s Banned by the nomorefakerookies plugin", SteamId,
				self.Config.Bantime)
			Shared.ConsoleCommand(bancommand)
		elseif self.Config.Kick then
			Shared.ConsoleCommand( string.format("sh_kick %s Kicked by the nomorefakerookies plugin", SteamId))
		end
	end

	return true
end

function Plugin:CleanUp()
	self.BaseClass.CleanUp()
	self.Enabled = false
end

Shine:RegisterExtension( "nomorefakerookies", Plugin )

