--[[
Shine Custom Spawns plug-in. - Server
]]

local Shine = Shine

local Lower = string.lower
local StringFormat = string.format
local IsType = Shine.IsType

local Plugin = {}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "customspawns/config.json"
Plugin.DefaultConfig =
{
    Maps = {
        [ "ns2_biodome" ] = true,
        [ "ns2_descent" ] = true,
        [ "ns2_docking" ] = true,
        [ "ns2_mineshaft" ] = true,
        [ "ns2_summit" ] = true,
        [ "ns2_eclipse" ] = true,
        [ "ns2_veil" ] = false,
        [ "ns2_kodiak" ] = false
    }
}

--list of default cross spawn map settings
local MapConfigs = {
	[ "ns2_biodome" ] = {
		{
			name = "Reception",
			team = "marines",
			enemyspawns = {
				"Atmosphere Exchange"
			}
		},
		{
			name = "Atmosphere Exchange",
			team = "aliens"
		}
	},
	[ "ns2_descent" ] = {
		{
			name = "Drone Bay",
			team = "both",
			enemyspawns = {
				"Fabrication" 
			}
		},
		{
			name = "Fabrication",
			team = "both",
			enemyspawns = {
				"Drone Bay"
			}
		},
		{
			name = "Launch Control",
			team = "both",
			enemyspawns = { 
				"Monorail" 
			}
		},
		{
			name = "Monorail",
			team = "both",
			enemyspawns = { 
				"Launch Control" 
			}
		}
	},
	[ "ns2_docking" ] = {
		{
			name = "Terminal",
			team = "marines",
			enemyspawns = { 
				"Generator" 
			}
		},
		{
			name = "Generator",
			team = "aliens"
		}
	},
	[ "ns2_mineshaft" ] = {
		{
			name = "Operations",
			team = "marines",
			enemyspawns = { 
				"Cave" 
			}
		},
		{
			name = "Repair",
			team = "marines",
			enemyspawns = { 
				"Sorting" 
			}
		},
		{
			name = "Cave",
			team = "aliens"
		},
		{
			name = "Sorting",
			team = "aliens"
		}
	},
	[ "ns2_summit" ] = {
		{
			name = "Sub Access",
			team = "both",
			enemyspawns = { 
				"Atrium" 
			}
		},
		{
			name = "Data Core",
			team = "both",
			enemyspawns = { 
				"Flight Control" 
			}
		},
		{
			name = "Flight Control",
			team = "both",
			enemyspawns = { 
				"Data Core" 
			}
		},
		{
			name = "Atrium",
			team = "both",
			enemyspawns = { 
				"Sub Access" 
			}
		}
	},
	[ "ns2_eclipse" ] = {
		{
			name = "Marine Start",
			team = "marines",
			enemyspawns = { 
				"Computer Core" 
			}
		},
		{
			name = "Computer Core",
			team = "aliens"
		}
	},
	[ "ns2_veil" ] = {
		{
			name = "Control",
			team = "marines",
			enemyspawns = { 
				"Cargo" 
			}
		},
		{
			name = "Cargo",
			team = "aliens"
		}
	},
	[ "ns2_kodiak" ] = {
		{
			name = "Astroid Tracking",
			team = "marines",
			enemyspawns = { 
				"Command" 
			}
		},
		{
			name = "Command",
			team = "aliens"
		}
	},
}

Shine.Hook.SetupClassHook( "NS2Gamerules", "ChooseTechPoint", "OnChooseTechPoint",
	function( OldFunc, NS2Gamerules,  TechPoints, TeamNumber )

	Shine.Hook.Call( "PreChooseTechPoint",  NS2Gamerules, TechPoints, TeamNumber )

    --Override default tech point choosing function to something that supports using the caches
    local TechPoint = OldFunc( NS2Gamerules, TechPoints, TeamNumber )
    local Ret = Shine.Hook.Call( "OnChooseTechPoint",  NS2Gamerules, TechPoint, TeamNumber, TechPoints )
    return Ret or TechPoint
end )
Shine.Hook.SetupClassHook( "NS2Gamerules", "ResetGame", "OnGameReset", "PassivePre")
Shine.Hook.SetupClassHook( "AlienTeam", "SpawnInitialStructures", "PostAlienTeamSpawnInitialStructures",
	function( OldFunc, self, TechPoint)
		local Tower, CommandStructure = OldFunc(self, TechPoint)
		Shine.Hook.Call( "PostAlienTeamSpawnInitialStructures", self, TechPoint, Tower, CommandStructure )
		return Tower, CommandStructure
	end)

