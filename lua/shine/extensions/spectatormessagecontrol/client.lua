local Plugin = Plugin
local Shine = Shine

Plugin.Buttons = {}

function Plugin:Initialise()
	self.Enabled = true
	return true
end

local TeamNames =
{
	"Ready Room",
	"Marines",
	"Aliens",
	"Spectators"
}

function Plugin:CreateButtonSet( Page, Command, Field, Enabled, Disabled, StartStates)
	for i, teamname in ipairs(TeamNames) do
		local entryId = self.FieldToMenuOffset[Field] + i
		local button = self.Buttons[entryId]

		local Enabled = string.format(Enabled, teamname)
		local Disabled = string.format(Disabled, teamname)

		local state = button and button.State or StartStates[i]
		local Start = state and Enabled or Disabled

		local function DoClick(Button)
			Print(string.format("%s %s %s", Button.Command, Button.Team, not Button.State))

			Shared.ConsoleCommand(string.format("%s %s %s", Button.Command, Button.Team, not Button.State))
			return true
		end

		self.Buttons[entryId] = Page:AddSideButton( Start, DoClick )
		self.Buttons[entryId].Command = Command
		self.Buttons[entryId].Team = i - 1
		self.Buttons[entryId].EnabledMsg = Enabled
		self.Buttons[entryId].DisabledMsg = Disabled
		self.Buttons[entryId].State = StartStates

	end
end

function Plugin:UpdateMenuEntry( NewValue )
	if not self.MenuEntry then
		Shine.VoteMenu:AddPage( "Spectator Voice", function( Page )
			local StartStates = {
				false,
				false,
				false,
				true
			}
			self:CreateButtonSet(Page, "sh_spec_receive_voice", "Listen", "Receiving %s", "Not receiving %s", StartStates)
			self:CreateButtonSet(Page, "sh_spec_send_voice", "Speak", "Sending to %s", "Not sending to %s", StartStates)

			Page:AddBottomButton( "Back", function()
				Page:SetPage( "Spectator Control" )
			end )
		end )

		Shine.VoteMenu:AddPage( "Spectator Chat", function( Page )

			local StartStates = {
				false,
				false,
				false,
				true
			}
			self:CreateButtonSet(Page, "sh_spec_receive_chat", "Receive", "Receiving %s", "Not receiving %s", StartStates)
			self:CreateButtonSet(Page, "sh_spec_send_chat", "Send", "Sending to %s", "Not sending to %s", StartStates)

			Page:AddBottomButton( "Back", function()
				Page:SetPage( "Spectator Control" )
			end )
		end )

		Shine.VoteMenu:AddPage( "Spectator Control", function( Page )
			Page:AddSideButton( "Voice Control", function()
				Page:SetPage( "Spectator Voice" )
			end )
			Page:AddSideButton( "Chat Control", function()
				Page:SetPage( "Spectator Chat" )
			end )

			Page:AddBottomButton( "Back", function()
				Page:SetPage( "Main" )
			end )
		end )

		Shine.VoteMenu:EditPage( "Main", function( Page )
			self.MenuEntry = Page:AddSideButton( "Spectator Control", function()
				Page:SetPage( "Spectator Control" )
			end )

			self.MenuEntry:SetIsVisible( NewValue )
		end )
	else
		self.MenuEntry:SetIsVisible( NewValue )
	end
end

function Plugin:ReceiveMenu(Message)
	PrintTable(Message)
	self:UpdateMenuEntry(Message.add)
end

function Plugin:ReceiveMenuUpdate(Message)
	PrintTable(Message)
	local Button = self.Buttons[Message.id]

	if not Button then return end

	local newText = Message.enabled and Button.EnabledMsg or Button.DisabledMsg
	Button.State = Message.enabled
	Button:SetText(newText)
end

function Plugin:Cleanup()
	self:UpdateMenuEntry( false )

	self.BaseClass.Cleanup( self )
	self.Enabled = false
end

