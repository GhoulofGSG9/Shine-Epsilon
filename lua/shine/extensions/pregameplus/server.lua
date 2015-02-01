local Plugin = Plugin
Plugin.Version = "1.3"

Plugin.HasConfig = true 
Plugin.ConfigName = "PregamePlus.json"

Plugin.DefaultConfig = {
	CheckLimit = true,
	PlayerLimit = 8,
	LimitToggleDelay = 30,
	StatusTextPosX = 0.05,
	StatusTextPosY = 0.45,
	StatusTextColour = { 0, 255, 255 },
	AllowOnosExo = true,
	AllowMines = true,
	AllowCommanding = true,
	PregameArmorLevel = 3,
	PregameWeaponLevel = 3,
	PregameBiomassLevel = 9,
	PregameAlienUpgradesLevel = 3,
	ExtraMessageLine = "",
	Strings = {
		Status = "Pregame \"Sandbox\" - Mode is %s. A match has not started.",
		Limit = "Turns %s when %s %s players.",
		NoLimit = "No player limit.",
		Timer = "Pregame \"Sandbox\" - Mode turning %s in %s seconds.",
	}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook
local SetupGlobalHook = Shine.Hook.SetupGlobalHook
local StringFormat = string.format
local CreateTimer = Shine.Timer.Create
local GetEntitiesForTeam = GetEntitiesForTeam

function Plugin:Initialise()
	local Gamemode = Shine.GetGamemode()

    if Gamemode ~= "ns2" and Gamemode ~= "mvm" then        
        return false, StringFormat( "The pregameplus plugin does not work with %s.", Gamemode )
    end
	
	self.Enabled = true
	self.dt.AllowOnosExo = self.Config.AllowOnosExo
	self.dt.AllowMines = self.Config.AllowMines
	self.dt.AllowCommanding = self.Config.AllowCommanding
	self.dt.BioLevel = math.Clamp( self.Config.PregameBiomassLevel, 1, 12 )
	self.dt.UpgradeLevel = math.Clamp( self.Config.PregameAlienUpgradesLevel, 0, 3 )
	self.dt.WeaponLevel = math.Clamp( self.Config.PregameWeaponLevel, 0, 3 )
	self.dt.ArmorLevel = math.Clamp( self.Config.PregameArmorLevel, 0, 3 )
	
	self.dt.Enabled = false
	self.Ents = {}
	self.ProtectedEnts = {}

	self.firstreset = true

	self:SetupHooks()

	return true
end

local function GetPlayerinTeams()
	return #GetEntitiesForTeam( "Player", 1 ) + #GetEntitiesForTeam( "Player", 2 )
end

local function MakeTechEnt( techPoint, mapName, rightOffset, forwardOffset, teamType )
	local origin = techPoint:GetOrigin()
	local right = techPoint:GetCoords().xAxis
	local forward = techPoint:GetCoords().zAxis
	local position = origin + right * rightOffset + forward * forwardOffset

	local newEnt = CreateEntity( mapName, position, teamType)
	if HasMixin( newEnt, "Construct" ) then
		SetRandomOrientation( newEnt )
		newEnt:SetConstructionComplete() 
	end

	local ID = newEnt:GetId()
	table.insert( Plugin.Ents, ID )
	Plugin.ProtectedEnts[ ID ] = true
end

--Hacky stuff
local function ReplaceGameStarted1( OldFunc, ... )
	local Hook = Shine.Hook.Call( "CanEntDoDamageTo", ... )
	if not Hook then return OldFunc(...) end

	local gameinfo = GetGameInfoEntity()
	local oldGameInfoState = gameinfo:GetState()
	gameinfo:SetState( kGameState.Started )
	local temp = OldFunc(...)
	gameinfo:SetState( oldGameInfoState )

	return temp
end

local function ReplaceGameStarted2( OldFunc, ... )
	local Hook = Shine.Hook.Call("ProcessBuyAction", ...)
	if not Hook then return OldFunc(...) end

	local oldGetGameStarted = NS2Gamerules.GetGameStarted
	NS2Gamerules.GetGameStarted = function() return true end
	local temp = OldFunc(...)
	NS2Gamerules.GetGameStarted = oldGetGameStarted
	return temp
end

--stuff for modular Exo mod ( guys really use the techtree )
local function ReplaceModularExo_GetIsConfigValid( OldFunc, ... )
	local Hook = Shine.Hook.Call( "ModularExo_GetIsConfigValid", ... )
	if not Hook then return OldFunc(...) end

	local a, b, resourceCost, powerSupply, powerCost, exoTexturePath = OldFunc(...)
	resourceCost = resourceCost and 0

	return a, b, resourceCost, powerSupply, powerCost, exoTexturePath
end

function Plugin:SetupHooks()
	SetupClassHook( "Alien", "ProcessBuyAction", "PreProcessBuyAction", ReplaceGameStarted2 )
	SetupClassHook( "AlienTeam", "Update", "AlTeamUpdate", "PassivePost")
	SetupClassHook( "AlienTeam", "UpdateBioMassLevel", "AlTeamUpdateBioMassLevel", "ActivePre")
	SetupClassHook( "Crag", "GetMaxSpeed", "CragGetMaxSpeed", "ActivePre")
	SetupClassHook( "InfantryPortal", "FillQueueIfFree", "FillQueueIfFree", "Halt" )
	SetupClassHook( "MAC", "GetMoveSpeed", "MACGetMoveSpeed", "ActivePre" )
	SetupClassHook( "MAC", "OnUse", "MACOnUse", "PassivePost" )
	SetupClassHook( "MarineTeam", "Update", "MarTeamUpdate", "PassivePost" )
	SetupClassHook( "ScoringMixin", "AddAssistKill", "AddAssistKill", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddDeaths", "AddDeaths", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddKill", "AddKill", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddScore", "AddScore", "ActivePre" )
	SetupClassHook( "Shift", "GetMaxSpeed", "ShiftGetMaxSpeed", "ActivePre" )
	SetupClassHook( "TeleportMixin", "GetCanTeleport", "ShiftGetCanTeleport", "ActivePre" )
	SetupGlobalHook( "CanEntityDoDamageTo", "CanEntDoDamageTo", ReplaceGameStarted1 )

	SetupClassHook( "NS2Gamerules", "ResetGame", "OnResetGame", "PassivePre" )
	SetupClassHook( "AlienTeamInfo", "OnUpdate", "AlienTeamInfoUpdate", "PassivePost" )
	SetupClassHook( "Player", "GetGameStarted", "GetGameStarted", "ActivePre" )
	SetupClassHook( "Player", "GetIsPlaying", "GetIsPlaying", "ActivePre" )
	SetupClassHook( "TechNode", "GetResearched", "GetResearched", "ActivePre" )
	SetupClassHook( "TechNode", "GetHasTech", "GetHasTech", "ActivePre" )
	SetupGlobalHook( "LookupTechData", "LookupTechData", "ActivePre" )

	self:SimpleTimer( 1, function()
        SetupClassHook( "Embryo", "SetGestationData", "SetGestationData", "PassivePost" )
		SetupGlobalHook( "ModularExo_GetIsConfigValid", "ModularExo_GetIsConfigValid", ReplaceModularExo_GetIsConfigValid )
	end)
	SetupGlobalHook( "PlayerUI_GetPlayerResources", "PlayerUI_GetPlayerResources", "ActivePre" )
end

function Plugin:ProcessBuyAction()
	if self.dt.Enabled then return true end
end

function Plugin:CanEntDoDamageTo( Attacker, Target, ... )
	if not self.dt.Enabled then return end

	if self.ProtectedEnts[ Target:GetId() ] then
		return
	end

	return true
end

-- instantly spawn dead aliens
function Plugin:AlTeamUpdate( AlTeam, timePassed )
	if self.dt.Enabled then
		local alienSpectators = AlTeam:GetSortedRespawnQueue()
		for i = 1, #alienSpectators do
			local spec = alienSpectators[ i ]
			AlTeam:RemovePlayerFromRespawnQueue( spec )
			local success, newAlien = AlTeam:ReplaceRespawnPlayer( spec, nil, nil )
			newAlien:SetCameraDistance( 0 )
		end
	end
end

function Plugin:AlTeamUpdateBioMassLevel( AlienTeam )
	if self.dt.Enabled then
		AlienTeam.bioMassLevel = self.Config.PregameBiomassLevel
		AlienTeam.bioMassAlertLevel = 0
		AlienTeam.maxBioMassLevel = 12
		AlienTeam.bioMassFraction = self.Config.PregameBiomassLevel
		return true
	end
end

-- set all evolution times to 1 second
function Plugin:SetGestationData( Embryo, ... )
	if self.dt.Enabled then Embryo.gestationTime = 1 end
end

--Prevent comm from moving crag
function Plugin:CragGetMaxSpeed( Crag )
	if self.ProtectedEnts[ Crag:GetId() ] then return 0 end
end

--Prevent comm from moving shifts
function Plugin:ShiftGetMaxSpeed( Shift )
	if self.ProtectedEnts[ Shift:GetId() ] then return 0 end
end

--prevents start buildings from being teleported
function Plugin:ShiftGetCanTeleport( Shift )
	if self.ProtectedEnts[ Shift:GetId() ] then return false end
end

--prevents placing dead marines in IPs so we can do instant respawn
function Plugin:FillQueueIfFree()
	if self.dt.Enabled then return true end
end

--immobile macs so they don't get lost on the map
function Plugin:MACGetMoveSpeed( Mac )
	if self.ProtectedEnts[ Mac:GetId() ] then return 0 end
end

-- lets players use macs to instant heal since the immobile mac
-- cannot move, it may get stuck trying to weld distant objects
function Plugin:MACOnUse( Mac, Player, ... )
	if self.dt.Enabled then Player:AddHealth( 999, nil, false, nil ) end
end

-- instantly respawn dead marines
function Plugin:MarTeamUpdate( MarTeam, timePassed )
	if self.dt.Enabled then
		local specs = MarTeam:GetSortedRespawnQueue()
		for i = 1, #specs do
			local spec = specs[i]
			MarTeam:RemovePlayerFromRespawnQueue( spec )
			local success, newMarine = MarTeam:ReplaceRespawnPlayer( spec, nil, nil )
			newMarine:SetCameraDistance( 0 )
		end
	end
end

function Plugin:AddAssistKill()
	if self.dt.Enabled then return true end
end

function Plugin:AddKill()
	if self.dt.Enabled then return true end
end

function Plugin:AddDeaths()
	if self.dt.Enabled then return true end
end

function Plugin:AddScore(points, res, wasKill)
	if self.dt.Enabled then return true end
end

function Plugin:SendText( Player )
	local Text = StringFormat("%s\n%s\n%s", StringFormat(self.Config.Strings.Status, self.dt.Enabled and "enabled" or "disabled"),
		self.Config.CheckLimit and StringFormat( self.Config.Strings.Limit, self.dt.Enabled and "off" or "on", 
		self.dt.Enabled and "being above" or "being under", self.Config.PlayerLimit ) or self.Config.Strings.NoLimit, self.Config.ExtraMessageLine )
	local r,g,b = unpack( self.Config.StatusTextColour )
	local Message = Shine.BuildScreenMessage( 70, self.Config.StatusTextPosX, self.Config.StatusTextPosY, Text, 1800, r, g, b, 0, 1, 0 )
	Shine:SendText( Player, Message )
end

function Plugin:UpdateText( NewText )
	local Message = {}
	Message.ID = 70
	Message.Message = NewText
	Shine:UpdateText( nil, Message )
end

function Plugin:RemoveText( Player )
	local Message = {}
	Message.ID = 70
	Shine:RemoveText( Player, Message )
end

function Plugin:StartText()
	self:SendText()
	self:CreateTimer("PGPText", 1800, -1, function() self:SendText() end)
end

function Plugin:DestroyEnts()
	for i = 1, #self.Ents do
		local entid = self.Ents[ i ]
		local ent = Shared.GetEntity(entid)
		if ent then 
			DestroyEntity( ent )
		end
	end

	self.Ents = {}
	self.ProtectedEnts = {}
end

local function SpawnBuildings( team )
	local teamNr = team:GetTeamNumber()
	local techPoint = team:GetInitialTechPoint()

	if team:GetTeamType() == kAlienTeamType then
		MakeTechEnt( techPoint, Crag.kMapName, 3.5, 2, teamNr )
		MakeTechEnt( techPoint, Crag.kMapName, 3.5, -2, teamNr )
		MakeTechEnt( techPoint, Shift.kMapName, -3.5, 2, teamNr )
	else
		--don't spawn them if cheats is on(it already does it)
		if not ( Shared.GetCheatsEnabled() and MarineTeam.gSandboxMode ) then
			MakeTechEnt(techPoint, AdvancedArmory.kMapName, 3.5, -2, teamNr)
			MakeTechEnt(techPoint, PrototypeLab.kMapName, -3.5, 2, teamNr)
		end

		for i = 1, 3 do
			MakeTechEnt(techPoint, MAC.kMapName, 3.5, 2, teamNr)
		end
	end
end

local function CheckState()
	local self = Plugin

	local Gamerules = GetGamerules()
	local State = Gamerules:GetGameState()

	if State == kGameState.NotStarted then
		self:Enable()
	end
end

function Plugin:OnResetGame()
	self:Disable()

	self:SimpleTimer(0.1, CheckState)
end

function Plugin:Enable()    
	if self.dt.Enabled then return end

	self:StartText()

	self.PlayerCount = GetPlayerinTeams()
	if self.Config.CheckLimit and tonumber( self.Config.PlayerLimit ) <= self.PlayerCount then return end

	self.dt.Enabled = true

	local Rules = GetGamerules()
	if not Rules then return end

	Rules:SetAllTech( true )

	local Team1 = Rules:GetTeam1()
	local Team2 = Rules:GetTeam2()

	SpawnBuildings(Team1)
	SpawnBuildings(Team2)

	for _, ent in ipairs( GetEntitiesWithMixin( "Construct" ) ) do
		self.ProtectedEnts[ ent:GetId() ] = true
	end
end

function Plugin:Disable()

	self:RemoveText()

	if not self.dt.Enabled then return end

	self:DestroyEnts()

	self.dt.Enabled = false

	self:DestroyAllTimers()
	
	local rules = GetGamerules()
	if not rules then return end

	rules:SetAllTech( false )
end

function Plugin:CreateLimitTimer( On, Gamerules )
	local OnTimer = On and "PGPLimitOn" or "PGPLimitOFF"
	local OffTime = On and "PGPLimitOFF" or "PGPLimitOn"    
	local PlayerLimit = tonumber( self.Config.PlayerLimit )
	
	if self.Config.LimitToggleDelay > 0 then
		if self:TimerExists( OnTimer ) then return end
		self:DestroyTimer( OffTimer )
		
		self:CreateTimer( OnTimer, 1, self.Config.LimitToggleDelay, function( Timer )
			if On and self.PlayerCount >= PlayerLimit or not On and self.PlayerCount < PlayerLimit then
				Timer:Destroy()
				self:SendText()
				return
			end
			
			self:UpdateText( StringFormat( "%s\n%s\n%s", StringFormat( self.Config.Strings.Status, On and "disabled" or "enabled" ),
				StringFormat( self.Config.Strings.Timer, On and "on" or "off", Timer:GetReps() ), self.Config.ExtraMessageLine ))
			
			if Timer:GetReps() == 0 then
				Gamerules:ResetGame()

				if On then 
					self:Enable()
				else
					self:SimpleTimer( 1, function() self:StartText() end )					
				end
			end
		end)
	else
		Gamerules:ResetGame()

		if On then 
			self:Enable()
		end
	end
end

function Plugin:CheckLimit( Gamerules )
	if not self.Config.CheckLimit and Gamerules:GetGameState() ~= kGameState.NotStarted then return end

	self.PlayerCount = GetPlayerinTeams()

	if tonumber( self.Config.PlayerLimit ) >= self.PlayerCount and self.dt.Enabled or not self.dt.Enabled then
		self:CreateLimitTimer( not self.dt.Enabled , Gamerules )
	end
end

function Plugin:PostJoinTeam( Gamerules, Player )
	if Gamerules:GetGameState() == kGameState.NotStarted then
		self:SendText( Player )
		self:CheckLimit( Gamerules )
	end
end

function Plugin:Cleanup()
	self:Disable()
	self.BaseClass.Cleanup( self )

	self.Enabled = false
end