function Plugin:Initialise()
    self.Gamemode = Shine.GetGamemode()
    if self.Gamemode ~= "ns2" and self.Gamemode ~= "mvm" then
        return false, StringFormat( "The customspawns plugin does not work with %s.", Gamemode )
    end
    
	self.Enabled = true
	 
	if GetGamerules and GetGamerules() then
		GetGamerules():ResetGame()
	end
	
    return true
end

local function LoadMapConfig( Mapname, Gamemode )
	local MapPath = StringFormat( "customspawns/%s.json" , Mapname )
	
	local Path = Shine.Config.ExtensionDir .. MapPath
	local MapConfig = Shine.LoadJSONFile( Path )

	--Look for gamemode specific config file.
	if not MapConfig and Gamemode ~= "ns2" then
		Path = StringFormat( "%s%s/%s", Shine.Config.ExtensionDir, Gamemode, MapPath )
		MapConfig = Shine.LoadJSONFile( Path )
	end
	
	if ( not MapConfig or not IsType( MapConfig, "table" ) ) and MapConfigs[ Mapname ] then
		Shine.SaveJSONFile( MapConfigs[ Mapname ], Path )
		MapConfig = MapConfigs[ Mapname ]
	end
	
	return MapConfig
end

local ValidFile = false
function Plugin:PreChooseTechPoint( _, TechPoints )
	if ValidFile or not self.Enabled then return end

	if not self.Config.Maps[ Shared.GetMapName() ] then 
		self.Enabled = false
		return
	end

	local Mapname = Shared.GetMapName()
	local Temp = LoadMapConfig( Mapname, self.Gamemode )
	
	if Temp then
		for _, TempTechPoint in ipairs( Temp ) do
			for _, CurrentTechPoint in ipairs( TechPoints ) do
				if Lower( TempTechPoint.name ) == Lower( CurrentTechPoint:GetLocationName() ) then						
					--Modify the teams allowed to spawn here
					if  Lower( TempTechPoint.team ) == "marines" then
						CurrentTechPoint.allowedTeamNumber = 1
					elseif Lower( TempTechPoint.team ) == "aliens" then
						CurrentTechPoint.allowedTeamNumber = 2
					elseif Lower( TempTechPoint.team ) == "both" then
						CurrentTechPoint.allowedTeamNumber = 0
					--If we don't understand the team, no teams can spawn here
					else
						CurrentTechPoint.allowedTeamNumber = 3
					end
					
					--Assign the valid enemy spawns to the tech point
					if TempTechPoint.enemyspawns then
						CurrentTechPoint.enemyspawns = TempTechPoint.enemyspawns
					end
					
					--Reset the weight parameter (will be customizable in the File later)
					CurrentTechPoint.chooseWeight = 1

					ValidFile = true
				end
			end
		end
	end

	if not ValidFile then
		self.Enabled = false
		Shared.Message( StringFormat( "[Custom Spawns]: Couldn't find a valid spawn set-up file for %s, disabling the plug-in for now", Mapname ))
	end
end

function Plugin:OnChooseTechPoint( _, TechPoint, TeamNumber, TechPoints)
	if TeamNumber == kTeam1Index then
		--If getting team1 spawn location, build alien spawns for next check
		local RandomTechPointIndex = math.random( #TechPoint.enemyspawns )
		self.ValidAlienSpawn = TechPoint.enemyspawns[ RandomTechPointIndex ]
	elseif TeamNumber == kTeam2Index and self.ValidAlienSpawn and
			Lower( TechPoint:GetLocationName() ) ~= Lower( self.ValidAlienSpawn ) then
		for _, techPoint in pairs(TechPoints) do
			if Lower( techPoint:GetLocationName() ) == Lower(self.ValidAlienSpawn) then
				TechPoint = techPoint
			end
		end
	end
	
    return TechPoint
end

function Plugin:OnGameReset()
    Server.spawnSelectionOverrides = false
end

--Needed to avoid that Harvester die at tech point where no cysts are pre-placed
function Plugin:PostAlienTeamSpawnInitialStructures( Team, _, Tower )
	local origin = Tower:GetOrigin()
	if #GetEntitiesWithinRange( "Cyst", origin, kInfestationRadius ) > 0 then return end

	local cystPoints, parent, normals = GetCystPoints( origin )

	if parent then
		local previousParent
		for i = 2, #cystPoints do

			local cyst = CreateEntity(Cyst.kMapName, cystPoints[i], Team:GetTeamNumber())
			cyst:SetCoords(AlignCyst(Coords.GetTranslation(cystPoints[i]), normals[i]))

			cyst:SetImmuneToRedeploymentTime(0.05)
			cyst:SetConstructionComplete()
			cyst:SetInfestationFullyGrown()

			if not cyst:GetIsConnected() and previousParent then
				cyst:ReplaceParent(previousParent)
			end

			previousParent = cyst
		end
	end
end

Shine:RegisterExtension( "customspawns", Plugin )