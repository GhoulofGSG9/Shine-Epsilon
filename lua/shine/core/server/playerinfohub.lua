--[[
	Shine PlayerInfoHub
]]
local Shine = Shine

local StringFormat = string.format
local JsonDecode = json.decode
local tostring = tostring
local Type = type
local IPairs = ipairs
local Pairs = pairs
local TableInsert = table.insert
local TableRemove = table.remove

local Add = Shine.Hook.Add
local IsValidClient = Shine.IsValidClient
local GetAllClients = Shine.GetAllClients

Shine.PlayerInfoHub = {}
local PlayerInfoHub = Shine.PlayerInfoHub

PlayerInfoHub.SteamData = {}
PlayerInfoHub.GeoData = {}
PlayerInfoHub.ENSLData = {}

local function Call( Name, Client, ... )
	if not IsValidClient( Shine, Client ) then return end
	Shine.Hook.Call( Name, Client, ... )
end

local ExternalAPIHandler = Shine.ExternalAPIHandler
local ENSLPoolSize = 256

PlayerInfoHub.ENSLEndpointBySteamId = PlayerInfoHub.ENSLEndpointBySteamId or {}
PlayerInfoHub.ENSLSteamIdByEndpointIndex = PlayerInfoHub.ENSLSteamIdByEndpointIndex or {}
PlayerInfoHub.ENSLNextEndpointIndex = PlayerInfoHub.ENSLNextEndpointIndex or 1

local function RegisterExternalAPIEndpoints()
	ExternalAPIHandler = Shine.ExternalAPIHandler
	if not ExternalAPIHandler or PlayerInfoHub.ExternalEndpointsRegistered then return end

	Shine.RegisterExternalAPIEndPoint( "Steam", "GetNS2PlayTime", {
		Protocol = "GET",
		URL = "IPlayerService/GetOwnedGames/v1/",
		Params = {
			steamid = Shine.NS2IDTo64,
			appid = function( AppID )
				return { { "appids_filter[0]", tostring( AppID ) } }
			end
		},
		DefaultRequestParams = {
			format = "json"
		},
		GetCacheKey = function( Params )
			return StringFormat( "%s:%s", tostring( Params.steamid ), tostring( Params.appid ) )
		end,
		ResponseTransformer = function( Response )
			if Type( Response ) ~= "table" then return nil end

			local Game = Response.response and Response.response.games and Response.response.games[ 1 ]
			if not Game then return 0 end

			return ( Game.playtime_forever or 0 ) * 60
		end
	} )

	Shine.RegisterExternalAPIEndPoint( "Steam", "GetPlayerBansByNS2ID", {
		Protocol = "GET",
		URL = "ISteamUser/GetPlayerBans/v1/",
		Params = {
			steamids = Shine.NS2IDTo64
		},
		DefaultRequestParams = {
			format = "json"
		},
		GetCacheKey = function( Params ) return tostring( Params.steamids ) end,
		ResponseTransformer = function( Response )
			if Type( Response ) ~= "table" then return nil end
			return Response.players and Response.players[ 1 ] or 0
		end
	} )

	Shine.RegisterExternalAPIEndPoint( "Steam", "GetNS2Badges", {
		Protocol = "GET",
		URL = "IPlayerService/GetBadges/v1/",
		Params = {
			steamid = Shine.NS2IDTo64
		},
		DefaultRequestParams = {
			format = "json"
		},
		GetCacheKey = function( Params ) return tostring( Params.steamid ) end,
		ResponseTransformer = function( Response )
			if Type( Response ) ~= "table" then return nil end

			local Badges = {
				Normal = 0,
				Foil = 0
			}

			local BadgeData = Response.response and Response.response.badges
			if BadgeData then
				for i = 1, #BadgeData do
					local Badge = BadgeData[ i ]
					if Badge.appid == 4920 then
						if Badge.border_color == 1 then
							Badges.Foil = 1
						else
							Badges.Normal = Badge.level
						end
					end
				end
			end

			return Badges
		end
	} )

	if not ExternalAPIHandler:GetAPI( "GeoIP" ) then
		Shine.RegisterExternalAPI( "GeoIP", {
			URL = "https://api.ipapi.is/",
			Params = {},
			GlobalRequestParams = {},
			EndPoints = {}
		} )
	end

	Shine.RegisterExternalAPIEndPoint( "GeoIP", "Lookup", {
		Protocol = "GET",
		URL = "",
		Params = {
			q = tostring
		},
		GetCacheKey = function( Params ) return tostring( Params.q ) end,
		ResponseTransformer = function( Response )
			if Type( Response ) ~= "table" then return nil end
			if Response.error or not Response.ip then return 0 end
			return Response
		end
	} )

	if not ExternalAPIHandler:GetAPI( "ENSL" ) then
		Shine.RegisterExternalAPI( "ENSL", {
			URL = "http://www.ensl.org/",
			Params = {},
			GlobalRequestParams = {},
			EndPoints = {}
		} )
	end

	PlayerInfoHub.ExternalEndpointsRegistered = true
