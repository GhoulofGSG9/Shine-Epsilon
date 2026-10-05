local Plugin = Shine.Plugin(...)

Plugin.Version = "1.1"

Plugin.NotifyPrefixColour = {
    255, 160, 0
}

function Plugin:SetupDataTable()
    local MessageTypes = {
        QueuePosition = {
            Position = "integer"
        },
        Time = {
            Time = "integer"
        }
    }

    self:AddNetworkMessages( "AddTranslatedNotify", {
        [ MessageTypes.QueuePosition ] = {
            "QUEUE_CHANGED", "PRIORITY_QUEUE_CHANGED", "QUEUE_ADDED", "PRIORITY_QUEUE_ADDED",
            "QUEUE_POSITION", "PRIORITY_QUEUE_POSITION", "QUEUE_INFORM", "QUEUE_WELCOME_BACK",
            "QUEUE_CHANGED_VIP", "PRIORITY_QUEUE_CHANGED_VIP",
        },
        [ MessageTypes.Time ] = {
            "RR_GRACE_WARNING", "QUEUE_WAITTIME"
        }
    } )

    self:AddNetworkMessage( "QueueLeft", {}, "Client")
end

return Plugin
