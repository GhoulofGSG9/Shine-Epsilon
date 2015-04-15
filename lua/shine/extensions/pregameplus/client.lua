local Plugin = Plugin
local Shine = Shine

function Plugin:ShowStatus( NewStatus )
	if NewStatus then
		Shine:AddMessageToQueue( 70, self.dt.StatusX, self.dt.StatusY, self.dt.StatusText, 1800,
			self.dt.StatusR, self.dt.StatusG, self.dt.StatusB, 0, 1,0 )
	else
		Shine:EndMessage( 70 )
	end
end

function Plugin:UpdateStatusText( NewText )
	local Message = {
		ID = 70,
		Message = NewText
	}

	Shine:UpdateMessageText( Message )
end
