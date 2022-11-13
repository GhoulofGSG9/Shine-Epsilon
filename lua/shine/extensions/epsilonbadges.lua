--[[
    Shine Epsilon Badges
]]
local InfoHub = Shine.PlayerInfoHub

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.6"

Plugin.HasConfig = true

Plugin.ConfigName = "EpsilonBadges.json"
Plugin.DefaultConfig =
{
    Flags = true,
    FlagsRow = 2,
    ForceFlagsBadge = false,
    SteamBadges = true,
    SteamBadgesRow = 5,
    ForceSteamBadge = false,
    ENSLTeams = false,
    ENSLTeamsRow = 4,
    ForceENSLTeamsBadge = false,
    Debug = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Enabled = true
	
    if self.Config.Flags then
        InfoHub:Request("epsilonbadges", "GEODATA")
    end

    if self.Config.ENSLTeams then
        InfoHub:Request("epsilonbadges", "ENSL")
    end

    if self.Config.SteamBadges then
        InfoHub:Request("epsilonbadges", "STEAMBADGES")
    end

    self.ForcedBadges = {}
	
	return true
end

function Plugin:OnFirstThink()
    Shine.Hook.SetupGlobalHook( "Badges_OnClientBadgeRequest", "OnClientBadgeRequest", "ActivePre" )
end

function Plugin:SetBadge( Client, Badge, Row, Name, Force )
    if not ( Badge or Client ) then return end
 
    local ClientId = Client:GetUserId()
    if ClientId <= 0 then return end
    
    local SetBadge = GiveBadge( ClientId, Badge, Row )
    if not SetBadge then return end
    
    SetFormalBadgeName( Badge, Name)

    if Force then
        Badges_SetBadge( ClientId, Badge, Row )
        self.ForcedBadges[ClientId] = self.ForcedBadges[ClientId] or {}
        self.ForcedBadges[ClientId][Row] = true
    end
    
    return true
end

function Plugin:OnClientBadgeRequest( ClientID, Message )
    local Client = ClientID and Server.GetClientById( ClientID )
    if not Client then return end

    local ForcedBadges = self.ForcedBadges[ Client:GetUserId() ]
    if not ForcedBadges then return end

    -- Prevent the user changing their badge if it's been forced
    -- for the given column.
    if ForcedBadges[ Message.column ] then return false end
end

local SteamBadges = {
    "steam_Rookie",
    "steam_Squad Leader",
    "steam_Veteran",
    "steam_Commander",
    "steam_Special Ops"
}

local SteamBadgeName = {
    "Steam NS2 Badge - Rookie",
    "Steam NS2 Badge - Squad Leader",
    "Steam NS2 Badge - Veteran",
    "Steam NS2 Badge - Commander",
    "Steam NS2 Badge - Special Ops"
}

function Plugin:OnReceiveSteamData( Client, SteamData )
    if not self.Config.SteamBadges then return end
    
    if SteamData.Badges.Normal and SteamData.Badges.Normal > 0 then
        self:SetBadge( Client, SteamBadges[SteamData.Badges.Normal], self.Config.SteamBadgesRow,
            SteamBadgeName[SteamData.Badges.Normal], self.Config.ForceSteamBadge )
    end
        
    if SteamData.Badges.Foil and SteamData.Badges.Foil == 1 then
        self:SetBadge( Client, "steam_Sanji Survivor", self.Config.SteamBadgesRow,
            "Steam NS2 Badge - Sanji Survivor", self.Config.ForceSteamBadge)
    end
end

function Plugin:OnReceiveGeoData( Client, GeoData )
    if not self.Config.Flags then return end

    if self.Config.Debug then
        Print(string.format("Epsilon Badge Debug: Received GeoData of %s\n%s ",
            Client:GetUserId(), type(GeoData) == "table" and table.ToString(GeoData) or GeoData))
    end
    
    local Nationality = type(GeoData) == "table" and GeoData.countryCode or "UNO"
    local Country = type(GeoData) == "table" and GeoData.country or "Unknown"

    local SetBagde = self:SetBadge( Client, Nationality, self.Config.FlagsRow,
        string.format("Nationality - %s", Country), self.Config.ForceFlagsBadge )
    
    if not SetBagde then
        Nationality = "UNO"
        self:SetBadge( Client, Nationality, self.Config.FlagsRow,
            string.format("Nationality - %s", Country), self.Config.ForceFlagsBadge )
    end
end

function Plugin:OnReceiveENSLData( Client, Data )
    if not self.Config.ENSLTeams then return end

	if type(Data) ~= "table" then return end

	local Teamname = Data.team and Data.team.name
	local TeamID = Data.team and string.format("ENSL#%s", Data.team.id)

	if Teamname then
		self:SetBadge( Client, TeamID, self.Config.ENSLTeamsRow, string.format("ENSL Team - %s", Teamname),
        self.Config.ForceENSLTeamsBadge)
	end
end

function Plugin:Cleanup()
    InfoHub:RemoveRequest("epsilonbadges")

    self.BaseClass.Cleanup( self )

    self.Enabled = false
end

return Plugin