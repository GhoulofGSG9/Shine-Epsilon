--[[
    Shine NS2Panel.com plugin
]]

local Plugin = Shine.Plugin(...)

Plugin.Version = "1.1"
Plugin.HasConfig = true

Plugin.ConfigName = "NS2Panel.json"
Plugin.DefaultConfig = {
    AuthToken = "",
    RoundEndReport = {
        MaxSubmitRetries = 3,
        SubmitTimeout = 5
    },
    PlayerConnectReport = {
        Enabled = true,
        SubmitTimeout = 5
    }
    ,
    PlayerSkillReport = {
        Enabled = true,
        MaxSubmitRetries = 1,
        SubmitTimeout = 5
    }
}
Plugin.CheckConfig = true

Plugin.BaseUrl = "https://ns2panel.com/"

function Plugin:Initialise()
    self.Enabled = true

    if ModLoader and ModLoader.GetModInfo("NS2Panel") then
        return false,
            "Please do not use the NS2Panel Mod and NS2Panel Shine extension at the same time.\n" ..
            "Using both will cause duplicate round reports at NS2Panel!"
    end

    if self.Config.AuthToken == "" then
        return false,
            "Please add your ns2panel auth token to the plugin config!\n" ..
            "Go to https://ns2panel.com/register to register your account\n" ..
            "You'll have to go to https://ns2panel.com/user/profile to set up a new community." ..
            "Once you've set up the community, go to https://ns2panel.com/user/api-tokens and generate a new token"
    end

    return true
end

function Plugin:OnFirstThink()
    local SetupGlobalHook = Shine.Hook.SetupGlobalHook
    local SetupClassHook = Shine.Hook.SetupClassHook

    SetupGlobalHook("StatsUI_SaveRoundStats", "PostSaveRounStats", "PassivePost")
    -- Ensure we send player skill reports after the game's vanilla code has updated skills.
    -- Hook into Badges_FetchBadges which is called after PlayerRanking fetches and sets stats.
    SetupGlobalHook("Badges_FetchBadges", "OnBadgesFetchBadges", "PassivePost")
    -- Also hook end-of-game player ranking completion to catch cases where badges hook isn't used.
    SetupClassHook("PlayerRanking", "EndGameStatsResults", "OnPlayerRankingEndGameStatsResults", "PassivePost")
end

function Plugin:ClientConfirmConnect(Client)
    if not self.Config.PlayerConnectReport.Enabled then return end

    if not Client or Client:GetIsVirtual() then return end

    local PlayerPingEndpoint = "api/player-ping"
    local RequestBody = {
        ip = IPAddressToString(Server.GetClientAddress(Client)),
        steam_id = Client:GetUserId()
    }
    local RequestPath = string.format("%s%s", self.BaseUrl, PlayerPingEndpoint)
    Shine.TimedHTTPRequest(RequestPath, "POST", RequestBody,
        function() end, function() end, self.Config.PlayerConnectReport.SubmitTimeout)
end

function Plugin:PostSaveRounStats(WinningTeam)
    local NewRoundEndpoint = "new-round"
    local LastRoundStats = CHUDGetLastRoundStats()

    if not LastRoundStats.ServerInfo then
        Shine:Print("[NS2Panel] Unable to send round stats. Make sure stats saving is enabled in ns2 configs")
        return
    end

    local RequestBody = {
        authToken = self.Config.AuthToken,
        stats = json.encode(LastRoundStats)
    }

    local Callbacks =
    {
        OnSuccess = function(Response, RequestError)
            if RequestError then
                Shine:Print("[NS2Panel]: Failed to publish end round report. Error:\n %s", true, RequestError)
            end
        end,
        OnFailure = function()
            Shine:Print("[NS2Panel]: Failed to publish end round report. No response after all retries")
        end,
        OnTimeout = function(Attempt)
        end
    }

    local RequestPath = string.format("%s%s", self.BaseUrl, NewRoundEndpoint)
    Shine.HTTPRequestWithRetry(RequestPath, "POST", RequestBody,
        Callbacks, self.Config.RoundEndReport.MaxSubmitRetries, self.Config.RoundEndReport.SubmitTimeout)
end

