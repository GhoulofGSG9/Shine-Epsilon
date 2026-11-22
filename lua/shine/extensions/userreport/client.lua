--[[
    Shine User Report - Client
]]
local Plugin = ...

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector
local Auto = Units.Auto

local Date = os.date
local Min = math.min
local StringFormat = string.format
local TableConcat = table.concat

function Plugin:Initialise()
    self:SetupAdminMenu()

    self.Enabled = true

    return true
end

function Plugin:OnFirstThink()
    -- Defensive check in case the scoreboard code changes.
    if not Scoreboard_GetPlayerData or not GUIScoreboard or not GUIScoreboard.SendKeyEvent then return end

    Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "OnGUIScoreboardSendKeyEvent", "PassivePost" )
end

function Plugin:OnGUIScoreboardSendKeyEvent( Scoreboard, Key, Down )
    local HoverMenu = Scoreboard.hoverMenu
    if not Scoreboard.visible or not HoverMenu or not HoverMenu.background
    or not HoverMenu.background:GetIsVisible() then
        return
    end

    local Buttons = HoverMenu.links
    if not Buttons then return end

    local ClientIndex = Scoreboard.hoverPlayerClientIndex
    local SteamID = GetSteamIdForClientIndex( ClientIndex ) or 0
    if SteamID == 0 or SteamID == Client.GetSteamId() then return end

    local BackgroundColour, HighlightColour, TextColour
    for i = #Buttons, 1, -1 do
        local Button = Buttons[ i ]
        if Button.IsUserReportButton then return end

        if not BackgroundColour and not Button.isSeparator then
            BackgroundColour = Button.bgColor
            HighlightColour = Button.bgHighlightColor
            TextColour = Button.link:GetColor()
        end
    end

    local Name = Scoreboard_GetPlayerData( ClientIndex, "Name" )

    HoverMenu:AddSeparator( "UserReport" )
    HoverMenu:AddButton( self:GetPhrase( "REPORT_PLAYER" ), BackgroundColour, HighlightColour, TextColour, function()
        self:OpenReportWindow( SteamID, Name )
    end )
    HoverMenu.links[ #HoverMenu.links ].IsUserReportButton = true

    HoverMenu:AdjustMenuSize()
end

function Plugin:OpenReportWindow( SteamID, Name )
    if SGUI.IsValid( self.ReportWindow ) then
        self.ReportWindow:Close()
    end

    local Font = {
        Family = "kAgencyFB",
        Size = HighResScaled( 27 )
    }

    local Modal = SGUI:Create( "Modal" )
    Modal.TitleBarHeight = HighResScaled( 28 )
    Modal:AddTitleBar( self:GetInterpolatedPhrase( "REPORT_TITLE", { TargetName = Name } ), Font )

    local Tree = {
        Parent = Modal,
        {
            Class = "Label",
            Props = {
                AutoFont = Font,
                Text = self:GetPhrase( "REASONS_LABEL" ),
                Margin = Spacing( 0, HighResScaled( 4 ), 0, HighResScaled( 5 ) )
            }
        }
    }

    Tree[ #Tree + 1 ] = {
        ID = "ReasonDropdown",
        Class = "Dropdown",
        Props = {
            AutoFont = Font,
            AutoSize = UnitVector( Percentage.ONE_HUNDRED, HighResScaled( 32 ) ),
            Text = self:GetPhrase( "SELECT_REASON" )
        }
    }

    Tree[ #Tree + 1 ] = {
        Class = "Label",
        Props = {
            AutoFont = Font,
            Text = self:GetPhrase( "DETAILS_LABEL" ),
            Margin = Spacing( 0, HighResScaled( 4 ), 0, HighResScaled( 5 ) )
        }
    }
    Tree[ #Tree + 1 ] = {
        ID = "DetailsEntry",
        Class = "TextEntry",
        Props = {
            AutoFont = Font,
            AutoSize = UnitVector( Percentage.ONE_HUNDRED, HighResScaled( 32 ) ),
            MaxLength = 255
        }
    }
    Tree[ #Tree + 1 ] = {
        ID = "SendButton",
        Class = "Button",
        Props = {
            AutoFont = Font,
            AutoSize = UnitVector( Units.Max( Auto.INSTANCE, HighResScaled( 128 ) ), HighResScaled( 32 ) ),
            CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
            StyleName = "DangerButton",
            Text = self:GetPhrase( "SEND_REPORT" ),
            Enabled = false,
            Margin = Spacing( 0, HighResScaled( 8 ), 0, 0 )
        }
    }

    local Elements = SGUI:BuildTree( Tree )

    local SendButton = Elements.SendButton
    local ReasonDropdown = Elements.ReasonDropdown

    local function OnReasonSelected()
        SendButton:SetEnabled( true )
    end

    local Options = {}
    for i = 1, #self.Reasons do
        local Reason = self.Reasons[ i ]
        Options[ i ] = {
            Text = self:GetPhrase( "REASON_"..Reason ),
            Tooltip = self:GetPhrase( "REASON_"..Reason.."_TIP" ),
            Value = Reason,
            DoClick = OnReasonSelected
        }
    end
    ReasonDropdown:SetOptions( Options )

    function SendButton.DoClick()
        self:SendNetworkMessage( "Report", {
            TargetID = tostring( SteamID ),
            Reasons = self.ReasonBits[ ReasonDropdown:GetSelectedOption().Value ],
            Details = Elements.DetailsEntry:GetText()
        }, true )

        Modal:Close()
    end

    Modal.Layout:SetPadding(
        Spacing( HighResScaled( 16 ), HighResScaled( 4 ), HighResScaled( 16 ), HighResScaled( 8 ) )
    )
    Modal:SetSize( Vector2( HighResScaled( 400 ):GetValue(), Modal:GetContentSizeForAxis( 2 ) ) )
    Modal:SetPos( Vector2( Client.GetScreenWidth(), Client.GetScreenHeight() ) * 0.5 - Modal:GetSize() * 0.5 )
    Modal:SetDraggable( true )
    Modal:PopUp()

    self.ReportWindow = Modal
end

function Plugin:SetupAdminMenu()
    self.ReportMenuOpen = false

    self:AddAdminMenuTab( self:GetPhrase( "REPORTS_TAB" ), {
        Icon = SGUI.Icons.Ionicons.Flag,
        OnInit = function( Panel, Data )
            self.ReportMenuOpen = true

            local Layout = SGUI.Layout:CreateLayout( "Vertical", {
                Padding = Spacing( HighResScaled( 16 ), HighResScaled( 32 ),
                    HighResScaled( 16 ), HighResScaled( 16 ) )
            } )

            local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

            local SearchIcon = SGUI:Create( "Label", Panel )
            SearchIcon:SetFontScale( SGUI.FontManager.GetHighResFont( "Ionicons", 29 ) )
            SearchIcon:SetText( SGUI.Icons.Ionicons.Search )
            SearchIcon:SetMargin( Spacing( 0, 0, HighResScaled( 8 ), 0 ) )

            local SearchBox = SGUI:Create( "TextEntry", Panel )
            SearchBox:SetFontScale( Font, Scale )
            SearchBox:SetFill( true )
            SearchBox:SetPlaceholderText( self:GetPhrase( "SEARCH_HINT" ) )

            local SearchBar = SGUI.Layout:CreateLayout( "Horizontal", {
                Margin = Spacing( 0, 0, 0, HighResScaled( 16 ) ),
                AutoSize = UnitVector( Percentage.ONE_HUNDRED, Auto( SearchBox ) + 2 ),
                Fill = false
            } )

            SearchBar:AddElement( SearchIcon )
            SearchBar:AddElement( SearchBox )

            Layout:AddElement( SearchBar )

            local List = SGUI:Create( "List", Panel )
            List:SetColumns( self:GetPhrase( "DATE" ), self:GetPhrase( "REPORTED_PLAYER" ),
                self:GetPhrase( "REASONS" ), self:GetPhrase( "REPORTED_BY" ) )
            List:SetSpacing( 0.2, 0.25, 0.3, 0.25 )
            List:SetFill( true )

            Shine.AdminMenu.SetupListWithScaling( List )

            List:SetSortedExternally( true )

            Layout:AddElement( List )

            self.ReportList = List

            Data = Data or {
                Page = 1,
                MaxResults = 15,
                SortColumn = self.SortColumn.DATE,
                SortAscending = false,
                Filter = ""
            }
            self.CurrentPage = Data

            function List.HandleExternalSorting( List, Column, Descending )
                Data.SortColumn = Column
                Data.SortAscending = not Descending

                self:RequestReportPage( Data )

                return true
            end

            function SearchBox.OnTextChanged()
                self.SearchTimer = self.SearchTimer or self:SimpleTimer( 0.3, function()
                    self.SearchTimer = nil

                    if not SGUI.IsValid( SearchBox ) then return end

                    Data.Filter = SearchBox:GetText()

                    self:RequestReportPage( Data )
                end )
                self.SearchTimer:Debounce()
            end

            local ControlLayout = SGUI.Layout:CreateLayout( "Horizontal", {
                Margin = Spacing( 0, HighResScaled( 16 ), 0, 0 ),
                Fill = false
            } )

            local PageButtonSize = UnitVector(
                Units.Max( HighResScaled( 32 ), Auto.INSTANCE + HighResScaled( 8 ) ),
                Percentage.ONE_HUNDRED
            )

            local PageBack = SGUI:Create( "Button", Panel )
            PageBack:SetIcon( SGUI.Icons.Ionicons.ArrowLeftB )
            PageBack:SetEnabled( Data.Page > 1 )
            PageBack:SetAutoSize( PageButtonSize )
            PageBack:SetAlignment( SGUI.LayoutAlignment.CENTRE )
            function PageBack.DoClick()
                Data.Page = Data.Page - 1
                self:RequestReportPage( Data )
            end
            self.PageBack = PageBack

            ControlLayout:AddElement( PageBack )

            local PageLabel = SGUI:Create( "Label", Panel )
            PageLabel:SetFontScale( Font, Scale )
            PageLabel:SetText( StringFormat( "%d / %d", Data.Page, Data.Page ) )
            PageLabel:SetAlignment( SGUI.LayoutAlignment.CENTRE )
            PageLabel:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
            PageLabel:SetMargin( Spacing( HighResScaled( 16 ), 0, HighResScaled( 16 ), 0 ) )

            function PageLabel.DoClick()
                local TextEntry = SGUI:Create( "TextEntry", Panel )
                TextEntry:SetFontScale( Font, Scale )
                TextEntry:SetSize( PageLabel:GetSize() )
                TextEntry:SetMargin( PageLabel:GetMargin() )
                TextEntry:SetText( tostring( Data.Page ) )
                TextEntry:SetNumeric( true )
                TextEntry:SetAlignment( SGUI.LayoutAlignment.CENTRE )
                TextEntry:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
                function TextEntry.OnEnter()
                    local MaxPages = self.PageData and self.PageData.NumPages or Data.Page

                    Data.Page = tonumber( TextEntry:GetText() ) or Data.Page
                    PageLabel:SetText( StringFormat( "%d / %d", Min( Data.Page, MaxPages ), MaxPages ) )

                    self:RequestReportPage( Data )

                    TextEntry:OnEscape()
                end
                function TextEntry.OnEscape()
                    TextEntry:Destroy()
                    PageLabel:SetIsVisible( true )
                    ControlLayout:RemoveElement( TextEntry )
                end
                TextEntry.OnLoseFocus = TextEntry.OnEscape

                ControlLayout:InsertElementAfter( PageLabel, TextEntry )

                PageLabel:SetIsVisible( false )

                TextEntry:RequestFocus()
                TextEntry:SelectAll()
            end
            self.PageLabel = PageLabel

            ControlLayout:AddElement( PageLabel )

            local PageForward = SGUI:Create( "Button", Panel )
            PageForward:SetIcon( SGUI.Icons.Ionicons.ArrowRightB )
            PageForward:SetEnabled( false )
            PageForward:SetAutoSize( PageButtonSize )
            PageForward:SetAlignment( SGUI.LayoutAlignment.CENTRE )
            function PageForward.DoClick()
                Data.Page = Data.Page + 1
                self:RequestReportPage( Data )
            end
            self.PageForward = PageForward

            ControlLayout:AddElement( PageForward )

            local Delete = SGUI:Create( "Button", Panel )
            Delete:SetText( self:GetPhrase( "DELETE_REPORT" ) )
            Delete:SetFontScale( Font, Scale )
            Delete:SetStyleName( "DangerButton" )
            Delete:SetIcon( SGUI.Icons.Ionicons.TrashB )
            Delete:SetAlignment( SGUI.LayoutAlignment.MAX )
            Delete:SetAutoSize( UnitVector(
                Units.Max( HighResScaled( 128 ), Auto.INSTANCE + HighResScaled( 16 ) ),
                Percentage.ONE_HUNDRED
            ) )
            Delete:SetEnabled( false )
            function Delete.DoClick()
                local Row = List:GetSelectedRow()
                if not Row or not Row.ReportData then return end

                Shine.AdminMenu:RunCommand( self.DeleteCommand, Row.ReportData.ID )
            end

            ControlLayout:AddElement( Delete )

            ControlLayout:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED,
                Units.Max( Auto( Delete ), Auto( PageForward ) ) + HighResScaled( 8 ) ) )

            Layout:AddElement( ControlLayout )

            function List:OnRowSelected()
                Delete:SetEnabled( true )
            end

            function List:OnRowDeselected()
                Delete:SetEnabled( false )
            end

            Panel:SetLayout( Layout )
            Panel:InvalidateLayout( true )
            List:SortRows( Data.SortColumn, nil, not Data.SortAscending )
        end,

        OnCleanup = function()
            self.ReportList = nil
            self.ReportMenuOpen = false

            return self.CurrentPage
        end
    } )
