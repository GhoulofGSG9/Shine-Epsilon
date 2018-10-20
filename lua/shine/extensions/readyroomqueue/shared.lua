local Plugin = {}
Plugin.NotifyPrefixColour = {
    255, 160, 0
}

function Plugin:SetupDataTable()
    local MessageTypes = {
        QueueChanged = {
            Position = "integer"
        },
        MapCycle = {
            TimeLeft = "integer"
        }
    }

    self:AddTranslatedNotify( "UNSTICKING", MessageTypes.TimeLeft )
end

Shine:RegisterExtension( "readyroomqueue", Plugin )