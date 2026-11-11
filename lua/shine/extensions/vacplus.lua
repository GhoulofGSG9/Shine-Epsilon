local InfoHub = Shine.PlayerInfoHub

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.HasConfig = true

Plugin.ConfigName = "VACPlus.json"
Plugin.DefaultConfig =
{
    CheckVACBans = true,
    CheckCommunityBans = true,
    CheckEconomyBans = true,
    CheckENSLGatherBans = false,
    CheckENSLMutes = false,
    CheckENSLBans = false,
    AutoBan = true,
    BanTime = 60,
    MaxDaysSinceLastSteamBan = 180,
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
    self.Enabled = true

    if self.Config.CheckVACBans or self.Config.CheckCommunityBans or self.Config.CheckEconomyBans then
        InfoHub:Request( "VAC+", "STEAMBANS")
    end

    if self.Config.CheckENSLGatherBans or self.Config.CheckENSLMutes or self.Config.CheckENSLBans then
	    InfoHub:Request( "VAC+", "ENSL")
    end

    return true
end

function Plugin:GetSteamBanType( Bans )
    if type(Bans) ~= "table" then return nil end

    if Bans.CommunityBanned and self.Config.CheckCommunityBans then
        return 2
    end

    if Bans.EconomyBan == "banned" and self.Config.CheckEconomyBans then
        return 3
    end

    -- Steam only counts VAC and game bans in DaysSinceLastBan, so the age limit only applies to those.
    local MaxDays = self.Config.MaxDaysSinceLastSteamBan
    if Bans.VACBanned and self.Config.CheckVACBans and (MaxDays <= 0 or (Bans.DaysSinceLastBan or 0) <= MaxDays) then
        return 1
    end

    return nil
end

function Plugin:OnReceiveSteamData( Client, Data )
    if Shine:HasAccess( Client, "sh_ignorevacbans" ) then return end

    local BanType = self:GetSteamBanType( Data.Bans )
    if BanType then
        self:Kick( Client, BanType )
        return
    end

    -- Engine builds 345 and later report the account a family shared copy is borrowed from.
    local Owner = Server.GetOwnerUserId and Server.GetOwnerUserId( Client ) or 0
    local ExternalAPIHandler = Shine.ExternalAPIHandler
    if Owner == 0 or Owner == Client:GetUserId() or not ExternalAPIHandler or not ExternalAPIHandler:HasAPIKey( "Steam" ) then
        return
    end

    local function OnFailure() end
    ExternalAPIHandler:PerformRequest( "Steam", "GetPlayerBansByNS2ID", { steamids = Owner }, {
        OnSuccess = function( Bans )
            local OwnerBanType = self:GetSteamBanType( Bans )
            if OwnerBanType and self.Enabled and Shine:IsValidClient( Client ) then
                self:Kick( Client, OwnerBanType, true )
            end
        end,
        OnFailure = OnFailure,
        OnTimeout = OnFailure
    }, 2 )
end

function Plugin:OnReceiveENSLData( Client, Data )
    if Shine:HasAccess( Client, "sh_ignorevacbans" ) then return end

    if type(Data) ~= "table" or not Data.bans then
        return
    end

    if Data.bans.gather and self.Config.CheckENSLGatherBans then
        self:Kick( Client, 4 )
    end

    if Data.bans.mute and self.Config.CheckENSLMutes then
        self:Kick( Client, 5 )
    end

    if Data.bans.site and self.Config.CheckENSLBans then
        self:Kick( Client, 6 )
    end
end

local BanTypes = {
    "VAC banned", "Steam Community banned", "Steam Economy banned",
	"ENSl Gather banned", "ENSL muted", "ENSL banned"
}

function Plugin:Kick( Client, BanType, IsOwner )
	local time = (BanType ~= 1 or self.Config.MaxDaysSinceLastSteamBan <= 0) and "" or string.format("less than %s days ago", self.Config.MaxDaysSinceLastSteamBan)
    local reason = string.format("The %s has been %s %s", IsOwner and "account sharing the game with the given user" or "given user", BanTypes[BanType],time)

    if self.Config.AutoBan then
        Shared.ConsoleCommand( string.format("sh_ban %s %s %s",Client:GetUserId(), self.Config.BanTime, reason ))
    else
        Shared.ConsoleCommand( string.format("sh_kick %s %s",Client:GetUserId(), reason ))
    end
end

function Plugin:Cleanup()
    InfoHub:RemoveRequest( "VAC+" )

    self.BaseClass.Cleanup( self )

    self.Enabled = false
end

return Plugin