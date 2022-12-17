--[[
    Shine NS2Panel.com plugin
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.HasConfig = true

Plugin.ConfigName = "NS2Panel.json"
Plugin.DefaultConfig = {
    AuthToken = "",
    RoundEndReport = {
        MaxSubmitRetries = 3,
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

    SetupGlobalHook("StatsUI_SaveRoundStats", "PostSaveRounStats", "PassivePost")
end


function Plugin:PostSaveRounStats( WinningTeam )
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
        OnSuccess = function( Response, RequestError )
            if RequestError then
                Shine:Print("[NS2Panel]: Failed to publish end round report. Error:\n %s", true, RequestError)
            end
        end,
        OnFailure = function()
            Shine:Print("[NS2Panel]: Failed to publish end round report. No response after all retries")
        end,
        OnTimeout = function( Attempt )
        end
    }

    local RequestPath = string.format("%s%s", self.BaseUrl, NewRoundEndpoint)
    Shine.HTTPRequestWithRetry( RequestPath, "POST", RequestBody,
            Callbacks, self.Config.RoundEndReport.MaxSubmitRetries, self.Config.RoundEndReport.SubmitTimeout)
end

return Plugin