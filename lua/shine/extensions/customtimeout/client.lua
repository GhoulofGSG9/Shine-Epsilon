--[[
    Shine Custom Timeout plugin.
]]
local Plugin = Plugin

function Plugin:Initialise()
    self:CreateTimer( "SendHeartbeat", .2, -1, function() self:SendHeartBeat() end )
end

function Plugin:SendHeartBeat()
    self:SendNetworkMessage( "Heartbeat", {}, true)
end