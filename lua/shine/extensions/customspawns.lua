--[[
Shine Custom Spawns plug-in. - Server
]]

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook


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

SetupClassHook( "NS2Gamerules", "ChooseTechPoint", "OverrideChooseTechPoint",
	function( OldFunc, NS2Gamerules,  TechPoints, TeamNumber )

	local Pre = Shine.Hook.Call( "PreChooseTechPoint",  NS2Gamerules, TechPoints, TeamNumber)
	if Pre then return Pre end

    local TechPoint = OldFunc( NS2Gamerules, TechPoints, TeamNumber )
    Shine.Hook.Call( "PostChooseTechPoint",  NS2Gamerules, TechPoint, TeamNumber)
    return TechPoint
end )
SetupClassHook( "NS2Gamerules", "ResetGame", "OnGameReset", "PassivePre")
SetupClassHook( "TechPoint", "OnInitialized", "TechPointIntialized", "PassivePost")
SetupClassHook( "TechPoint", "GetChooseWeight", "OnGetChooseWeight", "ActivePre")
SetupClassHook( "TechPoint", "GetTeamNumberAllowed", "OnGetTeamNumberAllowed", "ActivePre")
SetupClassHook( "AlienTeam", "SpawnInitialStructures", "PostAlienTeamSpawnInitialStructures",
	function( OldFunc, self, TechPoint)
		local Tower, CommandStructure = OldFunc(self, TechPoint)
		Shine.Hook.Call( "PostAlienTeamSpawnInitialStructures", self, TechPoint, Tower, CommandStructure )
		return Tower, CommandStructure
	end)

function Plugin:Initialise()
	self.Gamemode = Shine.GetGamemode()
	if self.Gamemode ~= "ns2" and self.Gamemode ~= "mvm" then
		return false, StringFormat( "The customspawns plugin does not work with %s.", self.Gamemode )
	end

	self.TechPoints = {}
	self.Enabled = true
	
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

function Plugin:TechPointIntialized( TechPoint )
	--Don't rebuild table after we have parsed the config!
	if self.Spawns then return end

	self.TechPoints[ Lower(TechPoint:GetLocationName()) ] = TechPoint
end

function Plugin:OnGetChooseWeight()
	return 1
end

function Plugin:ParseMapConfig()
	local MapName = Lower( Shared.GetMapName() )
	if not self.Config.Maps[ MapName ] then
		Shine:UnloadExtension( "customspawns" )
		return
	end

	self.Spawns = self.TechPoints
	self.TechPoints = nil

	local Spawns = LoadMapConfig( MapName, self.Gamemode )

	local NumAlienSpawns = 0
	local NumMarineSpawns = 0

	for _, Spawn in ipairs(Spawns) do
		local name = Lower( Spawn.name )

		if not self.Spawns[ name ] then
			return StringFormat("[CustomSpawns]: Couldn't parse the given mapconfig as %s is not a valid spawn!", Spawn.Name )
		end

		if not Spawn.enemyspawns or not type( Spawn.enemyspawns ) == "table" or #Spawn.enemyspawns < 1 then
			return StringFormat("[CustomSpawns]: Couldn't parse the given mapconfig as %s has no valid enemyspawns!", Spawn.Name )
		end

		self.Spawns[ name ].enemyspawns = Spawn.enemyspawns

		if not Spawn.team then
			return StringFormat("[CustomSpawns]: Couldn't parse the given mapconfig as %s has no valid team!", Spawn.Name )
		end

		local team = 3
		local teamname = Lower( Spawn.team )
		if teamname == "both" then
			NumAlienSpawns = NumAlienSpawns + 1
			NumMarineSpawns = NumMarineSpawns + 1
			team = 0
		elseif teamname == "aliens" then
			NumAlienSpawns = NumAlienSpawns + 1
			team = 2
		elseif teamname == "marines" then
			NumMarineSpawns = NumMarineSpawns + 1
			team = 1
		end

		self.Spawns[ name ].team = team
	end

	if NumAlienSpawns < 1 or NumMarineSpawns < 1 then
		return "[CustomSpawns]: Couldn't parse the given mapconfig are not enought spawns for both teams!"
	end
end

function Plugin:OnGetTeamNumberAllowed( TechPoint )
	if self.Spawns == nil then
		local error = self:ParseMapConfig()
		if error then
			Shared.Message(error)
			Shine.UnloadExtension( "customspawns" )
			return
		end
	end

	local name =  Lower( TechPoint:GetLocationName() )
	return self.Spawns[ name ] and self.Spawns[ name ].team or 3
end

--Called after a techpoint has been chosen.
function Plugin:PostChooseTechPoint( _, TechPoint, TeamNumber)
	if TeamNumber == kTeam1Index then
		local name =  Lower( TechPoint:GetLocationName() )
		local enemyspawns = self.Spawns[ name ] and self.Spawns[ name ].enemyspawns
		if enemyspawns then
			local random = math.random( #enemyspawns )
			self.ValidAlienSpawn = self.Spawns[ Lower( enemyspawns[ random ] ) ]
		end
	end
end

--Called before a techpoint has been chosen, if this returns soemthing it gets immediately returned by the hooked function
function Plugin:PreChooseTechPoint( _, _, TeamNumber)
	if TeamNumber == kTeam2Index and self.ValidAlienSpawn then
		local TechPoint = self.ValidAlienSpawn
		self.ValidAlienSpawn = nil
		return TechPoint
	end
end

function Plugin:OnGameReset()
    Server.spawnSelectionOverrides = false
    Server.teamSpawnOverride = false
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

function Plugin:CleanUp()
	self.TechPoints = nil
	self.Spawns = nil
	self.ValidAlienSpawn = nil

	self.BaseClass.CleanUp()

	self.Enabled = false
end


Shine:RegisterExtension( "customspawns", Plugin )