end

RegisterExternalAPIEndpoints()

local function PerformExternalRequest( APIName, EndPointName, Params, OnSuccess, OnFailure )
	ExternalAPIHandler = Shine.ExternalAPIHandler
	if not ExternalAPIHandler then
		OnFailure()
		return
	end

	ExternalAPIHandler:PerformRequest( APIName, EndPointName, Params, {
		OnSuccess = OnSuccess,
		OnFailure = OnFailure,
		OnTimeout = OnFailure
	}, 2 )
end

local function RegisterENSLEndPoint( EndPointName, SteamId )
	Shine.RegisterExternalAPIEndPoint( "ENSL", EndPointName, {
		Protocol = "GET",
		URL = StringFormat( "api/v1/users/show/%s.steamid", SteamId ),
		Params = {},
		GetCacheKey = function() return tostring( SteamId ) end,
		ResponseTransformer = function( Response )
			if Type( Response ) ~= "table" then return nil end

			if Response and not Response.id then return 0 end

			return Response or 0
		end
	} )
end

local function GetENSLEndPointName( SteamId )
	local EndPointName = PlayerInfoHub.ENSLEndpointBySteamId[ SteamId ]
	if EndPointName then
		return EndPointName
	end

	local Index = PlayerInfoHub.ENSLNextEndpointIndex
	PlayerInfoHub.ENSLNextEndpointIndex = Index + 1
	if PlayerInfoHub.ENSLNextEndpointIndex > ENSLPoolSize then
		PlayerInfoHub.ENSLNextEndpointIndex = 1
	end

	local PreviousSteamId = PlayerInfoHub.ENSLSteamIdByEndpointIndex[ Index ]
	if PreviousSteamId then
		PlayerInfoHub.ENSLEndpointBySteamId[ PreviousSteamId ] = nil
	end

	EndPointName = StringFormat( "GetUserBySteamIDSlot_%s", Index )
	PlayerInfoHub.ENSLSteamIdByEndpointIndex[ Index ] = SteamId
	PlayerInfoHub.ENSLEndpointBySteamId[ SteamId ] = EndPointName

	RegisterENSLEndPoint( EndPointName, SteamId )

	return EndPointName
end

local function PerformENSLRequest( SteamId, OnSuccess, OnFailure )
	RegisterExternalAPIEndpoints()
	ExternalAPIHandler = Shine.ExternalAPIHandler
	if not ExternalAPIHandler then
		OnFailure()
		return
	end

	local EndPointName = GetENSLEndPointName( SteamId )
	if not ExternalAPIHandler:GetEndPoint( "ENSL", EndPointName ) then
		RegisterENSLEndPoint( EndPointName, SteamId )
	end

	PerformExternalRequest( "ENSL", EndPointName, {}, OnSuccess, OnFailure )
end

--[[
--Datatypes:
 - STEAMPLAYTIME
 - STEAMBADGES
 - STEAMBANS
 - GEOIP
 - ENSL
 ]]
PlayerInfoHub.Requests = {
	STEAMPLAYTIME = {},
	STEAMBADGES = {},
	STEAMBANS = {},
	GEODATA = {},
	ENSL = {}
}

PlayerInfoHub.HiveQueue = {}

function PlayerInfoHub:Request( Name, DataType)
	if not Name or not DataType then return end
	local Requests = self.Requests

	if Type( DataType ) == "table" then
		for i = 1, #DataType do
			local RequestType = DataType[ i ]
			TableInsert( Requests[ RequestType ], Name )
		end
	else
		TableInsert( Requests[ DataType ], Name )
	end

	local Clients = GetAllClients()
	for i = 1, #Clients do
		self:OnConnect( Clients[ i ] )
	end
