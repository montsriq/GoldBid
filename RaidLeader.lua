local addon = GoldBid

SLASH_GOLDBID1 = "/gbid"

local function trim(value)
    return (value and string.gsub(value, "^%s*(.-)%s*$", "%1")) or ""
end

SlashCmdList["GOLDBID"] = function(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
    local minBid, increment, duration

    command = string.lower(command or "")
    rest = trim(rest)

    if command == "" then
        addon:ShowMainWindow(true)
        return
    end

    if command == "show" then
        addon:ShowMainWindow(true)
        addon:RefreshMainWindow()
        return
    end

    if command == "settings" then
        addon:ShowSettingsWindow()
        return
    end

    if command == "item" then
        if rest == "" then
            addon:Print("Использование: /gbid item [ссылка на предмет]")
            return
        end

        addon:SetPendingItem(rest)
        addon:ShowMainWindow(true)
        return
    end

    if command == "start" then
        minBid, increment, duration = string.match(rest, "^(%d+)%s*(%d*)%s*(%d*)$")

        addon:StartAuction(
            addon.pendingItemLink or addon.currentAuction.itemLink,
            tonumber(minBid) or tonumber(rest) or 100,
            tonumber(increment) or 10,
            tonumber(duration) or 20
        )
        return
    end

    if command == "mode" then
        rest = string.lower(rest or "")

        if rest == "goldbid" or rest == "roll" then
            addon:SetSelectedAuctionMode(rest)
            addon:Print("Режим распределения: " .. addon:GetAuctionModeDisplayName(rest) .. ".")
            return
        end

        addon:Print("Использование: /gbid mode goldbid|roll")
        return
    end

    if command == "bid" then
        addon:SubmitBid(rest)
        return
    end

    if command == "pass" then
        addon:SubmitPass()
        return
    end

    if command == "end" then
        addon:EndAuction()
        return
    end

    if command == "sync" then
        addon:RequestSync()
        return
    end

    if command == "export" then
        addon:ShowExportWindow()
        return
    end

    if command == "split" then
        local payout

        if not addon:IsPlayerController() then
            addon:Print("Только мастер лутер может рассчитать сплит.")
            return
        end

        payout = addon:ComputePayout()
        addon:SendPayoutState()
        addon:Print("Сплит готов: " .. tostring(payout.perPlayer or 0) .. "g на игрока.")
        return
    end

    if command == "mail" then
        addon:StartMailPayout(false)
        return
    end

    addon:Print("Команды: /gbid, /gbid show, /gbid settings, /gbid item [ссылка], /gbid mode goldbid|roll, /gbid start [мин] [шаг] [сек], /gbid bid [сумма], /gbid pass, /gbid end, /gbid sync, /gbid export, /gbid split, /gbid mail")
end
