local Plugin = {}

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook
local SetupGlobalHook = Shine.Hook.SetupGlobalHook

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "Enabled", false )
	self:AddDTVar( "boolean", "AllowOnosExo", true )
	self:AddDTVar( "boolean", "AllowMines", true )
	self:AddDTVar( "boolean", "AllowCommanding", true )
	self:AddDTVar( "integer (1 to 12)", "BioLevel", 9 )
	self:AddDTVar( "integer (0 to 3)", "UpgradeLevel", 3 )
	self:AddDTVar( "integer (0 to 3)", "WeaponLevel", 3 )
	self:AddDTVar( "integer (0 to 3)", "ArmorLevel", 3 )
end

local function SetupHooks()
	SetupClassHook( "AlienTeamInfo", "OnUpdate", "AlienTeamInfoUpdate", "PassivePost" )
	SetupClassHook( "Player", "GetGameStarted", "GetGameStarted", "ActivePre" )
	SetupClassHook( "Player", "GetIsPlaying", "GetIsPlaying", "ActivePre" )
	SetupClassHook( "TechNode", "GetResearched", "GetResearched", "ActivePre" )
	SetupClassHook( "TechNode", "GetHasTech", "GetHasTech", "ActivePre" )
	SetupGlobalHook( "LookupTechData", "LookupTechData", "ActivePre" )
	SetupGlobalHook( "ModularExo_GetIsConfigValid", "ModularExo_GetIsConfigValid", ReplaceModularExo_GetIsConfigValid )
	SetupGlobalHook( "PlayerUI_GetPlayerResources", "PlayerUI_GetPlayerResources", "ActivePre" )
end

function Plugin:Initialise()
	self.Enabled = true
	self:SimpleTimer( 1, function() SetupHooks() end)
	self.Gamemode = Shine.GetGamemode()
	return true
end

--stuff for modular Exo mod ( guys really use the techtree )
local function ReplaceModularExo_GetIsConfigValid( OldFunc, ... )
	local Hook = Shine.Hook.Call( "ModularExo_GetIsConfigValid", ... )
	if not Hook then return OldFunc(...) end
	
	local a, b, resourceCost, powerSupply, powerCost, exoTexturePath = OldFunc(...)
	resourceCost = resourceCost and 0
	
	return a, b, resourceCost, powerSupply, powerCost, exoTexturePath
end

function Plugin:ModularExo_GetIsConfigValid()
	if self.dt.Enabled then
		return self.dt.AllowOnosExo
	end
end

function Plugin:PlayerUI_GetPlayerResources()
	if self.dt.Enabled then 
		return 100
	end
end

function Plugin:LookupTechData( techId, fieldName )
	if self.dt.Enabled and ( fieldName == kTechDataUpgradeCost or fieldName == kTechDataCostKey ) then
		if not self.dt.AllowOnosExo and ( techId == kTechId.Onos or techId == kTechId.Exosuit or techId == kTechId.ClawRailgunExosuit ) then
			return 999
		end
		
		if not self.dt.AllowMines then 
			if self.Gamemode == "ns2" and techId == kTechId.LayMines or self.Gamemode == "mvm" and ( techId == kTechId.DemoMines or techId == kTechId.Mine ) then
				return 999 
			end
		end	
		
		return 0
	end
end

--fixing issues with TechNode
function TechNode:GetCost()
	return LookupTechData(self.techId, kTechDataCostKey, 0)
end

function Plugin:GetHasTech( Tech )
	if self.dt.Enabled then
		local TechId = Tech.techId
		if TechId == kTechId.Weapons3 and self.dt.WeaponLevel < 3 then return false end
		if TechId == kTechId.Weapons2 and self.dt.WeaponLevel < 2 then return false end
		if TechId == kTechId.Weapons1 and self.dt.WeaponLevel < 1 then return false end
		
		if TechId == kTechId.Armor3 and self.dt.ArmorLevel < 3 then return false end
		if TechId == kTechId.Armor2 and self.dt.ArmorLevel < 2 then return false end
		if TechId == kTechId.Armor1 and self.dt.ArmorLevel < 1 then return false end
		return true
	end
end

function Plugin:GetResearched( Tech )
	return self:GetHasTech( Tech )
end

function Plugin:GetGameStarted( Player )
	if self.dt.Enabled then
		if Player:isa( "Commander" ) and not self.dt.AllowCommanding then return false end
		return true 
	end
end

function Plugin:GetIsPlaying( Player )
	return Player:GetGameStarted() and Player:GetIsOnPlayingTeam()
end

function Plugin:AlienTeamInfoUpdate( AlienTeamInfo )
	if not self.dt.Enabled then return end
	AlienTeamInfo.bioMassLevel = self.dt.BioLevel
	AlienTeamInfo.numHives = 3
	AlienTeamInfo.veilLevel = self.dt.UpgradeLevel
	AlienTeamInfo.spurLevel = self.dt.UpgradeLevel
	AlienTeamInfo.shellLevel = self.dt.UpgradeLevel
end

Shine:RegisterExtension( "pregameplus", Plugin )