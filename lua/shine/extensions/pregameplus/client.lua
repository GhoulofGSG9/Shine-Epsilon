local Plugin = Plugin
local Shine = Shine

--Hooks
do
	local SetupGlobalHook = Shine.Hook.SetupGlobalHook

	SetupGlobalHook( "PlayerUI_GetPlayerResources", "PlayerUI_GetPlayerResources", "ActivePre" )
	SetupGlobalHook( "PlayerUI_GetWeaponLevel", "PlayerUI_GetWeaponLevel", "ActivePre" )
	SetupGlobalHook( "PlayerUI_GetArmorLevel", "PlayerUI_GetArmorLevel", "ActivePre" )
end

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:PlayerUI_GetPlayerResources()
	if self.dt.Enabled then
		return 100
	end
end

function Plugin:PlayerUI_GetWeaponLevel()
	if self.dt.Enabled then
		return self.dt.WeaponLevel
	end
end

function Plugin:PlayerUI_GetArmorLevel()
	if self.dt.Enabled then
		return self.dt.ArmorLevel
	end
end

function Plugin:ShowStatus( NewStatus )
	if NewStatus then
		if not self.Status then
			self.Status = Shine:AddMessageToQueue( 70, self.dt.StatusX, self.dt.StatusY, self.dt.StatusText, 1,
				self.dt.StatusR, self.dt.StatusG, self.dt.StatusB, 0, 1,0 )
			self.Status.UpdateText = function(TextObject)
				if self.dt.Countdown then
					local Text = string.gsub( TextObject.Text, "<t>",
						string.TimeToString( TextObject.Duration ) )
					TextObject.Obj:SetText( Text )
				end

				if TextObject.Duration == 0 then
					TextObject.Duration = 1
				end
			end
		else
			self.Status.Obj:SetIsVisible(true)
		end
	elseif self.Status then
		self.Status.Obj:SetIsVisible(false)
	end
end

function Plugin:UpdateStatusText( NewText )
	if not self.Status then
		self:ShowStatus(true)
	end

	self.Status.Text = NewText
	if not self.dt.Countdown then
		self.Status.Obj:SetText( NewText )
	end
end

function Plugin:UpdateStatusCountdown( NewStatus )
	if NewStatus then
		self.Status.Duration = self.dt.StatusDelay
	end
end

function Plugin:Cleanup()
	Shine:RemoveMessage(70)

	self.BaseClass.Cleanup( self )

	self.Enabled = false
end