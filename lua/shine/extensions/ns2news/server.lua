--[[
	Shine NS2News plugin.
]]
local Shine = Shine
local Plugin = Plugin

Plugin.HasConfig = true
Plugin.ConfigName = "NS2News.json"

local webUrl = "http://ns2news.org/"

Plugin.DefaultConfig = {
	ShowMenuEntry = true
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self:CreateCommands()

	self.dt.ShowMenuEntry = self.Config.ShowMenuEntry

	self.Enabled = true

	return true
end

function Plugin:ShowNews( Client )
	if not Shine:IsValidClient( Client ) then return end

	Shine.SendNetworkMessage( Client, "Shine_Web", {
		URL = webUrl,
		Title = "NS2News"
	}, true )
end

function Plugin:CreateCommands()

	local function News( Client )
		if not Client then return end

		self:ShowNews( Client )
	end
	local NewsCommand = self:BindCommand( "sh_news", "news", News, true )
	NewsCommand:Help( "Shows the NS2 news." )

	local function ShowNews( _, Target )
		self:ShowNews( Target )
	end
	local ShowNewsCommand = self:BindCommand( "sh_shownews", "shownews", ShowNews )
	ShowNewsCommand:AddParam{ Type = "client" }
	ShowNewsCommand:Help( "<player> Shows the NS2 news to the given player." )

end

