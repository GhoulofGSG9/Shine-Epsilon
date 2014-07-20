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
	ExtraMessageLine = ""
}
Plugin.CheckConfig = true
Plugin.DefaultState = true

--Text for telling players the current status of PGP
local statusString = "Pregame \"Sandbox\" - Mode is %s. A match has not started."
local limitString = "Turns %s when %s %s players."
local noLimitString = "No player limit."
local timerString = "Pregame \"Sandbox\" - Mode turning %s in %s seconds."

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook
local SetupGlobalHook = Shine.Hook.SetupGlobalHook
local StringFormat = string.format
local CreateTimer = Shine.Timer.Create
local GetEntitiesForTeam = GetEntitiesForTeam

function Plugin:Initialise()
	self.Enabled = true
	self.dt.AllowOnosExo = self.Config.AllowOnosExo
	self.dt.AllowMines = self.Config.AllowMines
	self.dt.AllowCommanding = self.Config.AllowCommanding
	self.dt.BioLevel = math.Clamp( self.Config.PregameBiomassLevel, 1, 12 )
	self.dt.UpgradeLevel = math.Clamp( self.Config.PregameAlienUpgradesLevel, 0, 3 )
	self.dt.Enabled = false
	self.Ents = {}
	self.ProtectedEnts = {}
	self:SimpleTimer( 1, function()
		self:SetupHooks()
		local rules = GetGamerules()
		if rules and rules:GetGameState() == kGameState.NotStarted then
			self:Enable()
			rules:ResetGame() 
		end
	end)
	
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

function Plugin:ProcessBuyAction()
	if self.dt.Enabled then return true end
end

function Plugin:CanEntDoDamageTo( Attacker, Target, ... )
	if not self.dt.Enabled then return end
	if self.ProtectedEnts[ Target:GetId() ] or Target:isa( "InfantryPortal" ) or Target:isa( "Egg" ) or Target:isa( "CommandStructure" ) then return end
	return true
end

-- spawn crags for faster healing
function Plugin:AlienSpawnInitialStructures( AlienTeam, techPoint )	
	if not self.dt.Enabled then return end
	
	local teamNr = AlienTeam:GetTeamNumber()
	MakeTechEnt( techPoint, Crag.kMapName, 3.5, 2, teamNr )
	MakeTechEnt( techPoint, Crag.kMapName, 3.5, -2, teamNr )
	MakeTechEnt( techPoint, Shift.kMapName, -3.5, 2, teamNr )
end

function Plugin:GetArmorUpgradeLevel( Player )
	if self.dt.Enabled and not Player:isa("Exo") then return self.Config.PregameArmorLevel end
end

function Plugin:GetWeaponUpgradeLevel( Player )
	if self.dt.Enabled and not Player:isa("Exo") then return self.Config.PregameWeaponLevel end
end

function Plugin:GetArmorAmount( Marine )
	if self.dt.Enabled then return Marine.kBaseArmor + self.Config.PregameArmorLevel * Marine.kArmorPerUpgradeLevel end
end

function Plugin:ExoGetArmorAmount()
	if self.dt.Enabled then return kExosuitArmor + self.Config.PregameArmorLevel * kExosuitArmorPerUpgradeLevel end
end

-- spawns the armory, proto, armslab and 3 macs
function Plugin:MarSpawnInitialStructures( MarTeam, techPoint )
	if not self.dt.Enabled then return end	
	local teamNr = MarTeam:GetTeamNumber()
	
	--don't spawn them if cheats is on(it already does it)
	if not ( Shared.GetCheatsEnabled() and MarineTeam.gSandboxMode ) then
		MakeTechEnt(techPoint, AdvancedArmory.kMapName, 3.5, -2, teamNr)
		MakeTechEnt(techPoint, PrototypeLab.kMapName, -3.5, 2, teamNr)
	end

	for i = 1, 3 do
		MakeTechEnt(techPoint, MAC.kMapName, 3.5, 2, teamNr)
	end	
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
	local Text = StringFormat("%s\n%s\n%s", StringFormat(statusString, self.dt.Enabled and "enabled" or "disabled"),
		self.Config.CheckLimit and StringFormat( limitString, self.dt.Enabled and "off" or "on", 
		self.dt.Enabled and "being above" or "being under", self.Config.PlayerLimit ) or noLimitString, self.Config.ExtraMessageLine )
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

function Plugin:Enable()    
	if self.dt.Enabled then return end
	self.dt.Enabled = true
	self:StartText()
	self.PlayerCount = GetPlayerinTeams()
	
	--Timer avoids issue that teams might not yet be initialized
	self:SimpleTimer( 1, function()
		local rules = GetGamerules()
		if not rules then return end
		rules:SetAllTech( true )
		self:CheckLimit( rules )
	end)
	
end