end

function PlayerInfoHub:RemoveRequest( Name, DataType)
	local Requests = self.Requests
	if not DataType then
		for _, RequestList in Pairs( Requests ) do
			for i, name in IPairs( RequestList ) do
				if name == Name then
					TableRemove( RequestList, i )
				end
			end
		end
	else
		for i, name in IPairs( Requests[ DataType ] ) do
			if name == Name then
				TableRemove( Requests[ DataType ], i )
			end
		end
	end
end

function PlayerInfoHub:OnConnect( Client )
	PROFILE("PlayerInfoHub:OnConnect()")
	if not IsValidClient( Shine, Client ) then return end

	local SteamId = Client:GetUserId()
	if not SteamId or SteamId <= 0 then return end
	local SteamData = self.SteamData
	local GeoData = self.GeoData
	local ENSLData = self.ENSLData
	local Requests = self.Requests

	if not SteamData[ SteamId ] then
		SteamData[ SteamId ] = {
			Badges = {}
		}
	end

	local SteamEntry = SteamData[ SteamId ]

	local HiveData = self:GetHiveData( SteamId )
	if not HiveData then
		if self.HiveQueue[ SteamId ] == nil then
			self.HiveQueue[ SteamId ] = true
			Shine.Timer.Create( StringFormat("HiveRequest%s", SteamId), 5, 1, function()
				PlayerInfoHub.HiveQueue[ SteamId ] = false
				Call( "OnReceiveHiveData", Client, nil )
			end )
		end
	elseif self.HiveQueue[ SteamId ] == false then
		Call( "OnReceiveHiveData", Client, HiveData )
	end

	--[[
	-- Status:
	 - -2 = Fetching
	 - -1 = Timeout
	 ]]
	if Requests.STEAMPLAYTIME[1] then
		local function CallEvent()
			if (not Requests.STEAMBADGES[1] or SteamEntry.Badges.Normal ~= -2) and
					(not Requests.STEAMBANS[1] or SteamEntry.Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, SteamEntry )
			end
		end

		if not SteamEntry.PlayTime then
			SteamEntry.PlayTime = -2
			ExternalAPIHandler = Shine.ExternalAPIHandler

			if not ExternalAPIHandler or not ExternalAPIHandler:HasAPIKey( "Steam" ) then
				SteamEntry.PlayTime = -1
				CallEvent()
			else
				PerformExternalRequest( "Steam", "GetNS2PlayTime", {
					steamid = SteamId,
					appid = 4920
				}, function( PlayTime )
					SteamEntry.PlayTime = PlayTime or 0
					CallEvent()
				end, function()
					SteamEntry.PlayTime = -1
					CallEvent()
				end )
			end
		elseif SteamEntry.PlayTime ~= -2 then
			CallEvent()
		end
	end

	if Requests.STEAMBANS[1] then
		local function CallEvent()
			if (not Requests.STEAMPLAYTIME[1] or SteamEntry.PlayTime ~= -2) and
					(not Requests.STEAMBADGES[1] or SteamEntry.Badges.Normal ~= -2) then
				Call( "OnReceiveSteamData", Client, SteamEntry )
			end
		end

		if not SteamEntry.Bans then
			SteamEntry.Bans = -2
			ExternalAPIHandler = Shine.ExternalAPIHandler

			if not ExternalAPIHandler or not ExternalAPIHandler:HasAPIKey( "Steam" ) then
				SteamEntry.Bans = -1
				CallEvent()
			else
				PerformExternalRequest( "Steam", "GetPlayerBansByNS2ID", {
					steamids = SteamId
				}, function( Data )
					SteamEntry.Bans = Data or 0
					CallEvent()
				end, function()
					SteamEntry.Bans = -1
					CallEvent()
				end )
			end
		elseif SteamEntry.Bans ~= -2 then
			CallEvent()
		end
	end
	
	if Requests.ENSL[1] then
		local function CallEvent()
			Call( "OnReceiveENSLData", Client, ENSLData[ SteamId ] )
		end

		if not ENSLData[ SteamId ] then
			ENSLData[ SteamId ] = -2

			PerformENSLRequest( SteamId, function( Data )
				ENSLData[ SteamId ] = Data
				CallEvent()
			end, function()
				ENSLData[ SteamId ] = -1
				CallEvent()
			end )
		elseif ENSLData[ SteamId ] ~= -2 then
			CallEvent()
		end
	end

	if Requests.GEODATA[1] then
		if not GeoData[ SteamId ] then
			GeoData[ SteamId ] = -2

			PerformExternalRequest( "GeoIP", "Lookup", {
				q = IPAddressToString( Server.GetClientAddress( Client ) )
			}, function( Data )
				GeoData[ SteamId ] = Data or 0
				Call( "OnReceiveGeoData", Client, GeoData[ SteamId ] )
			end, function()
				GeoData[ SteamId ] = -1
				Call( "OnReceiveGeoData", Client, GeoData[ SteamId ] )
			end )
		elseif GeoData[ SteamId ] ~= -2 then
			Call( "OnReceiveGeoData", Client, GeoData[ SteamId ] )
		end
	end

	if Requests.STEAMBADGES[1] then
		local function CallEvent()
			if (not Requests.STEAMPLAYTIME[1] or SteamEntry.PlayTime ~= -2) and
					(not Requests.STEAMBANS[1] or SteamEntry.Bans ~= -2) then
				Call( "OnReceiveSteamData", Client, SteamEntry )
			end
		end

		if not SteamEntry.Badges.Normal then
			SteamEntry.Badges.Normal = -2
			ExternalAPIHandler = Shine.ExternalAPIHandler

			if not ExternalAPIHandler or not ExternalAPIHandler:HasAPIKey( "Steam" ) then
				SteamEntry.Badges.Normal = -1
				SteamEntry.Badges.Foil = -1
				CallEvent()
			else
				PerformExternalRequest( "Steam", "GetNS2Badges", {
					steamid = SteamId
				}, function( Badges )
					Badges = Badges or {
						Normal = 0,
						Foil = 0
					}

					SteamEntry.Badges.Normal = Badges.Normal
					SteamEntry.Badges.Foil = Badges.Foil
					CallEvent()
				end, function()
					SteamEntry.Badges.Normal = -1
					SteamEntry.Badges.Foil = -1
					CallEvent()
				end )
			end
		elseif SteamEntry.Badges.Normal ~= -2 then
			CallEvent()
		end
	end

