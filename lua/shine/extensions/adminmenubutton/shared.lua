-- Shine adminmenubutton

local Shine = Shine
local Plugin = {}

Plugin.Version = "1.0"
Plugin.HasConfig = false

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "AdminMenu", {}, "Client" )
end

Shine:RegisterExtension( "adminmenubutton", Plugin )

if Server then
	function Plugin:Initialise()
		self.Enabled = true
		for _, Client in ipairs( Shine.GetAllClients() ) do
			self:ClientConfirmConnect( Client )
		end
		return true
	end
	
	function Plugin:ClientConfirmConnect( Client )
		if Shine:HasAccess( Client, "sh_adminmenu" ) then
			self:SendNetworkMessage( Client, "AdminMenu", {}, true )
		end
	end
end

if Client then
	function Plugin:ReceiveAdminMenu()
		Shine.VoteMenu:EditPage( "Main", function( self )
			self:AddSideButton( "Admin Menu", function()
				Shared.ConsoleCommand("sh_adminmenu")
				self:SetIsVisible( false )
		end )
		end )
	end
end