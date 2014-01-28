--[[
    Shine 2ndIp Plugin
]]
local Shine = Shine

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
    if Gamemode ~= "ns2" then        
        return false, StringFormat( "The 2ndIp plugin does not work with %s.", Gamemode )
    end
  
    self.Enabled = true
    return true
end

Shine.Hook.SetupClassHook("MarineTeam","SpawnInitialStructures","OnSpawnInitialStructures", "PassivePost")

local function Spawn2ndInfantryPortal(team, techPoint)
    local techPointOrigin = techPoint:GetOrigin()
    local spawnPoint = GetRandomBuildPosition(kTechId.InfantryPortal, techPointOrigin, 5)
    if spawnPoint then
        spawnPoint = spawnPoint - Vector(0,0.6,0)
        local ip = CreateEntity(InfantryPortal.kMapName, spawnPoint, team:GetTeamNumber())
        SetRandomOrientation(ip)
        ip:SetConstructionComplete()
    end
end


function Plugin:OnSpawnInitialStructures( Team, techPoint )
    if Server.GetNumPlayers() < self.Config.MinPlayers then return end    
    Spawn2ndInfantryPortal(Team, techPoint)
end

Shine:RegisterExtension( "2ndip", Plugin )