function Plugin:Disable( ChangedGamestate )
	if not self.dt.Enabled then return end
	self.dt.Enabled = false    
	self:DestroyAllTimers()
	self:RemoveText()
	
	local rules = GetGamerules()
	if not rules then return end
	rules:SetAllTech( false )
	
	if rules:GetGameState() == kGameState.NotStarted then
		if not ChangedGamestate then
			rules:ResetGame()
		end
	end
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
			
			self:UpdateText( StringFormat( "%s\n%s\n%s", StringFormat( statusString, On and "disabled" or "enabled" ),
				StringFormat( timerString, On and "on" or "off", Timer:GetReps() ), self.Config.ExtraMessageLine ))
			
			if Timer:GetReps() == 0 then
				if On then 
					self:Enable()
					Gamerules:ResetGame() 
				else
					self:Disable()
					self:SimpleTimer( 1, function() self:StartText() end )					
				end
			end
		end)
	else
		if On then 
			self:Enable()
		else
			self:Disable()
		end
	end
end

function Plugin:CheckLimit( Gamerules )
	self.PlayerCount = GetPlayerinTeams()
	
	if self.Config.CheckLimit and Gamerules:GetGameState() == kGameState.NotStarted then
		local PlayerLimit = tonumber( self.Config.PlayerLimit )
		if self.PlayerCount >= PlayerLimit and self.dt.Enabled then
			self:CreateLimitTimer( false, Gamerules )
		elseif self.PlayerCount < PlayerLimit and not self.dt.Enabled then
			self:CreateLimitTimer( true, Gamerules )
		end
	end
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force )
	if Gamerules:GetGameState() == kGameState.NotStarted then self:SendText( Player ) end    
	self:CheckLimit( Gamerules )
end

function Plugin:ClientDisconnect( Client )
	local Gamerules = GetGamerules()
	if Gamerules then self:CheckLimit( Gamerules ) end
end

function Plugin:PreSetGameState( Gamerules, NewState )
	self:DestroyEnts()
	if Gamerules:GetGameState() == NewState then return end
	
	if NewState ~= kGameState.NotStarted then 
		self:Disable( true )
	else
		self:Enable()
	end
end

function Plugin:SetupHooks()
	SetupClassHook( "Alien", "ProcessBuyAction", "PreProcessBuyAction", ReplaceGameStarted2 )
	SetupClassHook( "AlienTeam", "SpawnInitialStructures", "AlienSpawnInitialStructures", "PassivePost" )
	SetupClassHook( "AlienTeam", "Update", "AlTeamUpdate", "PassivePost")
	SetupClassHook( "AlienTeamInfo", "OnUpdate", "AlienTeamInfoUpdate", "PassivePost" )
	SetupClassHook( "Crag", "GetMaxSpeed", "CragGetMaxSpeed", "ActivePre")
	SetupClassHook( "Embryo", "SetGestationData", "SetGestationData", "PassivePost" )
	SetupClassHook( "Exo", "GetArmorAmount", "ExoGetArmorAmount", "ActivePre" )
	SetupClassHook( "InfantryPortal", "FillQueueIfFree", "FillQueueIfFree", "Halt" )
	SetupClassHook( "MAC", "GetMoveSpeed", "MACGetMoveSpeed", "ActivePre" )
	SetupClassHook( "MAC", "OnUse", "MACOnUse", "PassivePost" )
	SetupClassHook( "Marine", "GetArmorAmount", "GetArmorAmount", "ActivePre" )
	SetupClassHook( "Marine", "GetArmorLevel", "GetArmorUpgradeLevel", "ActivePre" )
	SetupClassHook( "Marine", "GetWeaponLevel", "GetWeaponUpgradeLevel", "ActivePre" )
	SetupClassHook( "MarineTeam", "SpawnInitialStructures", "MarSpawnInitialStructures", "PassivePost" )
	SetupClassHook( "MarineTeam", "Update", "MarTeamUpdate", "PassivePost" )
	SetupClassHook( "NS2Gamerules", "SetGameState", "PreSetGameState", "PassivePre")
	SetupClassHook( "Player", "GetGameStarted", "GetGameStarted", "ActivePre" )
	SetupClassHook( "Player", "GetIsPlaying", "GetIsPlaying", "ActivePre" )
	SetupClassHook( "Player", "GetWeaponUpgradeLevel", "GetWeaponUpgradeLevel", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddAssistKill", "AddAssistKill", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddDeaths", "AddDeaths", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddKill", "AddKill", "ActivePre" )
	SetupClassHook( "ScoringMixin", "AddScore", "AddScore", "ActivePre" )
	SetupClassHook( "Shift", "GetMaxSpeed", "ShiftGetMaxSpeed", "ActivePre" )
	SetupClassHook( "TeleportMixin", "GetCanTeleport", "ShiftGetCanTeleport", "ActivePre" )
	SetupGlobalHook( "CanEntityDoDamageTo", "CanEntDoDamageTo", ReplaceGameStarted1 )
	SetupGlobalHook( "LookupTechData", "LookupTechData", "ActivePre" )
end

function Plugin:Cleanup()
	self:Disable()
	self.BaseClass.Cleanup( self )    
	self.Enabled = false
end