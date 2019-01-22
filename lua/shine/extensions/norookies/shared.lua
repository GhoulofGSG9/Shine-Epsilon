--[[
	Shine No Rookies - Shared
]]
local Plugin = Shine.Plugin( ... )

local Options = {
	Base = "hiveteamrestriction",
	BlacklistKeys = {
		BuildBlockMessage = true
	}
}

return Plugin, Options