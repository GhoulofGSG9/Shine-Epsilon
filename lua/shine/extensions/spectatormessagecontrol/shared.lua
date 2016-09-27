local Plugin = {}

Plugin.FieldToMenuOffset = {
	Listen = 0,
	Speak = 4,
	Receive = 8,
	Send = 12
}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "Menu", { add = "boolean" }, "Client" )
	self:AddNetworkMessage( "MenuUpdate", { button = "integer", enabled = "boolean" }, "Client" )
end

Shine:RegisterExtension("spectatormessagecontrol", Plugin)