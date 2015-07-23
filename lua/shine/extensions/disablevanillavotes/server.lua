--[[
	DisableVanillaVotes - Server
	Inspired by the TF plugin from ShamelessCookie which can be found here:
	https://github.com/ShamelessCookie/tactical-freedom/blob/master/output/lua/shine/extensions/tf_disablestockvoting.lua
 ]]

local Plugin = Plugin
local Shine = Shine

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "DisableVanillaVotes.json"
Plugin.DefaultConfig = {
	VoteChangeMap = {
		Enabled = true,
		Message = "To vote to change the map, press %s > RTV."
	},
	VotingForceEvenTeams = {
		Enabled = true,
		Message = "To vote to force even teams, press %s > Shuffle."
	},
	VoteRandomizeRR = {
		Enabled = true,
		Message = "To vote to randomize teams, press %s > Shuffle."
	},
	VoteKickPlayer = {
		Enabled = true,
		Message = "Please contact a server operator to get a player kicked."
	},
	VoteResetGame = {
		Enabled = true,
		Message = "Please contact a  server operator to reset the game."
	},
	Message = {
		R = 81,
		G = 194,
		B = 243
	}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Enabled = true

	self.dt.R = math.Clamp(self.Config.Message.R, 0, 255)
	self.dt.G = math.Clamp(self.Config.Message.G, 0, 255)
	self.dt.B = math.Clamp(self.Config.Message.B, 0, 255)

	return true
end

function Plugin:NS2StartVote(VoteName, Client)
	local VoteOption =  self.Config[VoteName]
	if VoteOption and not VoteOption.Enabled then
		self:Notify(Client, VoteOption.Message)
		return false
	end

end

function Plugin:Notify( Client, Message )
	self:SendNetworkMessage( Client, "Message", { Message = Message }, true )
end

