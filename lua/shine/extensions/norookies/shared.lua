--[[
    Shine No Rookies - Shared
]]
local Plugin = {}

Shine:RegisterExtension( "norookies", Plugin, {
	Base = "hiveteamrestriction",
	BlacklistKeys = {
		BuildBlockMessage = true
	}
} )