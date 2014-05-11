--[[
Shine Crossspawns plugin. - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Lower = string.lower
local Insert = table.insert
local JsonDecode = json.decode
local StringFormat = string.format

local Plugin = {}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "crossspawns.json"
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
        [ "ns2_kodiak" ] = false,
        [ "ns2_nsl_biodome" ] = true,
        [ "ns2_nsl_descent" ] = true,
        [ "ns2_nsl_docking" ] = true,
        [ "ns2_nsl_mineshaft" ] = true,
        [ "ns2_nsl_summit" ] = true,
        [ "ns2_nsl_eclipse" ] = true,
        [ "ns2_nsl_veil" ] = false,
    }
}
Plugin.CheckConfig = true

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
        return false, StringFormat( "The crossspawns plugin does not work with %s.", Gamemode )
    end
    
    self.Enabled = true
    return true
end

local LoadedSpawnFile
local ValidAlienSpawn
gCustomTechPoints = { }

--Load this File on server startup, cache table
local function LoadCustomTechPointData()
	local File = io.open( StringFormat( "maps/%s.txt", Shared.GetMapName() ), "r" )
	local ValidFile = false
	if File then
		local Temp = JsonDecode( File:read("*all"), 1, nil)
		local TechPoints = EntityListToTable( Shared.GetEntitiesWithClassname( "TechPoint" ) )
		File:close()
		if Temp then
			for _, TempTechPoint in pairs( Temp ) do
				for _, CurrentTechPoint in pairs( TechPoints ) do
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
						if TempTechPoint.enemyspawns ~= nil then
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
	end

	if not ValidFile then
		gCustomTechPoints = nil
	end
	
	LoadedSpawnFile = true
end

function Plugin:OnChooseTechPoint( NS2Gamerules, TechPoint, TeamNumber)
	if not self.Config.Maps[ Shared.GetMapName()] then return end
	
    if not LoadedSpawnFile then
        LoadCustomTechPointData()
    end

    if gCustomTechPoints ~= nil then
        if TeamNumber == kTeam1Index then
            Insert( gCustomTechPoints, TechPoint)
            --If getting team1 spawn location, build alien spawns for next check
            local ValidAlienSpawns = { }
            for _, CurrentTechPoint in pairs( gCustomTechPoints ) do
                local TeamNum = CurrentTechPoint:GetTeamNumberAllowed()
                if TechPoint.enemyspawns ~= nil and ( TeamNum == 0 or TeamNum == 2 ) then
                    for _, TempTechPoint in pairs(TechPoint.enemyspawns) do
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
    end
    return TechPoint
end

function Plugin:OnGameReset()
    if not self.Config.Maps[ Shared.GetMapName() ] then return end
    Server.spawnSelectionOverrides = false
end

Shine:RegisterExtension( "crossspawns", Plugin )