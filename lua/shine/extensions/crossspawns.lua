--[[
Shine Crossspawns plugin. - Server
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "crossspawns.json"
Plugin.DefaultConfig =
{
    Maps = {
        ["ns2_biodome"] = true,
        ["ns2_descent"] = true,
        ["ns2_docking"] = true,
        ["ns2_mineshaft"] = true,
        ["ns2_summit"] = true,
        ["ns2_eclipse"] = true,
    }
}
Plugin.CheckConfig = true

--Override default tech point choosing function to something that supports using the caches
Shine.Hook.SetupClassHook( "NS2Gamerules", "ChooseTechPoint", "OnChooseTechPoint", function( OldFunc, NS2Gamerules,  techPoints, teamNumber )
    local techPoint = OldFunc( NS2Gamerules, techPoints, teamNumber )
    local Ret = Shine.Hook.Call( "OnChooseTechPoint",  NS2Gamerules, techPoint, teamNumber )
    return Ret or techPoint
end )
Shine.Hook.SetupClassHook("NS2Gamerules","ResetGame","OnGameReset","PassivePre")

function Plugin:Initialise()
    local Gamemode = Shine.GetGamemode()
    if Gamemode ~= "ns2" then        
        return false, StringFormat( "The crossspawns plugin does not work with %s.", Gamemode )
    end
    
    self.Enabled = true
    return true
end

local kLoadedSpawnFile = false
local kValidAlienSpawn = nil
gCustomTechPoints = { }

--Load this file on server startup, cache table
local function LoadCustomTechPointData()
	local file = io.open("maps/" .. Shared.GetMapName() .. ".txt", "r")
	local validfile = false
	if file then
		local t = json.decode(file:read("*all"), 1, nil)
		local techPoints = EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))
		file:close()
		if t then
			for i,v in pairs(t) do
				for index, currentTechPoint in pairs(techPoints) do
					if (string.lower(v.name) == string.lower(currentTechPoint:GetLocationName())) then						
						--Modify the teams allowed to spawn here
						if (string.lower(v.team) == "marines") then
							currentTechPoint.allowedTeamNumber = 1
						elseif (string.lower(v.team) == "aliens") then
							currentTechPoint.allowedTeamNumber = 2
						elseif (string.lower(v.team) == "both") then
							currentTechPoint.allowedTeamNumber = 0
						--If we don't understand the team, no teams can spawn here
						else
							currentTechPoint.allowedTeamNumber = 3
						end
						
						--Assign the valid enemy spawns to the tech point
						if (v.enemyspawns ~= nil) then
							currentTechPoint.enemyspawns = v.enemyspawns
						end
						
						--Reset the weight parameter (will be customizable in the file later)
						currentTechPoint.chooseWeight = 1
						
						table.insert(gCustomTechPoints, currentTechPoint)
						validfile = true
					end
				end
			end
		end
	end

	if not validfile then
		gCustomTechPoints = nil
	end
	
	if validfile then
		--Prevent Map Specific spawn overrides from being used
		Server.spawnSelectionOverrides = nil
	end
	kLoadedSpawnFile = true
	
end

function Plugin:OnChooseTechPoint(NS2Gamerules, techPoint, teamNumber)
	if not self.Config.Maps[Shared.GetMapName()] then return end
	
    if not kLoadedSpawnFile then
        LoadCustomTechPointData()
    end

    if gCustomTechPoints ~= nil then
        if teamNumber == kTeam1Index then
            table.insert(gCustomTechPoints, techPoint)
            --If getting team1 spawn location, build alien spawns for next check
            local ValidAlienSpawns = { }
            for index, currentTechPoint in pairs(gCustomTechPoints) do
                local teamNum = currentTechPoint:GetTeamNumberAllowed()
                if (techPoint.enemyspawns ~= nil and (teamNum == 0 or teamNum == 2)) then
                    for i,v in pairs(techPoint.enemyspawns) do
                        if (v == currentTechPoint:GetLocationName()) then
                            table.insert(ValidAlienSpawns, currentTechPoint)
                        end
                    end
                end
            end
            local randomTechPointIndex = math.random(#ValidAlienSpawns)
            kValidAlienSpawn = ValidAlienSpawns[randomTechPointIndex]
        elseif teamNumber == kTeam2Index then
            techPoint = kValidAlienSpawn
        end
    end
    return techPoint
end

function Plugin:OnGameReset()
    if not self.Config.Maps[Shared.GetMapName()] then return end
    Server.spawnSelectionOverrides = false
end
Shine:RegisterExtension( "crossspawns", Plugin )