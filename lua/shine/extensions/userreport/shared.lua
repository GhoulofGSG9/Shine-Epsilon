--[[
    Shine User Report - Shared
]]
local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"

Plugin.NotifyPrefixColour = {
    255, 50, 50
}

Plugin.DeleteCommand = "sh_deletereport"

-- Order matters: a reason's position is its bit in the networked Reasons mask.
Plugin.Reasons = {
    "OFFENSIVE_LANGUAGE",
    "VERBAL_ABUSE",
    "GRIEFING",
    "SPAMMING",
    "NEGATIVE_ATTITUDE",
    "INAPPROPRIATE_NAME",
    "UNSKILLED",
    "STACKING",
    "SMURFING",
    "CHEATING"
}

Plugin.SortColumn = table.AsEnum( {
    "DATE", "TARGET", "REASONS", "REPORTER"
}, function( Index ) return Index end )

local Band = bit.band
local Bor = bit.bor
local LShift = bit.lshift

Plugin.ReasonBits = {}
for i = 1, #Plugin.Reasons do
    Plugin.ReasonBits[ Plugin.Reasons[ i ] ] = LShift( 1, i - 1 )
end

function Plugin:ReasonsToMask( Reasons )
    local Mask = 0
    for i = 1, #Reasons do
        Mask = Bor( Mask, self.ReasonBits[ Reasons[ i ] ] or 0 )
    end
    return Mask
end

function Plugin:MaskToReasons( Mask )
    local Reasons = {}
    for i = 1, #self.Reasons do
        local Reason = self.Reasons[ i ]
        if Band( Mask, self.ReasonBits[ Reason ] ) ~= 0 then
            Reasons[ #Reasons + 1 ] = Reason
        end
    end
    return Reasons
end

function Plugin:SetupDataTable()
    local NameField = self:GetNameNetworkField()

    self:AddNetworkMessage( "Report", {
        TargetID = "string (32)",
        Reasons = "integer",
        Details = "string (255)"
    }, "Server" )

    self:AddNetworkMessage( "RequestReportPage", {
        Page = "integer",
        MaxResults = "integer",
        Filter = "string (128)",
        SortColumn = "integer (1 to 4)",
        SortAscending = "boolean"
    }, "Server" )

    self:AddNetworkMessage( "ReportPage", {
        Page = "integer",
        NumPages = "integer",
        MaxResults = "integer",
        TotalNumResults = "integer"
    }, "Client" )

    self:AddNetworkMessage( "ReportData", {
        ID = "integer",
        Date = "integer",
        TargetID = "string (32)",
        TargetName = NameField,
        SharerID = "string (32)",
        ReporterID = "string (32)",
        ReporterName = NameField,
        Reasons = "integer",
        Details = "string (255)"
    }, "Client" )

    self:AddNetworkMessage( "ReportDataChanged", {}, "Client" )

    self:AddTranslatedNotify( "NEW_REPORT", {
        ReporterName = NameField,
        TargetName = NameField
    } )
end

return Plugin
