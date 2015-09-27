local Plugin = Plugin

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
		Countdown = "Pregame \"Sandbox\" - Mode turning %s in %s.",
	}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local Shine = Shine
local StringFormat = string.format

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

--Hooks
do
	local SetupClassHook = Shine.Hook.SetupClassHook
	local SetupGlobalHook = Shine.Hook.SetupGlobalHook

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

	--SetGestationData gets overloaded by the comp mod
	Shine.Hook.Add( "Think", "LoadPGPHooks", function()
		SetupClassHook( "Embryo", "SetGestationData", "SetGestationData", "PassivePost" )

		Shine.Hook.Remove( "Think", "LoadPGPHooks")
	end)

	PrecacheAssetIfExists("models/marine/mac/mac.model")
	PrecacheAssetIfExists("models/marine/mac/mac.animation_graph")
end

function Plugin:Initialise()
	local Gamemode = Shine.GetGamemode()

    if Gamemode ~= "ns2" and Gamemode ~= "mvm" then        
        return false, StringFormat( "The pregameplus plugin does not work with %s.", Gamemode )
    end

	--Checks if all config strings are okay syntax wise
	self:CheckConfigStrings()

	self.Enabled = true

	self.dt.AllowOnosExo = self.Config.AllowOnosExo
	self.dt.AllowMines = self.Config.AllowMines
	self.dt.AllowCommanding = self.Config.AllowCommanding

	self.dt.BioLevel = math.Clamp( self.Config.PregameBiomassLevel, 1, 12 )
	self.dt.UpgradeLevel = math.Clamp( self.Config.PregameAlienUpgradesLevel, 0, 3 )
	self.dt.WeaponLevel = math.Clamp( self.Config.PregameWeaponLevel, 0, 3 )
	self.dt.ArmorLevel = math.Clamp( self.Config.PregameArmorLevel, 0, 3 )

	self.dt.StatusX = math.Clamp(self.Config.StatusTextPosX, 0 , 1)
	self.dt.StatusY = math.Clamp(self.Config.StatusTextPosY, 0 , 1)
	self.dt.StatusR = math.Clamp(self.Config.StatusTextColour[1], 0 , 255 )
	self.dt.StatusG = math.Clamp(self.Config.StatusTextColour[2], 0 , 255 )
	self.dt.StatusB = math.Clamp(self.Config.StatusTextColour[3], 0 , 255 )
	self.dt.StatusDelay = math.Clamp(self.Config.LimitToggleDelay, 0, 1023)

	self.Ents = {}
	self.ProtectedEnts = {}

	--if the plugin gets enabled at a later point then the first load
	self:OnResume()

	return true
end

function Plugin:CheckConfigStrings()
	local changed

	for i, value in pairs( self.DefaultConfig.Strings ) do
		if not self.Config.Strings[i] then
			self.Config.Strings[i] = value
			changed = true
		end
	end
	
	if changed then
		self:SaveConfig()
	end
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

	if HasMixin( newEnt, "Live" ) then
		newEnt:SetIsAlive(true)
	end

	local ID = newEnt:GetId()
	table.insert( Plugin.Ents, ID )
	Plugin.ProtectedEnts[ ID ] = true
end

function Plugin:ProcessBuyAction()
	if self.dt.Enabled then return true end
end

function Plugin:CanEntDoDamageTo( _, Target )
	if not self.dt.Enabled then return end

	if self.ProtectedEnts[ Target:GetId() ] then
		return
	end

	return true
end

local function RespawnAllDeadPlayer( Team )
	local spectators = Team:GetSortedRespawnQueue()
	for i = 1, #spectators do
		local spec = spectators[ i ]
		Team:RemovePlayerFromRespawnQueue( spec )
		local success, newAlien = Team:ReplaceRespawnPlayer( spec, nil, nil )
		if success then newAlien:SetCameraDistance( 0 ) end
	end
end

-- instantly respawns dead aliens
function Plugin:AlTeamUpdate( AlTeam )
	if self.dt.Enabled then
		RespawnAllDeadPlayer( AlTeam )
	end
end

