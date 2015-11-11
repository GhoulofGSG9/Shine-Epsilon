local Plugin = {}
local Shine = Shine

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

Shine.Hook.SetupGlobalHook("IPAddressToString", "OnIPAddressToString", "ActivePre")

local serverip = Server.GetIpAddress()
function Plugin:OnIPAddressToString(address)
	if address == serverip then
		return self.Config.FakeIP
	end
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

Shine:RegisterExtension( "fakeserverip", Plugin )

