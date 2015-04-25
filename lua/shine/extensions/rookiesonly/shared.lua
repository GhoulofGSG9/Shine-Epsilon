--[[
    Shine Rookies Only - Shared
]]
local Plugin = {}

Shine:RegisterExtension( "rookiesonly", Plugin, {
    Base = "hiveteamrestriction",
    BlacklistKeys = {
        BuildBlockMessage = true
    }
} )

