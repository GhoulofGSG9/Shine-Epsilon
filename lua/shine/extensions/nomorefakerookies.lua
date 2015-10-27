local Plugin = {}
local Shine = Shine
local InfoHub = Shine.PlayerInfoHub

Plugin.Version = "1.0"
Plugin.NS2Only = true

Plugin.HasConfig = true
Plugin.ConfigName = "NoMoreFakeRookies.json"
Plugin.DefaultConfig =
{
	MaxRookieTime = 15,
	MaxHiveLevel = 2,
	Kick = false,
	Ban = false,
	Bantime = 30,
	UseSteamPlayTime = true
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Shine.Hook.SetupClassHook("Player", "SetRookieMode", "OnSetRookie", "Halt")

function Plugin:Initialise()
	self.Enabled = true
	self.Playtimes = {}
	self.Levels =  {}

	self.Config.MaxRookieTime = math.min(8, self.Config.MaxRookieTime)

	if self.Config.UseSteamPlayTime then
		InfoHub:Request("nomorefakerookies", "STEAMPLAYTIME")
	else
		for _, client in ipairs(Shine.GetAllClients()) do
			local data = InfoHub:GetHiveData(client:GetUserId())
			if data then
				self:OnReceiveHiveData(client, data)
			end
		end
	end

	return true
end

function Plugin:OnReceiveSteamData(Client, Data)
	local SteamId = Client:GetUserId()

	if not self.Playtimes[SteamId] then self.Playtimes[SteamId] = -1 end

	if Data.PlayTime > self.Playtimes[SteamId] then
		self.Playtimes[SteamId] = Data.PlayTime
	end

	self:CheckPlayer(Client:GetControllingPlayer())
end

function Plugin:OnReceiveHiveData(Client, Data)
	local SteamId = Client:GetUserId()

	if not self.Playtimes[SteamId] then self.Playtimes[SteamId] = -1 end

	self.Levels[SteamId] = Data and Data.level or -1

	if Data and Data.playTime > self.Playtimes[SteamId] then
		self.Playtimes[SteamId] = Data.playTime
	end

	self:CheckPlayer(Client:GetControllingPlayer())
end

function Plugin:OnSetRookie(Player, Mode)
	if not Mode then return end

	return self:CheckPlayer(Player, Mode)
end

function Plugin:CheckPlayer(Player, Mode)
	if not Player then return end

	local Client = Player:GetClient()
	local SteamId = Client and Player:GetSteamId()

	if not SteamId or SteamId < 1 or not self.Levels[SteamId] then return end

	if self.Playtimes[SteamId] <= self.Config.MaxRookieTime then return end --real rookies or timeouts

	if self.Levels[SteamId] <= self.Config.MaxHiveLevel then return end -- hive level check

	if Player:GetIsRookie() or Mode then --Player tried to fake rookie status
		Player:SetRookieMode(false)
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
	InfoHub:RemoveRequest("nomorefakerookies", "STEAMPLAYTIME")

	self.BaseClass.CleanUp()
	self.Enabled = false
end

Shine:RegisterExtension("nomorefakerookies", Plugin)

