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
	ExtraMessageLine = ""
}
Plugin.CheckConfig = true
Plugin.DefaultState = true

--Text for telling players the current status of PGP
local statusString = "PGP is %s. A match has not started."
local limitString = "Turns %s when %s %s players."
local noLimitString = "No player limit."
local timerString = "PGP turning %s in %s seconds."

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook
local SetupGlobalHook = Shine.Hook.SetupGlobalHook
local StringFormat = string.format
local CreateTimer = Shine.Timer.Create

function Plugin:Initialise()
	self.Enabled = true
	self.dt.AllowOnosExo = self.Config.AllowOnosExo
	self.dt.AllowMines = self.Config.AllowMines
	self.dt.Enabled = false
	Shine.Hook.Add( "Think", "StartServerPGP", function( Deltatime )
		if self.Enabled then self:Enable() end		
		Shine.Hook.Remove( "Think", "StartServerPGP" )
	end )
	self.PlayerCount = 0
	return true
end

local function MakeTechEnt(techPoint, mapName, rightOffset, forwardOffset, teamType)
	local origin = techPoint:GetOrigin()
	local right = techPoint:GetCoords().xAxis
	local forward = techPoint:GetCoords().zAxis
	local position = origin+right*rightOffset+forward*forwardOffset

	local newEnt = CreateEntity( mapName, position, teamType)
	if HasMixin( newEnt, "Construct" ) then newEnt:SetConstructionComplete() end
end

--Hacky stuff
local function ReplaceGameStarted1( OldFunc, ... )
	local Hook = Shine.Hook.Call("CanEntDoDamageTo", ...)
	if not Hook then return OldFunc(...) end

	local gameinfo = GetGameInfoEntity()
	local oldGameInfoState = gameinfo:GetState()
	gameinfo:SetState(kGameState.Started)
	local temp = OldFunc(...)
	gameinfo:SetState(oldGameInfoState)

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

SetupClassHook( "Alien", "ProcessBuyAction", "PreProcessBuyAction", ReplaceGameStarted2 )
function Plugin:ProcessBuyAction()
	if self.dt.Enabled then return true end
end

SetupGlobalHook( "CanEntityDoDamageTo", "CanEntDoDamageTo", ReplaceGameStarted1)
function Plugin:CanEntDoDamageTo( Attacker, Target, ... )
	if not self.dt.Enabled then return end
	if HasMixin( Target, "Construct" ) or Target:isa("MAC") then return end
	return true
end

-- spawn crags for faster healing
SetupClassHook("AlienTeam", "SpawnInitialStructures", "AlienSpawnInitialStructures", "PassivePost")
function Plugin:AlienSpawnInitialStructures(AlienTeam, techPoint)	
	if not self.dt.Enabled then return end
	
	local teamNr = AlienTeam:GetTeamNumber()
	MakeTechEnt(techPoint, Crag.kMapName, 3.5, 1.5, teamNr)
	MakeTechEnt(techPoint, Crag.kMapName, 3.5, -1.5, teamNr)
	MakeTechEnt(techPoint, Shift.kMapName, -3.5, 1.5, teamNr)
end

-- spawns the armory, proto, armslab and 3 macs
SetupClassHook("MarineTeam", "SpawnInitialStructures", "MarSpawnInitialStructures", "PassivePost")
function Plugin:MarSpawnInitialStructures(MarTeam, techPoint)
	if not self.dt.Enabled then return end	
	local teamNr = MarTeam:GetTeamNumber()
	
	--don't spawn them if cheats is on(it already does it)
	if not ( Shared.GetCheatsEnabled() and MarineTeam.gSandboxMode ) then
		MakeTechEnt(techPoint, AdvancedArmory.kMapName, 3.5, 1.5, teamNr)
		MakeTechEnt(techPoint, PrototypeLab.kMapName, 3.5, -1.5, teamNr)
	end

	for i=1, 3 do
	  MakeTechEnt(techPoint, MAC.kMapName, -3.5, -1.5, teamNr)
	end   
	
	MakeTechEnt(techPoint, ArmsLab.kMapName, -3.5, 1.5, teamNr)
	local techTree = MarTeam:GetTechTree()
	if techTree then
		techTree:GetTechNode( kTechId.Armor1 ):SetResearched( true )
		techTree:GetTechNode( kTechId.Weapons1 ):SetResearched( true )
		techTree:GetTechNode( kTechId.Armor2 ):SetResearched( true )
		techTree:GetTechNode( kTechId.Weapons3 ):SetResearched( true )
		techTree:GetTechNode( kTechId.Armor3 ):SetResearched( true )
		techTree:GetTechNode( kTechId.Weapons3 ):SetResearched( true )
	end
end

-- instantly spawn dead aliens
SetupClassHook( "AlienTeam", "Update", "AlTeamUpdate", "PassivePost")
function Plugin:AlTeamUpdate(AlTeam, timePassed)
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
SetupClassHook("Embryo", "SetGestationData", "SetGestationData", "PassivePost")
function Plugin:SetGestationData( Embryo, ... )
	if self.dt.Enabled then Embryo.gestationTime = 1 end
end

--Prevent comm from moving crag
SetupClassHook( "Crag", "GetMaxSpeed", "CragGetMaxSpeed", "ActivePre")
function Plugin:CragGetMaxSpeed()
	if self.dt.Enabled then return 0 end
end

--Prevent comm from moving shifts
SetupClassHook( "Shift", "GetMaxSpeed", "ShiftGetMaxSpeed", "ActivePre")
function Plugin:ShiftGetMaxSpeed()
	if self.dt.Enabled then return 0 end