end

function Plugin:RequestReportPage( PageRequest )
    self:SendNetworkMessage( "RequestReportPage", PageRequest, true )
end

function Plugin:GetReasonLabels( Mask )
    local Reasons = self:MaskToReasons( Mask )
    for i = 1, #Reasons do
        Reasons[ i ] = self:GetPhrase( "REASON_"..Reasons[ i ] )
    end
    return TableConcat( Reasons, ", " )
end

function Plugin:BuildTooltip( Data )
    local Lines = {
        self:GetInterpolatedPhrase( "REPORTED_PLAYER_TIP", { Name = Data.TargetName, ID = Data.TargetID } )
    }

    if Data.SharerID ~= "" then
        Lines[ #Lines + 1 ] = self:GetInterpolatedPhrase( "FAMILY_SHARER_TIP", { ID = Data.SharerID } )
    end

    Lines[ #Lines + 1 ] = self:GetInterpolatedPhrase( "REPORTED_BY_TIP", {
        Name = Data.ReporterName, ID = Data.ReporterID
    } )

    if Data.Details ~= "" then
        Lines[ #Lines + 1 ] = self:GetInterpolatedPhrase( "DETAILS_TIP", { Details = Data.Details } )
    end

    return TableConcat( Lines, "\n" )
end

function Plugin:ReceiveReportData( Data )
    if not SGUI.IsValid( self.ReportList ) then return end

    local Row = self.ReportList:AddRow(
        Date( self:GetPhrase( "DATE_FORMAT" ), Data.Date ),
        Data.TargetName,
        self:GetReasonLabels( Data.Reasons ),
        Data.ReporterName
    )
    Row:SetTooltip( self:BuildTooltip( Data ) )
    Row.ReportData = Data
end

function Plugin:ReceiveReportPage( PageData )
    if not SGUI.IsValid( self.ReportList ) then return end

    self.ReportList:Clear()

    self.CurrentPage.Page = PageData.Page
    self.CurrentPage.MaxResults = PageData.MaxResults

    self.PageData = PageData

    self.PageLabel:SetText( StringFormat( "%d / %d", PageData.Page, PageData.NumPages ) )
    self.PageLabel:SetTooltip( self:GetInterpolatedPhrase( "TOTAL_RESULTS_TIP", {
        TotalResults = PageData.TotalNumResults
    } ) )
    self.PageBack:SetEnabled( PageData.Page > 1 )
    self.PageForward:SetEnabled( PageData.Page < PageData.NumPages )
end

function Plugin:ReceiveReportDataChanged()
    if not self.ReportMenuOpen or not self.CurrentPage then return end

    self:RequestReportPage( self.CurrentPage )
end

function Plugin:Cleanup()
    if SGUI.IsValid( self.ReportWindow ) then
        self.ReportWindow:Close()
    end

    self.BaseClass.Cleanup( self )
end