end

Add( "ClientConnect", "GetPlayerInfo", function( Client )
	PlayerInfoHub:OnConnect( Client )
end )

if not GetHiveDataBySteamId then
	function GetHiveDataBySteamId(SteamId)

		local client = Shine.GetClientByNS2ID(SteamId)
		if not client then return end

		local kThunderdomeStatFields_TimePlayed = "td_total_time_player"
		local kThunderdomeStatFields_TimePlayedCommander = "td_total_time_commander"
		local kThunderdomeStatFields_Victories = "td_rounds_won_player"
		local kThunderdomeStatFields_CommanderVictories = "td_rounds_won_commander"


		local skillData =
		{
			skill = Server.GetUserStat_Int(client, Server.kSkillFields_Skill) or 0,
			skill_offset = Server.GetUserStat_Int(client, Server.kSkillFields_SkillOffset) or 0,
			comm_skill = Server.GetUserStat_Int(client, Server.kSkillFields_CommSkill) or 0,
			comm_skill_offset = Server.GetUserStat_Int(client, Server.kSkillFields_CommSkillOffset) or 0,
			adagrad = Server.GetUserStat_Float(client, Server.kSkillFields_Adagrad) or 0,
			comm_adagrad = Server.GetUserStat_Float(client, Server.kSkillFields_CommAdagrad) or 0,
			skill_sign = Server.GetUserStat_Int(client, Server.kSkillFields_SkillSign) or 0,
			comm_skill_sign = Server.GetUserStat_Int(client, Server.kSkillFields_CommSkillSign) or 0,

			td_skill = Server.GetUserStat_Int(client, Server.kSkillFields_TD_Skill) or 0,
			td_skill_offset = Server.GetUserStat_Int(client, Server.kSkillFields_TD_SkillOffset) or 0,
			td_comm_skill = Server.GetUserStat_Int(client, Server.kSkillFields_TD_CommSkill) or 0,
			td_comm_skill_offset = Server.GetUserStat_Int(client, Server.kSkillFields_TD_CommSkillOffset) or 0,
			td_adagrad = Server.GetUserStat_Float(client, Server.kSkillFields_TD_Adagrad) or 0,
			td_comm_adagrad = Server.GetUserStat_Float(client, Server.kSkillFields_TD_CommAdagrad) or 0,
			td_skill_sign = Server.GetUserStat_Int(client, Server.kSkillFields_TD_SkillSign) or 0,
			td_comm_skill_sign = Server.GetUserStat_Int(client, Server.kSkillFields_TD_CommSkillSign) or 0,

			score = Server.GetUserStat_Int(client, Server.kSkillFields_Score) or 0,
			level = Server.GetUserStat_Int(client, Server.kSkillFields_Level) or 0,
			xp = Server.GetUserStat_Int(client, Server.kSkillFields_Xp) or 0,

			time_played = Server.GetUserStat_Int(client, kThunderdomeStatFields_TimePlayed) or -1,
			com_time_played= Server.GetUserStat_Int(client, kThunderdomeStatFields_TimePlayedCommander) or -1,
			rounds_won = Server.GetUserStat_Int(client, kThunderdomeStatFields_Victories) or -1,
			com_rounds_won = Server.GetUserStat_Int(client, kThunderdomeStatFields_CommanderVictories) or -1
		}

		return skillData
	end