end

--prevents placing dead marines in IPs so we can do instant respawn
SetupClassHook("InfantryPortal", "FillQueueIfFree", "FillQueueIfFree", "Halt")
function Plugin:FillQueueIfFree( ... )
	if self.dt.Enabled then return true end
end

--immobile macs so they don't get lost on the map
SetupClassHook("MAC", "GetMoveSpeed", "MACGetMoveSpeed", "ActivePre")
function Plugin:MACGetMoveSpeed( ... )
	if self.dt.Enabled then return 0 end
end

-- lets players use macs to instant heal since the immobile mac
-- cannot move, it may get stuck trying to weld distant objects
SetupClassHook("MAC", "OnUse", "MACOnUse", "PassivePost")
function Plugin:MACOnUse( MAC, player, ... )
	if self.dt.Enabled then player:AddHealth(999, nil, false, nil) end
end

-- instantly respawn dead marines
SetupClassHook("MarineTeam", "Update", "MarTeamUpdate", "PassivePost")
function Plugin:MarTeamUpdate( MarTeam, timePassed )
	if self.dt.Enabled then
		local specs = MarTeam:GetSortedRespawnQueue()
		for i = 1, #specs do
			local spec = specs[i]
			MarTeam:RemovePlayerFromRespawnQueue(spec)
			local success,newMarine = MarTeam:ReplaceRespawnPlayer(spec, nil, nil)
			newMarine:SetCameraDistance(0)
		end
	end
end

SetupClassHook( "ScoringMixin", "AddAssistKill", "AddAssistKill", "ActivePre")
function Plugin:AddAssistKill()
	if self.dt.Enabled then return true end
end

SetupClassHook( "ScoringMixin", "AddKill", "AddKill", "ActivePre")
function Plugin:AddKill()
	if self.dt.Enabled then return true end
end

SetupClassHook( "ScoringMixin", "AddDeaths", "AddDeaths", "ActivePre")
function Plugin:AddDeaths()
	if self.dt.Enabled then return true end
end

SetupClassHook( "ScoringMixin", "AddScore", "AddScore", "ActivePre")
function Plugin:AddScore(points, res, wasKill)
	if self.dt.Enabled then return true end
end

function Plugin:SendText( Player )
	local Text = StringFormat("%s\n%s\n%s", StringFormat(statusString, self.dt.Enabled and "enabled" or "diabled"),
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

function Plugin:Enable()
	if self.dt.Enabled then return end
	self.dt.Enabled = true
	self:SendText()
	self:CreateTimer("PGPText", 1800, -1, function() self:SendText() end)
	
	local rules = GetGamerules()
	if not rules then return end
	self.PlayerCount = #GetEntitiesForTeam( "Player", 1) + #GetEntitiesForTeam( "Player", 2 )
	
	rules:ResetGame()
	rules:SetAllTech( true )
end

function Plugin:Disable()
	if not self.dt.Enabled then return end
	self.dt.Enabled = false
	self:RemoveText()
	self:DestroyAllTimers()
	
	local rules = GetGamerules()
	if not rules then return end	
	rules:ResetGame()
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if NewTeam == 1 or NewTeam == 2 and not ( OldTeam == 1 or OldTeam == 2 ) then
		self.PlayerCount = self.PlayerCount + 1
	else
		self.PlayerCount = self.PlayerCount - 1
	end
	
	if self.Config.CheckLimit and Gamerules:GetGameState() == kGameState.NotStarted then
		local PlayerLimit = tonumber( self.Config.PlayerLimit )
		if self.PlayerCount >= PlayerLimit and self.dt.Enabled then
			if self.Config.LimitToggleDelay > 0 then
				Shine.Timer.Create( "PGPLimit", 1, self.Config.LimitToggleDelay , function( Timer )
					if self.PlayerCount < PlayerLimit then
						self:SendText()
						Timer:Destroy()
						return
					end
					
					if Timer:GetReps() == 0 then
						self:Disable()
						return
					end
					
					self:UpdateText( StringFormat( "%s\n%s\n%s", StringFormat(statusString, "enabled" ),
						StringFormat( timerString, "off", Timer:GetReps() ), self.Config.ExtraMessageLine ))
				end)
			else
				self:Disable()
			end
		elseif self.PlayerCount < PlayerLimit and not self.dt.Enabled then
			if self.Config.LimitToggleDelay > 0 then
				Shine.Timer.Create( "PGPLimit", 1, self.Config.LimitToggleDelay, function( Timer )
					if self.PlayerCount >= PlayerLimit then
						self:SendText()
						Timer:Destroy()
						return
					end
					
					if Timer:GetReps() == 0 then
						self:Enable()
						return
					end
					
					self:UpdateText( StringFormat( "%s\n%s\n%s", StringFormat(statusString, "disabled" ),
						StringFormat( timerString, "on", Timer:GetReps() ), self.Config.ExtraMessageLine ))
				end)
			else
				self.Enable()
			end
		end
	end
end

function Plugin:ClientConfirmConnect( Client )
	local Player = Client:GetControllingPlayer()
	if not Player then return end
	
	self:SendText( Player )
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	if self.dt.Enabled and NewState ~= kGameState.NotStarted then 
		self:Disable() 
		Gamerules:SetGameState( NewState ) 
	end
	
	if not self.dt.Enabled and NewState == kGameState.NotStarted and OldState ~= kGameState.Countdown and OldState ~= kGameState.PreGame then
		self:Enable()
	end
end

function Plugin:Cleanup()
	self:Disable()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end