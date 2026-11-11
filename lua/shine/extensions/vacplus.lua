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
    MinAccountAgeInDays = 0,
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

-- Steam hands out account IDs in runs, so an ID roughly dates its account. Each entry is
-- { account ID, creation date }, sampled from public profiles on 2026-11-11, and IDs in between
-- are interpolated. IDs Steam has not handed out carry a date in the future, which reads as
-- created now. Accounts from 2018 to 2024 are sampled coarsely and can be two months off.
-- Accounts younger than a year could not be sampled at all, so they can be further off.
-- The entry after 495M projects the current run, which counts down from 835M at 13M IDs a
-- month: resample when that drifts, or when Steam starts a new run.
local AccountCreationDates = {
    { 100000, "2003-09-12" },
    { 1000009, "2003-09-22" },
    { 5000003, "2004-03-25" },
    { 10000017, "2004-11-12" },
    { 25000003, "2006-10-03" },
    { 50000001, "2009-05-24" },
    { 75000002, "2010-12-19" },
    { 100000001, "2012-03-13" },
    { 125000000, "2013-03-01" },
    { 150000000, "2013-10-08" },
    { 175000000, "2014-04-30" },
    { 200000000, "2014-09-11" },
    { 225000001, "2015-03-14" },
    { 275000000, "2015-06-22" },
    { 300000000, "2015-11-13" },
    { 325000006, "2016-02-20" },
    { 350000001, "2016-06-10" },
    { 375000002, "2016-10-01" },
    { 400000001, "2017-01-17" },
    { 425000000, "2017-05-04" },
    { 450000000, "2017-08-02" },
    { 475000000, "2017-10-17" },
    { 487500002, "2017-11-22" },
    { 495020000, "2017-12-14" },
    { 495020001, "2027-10-24" },
    { 643210000, "2026-11-11" },
    { 800000006, "2025-12-16" },
    { 812500000, "2025-10-30" },
    { 818750003, "2025-10-13" },
    { 825000001, "2025-09-24" },
    { 831250000, "2025-08-29" },
    { 834375000, "2025-08-20" },
    { 834769999, "2025-08-19" },
    { 834770000, "2017-12-11" },
    { 835156252, "2017-12-12" },
    { 835937503, "2017-12-15" },
    { 837500001, "2017-12-21" },
    { 850000004, "2018-01-30" },
    { 900000001, "2018-09-15" },
    { 975000038, "2019-03-15" },
    { 1000000000, "2019-04-28" },
    { 1050000003, "2019-12-14" },
    { 1125000000, "2020-08-23" },
    { 1200000002, "2021-04-10" },
    { 1275000004, "2022-01-16" },
    { 1350000003, "2022-06-02" },
    { 1425000004, "2022-08-17" },
    { 1500000027, "2022-12-26" },
    { 1575000001, "2023-08-04" },
    { 1650000001, "2024-01-13" },
    { 1725000005, "2024-05-09" },
    { 1775000012, "2024-07-07" },
    { 1787500003, "2024-07-23" },
    { 1800000022, "2024-08-17" },
    { 1812500010, "2024-09-07" },
    { 1818750005, "2024-09-14" },
    { 1825000006, "2024-09-28" },
    { 1837500006, "2024-10-27" },
    { 1850000011, "2024-12-22" },
    { 1862500003, "2025-02-01" },
    { 1875000004, "2025-03-15" },
    { 1881250000, "2025-04-01" },
    { 1887500001, "2025-04-15" },
    { 1900000003, "2025-05-26" },
    { 1906250004, "2025-06-15" },
    { 1912500005, "2025-07-02" },
    { 1925000001, "2025-08-05" },
    { 1933090000, "2025-08-27" },
    { 1933090001, "2099-01-01" },
    { 4294967295, "2099-01-01" },
}

local AccountCreationTimes = {}
for i = 1, #AccountCreationDates do
    local Year, Month, Day = string.match( AccountCreationDates[ i ][ 2 ], "(%d+)-(%d+)-(%d+)" )
    AccountCreationTimes[ i ] = {
        AccountCreationDates[ i ][ 1 ],
        os.time( { year = Year, month = Month, day = Day, hour = 12 } )
    }
end

function Plugin:GetAccountAgeInDays( ID )
    local Times = AccountCreationTimes
    local Index = 2
    while Index < #Times and Times[ Index ][ 1 ] < ID do
        Index = Index + 1
    end

    local From, To = Times[ Index - 1 ], Times[ Index ]
    local Created = From[ 2 ] + ( ID - From[ 1 ] ) * ( To[ 2 ] - From[ 2 ] ) / ( To[ 1 ] - From[ 1 ] )

    return math.max( os.time() - math.max( Created, Times[ 1 ][ 2 ] ), 0 ) / 86400
end

function Plugin:CheckConnectionAllowed( ID )
    local MinAge = self.Config.MinAccountAgeInDays
    if MinAge <= 0 or Shine:HasAccess( ID, "sh_ignorevacbans" ) then return end

    local Age = self:GetAccountAgeInDays( ID )
    if Age < MinAge then
        self:Print( "Rejected %s as their Steam account is about %d days old.", true, ID, Age )
        return false, string.format( "Your Steam account has to be at least %d days old to play on this server.", MinAge )
    end
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