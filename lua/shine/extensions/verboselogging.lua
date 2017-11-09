--[[
    A verbose logging plugin intended to track down certain issues
]]

local Shine = Shine
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VerboseLogging.json"
Plugin.DefaultConfig =
{
    LogSpecs = true,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Shine.Hook.SetupClassHook( "Player", "SetIsSpectator", "OnSetIsSpectator", "PassivePost")

function Plugin:Initialise()
    self.Enabled = true

    return true
end

function Plugin:OnSetIsSpectator( Player, IsSpec)
    if not self.Config.LogSpecs then return end
    if not Player then return end

    local Client = Player:GetClient()
    if not Client then return end

    if Client:GetIsSpectator() ~= IsSpec then
        Shine:LogString( StringFormat( "Client %s failed to switch to a %s slot.",
            Shine.GetClientInfo( Client ),
            IsSpec and "Spectator" or "Player"
        ) )

    else

        Shine:LogString( StringFormat( "Client %s is now using a %s slot.",
            Shine.GetClientInfo( Client ),
            IsSpec and "Spectator" or "Player"
        ) )

    end
end

function Plugin:ClientDisconnect( Client )
    if not self.Config.LogSpecs then return end

    if not Client then return end

    local isSpec = Client:GetIsSpectator()
    Shine:LogString( StringFormat( "%s %s disconnected.", isSpec and "Spectator" or "Player", Shine.GetClientInfo( Client ) ) )
end

function Plugin:PostJoinTeam( _, _, _, _, Force )
    if not self.Config.LogSpecs then return end

    local Clients = Shine.GetAllClients()
    local NumSpecs = Server.GetNumSpectators()
    local NumCheck = 0
    for i = 1, #Clients do
        local Client = Clients[i]
        local IsSpec = not Client:GetIsVirtual() and Client:GetIsSpectator()

        if IsSpec then
            NumCheck = NumCheck + 1
        end
    end

    if NumSpecs ~= NumCheck then
        Shine:LogString( StringFormat( "Warning: Spectator slots do not match spectator clients after team join%s.", Force and " using force" or "" ) )
    end
end



function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )
    self.Enabled = false
end

Shine:RegisterExtension( "verboselogging", Plugin )