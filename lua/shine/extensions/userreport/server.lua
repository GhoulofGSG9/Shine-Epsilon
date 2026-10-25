--[[
    Shine User Report - Server
]]
local Band = bit.band
local Ceil = math.ceil
local Clamp = math.Clamp
local Max = math.max
local OSTime = os.time
local SharedTime = Shared.GetTime
local StringFind = string.find
local StringUTF8Lower = string.UTF8Lower
local TableConcat = table.concat
local TableRemove = table.remove
local TableSort = table.sort
local tonumber = tonumber
local tostring = tostring

local Plugin = ...
Plugin.PrintName = "User Report"

Plugin.HasConfig = true

Plugin.ConfigName = "UserReport.json"
Plugin.DefaultConfig = {
    ReportCooldown = 30, -- seconds a player has to wait between two reports
    AutoReact = {
        -- MinReporters is the number of different players that have to report someone for a matching reason.
        Gag = {
            Enabled = true,
            MinReporters = 3,
            Duration = 0 -- seconds (max. 1800), 0 gags for the rest of the map
        },
        Rename = {
            Enabled = true,
            MinReporters = 3
        },
        Kick = {
            Enabled = false,
            MinReporters = 5
        }
    }
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = true

Plugin.ReportsFile = "config://shine/UserReports.json"

-- Viewing reports and getting notified about them requires the same access as deleting them.
Plugin.ListPermission = Plugin.DeleteCommand
Plugin.ImmunityPermission = "sh_userreport_immune"

Plugin.MaxResultsPerPage = 30

-- Applied in this order, so the kick comes last.
Plugin.AutoReactions = {
    {
        Name = "Gag",
        Reasons = { "OFFENSIVE_LANGUAGE", "VERBAL_ABUSE", "SPAMMING", "NEGATIVE_ATTITUDE" },
        Apply = function( self, Target, Settings )
            Shine:RunCommand( nil, "sh_gag", false, tostring( Target:GetUserId() ), tostring( Settings.Duration ) )
        end
    },
    {
        Name = "Rename",
        Reasons = { "INAPPROPRIATE_NAME" },
        Apply = function( self, Target )
            local Player = Target:GetControllingPlayer()
            if not Player then return end

            local SteamID = Target:GetUserId()
            local Name = "NSPlayer"..SteamID

            Shine:AdminPrint( nil, "%s was renamed to '%s' after being reported for an inappropriate name.", true,
                Shine.GetClientInfo( Target ), Name )

            self.ForcedNames[ SteamID ] = Name
            Player:SetName( Name )
        end
    },
    {
        Name = "Kick",
        Reasons = { "CHEATING" },
        Apply = function( self, Target )
            Shine:AdminPrint( nil, "%s was kicked after being reported for cheating.", true,
                Shine.GetClientInfo( Target ) )

            Shine:DisconnectClient( Target, "Kicked after being reported for cheating by multiple players." )
        end
    }
}

function Plugin:Initialise()
    local Data = Shine.LoadJSONFile( self.ReportsFile )
    if Data == nil then
        return false, "Unable to parse "..self.ReportsFile..", fix or remove it to enable this plugin."
    end

    self.Reports = Data and Data.Reports or {}
    self.NextID = Data and Data.NextID or #self.Reports + 1

    -- Everything below only lives for the current map.
    self.LastReportTime = {}
    -- TargetID -> ReporterID -> Reasons mask
    self.ReportsByTarget = {}
    -- TargetID -> auto reaction name -> true
    self.Reacted = {}
    self.ForcedNames = {}

    self:CreateCommands()

    self.Enabled = true

    return true
end

function Plugin:SaveReports()
    Shine.SaveJSONFile( { NextID = self.NextID, Reports = self.Reports }, self.ReportsFile )
end

function Plugin:NotifyReportDataChanged()
    local Clients = Shine:GetClientsWithAccess( self.ListPermission )
    if #Clients > 0 then
        self:SendNetworkMessage( Clients, "ReportDataChanged", {}, true )
    end
end

--[[
    Returns the NS2ID of the account the given player borrows the game from via family sharing.
    If that is not known yet, OnAsyncResponse is called with it once Steam answers.
]]
function Plugin:GetFamilySharer( ID, OnAsyncResponse )
    local Params = { steamid = ID }

    local Sharer = Shine.ExternalAPIHandler:GetCachedValue( "Steam", "IsPlayingSharedGame", Params )
    if Sharer ~= nil then return Sharer or nil end

    if not Shine.ExternalAPIHandler:HasAPIKey( "Steam" ) then return nil end

    Shine.ExternalAPIHandler:PerformRequest( "Steam", "IsPlayingSharedGame", Params, {
        OnSuccess = self:WrapCallback( function( Sharer )
            if Sharer then
                OnAsyncResponse( Sharer )
            end
        end )
    } )

    return nil
end

function Plugin:ReceiveReport( Client, Data )
    local Reasons = self:MaskToReasons( Data.Reasons )
    if #Reasons == 0 then return end

    local TargetID = tonumber( Data.TargetID )
    local Target = TargetID and Shine.GetClientByNS2ID( TargetID )
    if not Target or Target == Client or Target:GetIsVirtual() then
        self:NotifyTranslatedError( Client, "ERROR_INVALID_TARGET" )
        return
    end

    local ReporterID = Client:GetUserId()
    local TargetReports = self.ReportsByTarget[ TargetID ] or {}
    if TargetReports[ ReporterID ] then
        self:NotifyTranslatedError( Client, "ERROR_ALREADY_REPORTED" )
        return
    end

    local Now = SharedTime()
    local LastReportTime = self.LastReportTime[ ReporterID ]
    if LastReportTime and Now - LastReportTime < self.Config.ReportCooldown then
        self:NotifyTranslatedError( Client, "ERROR_REPORT_COOLDOWN" )
        return
    end

    self.LastReportTime[ ReporterID ] = Now
    TargetReports[ ReporterID ] = self:ReasonsToMask( Reasons )
    self.ReportsByTarget[ TargetID ] = TargetReports

    local Report = {
        ID = self.NextID,
        Date = OSTime(),
        TargetID = TargetID,
        TargetName = Shine.GetClientName( Target ),
        ReporterID = ReporterID,
        ReporterName = Shine.GetClientName( Client ),
        Reasons = Reasons,
        Details = Data.Details
    }
    Report.SharerID = self:GetFamilySharer( TargetID, function( SharerID )
        Report.SharerID = SharerID
        self:SaveReports()
    end )

    self.NextID = self.NextID + 1
    self.Reports[ #self.Reports + 1 ] = Report
    self:SaveReports()

    self:Print( "%s reported %s for %s: %s", true, Shine.GetClientInfo( Client ), Shine.GetClientInfo( Target ),
        TableConcat( Reasons, ", " ), Report.Details )

    self:NotifyTranslated( Client, "REPORT_SENT" )

    local Admins = Shine:GetClientsWithAccess( self.ListPermission )
    if #Admins > 0 then
        self:SendTranslatedNotify( Admins, "NEW_REPORT", {
            ReporterName = Report.ReporterName,
            TargetName = Report.TargetName
        } )
        self:SendNetworkMessage( Admins, "ReportDataChanged", {}, true )
    end

    self:AutoReact( Target, TargetReports )
end

function Plugin:AutoReact( Target, TargetReports )
    if Shine:HasAccess( Target, self.ImmunityPermission ) then return end

    local TargetID = Target:GetUserId()
    local Reacted = self.Reacted[ TargetID ] or {}
    self.Reacted[ TargetID ] = Reacted

    for i = 1, #self.AutoReactions do
        local Reaction = self.AutoReactions[ i ]
        local Settings = self.Config.AutoReact[ Reaction.Name ]

        if Settings.Enabled and not Reacted[ Reaction.Name ] then
            local Mask = self:ReasonsToMask( Reaction.Reasons )
            local NumReporters = 0
            for _, Reasons in pairs( TargetReports ) do
                if Band( Reasons, Mask ) ~= 0 then
                    NumReporters = NumReporters + 1
                end
            end

            if NumReporters >= Settings.MinReporters then
                Reacted[ Reaction.Name ] = true
                Reaction.Apply( self, Target, Settings )
            end
        end
    end
end

function Plugin:CheckPlayerName( Player, Name, OldName )
    local Client = Player:GetClient()
    return Client and self.ForcedNames[ Client:GetUserId() ]
end

local function MatchesFilter( Report, Filter )
    return StringFind( StringUTF8Lower( Report.TargetName ), Filter, 1, true )
        or StringFind( StringUTF8Lower( Report.ReporterName ), Filter, 1, true )
        or StringFind( tostring( Report.TargetID ), Filter, 1, true )
        or StringFind( tostring( Report.ReporterID ), Filter, 1, true )
end

Plugin.SortKeys = {
    [ Plugin.SortColumn.DATE ] = function( self, Report ) return Report.ID end,
    [ Plugin.SortColumn.TARGET ] = function( self, Report ) return StringUTF8Lower( Report.TargetName ) end,
    [ Plugin.SortColumn.REASONS ] = function( self, Report ) return self:ReasonsToMask( Report.Reasons ) end,
    [ Plugin.SortColumn.REPORTER ] = function( self, Report ) return StringUTF8Lower( Report.ReporterName ) end
}

function Plugin:ReceiveRequestReportPage( Client, PageRequest )
    if not Shine:GetPermission( Client, self.ListPermission ) then return end

    local Filter = StringUTF8Lower( PageRequest.Filter )

    local Results = {}
    for i = 1, #self.Reports do
        local Report = self.Reports[ i ]
        if Filter == "" or MatchesFilter( Report, Filter ) then
            Results[ #Results + 1 ] = Report
        end
    end

    local GetSortKey = self.SortKeys[ PageRequest.SortColumn ]
    local Ascending = PageRequest.SortAscending
    TableSort( Results, function( A, B )
        local KeyA, KeyB = GetSortKey( self, A ), GetSortKey( self, B )
        if KeyA == KeyB then
            KeyA, KeyB = A.ID, B.ID
        end

        if Ascending then
            return KeyA < KeyB
        end
        return KeyA > KeyB
    end )

    local MaxResults = Clamp( PageRequest.MaxResults, 5, self.MaxResultsPerPage )
    local NumPages = Max( 1, Ceil( #Results / MaxResults ) )
    local Page = Clamp( PageRequest.Page, 1, NumPages )

    self:SendNetworkMessage( Client, "ReportPage", {
        Page = Page,
        NumPages = NumPages,
        MaxResults = MaxResults,
        TotalNumResults = #Results
    }, true )

    for i = ( Page - 1 ) * MaxResults + 1, Page * MaxResults do
        local Report = Results[ i ]
        if not Report then break end

        self:SendNetworkMessage( Client, "ReportData", {
            ID = Report.ID,
            Date = Report.Date,
            TargetID = tostring( Report.TargetID ),
            TargetName = Report.TargetName,
            SharerID = Report.SharerID and tostring( Report.SharerID ) or "",
            ReporterID = tostring( Report.ReporterID ),
            ReporterName = Report.ReporterName,
            Reasons = self:ReasonsToMask( Report.Reasons ),
            Details = Report.Details
        }, true )
    end
end

function Plugin:CreateCommands()
    local function DeleteReport( Client, ID )
        for i = 1, #self.Reports do
            if self.Reports[ i ].ID == ID then
                TableRemove( self.Reports, i )
                self:SaveReports()
                self:NotifyReportDataChanged()
                return
            end
        end

        Shine:NotifyCommandError( Client, "There is no report with ID %d.", true, ID )
    end
    local DeleteCommand = self:BindCommand( self.DeleteCommand, nil, DeleteReport )
    DeleteCommand:AddParam{ Type = "number", Round = true, Min = 1, Help = "report ID" }
    DeleteCommand:Help( "Deletes the user report with the given ID." )
end
