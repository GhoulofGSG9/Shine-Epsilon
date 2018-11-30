--[[
	Shine Custom Timeout plugin.

	Clients send a heartbeat every 200-500 ms to the server
	which allows the server to detect inactive client connections.
]]

local Plugin = {}
Plugin.Version = "1.1"
Plugin.NotifyPrefixColour = { 255, 50, 0 }

function Plugin:SetupDataTable()
    self:AddNetworkMessage( "Heartbeat", {}, "Server" )
end

Shine:RegisterExtension( "customtimeout", Plugin )
