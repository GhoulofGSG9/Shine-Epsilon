--[[
	Shine NS2News plugin.
]]

local Plugin = Plugin
local Shine = Shine

function Plugin:UpdateMenuEntry( NewValue )
	if not self.MenuEntry then
		Shine.VoteMenu:EditPage( "Main", function( Menu )
			self.MenuEntry = Menu:AddSideButton( "News", function()
				Menu.GenericClick( "sh_news" )
			end )
		end )
	end

	self.MenuEntry:SetIsVisible( NewValue )
end

function Plugin:Cleanup()
	self:UpdateMenuEntry( false )

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end