-- instantly respawn dead marines
function Plugin:MarTeamUpdate( MarTeam )
	if self.dt.Enabled then
		RespawnAllDeadPlayer( MarTeam )
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
function Plugin:SetGestationData( Embryo )
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
function Plugin:MACOnUse( _, Player )
	if self.dt.Enabled then Player:AddHealth( 999, nil, false, nil ) end
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

function Plugin:AddScore()
	if self.dt.Enabled then return true end
end

function Plugin:SendText()
	self.dt.StatusText = StringFormat("%s\n%s\n%s", StringFormat(self.Config.Strings.Status, self.dt.Enabled and "enabled" or "disabled"),
		self.Config.CheckLimit and StringFormat( self.Config.Strings.Limit, self.dt.Enabled and "off" or "on",
			self.dt.Enabled and "being at" or "being under", self.Config.PlayerLimit )
		or self.Config.Strings.NoLimit,	self.Config.ExtraMessageLine )
	self.dt.ShowStatus = true
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
		--don't spawn them if cheats is on (it already does it)
		if not ( Shared.GetCheatsEnabled() and MarineTeam.gSandboxMode ) then
			MakeTechEnt(techPoint, AdvancedArmory.kMapName, 3.5, -2, teamNr)
			MakeTechEnt(techPoint, PrototypeLab.kMapName, -3.5, 2, teamNr)
		end

		MakeTechEnt(techPoint, MAC.kMapName, 3.5, 2, teamNr)
	end
end

function Plugin:OnResetGame()
	self:Disable()

	self:SimpleTimer(1, function()
		if GetGamerules() and GetGamerules():GetGameState() == kGameState.NotStarted then
			self:Enable()
		end
	end)
end

function Plugin:Enable()
	local PlayerCount = #GetEntitiesForTeam( "Player", 1 ) + #GetEntitiesForTeam( "Player", 2 )
	self.dt.Enabled = not self.Config.CheckLimit or self.Config.PlayerLimit > PlayerCount
	self:SendText()

	if self.dt.Enabled then
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
end

function Plugin:Disable()

	self.dt.ShowStatus = false

	--stop the ongoing countdown
	self:DestroyTimer( "Countdown" )
	self.dt.CountdownText = ""

	if not self.dt.Enabled then return end

	self:DestroyEnts()
	self.dt.Enabled = false
	
	local rules = GetGamerules()
	if not rules then return end

	rules:SetAllTech( false )
end

function Plugin:CheckLimit( Gamerules )
	if not self.Config.CheckLimit or not self.dt.ShowStatus then return end

	local PlayerCount = #GetEntitiesForTeam( "Player", 1 ) + #GetEntitiesForTeam( "Player", 2 )

	local toogle = self.dt.Enabled

	if PlayerCount < self.Config.PlayerLimit then
		toogle = not toogle
	end

	if toogle then
		if not self:GetTimer( "Countdown" ) then
			self.dt.CountdownText = StringFormat( "%s\n%s\n%s", StringFormat( self.Config.Strings.Status,
				not self.dt.Enabled and "disabled" or "enabled" ), StringFormat( self.Config.Strings.Countdown,
				not self.dt.Enabled and "on" or "off", "%s"), self.Config.ExtraMessageLine )

			self:CreateTimer( "Countdown", self.dt.StatusDelay, 1, function()
				Gamerules:ResetGame()
			end)
		end
	elseif self:TimerExists( "Countdown" ) then
		self:DestroyTimer( "Countdown" )
		self.dt.CountdownText = ""
	end
end

function Plugin:PostJoinTeam( Gamerules )
	self:CheckLimit( Gamerules )
end

function Plugin:ClientDisconnect( Client )
	local Player = Client:GetControllingPlayer()
	if Player then
		self:CheckLimit(GetGamerules())
	end
end

function Plugin:OnSuspend()
	self:Disable()
end

function Plugin:OnResume()
	if GetGamerules and GetGamerules() and GetGamerules():GetGameState() ~= kGameState.NotStarted then
		self:Enable()
	end
end

function Plugin:Cleanup()
	self:Disable()

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end