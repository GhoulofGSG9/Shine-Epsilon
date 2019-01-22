local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "FakeServerIp.json"
Plugin.DefaultConfig =
{
	FakeIP = "127.0.0.1",
}
Plugin.CheckConfig = true

function Plugin:Initialise()
	if self.Config.FakeIP == "127.0.0.1" then
		return false, "Please setup the FakeSeverIp plugin correctly before using it!"
	end

	self.Enabled = true
	return true
end

function Plugin:OnFirstThink()
	Shine.Hook.SetupClassHook("Server", "GetIpAddress", "OnIPAddressToString", "ActivePre")
end

function Plugin:OnIPAddressToString()
	return self.Config.FakeIP
end

return Plugin

