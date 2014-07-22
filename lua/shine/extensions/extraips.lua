--[[
	Shine ExtraIps Plugin
]]
local Shine = Shine
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ExtraIps.json"
Plugin.DefaultConfig =
{
	MinPlayers = { 18, 26 }
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	local Gamemode = Shine.GetGamemode()
	if Gamemode ~= "ns2" and Gamemode ~= "mvm" then        
		return false, StringFormat( "The ExtraIps plugin does not work with %s.", Gamemode )
	end

	self.Enabled = true
	return true
end

local function SpawnExtraInfantryPortal( Team, TechPoint )
	local TechPointOrigin = TechPoint:GetOrigin()
	local SpawnPoint = GetRandomBuildPosition( kTechId.InfantryPortal, TechPointOrigin, 5 )
	if SpawnPoint then
		SpawnPoint = SpawnPoint - Vector( 0, 0.6, 0 )
		local Ip = CreateEntity( InfantryPortal.kMapName, SpawnPoint, Team:GetTeamNumber() )
		SetRandomOrientation( Ip )
		Ip:SetConstructionComplete()
	end
end

Shine.Hook.SetupClassHook( "MarineTeam", "SpawnInitialStructures", "OnSpawnInitialStructures", "PassivePost")
function Plugin:OnSpawnInitialStructures( Team, TechPoint )
	local MinPlayers = self.Config.MinPlayers
	local _, PlayerCount = Shine.GetAllPlayers()
	
	for i = 1, #MinPlayers do
		if PlayerCount >= MinPlayers[i] then 
			SpawnExtraInfantryPortal( Team, TechPoint )
		end
	end
end

Shine:RegisterExtension( "extraips", Plugin )