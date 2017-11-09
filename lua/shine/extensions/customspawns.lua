--[[
Shine Custom Spawns plug-in. - Server
]]

local Shine = Shine
local SetupClassHook = Shine.Hook.SetupClassHook


local Lower = string.lower
local StringFormat = string.format
local IsType = Shine.IsType

local Plugin = {}

Plugin.Version = "1.1"
Plugin.NS2Only = true

Plugin.HasConfig = true
Plugin.ConfigName = "customspawns/config.json"
Plugin.DefaultConfig =
{
    Maps = {
        [ "ns2_biodome" ] = true,
	    [ "ns2_caged" ] = false,
	    [ "ns2_derelict"] = false,
        [ "ns2_descent" ] = true,
        [ "ns2_docking" ] = true,
	    [ "ns2_eclipse" ] = true,
	    [ "ns2_kodiak" ] = false,
        [ "ns2_mineshaft" ] = true,
        [ "ns2_refinery" ] = false,
        [ "ns2_summit" ] = true,
        [ "ns2_tram" ] = false,
        [ "ns2_veil" ] = false,
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
			team = "aliens",
			enemyspawns = {
				"Reception"
			}
		}
	},
	[ "ns2_caged" ] = {
		{
			name = "main hold",
			team = "marines",
			enemyspawns = {
				"ventilation system"
			}
		},
		{
			name = "ventilation system",
			team = "aliens",
			enemyspawns = {
				"main hold"
			}
		}
	},
	[ "ns2_derelict" ] = {
		{
			enemyspawns = {
				"geothermal"
			},
			name = "western entrance",
			team = "marines"
		},
		{
			enemyspawns = {
				"atmospheric seeding"
			},
			name = "garage",
			team = "both"
		},
		{
			enemyspawns = {
				"western entrance"
			},
			name = "geothermal",
			team = "aliens"
		},
		{
			enemyspawns = {
				"garage"
			},
			name = "atmospheric seeding",
			team = "both"
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
	[ "ns2_kodiak" ] = {
		{
			name = "Asteroid Tracking",
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
	[ "ns2_refinery" ] = {
		{
			enemyspawns = {
				"pipeworks"
			},
			name = "smelting",
			team = "both"
		},{
			enemyspawns = {
				"flow control"
			},
			name = "containment",
			team = "both"
		},{
			enemyspawns = {
				"turbine",
				"smelting"
			},
			name = "pipeworks",
			team = "both"
		},{
			enemyspawns = {
				"containment"
			},
			name = "flow control",
			team = "both"
		},{
			enemyspawns = {
				"pipeworks"
			},
			name = "turbine",
			team = "both"
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
	[ "ns2_tram" ] = {
		{
			enemyspawns = {
				"shipping"
			},
			name = "warehouse",
			team = "both"
		},{
			enemyspawns = {},
			name = "repair room",
			team = "none"
		},{
			enemyspawns = {
				"shipping"
			},
			name = "server room",
			team = "both"
		},{
			enemyspawns = {
				"warehouse",
				"server room"
			},
			name = "shipping",
			team = "both"
		},{
			enemyspawns = {},
			name = "elevator transfer",
			team = "none"
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
SetupClassHook( "TechPoint", "GetChooseWeight", "OnTechPointGetChooseWeight", "ActivePre")
SetupClassHook( "TechPoint", "GetTeamNumberAllowed", "OnTechPointGetTeamNumberAllowed", "ActivePre")
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

function Plugin:OnTechPointGetChooseWeight()
	return 1
end

function Plugin:ParseMapConfig()
	local MapName = Lower( Shared.GetMapName() )

	self.Spawns = GetEntities("TechPoint")
	-- convert list into a set
	for i = 1, #self.Spawns do
		local TechPoint = self.Spawns[i]
		local Name = Lower( TechPoint:GetLocationName() )

		self.Spawns[Name] = TechPoint
	end

	if not self.Config.Maps[ MapName ] then
		self.Enabled = false --So the command might be used
		return
	end

	local Spawns = LoadMapConfig( MapName, self.Gamemode )

	local NumAlienSpawns = 0
	local NumMarineSpawns = 0

	for i = 1, #Spawns do
		local Spawn = Spawns[i]
		local name = Lower( Spawn.name )

		if not self.Spawns[ name ] then
			return StringFormat("%s in the given mapconfig is not a valid spawn!", Spawn.name )
		end

		if not Spawn.team then
			return StringFormat("the spawn %s has no valid team in the given mapconfig!", Spawn.name )
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

		if team < 2 and (not Spawn.enemyspawns or not type( Spawn.enemyspawns ) == "table" or #Spawn.enemyspawns < 1) then
			return StringFormat("the spawn %s has no valid enemyspawns in the given mapconfig!", Spawn.name )
		end

		self.Spawns[ name ].enemyspawns = Spawn.enemyspawns
	end

	if NumAlienSpawns < 1 or NumMarineSpawns < 1 then
		return "there are not enought spawns for both teams in the given mapconfig!"
	end
end

function Plugin:OnTechPointGetTeamNumberAllowed( TechPoint )
	local name = Lower( TechPoint:GetLocationName() )
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
	if self.Spawns == nil then
		local error = self:ParseMapConfig()
		if error then
			Shared.Message(StringFormat("[CustomSpawns] Error, %s", error))
			Shared.Message("[CustomSpawns] Unloading the plugin now ...")
			Shine:UnloadExtension( "customspawns" )
		else
			--doing this here as map has been completly loaded at this point.
			self:CreateCommands()
		end
	end

	if not self.Enabled then return end

    Server.spawnSelectionOverrides = false
    Server.teamSpawnOverride = false
end

-- Needed to avoid that Harvester die at tech point where no cysts are pre-placed
-- Todo: Merge this into vanilla
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

function Plugin:Notify( Player, String, Format, ... )
	Shine:NotifyDualColour( Player, 0, 100, 255, "[CustomSpawns]", 255, 255, 255, String, Format, ... )
end

function Plugin:CreateCommands()
	local function DumpSpawns( Client, DumpName)
		local SpawnsTable = {}
		local Spawns = {
			[0] = {},
			[1] = {},
			[2] = {},
			[3] = {},
		}
		local TeamNames = {
			[0] = "both",
			[1] = "marines",
			[2] = "aliens",
			[3] = "none",
		}

		local TechPoints = GetEntities("TechPoint")
		for i = 1, #TechPoints do
			local TechPoint = TechPoints[i]
			local Name = Lower( TechPoint:GetLocationName() )
			table.insertunique(Spawns[TechPoint.allowedTeamNumber], Name )
		end

		local function GetEnemySpawns( TeamNumber, TpName )
			if TeamNumber > 2 then return {} end

			local function filter(t, v)
				for i = 1, #t do
					local e = t[i]
					if e == v then
						table.remove(t, i)
						break
					end
				end

				return t
			end

			local function merge( t1, t2 )
				for i = 1, #t2 do
					local name = t2[i]
					t1[#t1 + 1] = name
				end
				return t1
			end

			--noinspection ArrayElementZero
			local spawns = table.Copy(Spawns[0]) --localize, so we don't overriding the original table

			if TeamNumber < 2 then
				return filter(merge( spawns, Spawns[2] ), TpName)
			else
				return filter(merge( spawns, Spawns[1] ), TpName)
			end
		end

		for i = 1, #TechPoints do
			local TechPoint = TechPoints[i]
			local Name = Lower( TechPoint:GetLocationName() )
			local SpawnEntry = {}

			SpawnEntry.name = Name
			SpawnEntry.team = TeamNames[ TechPoint.allowedTeamNumber ]
			SpawnEntry.enemyspawns = GetEnemySpawns( TechPoint.allowedTeamNumber, Name )
			SpawnsTable[ #SpawnsTable + 1 ] = SpawnEntry
		end

		local filename = StringFormat( "%scustomspawns/%s.json", Shine.Config.ExtensionDir, DumpName )
		Shine.SaveJSONFile( SpawnsTable, filename )
		self:Notify( Client, "Spawn Dump has been saved to %s!", true, filename)
	end

	local DumpSpawnsCommand = self:BindCommand( "sh_dumpspawns", "dumpspawns", DumpSpawns )
	DumpSpawnsCommand:AddParam{ Type = "string", Optional = true, Default = StringFormat("%s_dumped", Lower( Shared.GetMapName()))}
	DumpSpawnsCommand:Help( "<filename> Dumps the techpoints of this maps into a valid mapconfig file (with the given name)" )
end

function Plugin:Cleanup()
	self.Spawns = nil
	self.ValidAlienSpawn = nil

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end


Shine:RegisterExtension( "customspawns", Plugin )