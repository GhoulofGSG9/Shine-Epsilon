--[[
-- This is a hotfix plugin I'll use to realease hotfixes for ns2.
 ]]

local Plugin = Plugin

Shine.Hook.Add("Think", "SetupHotfix", function()

	if AchievementGiverMixin then
		function AchievementGiverMixin:PreUpdateMove(input, runningPrediction)
			if self.movementModiferState then
				self.lastSneak = Shared.GetTime()
			end
		end

		function AchievementGiverMixin:OnCommanderStructureLogout(hive)
			self.commanderLogoutTime = Shared.GetTime()
		end

		function AchievementGiverMixin:SetGestationData(techIds, previousTechId, healthScalar, armorScalar)
			if techIds and self.GetClient and self:GetClient() then
				--lifeform counts as one tech
				if #techIds == 2 then
					Server.SetAchievement(self:GetClient(), "Short_1_13")
				elseif #techIds == 4 then
					Server.SetAchievement(self:GetClient(), "Short_1_14")
				end
			end
		end
	end

	Shine.Hook.Remove("Think", "SetupHotfix")
end)