--[[
--Original idea and design by Andrew Krigline (https://github.com/akrigline)
--Original source can be found at https://github.com/akrigline/EnforceTeamSize
]]
local Shine = Shine

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "enforceteamsizes.json"

--[[
--TeamNumbers:
 - 0: RR
 - 1: Marines
 - 2: Aliens
 - 3: Spec
 ]]
Plugin.DefaultConfig = {
    Teams = {
        [1] = {
            MaxPlayers = 8,
            TooManyMessage = "The %s have currently too many players. Please Spectate until the round ends."
        },
        [2] = {
            MaxPlayers = 8,
            TooManyMessage = "The %s have currently too many players. Please Spectate until the round ends."
        }
    },
    MessageNameColor = {0, 255, 0}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
    self.Enabled = true
    return true
end
function Plugin:JoinTeam(Gamerules, Player, NewTeam, Force, ShineForce)
    if ShineForce or not self.Config.Teams[NewTeam] then return end

    --Check if team is above MaxPlayers
    if Gamerules:GetTeam(NewTeam):GetNumPlayers() >= self.Config.Teams[NewTeam].MaxPlayers then
        --Inform player
        Shine:NotifyDualColour( Player, self.Config.MessageNameColor[1], self.Config.MessageNameColor[2],
            self.Config.MessageNameColor[3], "EnforcedTeamSizes", 255, 255, 255,
            self.Config.Teams[NewTeam].TooManyMessage, true, Shine:GetTeamName(NewTeam, true) )
        return false
    end
end
Shine:RegisterExtension("enforceteamsizes", Plugin )

