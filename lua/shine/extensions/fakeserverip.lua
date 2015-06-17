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
	Print(IPAddressToString(Server.GetIpAddress()))

	if self.Config.FakeIP == "127.0.0.1" then
		return false, "Please setup the FakeSeverIp plugin correctly before using it!"
	end

	self.Enabled = true
	return true
end

local oldIPAddressToString = IPAddressToString
local serverip = Server.GetIpAddress()

function IPAddressToString(address)
	if address == serverip then
		return Plugin.Config.FakeIP
	else
		return oldIPAddressToString(address)
	end
end

function Plugin:CleanUp()
	self.BaseClass.CleanUp()
	self.Enabled = false
end

Shine:RegisterExtension( "fakeserverip", Plugin )

