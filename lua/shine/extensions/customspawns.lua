--[[
Shine Custom Spawns plug-in. - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Lower = string.lower
local Insert = table.insert
local JsonDecode = json.decode
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

Shine.Hook.SetupClassHook( "NS2Gamerules", "ChooseTechPoint", "OnChooseTechPoint", function( OldFunc, NS2Gamerules,  TechPoints, TeamNumber )
    --Override default tech point choosing function to something that supports using the caches
    local TechPoint = OldFunc( NS2Gamerules, TechPoints, TeamNumber )
    local Ret = Shine.Hook.Call( "OnChooseTechPoint",  NS2Gamerules, TechPoint, TeamNumber )
    return Ret or TechPoint
end )
Shine.Hook.SetupClassHook( "NS2Gamerules", "ResetGame", "OnGameReset", "PassivePre")

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" and Gamemode ~= "mvm" then        
        return false, StringFormat( "The customspawns plugin does not work with %s.", Gamemode )
    end
    
	self.Enabled = true
	 
	if Shared.GetMapName() then
		self:MapPostLoad()
	end
	
    return true
end

local function LoadMapConfig( Mapname, Gamemode )
	local MapConfig
	local MapPath = StringFormat( "customspawns/%s.json" , Mapname )
	
	local Path = Shine.Config.ExtensionDir .. MapPath
	local Err
	local Pos

	--Look for gamemode specific config file.
	if Gamemode ~= "ns2" then
		local Paths = {
			StringFormat( "%s%s/%s", Shine.Config.ExtensionDir, Gamemode, MapPath ),
			Path
		}
		for i = 1, #Paths do
			local File, ErrPos, ErrString = Shine.LoadJSONFile( Paths[ i ] )
			if File then
				MapConfig = File
				break
			elseif IsType( ErrPos, "number" ) then
				Err = ErrString
				Pos = ErrPos
			end
		end
	else
		MapConfig, Pos, Err = Shine.LoadJSONFile( Path )
	end
	
	if ( not MapConfig or not IsType( MapConfig, "table" ) ) and MapConfigs[ Mapname ] then
		Shine.SaveJSONFile( MapConfigs[ Mapname ], Path )
		MapConfig = MapConfigs[ Mapname ]
	end
	
	return MapConfig
end

local gCustomTechPoints = {}
function Plugin:MapPostLoad()
	if not self.Config.Maps[ Shared.GetMapName() ] then 
		self.Enabled = false
		return
	end
	
	local Gamemode = Shine.GetGamemode()
	local Mapname = Shared.GetMapName()
	local Temp = LoadMapConfig( Mapname, Gamemode )
	local ValidFile = false
	local TechPoints = EntityListToTable( Shared.GetEntitiesWithClassname( "TechPoint" ) )
	
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
					
					Insert( gCustomTechPoints, CurrentTechPoint )
					ValidFile = true
				end
			end
		end
	end

	if not ValidFile then
		self.Enabled = false
		Print( StringFormat( "[Custom Spawns]: Couldn't find a valid spawn set-up file for %s, disabling the plug-in for now", Mapname ))
		return
	end
	
	--reset game just to apply custom spawns directly
	self:SimpleTimer( 1, function() GetGamerules():ResetGame() end)
end

function Plugin:OnChooseTechPoint( NS2Gamerules, TechPoint, TeamNumber)
	if TeamNumber == kTeam1Index then
		Insert( gCustomTechPoints, TechPoint)
		--If getting team1 spawn location, build alien spawns for next check
		local ValidAlienSpawns = { }
		for _, CurrentTechPoint in ipairs( gCustomTechPoints ) do
			local TeamNum = CurrentTechPoint:GetTeamNumberAllowed()
			if TechPoint.enemyspawns and ( TeamNum == 0 or TeamNum == 2 ) then
				for _, TempTechPoint in ipairs(TechPoint.enemyspawns) do
					if ( TempTechPoint == CurrentTechPoint:GetLocationName() ) then
						Insert( ValidAlienSpawns, CurrentTechPoint )
					end
				end
			end
		end
		local RandomTechPointIndex = math.random( #ValidAlienSpawns )
		ValidAlienSpawn = ValidAlienSpawns[ RandomTechPointIndex ]
	elseif TeamNumber == kTeam2Index then
		TechPoint = ValidAlienSpawn
	end
	
    return TechPoint
end

function Plugin:OnGameReset()
    Server.spawnSelectionOverrides = false
end

Shine:RegisterExtension( "customspawns", Plugin )