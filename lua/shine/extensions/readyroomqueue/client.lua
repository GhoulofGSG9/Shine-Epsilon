local Plugin = ...

function Plugin:ReceiveQueueLeft()
    self:Notify( self:GetPhrase( "QUEUE_LEAVE" ) )

    Client.WindowNeedsAttention()
end