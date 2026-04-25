local addon = GoldBid
local frame = addon.eventFrame or CreateFrame("Frame")
addon.eventFrame = frame
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("INSPECT_TALENT_READY")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("TRADE_REQUEST")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_UPDATE")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
frame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
frame:RegisterEvent("TRADE_MONEY_CHANGED")
frame:RegisterEvent("PLAYER_TRADE_MONEY")
frame:SetScript("OnUpdate", function(_, elapsed)
    addon.updateThrottle = (addon.updateThrottle or 0) + elapsed
    addon.syncThrottle = (addon.syncThrottle or 0) + elapsed
    addon.lootWarningThrottle = (addon.lootWarningThrottle or 0) + elapsed

    -- Интервал перерисовки: 0.2с когда аукцион активен (таймер обновляется),
    -- 0.5с в остальное время (ничего не анимируется, экономим CPU).
    local refreshInterval = addon:IsAuctionActive() and 0.2 or 0.5

    if addon.updateThrottle < refreshInterval then
        if addon.syncThrottle < 2 then
            return
        end
    else
        addon.updateThrottle = 0

        if addon:IsPlayerController() and addon:IsAuctionActive() and addon:GetTimeLeft() <= 0 then
            addon:EndAuction()
            return
        end

        -- Обратный отсчёт последних 5 секунд в чат (только контроллер, только goldbid)
        if addon:IsPlayerController() and addon:IsAuctionActive()
            and addon:GetCurrentAuctionMode() == "goldbid" then
            local timeLeft = addon:GetTimeLeft()
            if timeLeft > 0 and timeLeft <= 5 then
                local secondsLeft = math.ceil(timeLeft)
                if (addon.lastCountdownSecond or 0) ~= secondsLeft then
                    addon.lastCountdownSecond = secondsLeft
                    local distChannel = addon:GetDistributionChannel()
                    if distChannel then
                        SendChatMessage(secondsLeft .. "...", distChannel)
                    end
                end
            end
        end

        -- Пока ждём авто-скрытия — не перерисовываем UI, чтобы сохранить
        -- финальное состояние торгов (ставки, победитель) на экране.
        -- Также пропускаем refresh когда окно скрыто — нет смысла пересчитывать невидимый UI.
        if not addon.pendingAuctionReset then
            if addon.RefreshMainWindow and addon.frame and addon.frame:IsShown() then
                addon:RefreshMainWindow()
            end
        end

        -- Автоскрытие: по истечении таймера сбрасываем аукцион, обновляем UI и прячем окно.
        if addon.autoHideFrameAt and (GetTime and GetTime() or 0) >= addon.autoHideFrameAt then
            addon.autoHideFrameAt = nil
            if addon.pendingAuctionReset then
                addon.pendingAuctionReset = nil
                addon:ResetAuction()
            end
            if addon.RefreshMainWindow then
                addon:RefreshMainWindow()
            end
            if addon.frame and addon.frame:IsShown() then
                addon.frame:Hide()
            end
        end
    end

    if addon.syncThrottle >= 2 then
        addon.syncThrottle = 0

        if addon:IsPlayerController() then
            if addon:IsAuctionActive() then
                addon:BroadcastState()
            end

            if GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.payout then
                addon:SendPayoutState()
            end
        elseif (UnitInRaid("player") or UnitInParty("player")) and not addon:IsAuctionActive() then
            if not addon.lastSyncRequestAt or (time() - addon.lastSyncRequestAt) >= 5 then
                addon:RequestSync()
            end
        end
    end

    if addon.lootWarningThrottle >= 5 then
        addon.lootWarningThrottle = 0
        addon:CheckLootExpiryWarnings()
    end

    addon:ProcessPendingLootWindowRetry()
    addon:ProcessPendingLootInventoryScan()
    addon:ProcessPendingTradeCompletionCheck()
    addon:ProcessInspectQueue()
    addon:ProcessPendingVersionReport()
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        addon:HandleAddonMessage(...)
        return
    end

    if event == "CHAT_MSG_LOOT" then
        addon:HandleLootChatMessage(...)
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        addon:HandleRollSystemMessage(...)
        return
    end

    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_PARTY" then
        local message, sender = ...
        addon:HandleRaidChatBid(message, sender)
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        addon:HandleCombatLogEvent(...)
        return
    end

    if event == "LOOT_OPENED" then
        addon:HandleLootOpened(...)
        return
    end

    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        addon:HandleLootInventoryChanged()
        return
    end

    if event == "INSPECT_TALENT_READY" then
        addon:HandleInspectTalentReady(...)
        return
    end

    if event == "MAIL_SHOW" then
        if addon.RefreshMainWindow then
            addon:RefreshMainWindow()
        end
        return
    end

    if event == "MAIL_CLOSED" then
        if addon.RefreshMainWindow then
            addon:RefreshMainWindow()
        end
        return
    end

    if event == "MAIL_SEND_SUCCESS" then
        addon:HandleMailSendSuccess()
        return
    end

    if event == "MAIL_FAILED" then
        addon:HandleMailSendFailed(...)
        return
    end

    if event == "UI_ERROR_MESSAGE" then
        addon:RememberMailError(...)
        return
    end

    if event == "TRADE_REQUEST" then
        addon:HandleTradeRequest(...)
        return
    end

    if event == "TRADE_SHOW" then
        addon:HandleTradeShow()
        return
    end

    if event == "TRADE_CLOSED" then
        addon:HandleTradeClosed()
        return
    end

    if event == "TRADE_UPDATE"
        or event == "TRADE_ACCEPT_UPDATE"
        or event == "TRADE_PLAYER_ITEM_CHANGED"
        or event == "TRADE_TARGET_ITEM_CHANGED"
        or event == "TRADE_MONEY_CHANGED"
        or event == "PLAYER_TRADE_MONEY" then
        addon:HandleTradeUpdate()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        addon:EnsureDB()
        addon:ResetAuction()
        addon:ResetMailPayoutState(true)
        addon:UpdateLeader()
        addon:UpdatePlayerSpecialization()

        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(addon.prefix)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(addon.prefix)
        end

        if addon.ShowMainWindow then
            addon:CreateMainWindow()
            addon:CreateSettingsWindow()
            addon:CreateMinimapButton()
            addon:RefreshMainWindow()
        end

        addon:QueueGroupSpecInspections(true)
        addon:SendPlayerSpec()
        addon:RequestSync()
        return
    end

    if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        addon:UpdatePlayerSpecialization()
        addon:SendPlayerSpec()
    end

    addon:UpdateLeader()
    addon:QueueGroupSpecInspections(event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED")

    if addon.RefreshMainWindow then
        addon:RefreshMainWindow()
    end

    if addon:IsPlayerController() then
        addon:BroadcastState()
        addon:SendPayoutState()
    elseif UnitInRaid("player") or UnitInParty("player") then
        if not addon.lastSyncRequestAt or (time() - addon.lastSyncRequestAt) >= 2 then
            addon:RequestSync()
        end
    end
end)