function Plugin:ProcessSkillReportResponse(Response, RequestError)
    if RequestError then
        Shine:Print("[NS2Panel]: Failed to publish player skill report. Error:\n %s", true, RequestError)
        return
    end

    Response = Response and json.decode(Response) or nil
    if not Response or not Response.should_update then return end

    local client = Shine.GetClientByNS2ID(Response.steam_id)
    if not client then return end

    local player = client:GetControllingPlayer()
    if not player then return end

    if Response.level then
        local Level = tonumber(Response.level)
        player:SetPlayerLevel(Level)

        local IsRookie = player:GetPlayerLevel() ~= -1 and player:GetPlayerLevel() < kRookieLevel
        player:SetRookie(IsRookie)
    end
    if Response.total_score then player:SetTotalScore(Response.total_score) end
    if Response.total_xp then player:SetTotalXP(Response.total_xp) end
    if Response.total_playtime then player:SetTotalPlayTime(Response.total_playtime) end

    if Response.skill then player:SetPlayerSkill(Response.skill) end
    if Response.skill_offset then player:SetPlayerSkillOffset(Response.skill_offset) end
    if Response.skill_adagrad then player:SetAdagradSum(Response.skill_adagrad) end

    if Response.comm_skill then player:SetCommanderSkill(Response.comm_skill) end
    if Response.comm_skill_offset then player:SetCommanderSkillOffset(Response.comm_skill_offset) end
    if Response.comm_adagrad then player:SetCommanderAdagradSum(Response.comm_adagrad) end

    if Response.td_skill then player:SetTDPlayerSkill(Response.td_skill) end
    if Response.td_skill_offset then player:SetTDPlayerSkillOffset(Response.td_skill_offset) end
    if Response.td_adagrad then player:SetTDAdagradSum(Response.td_adagrad) end

    if Response.td_comm_skill then player:SetTDCommanderSkill(Response.td_comm_skill) end
    if Response.td_comm_skill_offset then player:SetTDCommanderSkillOffset(Response.td_comm_skill_offset) end
    if Response.td_comm_adagrad then player:SetTDCommanderAdagradSum(Response.td_comm_adagrad) end

    -- Network changed values via player info to all clients
    local PlayerInfo = player:GetPlayerInfo()
    if PlayerInfo then
        PlayerInfo:UpdateScore()
    end
end

function Plugin:SendPlayerSkillReport(Client)
    local authToken = self.Config.AuthToken
    if not authToken or authToken == "" then return end

    if Client.GetIsVirtual and Client:GetIsVirtual() then return end

    local player = Client:GetControllingPlayer()
    if not player then return end

    --skip virtual players (bots)
    if player:GetIsVirtual() then return end

    local skillReport = {
        steam_id = Client:GetUserId(),
        ip_address = IPAddressToString(Server.GetClientAddress(Client)),
        level = player:GetPlayerLevel(),
        total_score = player.totalScore,       -- No getter for this
        total_xp = player:GetTotalXP(),
        total_playtime = player.totalPlayTime, -- No getter for this
        skill = player.GetPlayerSkill and player:GetPlayerSkill() or nil,
        skillOffset = player.GetPlayerSkillOffset and player:GetPlayerSkillOffset() or nil,
        commSkill = player.GetCommanderSkill and player:GetCommanderSkill() or nil,
        commSkillOffset = player.GetCommanderSkillOffset and player:GetCommanderSkillOffset() or nil,
        adagrad = player.GetAdagradSum and player:GetAdagradSum() or nil,
        commAdagrad = player.GetCommanderAdagradSum and player:GetCommanderAdagradSum() or nil,
        td_skill = player.GetTDPlayerSkill and player:GetTDPlayerSkill() or nil,
        td_skillOffset = player.GetTDPlayerSkillOffset and player:GetTDPlayerSkillOffset() or nil,
        td_commSkill = player.GetTDPlayerCommanderSkill and player:GetTDPlayerCommanderSkill() or nil,
        td_commSkillOffset = player.GetTDPlayerCommanderSkillOffset and player:GetTDPlayerCommanderSkillOffset() or nil,
        td_adagrad = player.GetTDAdagradSum and player:GetTDAdagradSum() or nil,
        td_commAdagrad = player.GetTDCommanderAdagradSum and player:GetTDCommanderAdagradSum() or nil
    }

    local body = {
        authToken = authToken,
        player = json.encode(skillReport)
    }

    local Callbacks = {
        OnSuccess = function(Response, RequestError)
            self:ProcessSkillReportResponse(Response, RequestError)
        end,
        OnFailure = function()
            Shine:Print("[NS2Panel]: Failed to publish player skill report. No response after all retries")
        end,
        OnTimeout = function(Attempt) end
    }

    local RequestPath = string.format("%s%s", self.BaseUrl, "api/player-skill-report")
    local retries = (self.Config.PlayerSkillReport and self.Config.PlayerSkillReport.MaxSubmitRetries) or 1
    local timeout = (self.Config.PlayerSkillReport and self.Config.PlayerSkillReport.SubmitTimeout) or 5

    Shine.HTTPRequestWithRetry(RequestPath, "POST", body, Callbacks, retries, timeout)
end

-- Called after badges fetch; signature: (steamID, response)
function Plugin:OnBadgesFetchBadges(clientID, response)
    if not self.Config.PlayerSkillReport or not self.Config.PlayerSkillReport.Enabled then return end

    if not clientID then return end
    local Client = clientID and Server.GetClientById(clientID)
    if not Client then return end

    self:SendPlayerSkillReport(Client)
end

-- Called after PlayerRanking.EndGameStatsResults; send reports for all clients
function Plugin:OnPlayerRankingEndGameStatsResults()
    if not self.Config.PlayerSkillReport or not self.Config.PlayerSkillReport.Enabled then return end

    for Client in Shine.IterateClients() do
        self:SendPlayerSkillReport(Client)
    end
end

return Plugin
