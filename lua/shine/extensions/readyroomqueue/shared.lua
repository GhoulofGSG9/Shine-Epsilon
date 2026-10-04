local StringFormat = string.format

local Plugin = Shine.Plugin(...)

Plugin.Version = "1.2"

Plugin.NotifyPrefixColour = {
    255, 160, 0
}

-- Largest string size Shine and vanilla use for a network variable.
Plugin.MaxQueueOrderLength = 255

function Plugin:SetupDataTable()
    -- Client IDs of the player queue in queue order, "-" for an entry whose client is not connected.
    self:AddDTVar( StringFormat( "string (%d)", Plugin.MaxQueueOrderLength ), "QueueOrder", "" )

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

    -- An empty URL switches the global seed queue off for that client.
    self:AddNetworkMessage( "SeedActive", { URL = "string (255)" }, "Client" )
    self:AddNetworkMessage( "SeedOffer", {
        Name = "string (128)", Address = "string (64)", Count = "integer", Time = "integer"
    }, "Client" )
    -- Reason: committed (being sent to the seed), declined (it goes ahead without them) or aborted.
    self:AddNetworkMessage( "SeedClosed", { Reason = "string (16)" }, "Client" )

    -- Version is the candidate list's version, a new one replaces the scores of the old list.
    self:AddNetworkMessage( "SeedScore", { Address = "string (64)", Score = "float", Version = "string (32)" },
        "Server" )
    self:AddNetworkMessage( "SeedAnswer", { Accept = "boolean" }, "Server" )
    self:AddNetworkMessage( "SeedPref", { Pref = "string (8)" }, "Server" )
end

return Plugin
