--[[
    Shine 2ndIp Plugin
]]
local Shine = Shine
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "2ndip.json"
Plugin.DefaultConfig =
{
    MinPlayers = 18
}
Plugin.CheckConfig = true

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" and Gamemode ~= "mvm" then        
        return false, StringFormat( "The 2ndIp plugin does not work with %s.", Gamemode )
    end
  
    self.Enabled = true
    return true
end

Shine.Hook.SetupClassHook( "MarineTeam", "SpawnInitialStructures", "OnSpawnInitialStructures", "PassivePost")

local function Spawn2ndInfantryPortal( Team, TechPoint )
    local TechPointOrigin = TechPoint:GetOrigin()
    local SpawnPoint = GetRandomBuildPosition( kTechId.InfantryPortal, TechPointOrigin, 5 )
    if SpawnPoint then
        SpawnPoint = SpawnPoint - Vector( 0, 0.6, 0 )
        local Ip = CreateEntity( InfantryPortal.kMapName, SpawnPoint, Team:GetTeamNumber() )
        SetRandomOrientation( Ip )
        Ip:SetConstructionComplete()
    end
end


function Plugin:OnSpawnInitialStructures( Team, TechPoint )
    if Server.GetNumPlayers() < self.Config.MinPlayers then return end
    Spawn2ndInfantryPortal( Team, TechPoint )
end

Shine:RegisterExtension( "2ndip", Plugin )