end

Shine.Hook.SetupClassHook("ScoringMixin", "SetPlayerLevel", "OnSetPlayerLevel", "PassivePost")
Add("OnSetPlayerLevel", "HiveRequestFinished", function(Player)
	local Client = Player.GetClient and Player:GetClient()
	local SteamId = Client and Client:GetUserId()

	if SteamId then
		Shine.Timer.Destroy(StringFormat("HiveRequest%s", SteamId))
		PlayerInfoHub.HiveQueue[ SteamId ] = false
		Call( "OnReceiveHiveData", Client, GetHiveDataBySteamId(SteamId) )
	end
end)

function PlayerInfoHub:GetHiveData( SteamId )
	if Shine.IsNS2Combat or not GetHiveDataBySteamId then return end

	local data = GetHiveDataBySteamId(SteamId)
	if data then
		--Fix for hive2 using a new format
		data.playTime = data.time_played or -1
		return data
	end
end

function PlayerInfoHub:GetSteamData( SteamId )
	return self.SteamData[ SteamId ]
end

function PlayerInfoHub:GetGeoData( SteamId )
	return self.GeoData[ SteamId ]
end

function PlayerInfoHub:GetENSLData( SteamId )
	return self.ENSLData[ SteamId ]
end

--[[
-- Returns if the requests have been finsihed for given SteamId
-- If a Name is give it will only check for requst registered with the given name
 ]]
function PlayerInfoHub:GetIsRequestFinished( SteamId, Name )
	local Requests = self.Requests
	local SteamData = self.SteamData[ SteamId ]
	local ENSLData = self.ENSLData[ SteamId ]
	local GeoData = self.GeoData[ SteamId ]

	if not Name then
		return (not Requests.STEAMPLAYTIME[1] or SteamData.Playtime ~= -2 ) and
				(not Requests.STEAMBADGES[1] or SteamData.Badges.Normal ~= -2) and
				(not Requests.STEAMBANS[1] or SteamData.Bans ~= -2) and
				(not Requests.ENSL[1] or ENSLData.Bans ~= -2) and
				(not Requests.GEODATA[1] or GeoData ~= -2) and self.HiveQueue[ SteamId ] == false
	else
		local result = self.HiveQueue[ SteamId ] == false
		if not result then return false end --avoid any not needed for loop via if checks

		for _, name in IPairs( Requests.STEAMPLAYTIME ) do
			if name == Name then
				result = SteamData.Playtime ~= -2
				break
			end
		end
		if not result then return false end

		for _, name in IPairs( Requests.STEAMBADGES ) do
			if name == Name then
				result = SteamData.Badges.Normal ~= -2
				break
			end
		end
		if not result then return false end

		for _, name in IPairs( Requests.STEAMBANS ) do
			if name == Name then
				result = SteamData.Bans ~= -2
				break
			end
		end
		if not result then return false end

		for _, name in IPairs( Requests.GEODATA ) do
			if name == Name then
				result = GeoData ~= -2
				break
			end
		end

		for _, name in IPairs( Requests.ENSL ) do
			if name == Name then
				result = ENSLData ~= -2
				break
			end
		end

		return result
	end
end