local addon = GoldBid
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)
local MINIMAP_ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Coin_02"

local function normalizeName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "none")
    end

    return string.match(name, "^[^-]+")
end

local function getItemIdentity(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    return string.match(itemLink, "item:[%-0-9:]+") or itemLink
end

local function createBackdrop(frame, bgColor, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {
            left = 3,
            right = 3,
            top = 3,
            bottom = 3,
        },
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
end

local function skinInputBox(editBox)
    local regions = { editBox:GetRegions() }
    local index

    for index = 1, table.getn(regions) do
        if regions[index] and regions[index].GetObjectType and regions[index]:GetObjectType() == "Texture" then
            regions[index]:Hide()
        end
    end

    createBackdrop(editBox, { 0.07, 0.07, 0.09, 0.96 }, { 0.45, 0.1, 0.1, 0.9 })
end

local function setupInputBox(editBox, width, text)
    skinInputBox(editBox)
    editBox:SetSize(width, 20)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetJustifyH("CENTER")
    editBox:SetFontObject(GameFontHighlight)
    editBox:SetTextColor(1, 0.95, 0.8)
    editBox:SetTextInsets(6, 6, 2, 0)
    editBox:SetMaxLetters(8)
    editBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    editBox:SetText(text or "")
end

local function setupTextBox(editBox, width, text)
    skinInputBox(editBox)
    editBox:SetSize(width, 18)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH("LEFT")
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetTextColor(1, 0.95, 0.8)
    editBox:SetTextInsets(6, 6, 1, 0)
    editBox:SetMaxLetters(32)
    editBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    editBox:SetText(text or "")
end

local function setupMiniActionButton(button, width, height, text)
    createBackdrop(button, { 0.2, 0.02, 0.02, 0.95 }, { 0.7, 0.16, 0.08, 0.95 })
    button:SetSize(width, height)
    button:EnableMouse(true)
    button:SetText(text or "")
    if button.SetNormalFontObject then
        button:SetNormalFontObject(GameFontHighlightSmall)
    end
    if button.SetHighlightFontObject then
        button:SetHighlightFontObject(GameFontHighlightSmall)
    end
    if button.SetDisabledFontObject then
        button:SetDisabledFontObject(GameFontDisableSmall)
    end
    if button.SetHitRectInsets then
        button:SetHitRectInsets(0, 0, 0, 0)
    end
    button:SetScript("OnEnter", function(selfButton)
        selfButton:SetBackdropColor(0.28, 0.05, 0.05, 0.98)
    end)
    button:SetScript("OnLeave", function(selfButton)
        selfButton:SetBackdropColor(0.2, 0.02, 0.02, 0.95)
    end)
end

local function formatGold(value)
    local number = math.floor(tonumber(value) or 0)
    local negative = false
    local formatted
    local changed

    if number < 0 then
        negative = true
        number = math.abs(number)
    end

    formatted = tostring(number)

    repeat
        formatted, changed = string.gsub(formatted, "^([0-9]+)([0-9][0-9][0-9])", "%1 %2")
    until changed == 0

    if negative then
        formatted = "-" .. formatted
    end

    return formatted .. "g"
end

local function formatGroupedInteger(value)
    local number = math.floor(tonumber(value) or 0)
    local negative = false
    local formatted
    local changed

    if number < 0 then
        negative = true
        number = math.abs(number)
    end

    formatted = tostring(number)

    repeat
        formatted, changed = string.gsub(formatted, "^([0-9]+)([0-9][0-9][0-9])", "%1 %2")
    until changed == 0

    if negative then
        formatted = "-" .. formatted
    end

    return formatted
end

local function parseNumberText(value)
    local text = tostring(value or "")

    text = string.gsub(text, "[^0-9%-]", "")

    if text == "" or text == "-" then
        return nil
    end

    return tonumber(text)
end

local function formatAmount(value)
    local number = tonumber(value) or 0
    local absolute = math.abs(number)

    if absolute >= 1000000000 then
        if absolute < 10000000000 then
            return string.format("%.2fB", number / 1000000000)
        elseif absolute < 100000000000 then
            return string.format("%.1fB", number / 1000000000)
        end

        return string.format("%.0fB", number / 1000000000)
    end

    if absolute >= 1000000 then
        if absolute < 10000000 then
            return string.format("%.2fM", number / 1000000)
        elseif absolute < 100000000 then
            return string.format("%.1fM", number / 1000000)
        end

        return string.format("%.0fM", number / 1000000)
    end

    if absolute >= 1000 then
        if absolute < 100000 then
            return string.format("%.1fK", number / 1000)
        end

        return string.format("%.0fK", number / 1000)
    end

    return tostring(math.floor(number + 0.5))
end

local function formatRate(value)
    return formatAmount(value)
end

local function formatClock(value)
    local totalSeconds = math.max(0, tonumber(value) or 0)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end

    return string.format("%d:%02d", minutes, seconds)
end

local function setTabButtonState(button, isActive)
    local label = button and button:GetFontString()

    if not button then
        return
    end

    button:SetAlpha(isActive and 1 or 0.7)

    if label then
        if isActive then
            label:SetTextColor(1, 0.82, 0)
        else
            label:SetTextColor(0.92, 0.88, 0.72)
        end
    end
end

function addon:ApplySuggestedRaiseStepForMinBid(frame, minBid, force)
    local suggestedStep

    if not frame or not frame.incrementBox or self:IsAuctionActive() then
        return
    end

    if frame.incrementManualOverride and not force then
        return
    end

    suggestedStep = self:GetSuggestedRaiseStepForMinBid(minBid)

    if not suggestedStep then
        return
    end

    frame.incrementBox:SetText(formatGroupedInteger(suggestedStep))
end

function addon:ApplyDefaultAuctionInputs(frame, force)
    if not frame or self:IsAuctionActive() then
        return
    end

    if frame.idleDefaultsApplied and not force then
        return
    end

    if frame.minBidBox and not frame.minBidBox:HasFocus() then
        frame.minBidBox:SetText(formatGroupedInteger(self:GetDefaultAuctionMinBid()))
    end

    if frame.incrementBox and not frame.incrementBox:HasFocus() then
        frame.incrementBox:SetText(formatGroupedInteger(self:GetDefaultAuctionIncrement()))
    end

    if frame.durationBox and not frame.durationBox:HasFocus() then
        frame.durationBox:SetText(tostring(self:GetDefaultAuctionDuration()))
    end

    frame.idleDefaultsApplied = true
end

function addon:ApplySuggestedMinBidForPendingItem(frame, itemLink)
    local suggestedMinBid

    if not frame or not frame.minBidBox or not frame.incrementBox or not itemLink or itemLink == "" or self:IsAuctionActive() then
        return
    end

    suggestedMinBid = self:GetSuggestedMinBidForItem(itemLink)

    if not suggestedMinBid then
        return
    end

    if frame.lastAutoMinBidItemLink ~= itemLink then
        frame.minBidBox:SetText(formatGroupedInteger(suggestedMinBid))
        self:ApplySuggestedRaiseStepForMinBid(frame, suggestedMinBid, true)
        frame.lastAutoMinBidItemLink = itemLink
    end
end

function addon:CreateExportWindow()
    local frame, title, closeButton, scrollFrame, editBox, doneButton

    if self.exportFrame then
        return self.exportFrame
    end

    frame = CreateFrame("Frame", "GoldBidExportFrame", UIParent)
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    createBackdrop(frame, { 0.03, 0.03, 0.05, 0.98 }, { 0.7, 0.08, 0.08, 1 })
    frame:Hide()

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("Экспорт журнала GDKP")

    closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    scrollFrame = CreateFrame("ScrollFrame", "GoldBidExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 46)

    editBox = CreateFrame("EditBox", "GoldBidExportEditBox", frame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(490)
    editBox:SetTextInsets(10, 10, 10, 10)
    editBox:SetJustifyH("LEFT")
    editBox:SetTextColor(1, 0.95, 0.8)
    if editBox.SetSpacing then
        editBox:SetSpacing(1)
    end
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    editBox:SetScript("OnTextChanged", function(selfBox)
        scrollFrame:UpdateScrollChildRect()
    end)

    editBox.bg = editBox:CreateTexture(nil, "BACKGROUND")
    editBox.bg:SetAllPoints(true)
    editBox.bg:SetTexture(0.08, 0.08, 0.1, 0.92)

    scrollFrame:SetScrollChild(editBox)

    doneButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    doneButton:SetSize(100, 24)
    doneButton:SetPoint("BOTTOM", 0, 14)
    doneButton:SetText("Закрыть")
    doneButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.scrollFrame = scrollFrame
    frame.editBox = editBox
    self.exportFrame = frame
    return frame
end

if not StaticPopupDialogs["GOLDBID_RESET_CONFIRM"] then
    StaticPopupDialogs["GOLDBID_RESET_CONFIRM"] = {
        text = "Сбросить все данные GoldBid?\n\nБудут очищены аукцион, продажи, касса и делёжка.",
        button1 = "Сбросить",
        button2 = "Отмена",
        OnAccept = function()
            addon:ResetAllData()
            addon:Print("Данные GoldBid были сброшены.")
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

if not StaticPopupDialogs["GOLDBID_PASS_CONFIRM"] then
    StaticPopupDialogs["GOLDBID_PASS_CONFIRM"] = {
        text = "Точно отказаться от участия в торгах?\n\nПосле ПАС вы больше не сможете делать ставки в этом аукционе.",
        button1 = "ПАС",
        button2 = "Отмена",
        OnAccept = function()
            addon:SubmitPass()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

if not StaticPopupDialogs["GOLDBID_SKIP_LOT_CONFIRM"] then
    StaticPopupDialogs["GOLDBID_SKIP_LOT_CONFIRM"] = {
        text = "Скрыть окно текущего лота?\n\nОно больше не будет появляться автоматически, пока торгуется этот лот.",
        button1 = "Пропустить",
        button2 = "Отмена",
        OnAccept = function()
            addon:SkipCurrentAuctionLot(addon.pendingSkipAuctionId)
        end,
        OnCancel = function()
            addon.pendingSkipAuctionId = nil
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

if not StaticPopupDialogs["GOLDBID_RESTART_AUCTION_CONFIRM"] then
    StaticPopupDialogs["GOLDBID_RESTART_AUCTION_CONFIRM"] = {
        text = "Вы уверены, что хотите перезапустить аукцион на эту вещь?",
        button1 = "Перезапустить",
        button2 = "Отмена",
        OnAccept = function()
            local restartData = addon.pendingRestartAuction

            if not restartData then
                return
            end

            addon:StartAuction(
                restartData.itemLink,
                restartData.minBid,
                restartData.increment,
                restartData.duration
            )
            addon.pendingRestartAuction = nil
        end,
        OnCancel = function()
            addon.pendingRestartAuction = nil
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

if not StaticPopupDialogs["GOLDBID_DELETE_SALE_CONFIRM"] then
    StaticPopupDialogs["GOLDBID_DELETE_SALE_CONFIRM"] = {
        text = "Удалить этот лот из сводки?\n\nСумма лота будет вычтена из общего банка.",
        button1 = "Удалить",
        button2 = "Отмена",
        OnAccept = function()
            local saleIndex = addon.pendingSaleDeleteIndex

            if saleIndex then
                addon:RemoveSaleAt(saleIndex)
            end

            addon.pendingSaleDeleteIndex = nil
        end,
        OnCancel = function()
            addon.pendingSaleDeleteIndex = nil
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

function addon:ShowExportWindow()
    local frame = self:CreateExportWindow()
    local text = self:BuildExportText()
    local lines = 1

    text = text or ""
    text = string.gsub(text, "\r\n", "\n")
    lines = select(2, string.gsub(text, "\n", "\n")) + 1

    frame.editBox:SetText(text)
    frame.editBox:SetHeight(math.max(260, lines * 16 + 20))
    frame.editBox:HighlightText()
    frame:Show()
end

function addon:IsAuctionWindowSuppressed(auctionId)
    local activeAuctionId = auctionId or (self.currentAuction and self.currentAuction.id)

    if not activeAuctionId or activeAuctionId == "" then
        return false
    end

    return tostring(self.skippedAuctionId or "") == tostring(activeAuctionId)
end

function addon:ConfirmSkipAuctionLot()
    if self:HasFullInterfaceAccess() then
        return
    end

    if not self:IsAuctionActive() or not (self.currentAuction and self.currentAuction.id) then
        self:Print("Нет активного аукциона.")
        return
    end

    self.pendingSkipAuctionId = tostring(self.currentAuction.id)
    StaticPopup_Show("GOLDBID_SKIP_LOT_CONFIRM")
end

function addon:SkipCurrentAuctionLot(targetAuctionId)
    local activeAuctionId = tostring((self.currentAuction and self.currentAuction.id) or "")

    self.pendingSkipAuctionId = nil

    if self:HasFullInterfaceAccess() then
        return
    end

    if not self:IsAuctionActive() or activeAuctionId == "" then
        self:Print("Нет активного аукциона.")
        return
    end

    if targetAuctionId and tostring(targetAuctionId) ~= "" and activeAuctionId ~= tostring(targetAuctionId) then
        return
    end

    self.skippedAuctionId = activeAuctionId

    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    end

    self:Print("Текущий лот скрыт. Окно снова появится на следующем лоте.")
end

function addon:ConfirmDeleteSale(index)
    if not self:IsPlayerController() then
        self:Print("Удалять лоты из сводки может только мастер лутер.")
        return
    end

    self.pendingSaleDeleteIndex = index
    StaticPopup_Show("GOLDBID_DELETE_SALE_CONFIRM")
end

function addon:ConfirmOrStartAuction(itemLink, minBid, increment, duration)
    local currentItemLink = self.currentAuction and self.currentAuction.itemLink or nil

    if self:IsAuctionActive() and currentItemLink and getItemIdentity(itemLink) == getItemIdentity(currentItemLink) then
        self.pendingRestartAuction = {
            itemLink = itemLink,
            minBid = minBid,
            increment = increment,
            duration = duration,
        }
        StaticPopup_Show("GOLDBID_RESTART_AUCTION_CONFIRM")
        return
    end

    self:StartAuction(itemLink, minBid, increment, duration)
end

function addon:RefreshControllerDropdown()
    local frame = self.settingsFrame or self:CreateSettingsWindow()
    local dropdown = frame.controllerDropDown
    local selectedName = normalizeName(GoldBidDB and GoldBidDB.ui and GoldBidDB.ui.controllerOverride)
    local autoName = self:GetAutoControllerName() or self:GetPlayerName() or "неизвестно"
    local candidates = self:GetControllerCandidates()
    local canManage = self:CanManageController(self:GetPlayerName())
    local index

    if not dropdown or not UIDropDownMenu_Initialize then
        return
    end

    UIDropDownMenu_Initialize(dropdown, function(selfDropDown, level)
        local info

        if level ~= 1 then
            return
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = "Авто (" .. tostring(autoName) .. ")"
        info.value = ""
        info.checked = not selectedName
        info.disabled = not canManage
        info.func = function()
            addon:SetControllerOverride(nil)
            addon:RefreshControllerDropdown()
        end
        UIDropDownMenu_AddButton(info, level)

        for index = 1, table.getn(candidates) do
            local candidateName = candidates[index]

            info = UIDropDownMenu_CreateInfo()
            info.text = tostring(candidateName)
            info.value = candidateName
            info.checked = selectedName and normalizeName(candidateName) == selectedName
            info.disabled = not canManage
            info.func = function()
                addon:SetControllerOverride(candidateName)
                addon:RefreshControllerDropdown()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetWidth(dropdown, 190)
    UIDropDownMenu_SetSelectedValue(dropdown, selectedName or "")
    UIDropDownMenu_SetText(dropdown, selectedName or ("Авто (" .. tostring(autoName) .. ")"))

    if canManage and UIDropDownMenu_EnableDropDown then
        UIDropDownMenu_EnableDropDown(dropdown)
    elseif not canManage and UIDropDownMenu_DisableDropDown then
        UIDropDownMenu_DisableDropDown(dropdown)
    end

    if frame.controllerHint then
        if canManage then
            frame.controllerHint:SetText("Лидер рейда, помощник или текущий мастер лутер могут выбрать, кто будет вести торги.")
        else
            frame.controllerHint:SetText("Вы можете только смотреть текущий выбор. Менять его может лидер рейда, помощник или текущий мастер лутер.")
        end
    end
end

function addon:RefreshModeDropdown()
    local frame = self.frame or self:CreateMainWindow()
    local dropdown = frame.modeDropDown
    local selectedMode = self:GetCurrentAuctionMode()
    local canChangeMode = self:IsPlayerController() and not self:IsAuctionActive()

    if not dropdown or not UIDropDownMenu_Initialize then
        return
    end

    UIDropDownMenu_Initialize(dropdown, function(selfDropDown, level)
        local info
        local modes = {
            { value = "goldbid", text = "GoldBid" },
            { value = "roll", text = "Roll" },
        }
        local index

        if level ~= 1 then
            return
        end

        for index = 1, table.getn(modes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = modes[index].text
            info.value = modes[index].value
            info.checked = selectedMode == modes[index].value
            info.disabled = not canChangeMode
            info.func = function()
                addon:SetSelectedAuctionMode(modes[index].value)
                addon:RefreshModeDropdown()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetWidth(dropdown, 110)
    UIDropDownMenu_SetSelectedValue(dropdown, selectedMode)
    UIDropDownMenu_SetText(dropdown, self:GetAuctionModeDisplayName(selectedMode))

    if canChangeMode and UIDropDownMenu_EnableDropDown then
        UIDropDownMenu_EnableDropDown(dropdown)
    elseif not canChangeMode and UIDropDownMenu_DisableDropDown then
        UIDropDownMenu_DisableDropDown(dropdown)
    end

    frame.lastModeDropdownValue = selectedMode
    frame.lastModeDropdownCanChange = canChangeMode
end

function addon:CreateSettingsWindow()
    local frame, title, closeButton, autoStartCheck, minimapCheck, controllerLabel, controllerDropDown

    if self.settingsFrame then
        return self.settingsFrame
    end

    frame = CreateFrame("Frame", "GoldBidSettingsFrame", UIParent)
    frame:SetSize(360, 280)
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    createBackdrop(frame, { 0.03, 0.03, 0.05, 0.97 }, { 0.7, 0.08, 0.08, 1 })
    frame:Hide()

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("GoldBid - Настройки")

    closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    autoStartCheck = CreateFrame("CheckButton", "GoldBidAutoStartCheck", frame, "UICheckButtonTemplate")
    autoStartCheck:SetPoint("TOPLEFT", 16, -48)
    autoStartCheck.text = _G[autoStartCheck:GetName() .. "Text"]
    autoStartCheck.text:SetText("Перетаскивание только выбирает предмет")
    autoStartCheck:SetScript("OnClick", function(selfButton)
        GoldBidDB.ui.autoStartOnDrag = selfButton:GetChecked() and true or false
    end)

    minimapCheck = CreateFrame("CheckButton", "GoldBidMinimapCheck", frame, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", autoStartCheck, "BOTTOMLEFT", 0, -8)
    minimapCheck.text = _G[minimapCheck:GetName() .. "Text"]
    minimapCheck.text:SetText("Показывать кнопку у миникарты")
    minimapCheck:SetScript("OnClick", function(selfButton)
        addon:EnsureDB()
        GoldBidDB.ui.minimap.hide = not selfButton:GetChecked()

        if LDBIcon then
            if GoldBidDB.ui.minimap.hide then
                LDBIcon:Hide("GoldBid")
            else
                addon:CreateMinimapButton()
                LDBIcon:Show("GoldBid")
            end
        elseif addon.minimapButton then
            addon.minimapButton:SetShown(not GoldBidDB.ui.minimap.hide)
        end
    end)

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 6, -10)
    frame.note:SetWidth(316)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText("Аукцион запускается только кнопкой Старт. Перетаскивание предмета лишь подставляет лот в окно.")

    controllerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    controllerLabel:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", -6, -18)
    controllerLabel:SetText("Кто ведёт торги")

    controllerDropDown = CreateFrame("Frame", "GoldBidControllerDropDown", frame, "UIDropDownMenuTemplate")
    controllerDropDown:SetPoint("TOPLEFT", controllerLabel, "BOTTOMLEFT", -14, -4)
    UIDropDownMenu_SetWidth(controllerDropDown, 190)
    UIDropDownMenu_SetText(controllerDropDown, "Авто")

    frame.controllerHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.controllerHint:SetPoint("TOPLEFT", controllerDropDown, "BOTTOMLEFT", 20, -8)
    frame.controllerHint:SetWidth(300)
    frame.controllerHint:SetJustifyH("LEFT")
    frame.controllerHint:SetText("")

    frame.autoStartCheck = autoStartCheck
    frame.minimapCheck = minimapCheck
    frame.controllerDropDown = controllerDropDown
    self.settingsFrame = frame
    return frame
end

function addon:ShowSettingsWindow()
    local frame = self:CreateSettingsWindow()
    self:EnsureDB()
    frame.autoStartCheck:SetChecked(true)
    frame.autoStartCheck:Disable()
    frame.minimapCheck:SetChecked(not (GoldBidDB and GoldBidDB.ui and GoldBidDB.ui.minimap and GoldBidDB.ui.minimap.hide))
    self:RefreshControllerDropdown()
    frame:Show()
end

function addon:GetEffectiveRaiseStep()
    local frame = self.frame or self:CreateMainWindow()
    local auctionStep = (self.currentAuction and tonumber(self.currentAuction.increment)) or 0
    local configuredStep = parseNumberText(frame.incrementBox:GetText()) or 0

    if configuredStep < auctionStep then
        configuredStep = auctionStep
    end

    if configuredStep <= 0 then
        configuredStep = 1
    end

    return configuredStep
end

function addon:NormalizeClientRaiseStep()
    local frame = self.frame or self:CreateMainWindow()
    local auctionStep = (self.currentAuction and tonumber(self.currentAuction.increment)) or 0
    local configuredStep = parseNumberText(frame.incrementBox:GetText()) or 0

    if configuredStep <= 0 then
        configuredStep = auctionStep > 0 and auctionStep or 1
    end

    if not self:IsPlayerController() and auctionStep > 0 and configuredStep < auctionStep then
        configuredStep = auctionStep
    end

    frame.incrementBox:SetText(formatGroupedInteger(configuredStep))
    return configuredStep
end

function addon:GetSuggestedBidBase()
    local auction = self.currentAuction or {}
    local playerName = self:GetPlayerName()
    local highestOtherBid = nil
    local ownBid = auction.bids and auction.bids[playerName] or nil
    local name, amount

    if not self:IsAuctionActive() then
        return 0
    end

    for name, amount in pairs(auction.bids or {}) do
        if name ~= playerName and amount and amount > 0 then
            if not highestOtherBid or amount > highestOtherBid then
                highestOtherBid = amount
            end
        end
    end

    if highestOtherBid then
        return highestOtherBid
    end

    if ownBid and ownBid > 0 then
        return ownBid
    end

    return auction.minBid or 0
end

function addon:IncrementBidAmount()
    local frame = self.frame or self:CreateMainWindow()
    local suggestedBase = self:GetSuggestedBidBase()
    local currentBid = tonumber(frame.bidBox:GetText()) or 0
    local step = self:GetEffectiveRaiseStep()

    if currentBid < suggestedBase then
        currentBid = suggestedBase
    end

    frame.bidPreviewBase = suggestedBase
    frame.bidPreviewValue = currentBid + step
    frame.bidBox:SetText(tostring(frame.bidPreviewValue))
    frame.bidManualOverride = true
end

function addon:ToggleMainWindow()
    local frame = self:CreateMainWindow()

    if frame:IsShown() then
        frame:Hide()
    else
        self:ShowMainWindow(true)
    end
end

function addon:UpdateMainWindowLayout()
    local frame = self.frame or self:CreateMainWindow()
    local hasFullAccess = self:HasFullInterfaceAccess()
    local isExpanded = hasFullAccess or frame.compactSectionOpen
    local isRollMode = self:GetCurrentAuctionMode() == "roll"
    local compactHeight

    if not hasFullAccess and frame.activeTab == "split" then
        frame.activeTab = "auction"
    end

    if not hasFullAccess and frame.activeTab == "spend" then
        frame.activeTab = "auction"
    end

    if not hasFullAccess and frame.activeTab == "loot" then
        frame.activeTab = "auction"
    end

    if not hasFullAccess and frame.activeTab == "damage" then
        frame.activeTab = "auction"
    end

    if not hasFullAccess and frame.activeTab == "summary" then
        frame.activeTab = "auction"
    end

    compactHeight = isExpanded and 308 or 140

    frame.compactTabsBar:SetShown(not hasFullAccess)
    frame.compactPotText:SetShown(false)
    frame.header:SetShown(hasFullAccess)
    frame.compactCloseButton:SetShown(not hasFullAccess)
    frame.compactSkipButton:SetShown(not hasFullAccess)
    frame.infoBar:SetShown(hasFullAccess)
    frame.leaderText:SetShown(hasFullAccess)
    frame.statusText:SetShown(hasFullAccess)
    frame.auctionTabButton:SetShown(hasFullAccess)
    frame.summaryTabButton:SetShown(hasFullAccess)
    frame.spendTabButton:SetShown(hasFullAccess)
    frame.lootTabButton:SetShown(hasFullAccess)
    frame.damageTabButton:SetShown(hasFullAccess)
    frame.splitTabButton:SetShown(hasFullAccess)
    frame.spendView:SetShown(hasFullAccess and frame.activeTab == "spend")
    frame.lootView:SetShown(hasFullAccess and frame.activeTab == "loot")
    frame.damageView:SetShown(hasFullAccess and frame.activeTab == "damage")
    frame.splitView:SetShown(hasFullAccess and frame.activeTab == "split")
    frame.tablesPanel:SetShown(isExpanded)
    frame.footerPanel:SetShown(hasFullAccess and isExpanded)
    frame.resetButton:SetShown(self:IsPlayerController())
    frame.resizeHandle:SetShown(hasFullAccess)

    frame.startButton:SetShown(hasFullAccess)
    frame.endButton:SetShown(hasFullAccess)
    frame.settingsActionButton:SetShown(hasFullAccess)
    frame.modeLabel:SetShown(hasFullAccess)
    frame.modeDropDown:SetShown(hasFullAccess)

    if hasFullAccess then
        frame:SetBackdropColor(0.02, 0.02, 0.04, 0.98)
        frame:SetBackdropBorderColor(0.7, 0.08, 0.08, 1)
        frame.controlsPanel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
        frame.controlsPanel:SetBackdropBorderColor(0.35, 0.08, 0.08, 0.9)
        frame.infoBar:SetBackdropColor(0.12, 0.03, 0.03, 0.88)
        frame.infoBar:SetBackdropBorderColor(0.45, 0.1, 0.1, 0.8)
        frame.tablesPanel:SetBackdropColor(0.04, 0.04, 0.08, 0.9)
        frame.tablesPanel:SetBackdropBorderColor(0.35, 0.08, 0.08, 0.85)
        frame.footerPanel:SetBackdropColor(0.08, 0.05, 0.03, 0.92)
        frame.footerPanel:SetBackdropBorderColor(0.35, 0.08, 0.08, 0.85)
        frame:SetResizable(true)
        frame:SetMinResize(760, 520)
        if frame:GetWidth() < 760 or frame:GetHeight() < 520 then
            frame:SetSize(math.max(frame:GetWidth(), 760), math.max(frame:GetHeight(), 520))
        end
        frame.controlsPanel:ClearAllPoints()
        frame.controlsPanel:SetPoint("TOPLEFT", 12, -58)
        frame.controlsPanel:SetPoint("TOPRIGHT", -12, -58)
        frame.controlsPanel:SetHeight(152)
        frame.compactAuctionButton:SetSize(84, 22)
        frame.compactSummaryButton:SetSize(84, 22)
        frame.compactAuctionButton:ClearAllPoints()
        frame.compactAuctionButton:SetPoint("LEFT", 0, 0)
        frame.compactSummaryButton:ClearAllPoints()
        frame.compactSummaryButton:SetPoint("LEFT", frame.compactAuctionButton, "RIGHT", 8, 0)
        frame.compactTabsBar:SetPoint("BOTTOMLEFT", 14, 10)
        frame.compactTabsBar:SetPoint("BOTTOMRIGHT", -14, 10)
        frame.compactTabsBar:SetHeight(24)
        frame.tablesPanel:SetPoint("TOPLEFT", 12, -222)
        frame.tablesPanel:SetPoint("BOTTOMRIGHT", -12, 58)
        frame.footerPanel:SetPoint("BOTTOMLEFT", 12, 12)
        frame.footerPanel:SetPoint("BOTTOMRIGHT", -12, 12)
        frame.resetButton:Show()
        frame.resetButton:SetSize(96, 22)
        frame.resetButton:ClearAllPoints()
        frame.resetButton:SetPoint("LEFT", frame.footerPanel, "LEFT", 12, 0)
        frame.resetButton:SetText("Сброс")
        frame.resetButton:SetScript("OnClick", function()
            if not addon:IsPlayerController() and (UnitInRaid("player") or GetNumPartyMembers() > 0) then
                addon:Print("Только мастер лутер может сбросить данные рейда.")
                return
            end

            StaticPopup_Show("GOLDBID_RESET_CONFIRM")
        end)
        if frame.mailPayoutButton then
            frame.mailPayoutButton:SetSize(132, 22)
            frame.mailPayoutButton:ClearAllPoints()
            frame.mailPayoutButton:SetPoint("LEFT", frame.resetButton, "RIGHT", 10, 0)
        end
        frame.itemButton:SetSize(50, 50)
        frame.itemButton:SetPoint("TOPLEFT", 54, -44)
        frame.itemText:Show()
        frame.itemText:SetPoint("TOP", frame.itemButton, "BOTTOM", 0, -8)
        frame.itemText:SetWidth(120)
        frame.itemText:SetJustifyH("CENTER")
        frame.modeDropDown:ClearAllPoints()
        frame.modeDropDown:SetPoint("RIGHT", frame.settingsButton, "LEFT", 8, -2)
        frame.modeLabel:ClearAllPoints()
        frame.modeLabel:SetPoint("RIGHT", frame.modeDropDown, "LEFT", 8, 0)
        frame.compactPotText:SetWidth(260)
        frame.minBidBox:SetWidth(90)
        frame.incrementBox:SetWidth(90)
        frame.durationBox:SetWidth(90)
        frame.bidBox:SetWidth(90)
        frame.minBidBox:EnableMouse(not isRollMode)
        frame.incrementBox:EnableMouse(not isRollMode)
        frame.durationBox:EnableMouse(true)
        frame.bidBox:EnableMouse(not isRollMode)
        frame.bidButton:SetSize(96, 22)
        frame.passButton:Show()
        frame.passButton:SetSize(96, 22)
        frame.passButton:ClearAllPoints()
        frame.passButton:SetPoint("LEFT", frame.bidButton, "RIGHT", 10, 0)
        frame.syncButton:SetSize(96, 22)
        frame.syncButton:Show()
        frame.footerText:Show()
        frame.compactCloseButton:ClearAllPoints()
        frame.compactCloseButton:SetPoint("TOPRIGHT", 2, 2)
        frame.compactSkipButton:ClearAllPoints()
        frame.compactSkipButton:SetPoint("RIGHT", frame.compactCloseButton, "LEFT", -4, 0)
        frame.minBidLabel:SetWidth(90)
        frame.incrementLabel:SetWidth(90)
        frame.durationLabel:SetWidth(90)
        frame.bidLabel:SetWidth(90)
        frame.minBidLabel:SetPoint("TOPLEFT", 236, -44)
        frame.incrementLabel:SetPoint("TOPLEFT", 346, -44)
        frame.durationLabel:SetPoint("TOPLEFT", 236, -86)
        frame.bidLabel:SetPoint("TOPLEFT", 346, -86)
        frame.startButton:SetPoint("TOPLEFT", 522, -48)
        frame.bidButton:SetPoint("TOPLEFT", 522, -82)
        frame.syncButton:SetPoint("TOPLEFT", 522, -116)
    else
        -- Компактный режим клиента: рамка обрезана почти по контенту
        local compactItemLeft = 16
        local compactItemTop = -20
        local compactFirstColumnLeft = 84
        local compactSecondColumnLeft = 164
        local compactTopRowLabel = -12
        local compactBottomRowLabel = -46
        local compactButtonWidth = 84
        local compactLeftButtonsLeft = 274
        local compactRightButtonsLeft = 366
        local compactButtonsTop = -10
        local compactButtonHeight = 24
        local compactButtonGapY = 25

        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        frame.controlsPanel:SetBackdropColor(0.035, 0.035, 0.06, 0.9)
        frame.controlsPanel:SetBackdropBorderColor(0.2, 0.05, 0.05, 0.7)
        frame.infoBar:SetBackdropColor(0, 0, 0, 0)
        frame.infoBar:SetBackdropBorderColor(0, 0, 0, 0)
        frame.tablesPanel:SetBackdropColor(0, 0, 0, 0)
        frame.tablesPanel:SetBackdropBorderColor(0, 0, 0, 0)
        frame.footerPanel:SetBackdropColor(0, 0, 0, 0)
        frame.footerPanel:SetBackdropBorderColor(0, 0, 0, 0)
        frame:SetResizable(false)
        frame:SetWidth(402)
        frame:SetHeight(132)
        frame.controlsPanel:ClearAllPoints()
        frame.controlsPanel:SetPoint("TOPLEFT", 10, -6)
        frame.controlsPanel:SetPoint("TOPRIGHT", -10, -6)
        frame.controlsPanel:SetHeight(90)
        frame.compactCloseButton:ClearAllPoints()
        frame.compactCloseButton:SetPoint("BOTTOMRIGHT", frame.controlsPanel, "TOPRIGHT", 2, -2)
        frame.compactSkipButton:ClearAllPoints()
        frame.compactSkipButton:SetPoint("RIGHT", frame.compactCloseButton, "LEFT", -4, 0)
        frame.compactTabsBar:ClearAllPoints()
        frame.compactTabsBar:SetPoint("TOPLEFT", compactLeftButtonsLeft, compactButtonsTop - (compactButtonGapY * 2))
        frame.compactTabsBar:SetSize(compactButtonWidth, compactButtonHeight)
        frame.tablesPanel:SetPoint("TOPLEFT", 10, -98)
        frame.tablesPanel:SetPoint("BOTTOMRIGHT", -10, 8)
        frame.footerPanel:SetPoint("BOTTOMLEFT", 12, 10)
        frame.footerPanel:SetPoint("BOTTOMRIGHT", -12, 10)
        -- Иконка без подписи (тултип на ховере)
        frame.itemButton:SetSize(44, 44)
        frame.itemButton:SetPoint("TOPLEFT", compactItemLeft, compactItemTop)
        frame.resetButton:Hide()
        frame.itemText:Hide()
        frame.modeLabel:Hide()
        frame.modeDropDown:Hide()
        -- Две колонки полей: слева Мин. ставка / Время, справа Шаг / Ваша ставка
        frame.minBidBox:SetWidth(60)
        frame.incrementBox:SetWidth(60)
        frame.durationBox:SetWidth(60)
        frame.bidBox:SetWidth(60)
        frame.minBidBox:EnableMouse(false)
        frame.incrementBox:EnableMouse(not isRollMode)
        frame.durationBox:EnableMouse(false)
        frame.bidBox:EnableMouse(not isRollMode)
        frame.minBidLabel:SetWidth(60)
        frame.incrementLabel:SetWidth(60)
        frame.durationLabel:SetWidth(60)
        frame.bidLabel:SetWidth(60)
        frame.minBidLabel:SetPoint("TOPLEFT", compactFirstColumnLeft, compactTopRowLabel)
        frame.incrementLabel:SetPoint("TOPLEFT", compactSecondColumnLeft, compactTopRowLabel)
        frame.durationLabel:SetPoint("TOPLEFT", compactFirstColumnLeft, compactBottomRowLabel)
        frame.bidLabel:SetPoint("TOPLEFT", compactSecondColumnLeft, compactBottomRowLabel)
        frame.addStepButton:ClearAllPoints()
        frame.addStepButton:SetPoint("LEFT", frame.bidBox, "RIGHT", 8, -1)
        -- Кнопки клиента: одна колонка Ставка/Пас/Торги
        frame.syncButton:Hide()
        frame.bidButton:SetSize(compactButtonWidth, compactButtonHeight)
        frame.passButton:Show()
        frame.passButton:SetSize(compactButtonWidth, compactButtonHeight)
        frame.bidButton:SetPoint("TOPLEFT", compactLeftButtonsLeft, compactButtonsTop)
        frame.passButton:ClearAllPoints()
        frame.passButton:SetPoint("TOPLEFT", compactLeftButtonsLeft, compactButtonsTop - compactButtonGapY)
        frame.compactAuctionButton:SetSize(compactButtonWidth, compactButtonHeight)
        frame.compactAuctionButton:ClearAllPoints()
        frame.compactAuctionButton:SetPoint("TOPLEFT", 0, 0)
        frame.compactAuctionButton:Show()
        frame.compactSummaryButton:Hide()
        -- Убрать дублирующийся текст пота
        frame.footerText:Hide()
        frame.compactPotText:SetWidth(150)
    end

    frame.addStepButton:SetShown(not isRollMode)
end

function addon:SetMainTab(tabName, preserveState)
    local frame = self.frame or self:CreateMainWindow()
    local activeTab = "auction"
    local hasFullAccess = self:HasFullInterfaceAccess()

    if tabName == "summary" or (hasFullAccess and (tabName == "split" or tabName == "spend" or tabName == "loot" or tabName == "damage")) then
        activeTab = tabName
    end

    if not hasFullAccess and not preserveState then
        if frame.compactSectionOpen and frame.activeTab == activeTab then
            frame.compactSectionOpen = false
        else
            frame.activeTab = activeTab
            frame.compactSectionOpen = true
        end
    elseif not hasFullAccess then
        frame.activeTab = frame.activeTab or activeTab
    else
        frame.activeTab = activeTab
        frame.compactSectionOpen = true
    end

    if frame.auctionView then
        frame.auctionView:SetShown((hasFullAccess or frame.compactSectionOpen) and frame.activeTab == "auction")
    end

    if frame.summaryView then
        frame.summaryView:SetShown((hasFullAccess or frame.compactSectionOpen) and frame.activeTab == "summary")
    end

    if frame.spendView then
        frame.spendView:SetShown(hasFullAccess and frame.activeTab == "spend")
    end

    if frame.lootView then
        frame.lootView:SetShown(hasFullAccess and frame.activeTab == "loot")
    end

    if frame.damageView then
        frame.damageView:SetShown(hasFullAccess and frame.activeTab == "damage")
    end

    if frame.splitView then
        frame.splitView:SetShown(hasFullAccess and frame.activeTab == "split")
    end

    setTabButtonState(frame.auctionTabButton, frame.activeTab == "auction")
    setTabButtonState(frame.summaryTabButton, frame.activeTab == "summary")
    setTabButtonState(frame.spendTabButton, frame.activeTab == "spend")
    setTabButtonState(frame.lootTabButton, frame.activeTab == "loot")
    setTabButtonState(frame.damageTabButton, frame.activeTab == "damage")
    setTabButtonState(frame.splitTabButton, frame.activeTab == "split")
    setTabButtonState(frame.compactAuctionButton, frame.compactSectionOpen and frame.activeTab == "auction")
    setTabButtonState(frame.compactSummaryButton, frame.compactSectionOpen and frame.activeTab == "summary")
    self:UpdateMainWindowLayout()
end

function addon:UpdateMinimapButtonPosition()
    if not LDBIcon or not LDBIcon:IsRegistered("GoldBid") then
        return
    end

    LDBIcon:Refresh("GoldBid", GoldBidDB.ui.minimap)
    self.minimapButton = _G["LibDBIcon10_GoldBid"]
end

function addon:CreateMinimapButton()
    self:EnsureDB()

    if not LDB or not LDBIcon then
        return nil
    end

    if not self.minimapLauncher then
        self.minimapLauncher = LDB:NewDataObject("GoldBid", {
            type = "launcher",
            icon = MINIMAP_ICON_TEXTURE,
            OnClick = function(_, mouseButton)
                if mouseButton == "RightButton" then
                    addon:ShowSettingsWindow()
                    return
                end

                addon:ToggleMainWindow()
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("GoldBid")
                tooltip:AddLine("|cffffff00ЛКМ|r: открыть/скрыть окно")
                tooltip:AddLine("|cffffff00ПКМ|r: настройки")
            end,
        })
    end

    if not LDBIcon:IsRegistered("GoldBid") then
        LDBIcon:Register("GoldBid", self.minimapLauncher, GoldBidDB.ui.minimap)
    else
        LDBIcon:Refresh("GoldBid", GoldBidDB.ui.minimap)
    end

    if GoldBidDB.ui.minimap.hide then
        LDBIcon:Hide("GoldBid")
    else
        LDBIcon:Show("GoldBid")
    end

    self.minimapButton = _G["LibDBIcon10_GoldBid"]
    return self.minimapButton
end

function addon:HandleItemDrop()
    local itemType, itemId, itemLink = GetCursorInfo()

    if itemType ~= "item" then
        return
    end

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может задать предмет аукциона.")
        ClearCursor()
        return
    end

    if self:IsAuctionActive() then
        ClearCursor()
        self:Print("Сначала завершите текущий аукцион.")
        return
    end

    self:SetPendingItem(itemLink)
    ClearCursor()
end

function addon:CreateMainWindow()
    local frame, header, itemButton, itemText, statusText, leaderText, closeButton, compactCloseButton, compactSkipButton, settingsButton
    local controlsPanel, tablesPanel, footerPanel, infoBar
    local modeLabel, modeDropDown
    local minBidBox, incrementBox, durationBox, bidBox, addStepButton
    local startButton, endButton, bidButton, passButton, syncButton, resetButton, splitMailButton
    local rows = {}
    local historyRows = {}
    local passRows = {}
    local summaryRows = {}
    local spendingRows = {}
    local lootRows = {}
    local damageRows = {}
    local splitRows = {}
    local index

    if self.frame then
        return self.frame
    end

    frame = CreateFrame("Frame", "GoldBidMainFrame", UIParent)
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(760, 520)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    createBackdrop(frame, { 0.02, 0.02, 0.04, 0.98 }, { 0.7, 0.08, 0.08, 1 })
    frame:Hide()

    header = CreateFrame("Frame", nil, frame)
    header:SetHeight(34)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    createBackdrop(header, { 0.33, 0.02, 0.02, 0.95 }, { 0.85, 0.3, 0.15, 1 })

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header.title:SetPoint("LEFT", 12, 0)
    header.title:SetText("GoldBid")

    header.byline = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.byline:SetPoint("LEFT", header.title, "RIGHT", 6, -1)
    header.byline:SetText("by monstrik")

    header.subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.subtitle:SetPoint("RIGHT", -34, 0)
    header.subtitle:SetText("GDKP аукцион")

    closeButton = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    settingsButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    settingsButton:SetSize(74, 20)
    settingsButton:SetPoint("RIGHT", header.subtitle, "LEFT", -8, 0)
    settingsButton:SetText("Экспорт")
    settingsButton:SetScript("OnClick", function()
        addon:ShowExportWindow()
    end)

    modeDropDown = CreateFrame("Frame", "GoldBidModeDropDown", header, "UIDropDownMenuTemplate")
    modeDropDown:SetPoint("RIGHT", settingsButton, "LEFT", 8, -2)
    UIDropDownMenu_SetWidth(modeDropDown, 100)
    UIDropDownMenu_SetText(modeDropDown, "GoldBid")

    modeLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeLabel:SetPoint("RIGHT", modeDropDown, "LEFT", 8, 0)
    modeLabel:SetText("Режим")

    controlsPanel = CreateFrame("Frame", nil, frame)
    controlsPanel:SetSize(736, 152)
    controlsPanel:SetPoint("TOP", 0, -58)
    controlsPanel:SetHeight(152)
    createBackdrop(controlsPanel, { 0.05, 0.05, 0.08, 0.92 }, { 0.35, 0.08, 0.08, 0.9 })

    infoBar = CreateFrame("Frame", nil, controlsPanel)
    infoBar:SetPoint("TOPLEFT", 10, -10)
    infoBar:SetPoint("TOPRIGHT", -10, -10)
    infoBar:SetHeight(22)
    createBackdrop(infoBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    leaderText = infoBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leaderText:SetPoint("LEFT", 8, 0)
    leaderText:SetWidth(280)
    leaderText:SetJustifyH("LEFT")
    leaderText:SetTextColor(0.95, 0.82, 0.28)

    statusText = infoBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("RIGHT", -8, 0)
    statusText:SetWidth(220)
    statusText:SetJustifyH("RIGHT")
    statusText:SetTextColor(0.95, 0.82, 0.28)

    compactCloseButton = CreateFrame("Button", nil, controlsPanel, "UIPanelCloseButton")
    compactCloseButton:SetPoint("TOPRIGHT", 2, 2)
    compactCloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    compactCloseButton:Hide()

    compactSkipButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    compactSkipButton:SetSize(120, 20)
    compactSkipButton:SetText("Пропустить лот")
    compactSkipButton:SetFrameLevel(compactCloseButton:GetFrameLevel())
    compactSkipButton:SetScript("OnClick", function()
        addon:ConfirmSkipAuctionLot()
    end)
    compactSkipButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("Пропустить лот")
        GameTooltip:AddLine("Скрывает окно текущего лота до появления следующего.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    compactSkipButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    compactSkipButton:Hide()

    tablesPanel = CreateFrame("Frame", nil, frame)
    tablesPanel:SetPoint("TOPLEFT", 12, -222)
    tablesPanel:SetPoint("BOTTOMRIGHT", -12, 58)
    createBackdrop(tablesPanel, { 0.04, 0.04, 0.08, 0.9 }, { 0.35, 0.08, 0.08, 0.85 })

    frame.auctionTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.auctionTabButton:SetSize(84, 22)
    frame.auctionTabButton:SetPoint("TOPLEFT", 12, -10)
    frame.auctionTabButton:SetText("Торги")
    frame.auctionTabButton:SetScript("OnClick", function()
        addon:SetMainTab("auction")
    end)

    frame.summaryTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.summaryTabButton:SetSize(84, 22)
    frame.summaryTabButton:SetPoint("LEFT", frame.auctionTabButton, "RIGHT", 8, 0)
    frame.summaryTabButton:SetText("Сводка")
    frame.summaryTabButton:SetScript("OnClick", function()
        addon:SetMainTab("summary")
    end)

    frame.spendTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.spendTabButton:SetSize(84, 22)
    frame.spendTabButton:SetPoint("LEFT", frame.summaryTabButton, "RIGHT", 8, 0)
    frame.spendTabButton:SetText("Траты")
    frame.spendTabButton:SetScript("OnClick", function()
        addon:SetMainTab("spend")
    end)

    frame.lootTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.lootTabButton:SetSize(84, 22)
    frame.lootTabButton:SetPoint("LEFT", frame.spendTabButton, "RIGHT", 8, 0)
    frame.lootTabButton:SetText("Лут")
    frame.lootTabButton:SetScript("OnClick", function()
        addon:SetMainTab("loot")
    end)

    frame.damageTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.damageTabButton:SetSize(84, 22)
    frame.damageTabButton:SetPoint("LEFT", frame.lootTabButton, "RIGHT", 8, 0)
    frame.damageTabButton:SetText("Дамаг")
    frame.damageTabButton:SetScript("OnClick", function()
        addon:SetMainTab("damage")
    end)

    frame.splitTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.splitTabButton:SetSize(84, 22)
    frame.splitTabButton:SetPoint("LEFT", frame.damageTabButton, "RIGHT", 8, 0)
    frame.splitTabButton:SetText("Делёжка")
    frame.splitTabButton:SetScript("OnClick", function()
        addon:SetMainTab("split")
    end)

    frame.auctionView = CreateFrame("Frame", nil, tablesPanel)
    frame.auctionView:SetPoint("TOPLEFT", 12, -40)
    frame.auctionView:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.summaryView = CreateFrame("Frame", nil, tablesPanel)
    frame.summaryView:SetPoint("TOPLEFT", 12, -40)
    frame.summaryView:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.spendView = CreateFrame("Frame", nil, tablesPanel)
    frame.spendView:SetPoint("TOPLEFT", 12, -40)
    frame.spendView:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.lootView = CreateFrame("Frame", nil, tablesPanel)
    frame.lootView:SetPoint("TOPLEFT", 12, -40)
    frame.lootView:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.damageView = CreateFrame("Frame", nil, tablesPanel)
    frame.damageView:SetPoint("TOPLEFT", 12, -40)
    frame.damageView:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.splitView = CreateFrame("Frame", nil, tablesPanel)
    frame.splitView:SetPoint("TOPLEFT", 12, -40)
    frame.splitView:SetPoint("BOTTOMRIGHT", -12, 12)

    footerPanel = CreateFrame("Frame", nil, frame)
    footerPanel:SetPoint("BOTTOMLEFT", 12, 12)
    footerPanel:SetPoint("BOTTOMRIGHT", -12, 12)
    footerPanel:SetHeight(36)
    createBackdrop(footerPanel, { 0.08, 0.05, 0.03, 0.92 }, { 0.35, 0.08, 0.08, 0.85 })

    frame.resizeHandle = CreateFrame("Button", nil, frame)
    frame.resizeHandle:SetSize(18, 18)
    frame.resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.resizeHandle:EnableMouse(true)
    frame.resizeHandle:RegisterForDrag("LeftButton")
    frame.resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeHandle:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    frame.resizeHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        addon:RefreshMainWindow()
    end)

    itemButton = CreateFrame("Button", nil, controlsPanel)
    itemButton:SetSize(50, 50)
    itemButton:SetPoint("TOPLEFT", 54, -44)
    itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    itemButton:RegisterForDrag("LeftButton")
    itemButton:SetScript("OnReceiveDrag", function()
        addon:HandleItemDrop()
    end)
    itemButton:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and addon:IsPlayerController() then
            addon:SetPendingItem(nil)
            return
        end

        addon:HandleItemDrop()
    end)
    createBackdrop(itemButton, { 0.1, 0.1, 0.1, 0.95 }, { 0.8, 0.35, 0.05, 1 })

    itemButton:SetScript("OnEnter", function(self)
        local link = addon.pendingItemLink or (addon.currentAuction and addon.currentAuction.itemLink)
        if link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    itemButton.icon = itemButton:CreateTexture(nil, "ARTWORK")
    itemButton.icon:SetPoint("TOPLEFT", 4, -4)
    itemButton.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    itemButton.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")

    itemText = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("TOP", itemButton, "BOTTOM", 0, -8)
    itemText:SetWidth(120)
    itemText:SetJustifyH("CENTER")
    itemText:SetText("Перетащите\nпредмет")

    frame.minBidLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.minBidLabel:SetPoint("TOPLEFT", 236, -44)
    frame.minBidLabel:SetWidth(90)
    frame.minBidLabel:SetJustifyH("CENTER")
    frame.minBidLabel:SetText("Мин ставка")

    minBidBox = CreateFrame("EditBox", nil, controlsPanel)
    minBidBox:SetPoint("TOPLEFT", frame.minBidLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(minBidBox, 90, formatGroupedInteger(addon:GetDefaultAuctionMinBid()))
    minBidBox:SetNumeric(false)
    minBidBox:SetScript("OnTextChanged", function(selfBox, userInput)
        if userInput then
            frame.minBidManualOverride = true
            addon:ApplySuggestedRaiseStepForMinBid(frame, parseNumberText(selfBox:GetText()), false)
        end
    end)
    minBidBox:SetScript("OnEnterPressed", function(selfBox)
        local value = math.max(0, parseNumberText(selfBox:GetText()) or 0)

        selfBox:SetText(formatGroupedInteger(value))
        selfBox:ClearFocus()
    end)
    minBidBox:SetScript("OnEditFocusLost", function(selfBox)
        local value = math.max(0, parseNumberText(selfBox:GetText()) or 0)

        selfBox:SetText(formatGroupedInteger(value))
    end)
    minBidBox:SetScript("OnEscapePressed", function(selfBox)
        local value = math.max(0, parseNumberText(selfBox:GetText()) or 0)

        selfBox:SetText(formatGroupedInteger(value))
        selfBox:ClearFocus()
    end)

    frame.incrementLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.incrementLabel:SetPoint("TOPLEFT", 346, -44)
    frame.incrementLabel:SetWidth(90)
    frame.incrementLabel:SetJustifyH("CENTER")
    frame.incrementLabel:SetText("Шаг")

    incrementBox = CreateFrame("EditBox", nil, controlsPanel)
    incrementBox:SetPoint("TOPLEFT", frame.incrementLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(incrementBox, 90, formatGroupedInteger(addon:GetDefaultAuctionIncrement()))
    incrementBox:SetNumeric(false)
    incrementBox:SetScript("OnTextChanged", function(selfBox, userInput)
        if userInput then
            frame.incrementManualOverride = true
        end
    end)
    incrementBox:SetScript("OnEnterPressed", function(selfBox)
        addon:NormalizeClientRaiseStep()
        selfBox:ClearFocus()
    end)
    incrementBox:SetScript("OnEditFocusLost", function()
        addon:NormalizeClientRaiseStep()
    end)
    incrementBox:SetScript("OnEscapePressed", function(selfBox)
        addon:NormalizeClientRaiseStep()
        selfBox:ClearFocus()
    end)

    frame.durationLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.durationLabel:SetPoint("TOPLEFT", 236, -86)
    frame.durationLabel:SetWidth(90)
    frame.durationLabel:SetJustifyH("CENTER")
    frame.durationLabel:SetText("Время")

    durationBox = CreateFrame("EditBox", nil, controlsPanel)
    durationBox:SetPoint("TOPLEFT", frame.durationLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(durationBox, 90, tostring(addon:GetDefaultAuctionDuration()))
    durationBox:SetScript("OnEnterPressed", function(selfBox)
        local value

        addon:EnsureAuctionState()
        value = math.max(1, tonumber(selfBox:GetText()) or addon.currentAuction.duration or addon:GetDefaultAuctionDuration())
        addon.currentAuction.duration = value
        selfBox:SetText(tostring(value))
        selfBox:ClearFocus()
    end)
    durationBox:SetScript("OnEditFocusLost", function(selfBox)
        local value

        addon:EnsureAuctionState()
        value = math.max(1, tonumber(selfBox:GetText()) or addon.currentAuction.duration or addon:GetDefaultAuctionDuration())
        addon.currentAuction.duration = value
        selfBox:SetText(tostring(value))
    end)
    durationBox:SetScript("OnEscapePressed", function(selfBox)
        addon:EnsureAuctionState()
        selfBox:SetText(tostring(addon.currentAuction.duration or addon:GetDefaultAuctionDuration()))
        selfBox:ClearFocus()
    end)

    startButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    startButton:SetSize(96, 22)
    startButton:SetPoint("TOPLEFT", 522, -48)
    startButton:SetText("Старт")
    startButton:SetScript("OnClick", function()
        addon:ConfirmOrStartAuction(
            addon.pendingItemLink or addon.currentAuction.itemLink,
            parseNumberText(minBidBox:GetText()) or addon:GetDefaultAuctionMinBid(),
            parseNumberText(incrementBox:GetText()) or addon:GetDefaultAuctionIncrement(),
            tonumber(durationBox:GetText()) or addon:GetDefaultAuctionDuration()
        )
    end)

    endButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    endButton:SetSize(96, 22)
    endButton:SetPoint("LEFT", startButton, "RIGHT", 10, 0)
    endButton:SetText("Финиш")
    endButton:SetScript("OnClick", function()
        addon:EndAuction()
    end)

    frame.bidLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.bidLabel:SetPoint("TOPLEFT", 346, -86)
    frame.bidLabel:SetWidth(90)
    frame.bidLabel:SetJustifyH("CENTER")
    frame.bidLabel:SetText("Ваша ставка")

    bidBox = CreateFrame("EditBox", nil, controlsPanel)
    bidBox:SetPoint("TOPLEFT", frame.bidLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(bidBox, 90, "0")
    bidBox:SetScript("OnTextChanged", function(selfBox, userInput)
        local typedValue

        if userInput then
            typedValue = tonumber(selfBox:GetText())

            if addon:IsAuctionActive() and not addon:IsRollAuction() and typedValue then
                frame.bidPreviewBase = addon:GetSuggestedBidBase()
                frame.bidPreviewValue = typedValue
            else
                frame.bidPreviewBase = nil
                frame.bidPreviewValue = nil
            end

            frame.bidManualOverride = true
        end
    end)

    addStepButton = CreateFrame("Button", nil, controlsPanel)
    addStepButton:SetSize(26, 26)
    addStepButton:SetPoint("LEFT", bidBox, "RIGHT", 6, 0)
    createBackdrop(addStepButton, { 0.11, 0.08, 0.02, 0.96 }, { 0.7, 0.45, 0.05, 0.95 })
    addStepButton.icon = addStepButton:CreateTexture(nil, "ARTWORK")
    addStepButton.icon:SetSize(16, 16)
    addStepButton.icon:SetPoint("CENTER", 0, 0)
    addStepButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    addStepButton:SetScript("OnClick", function()
        addon:IncrementBidAmount()
    end)
    addStepButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("Добавить шаг")
        GameTooltip:AddLine("Прибавляет значение поля 'Шаг' к текущей ставке.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    addStepButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    bidButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    bidButton:SetSize(96, 22)
    bidButton:SetPoint("TOPLEFT", 522, -82)
    bidButton:SetText("Ставка")
    bidButton:SetScript("OnClick", function()
        addon:SubmitBid(bidBox:GetText())
    end)

    passButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    passButton:SetSize(96, 22)
    passButton:SetPoint("LEFT", bidButton, "RIGHT", 10, 0)
    passButton:SetText("Пас")
    passButton:SetScript("OnClick", function()
        StaticPopup_Show("GOLDBID_PASS_CONFIRM")
    end)

    syncButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    syncButton:SetSize(96, 22)
    syncButton:SetPoint("TOPLEFT", 522, -116)
    syncButton:SetText("Синхр.")
    syncButton:SetScript("OnClick", function()
        addon:RequestSync()
    end)

    frame.settingsActionButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    frame.settingsActionButton:SetSize(96, 22)
    frame.settingsActionButton:SetPoint("LEFT", syncButton, "RIGHT", 10, 0)
    frame.settingsActionButton:SetText("Настройки")
    frame.settingsActionButton:SetScript("OnClick", function()
        addon:ShowSettingsWindow()
    end)

    frame.compactTabsBar = CreateFrame("Frame", nil, controlsPanel)
    frame.compactTabsBar:SetPoint("BOTTOMLEFT", 14, 10)
    frame.compactTabsBar:SetPoint("BOTTOMRIGHT", -14, 10)
    frame.compactTabsBar:SetHeight(24)

    frame.compactAuctionButton = CreateFrame("Button", nil, frame.compactTabsBar, "UIPanelButtonTemplate")
    frame.compactAuctionButton:SetSize(84, 22)
    frame.compactAuctionButton:SetPoint("LEFT", 0, 0)
    frame.compactAuctionButton:SetText("Торги")
    frame.compactAuctionButton:SetScript("OnClick", function()
        addon:SetMainTab("auction")
    end)

    frame.compactSummaryButton = CreateFrame("Button", nil, frame.compactTabsBar, "UIPanelButtonTemplate")
    frame.compactSummaryButton:SetSize(84, 22)
    frame.compactSummaryButton:SetPoint("LEFT", frame.compactAuctionButton, "RIGHT", 8, 0)
    frame.compactSummaryButton:SetText("Сводка")
    frame.compactSummaryButton:SetScript("OnClick", function()
        addon:SetMainTab("summary")
    end)

    frame.compactPotText = frame.compactTabsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.compactPotText:SetPoint("RIGHT", -4, 0)
    frame.compactPotText:SetWidth(260)
    frame.compactPotText:SetJustifyH("RIGHT")
    frame.compactPotText:SetTextColor(0.95, 0.82, 0.28)

    frame.tableHeader = CreateFrame("Frame", nil, frame.auctionView)
    frame.tableHeader:SetHeight(24)
    frame.tableHeader:SetPoint("TOPLEFT", 0, 0)
    frame.tableHeader:SetWidth(340)
    createBackdrop(frame.tableHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.tableHeader.rank = frame.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.tableHeader.rank:SetPoint("LEFT", 12, 0)
    frame.tableHeader.rank:SetText("#")

    frame.tableHeader.player = frame.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.tableHeader.player:SetPoint("LEFT", 52, 0)
    frame.tableHeader.player:SetText("Игрок")

    frame.tableHeader.amount = frame.tableHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.tableHeader.amount:SetPoint("RIGHT", -16, 0)
    frame.tableHeader.amount:SetText("Ставка")

    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, frame.auctionView)

        row:SetHeight(24)
        row:SetPoint("TOPLEFT", frame.tableHeader, "BOTTOMLEFT", 0, -((index - 1) * 26) - 6)
        row:SetPoint("TOPRIGHT", frame.tableHeader, "BOTTOMRIGHT", 0, -((index - 1) * 26) - 6)
        createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.rank:SetPoint("LEFT", 12, 0)
        row.rank:SetWidth(24)
        row.rank:SetJustifyH("LEFT")

        row.player = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.player:SetPoint("LEFT", 52, 0)
        row.player:SetWidth(220)
        row.player:SetJustifyH("LEFT")

        row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.amount:SetPoint("RIGHT", -16, 0)
        row.amount:SetWidth(90)
        row.amount:SetJustifyH("RIGHT")

        rows[index] = row
    end

    frame.passHeader = CreateFrame("Frame", nil, frame.auctionView)
    frame.passHeader:SetSize(140, 24)
    frame.passHeader:SetPoint("TOPLEFT", frame.tableHeader, "TOPRIGHT", 12, 0)
    createBackdrop(frame.passHeader, { 0.2, 0.02, 0.02, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.passHeader.title = frame.passHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.passHeader.title:SetPoint("CENTER", 0, 0)
    frame.passHeader.title:SetText("ПАС")

    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, frame.auctionView)

        row:SetSize(140, 24)
        row:SetPoint("TOPLEFT", frame.passHeader, "BOTTOMLEFT", 0, -((index - 1) * 26) - 6)
        createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 10, 0)
        row.name:SetWidth(118)
        row.name:SetJustifyH("LEFT")

        passRows[index] = row
    end

    frame.historyHeader = CreateFrame("Frame", nil, frame.auctionView)
    frame.historyHeader:SetSize(200, 24)
    frame.historyHeader:SetPoint("TOPLEFT", frame.passHeader, "TOPRIGHT", 12, 0)
    createBackdrop(frame.historyHeader, { 0.2, 0.02, 0.02, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.historyHeader.title = frame.historyHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.historyHeader.title:SetPoint("CENTER", 0, 0)
    frame.historyHeader.title:SetText("Продажи")

    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, frame.auctionView)

        row:SetSize(200, 24)
        row:SetPoint("TOPLEFT", frame.historyHeader, "BOTTOMLEFT", 0, -((index - 1) * 26) - 6)
        createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

        row.item = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.item:SetPoint("LEFT", 10, 0)
        row.item:SetWidth(180)
        row.item:SetJustifyH("LEFT")

        historyRows[index] = row
    end

    frame.summaryStatsBar = CreateFrame("Frame", nil, frame.summaryView)
    frame.summaryStatsBar:SetPoint("TOPLEFT", 0, 0)
    frame.summaryStatsBar:SetPoint("TOPRIGHT", 0, 0)
    frame.summaryStatsBar:SetHeight(28)
    createBackdrop(frame.summaryStatsBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    frame.summaryPotText = frame.summaryStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.summaryPotText:SetPoint("LEFT", 10, 0)
    frame.summaryPotText:SetWidth(220)
    frame.summaryPotText:SetJustifyH("LEFT")
    frame.summaryPotText:SetTextColor(0.95, 0.82, 0.28)

    frame.summaryLotsText = frame.summaryStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.summaryLotsText:SetPoint("CENTER", 0, 0)
    frame.summaryLotsText:SetWidth(180)
    frame.summaryLotsText:SetJustifyH("CENTER")
    frame.summaryLotsText:SetTextColor(0.95, 0.82, 0.28)

    frame.summarySplitText = frame.summaryStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.summarySplitText:SetPoint("RIGHT", -10, 0)
    frame.summarySplitText:SetWidth(220)
    frame.summarySplitText:SetJustifyH("RIGHT")
    frame.summarySplitText:SetTextColor(0.95, 0.82, 0.28)

    frame.summaryHeader = CreateFrame("Frame", nil, frame.summaryView)
    frame.summaryHeader:SetPoint("TOPLEFT", frame.summaryStatsBar, "BOTTOMLEFT", 0, -8)
    frame.summaryHeader:SetPoint("TOPRIGHT", frame.summaryStatsBar, "BOTTOMRIGHT", 0, -8)
    frame.summaryHeader:SetHeight(24)
    createBackdrop(frame.summaryHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.summaryHeader.index = frame.summaryHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryHeader.index:SetPoint("LEFT", 12, 0)
    frame.summaryHeader.index:SetText("#")

    frame.summaryHeader.item = frame.summaryHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryHeader.item:SetPoint("LEFT", 42, 0)
    frame.summaryHeader.item:SetText("Лот")

    frame.summaryHeader.winner = frame.summaryHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryHeader.winner:SetPoint("LEFT", 430, 0)
    frame.summaryHeader.winner:SetText("Кому ушёл")

    frame.summaryHeader.amount = frame.summaryHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryHeader.amount:SetPoint("RIGHT", -18, 0)
    frame.summaryHeader.amount:SetText("Цена")

    frame.summaryListPanel = CreateFrame("Frame", nil, frame.summaryView)
    frame.summaryListPanel:SetPoint("TOPLEFT", frame.summaryHeader, "BOTTOMLEFT", 0, -6)
    frame.summaryListPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    createBackdrop(frame.summaryListPanel, { 0.05, 0.05, 0.08, 0.75 }, { 0.25, 0.08, 0.08, 0.8 })

    frame.summaryScrollFrame = CreateFrame("ScrollFrame", "GoldBidSummaryScrollFrame", frame.summaryListPanel, "UIPanelScrollFrameTemplate")
    frame.summaryScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.summaryScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    frame.summaryContent = CreateFrame("Frame", nil, frame.summaryScrollFrame)
    frame.summaryContent:SetWidth(620)
    frame.summaryContent:SetHeight(1)
    frame.summaryScrollFrame:SetScrollChild(frame.summaryContent)

    frame.summaryEmptyText = frame.summaryContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summaryEmptyText:SetPoint("TOPLEFT", 12, -10)
    frame.summaryEmptyText:SetText("Продаж пока нет")

    frame.spendStatsBar = CreateFrame("Frame", nil, frame.spendView)
    frame.spendStatsBar:SetPoint("TOPLEFT", 0, 0)
    frame.spendStatsBar:SetPoint("TOPRIGHT", 0, 0)
    frame.spendStatsBar:SetHeight(28)
    createBackdrop(frame.spendStatsBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    frame.spendTotalText = frame.spendStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.spendTotalText:SetPoint("LEFT", 10, 0)
    frame.spendTotalText:SetWidth(220)
    frame.spendTotalText:SetJustifyH("LEFT")
    frame.spendTotalText:SetTextColor(0.95, 0.82, 0.28)

    frame.spendBuyersText = frame.spendStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.spendBuyersText:SetPoint("CENTER", 0, 0)
    frame.spendBuyersText:SetWidth(180)
    frame.spendBuyersText:SetJustifyH("CENTER")
    frame.spendBuyersText:SetTextColor(0.95, 0.82, 0.28)

    frame.spendLotsText = frame.spendStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.spendLotsText:SetPoint("RIGHT", -10, 0)
    frame.spendLotsText:SetWidth(220)
    frame.spendLotsText:SetJustifyH("RIGHT")
    frame.spendLotsText:SetTextColor(0.95, 0.82, 0.28)

    frame.spendHeader = CreateFrame("Frame", nil, frame.spendView)
    frame.spendHeader:SetPoint("TOPLEFT", frame.spendStatsBar, "BOTTOMLEFT", 0, -8)
    frame.spendHeader:SetPoint("TOPRIGHT", frame.spendStatsBar, "BOTTOMRIGHT", 0, -8)
    frame.spendHeader:SetHeight(24)
    createBackdrop(frame.spendHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.spendHeader.index = frame.spendHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spendHeader.index:SetPoint("LEFT", 12, 0)
    frame.spendHeader.index:SetText("#")

    frame.spendHeader.player = frame.spendHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spendHeader.player:SetPoint("LEFT", 42, 0)
    frame.spendHeader.player:SetText("Игрок")

    frame.spendHeader.guild = frame.spendHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spendHeader.guild:SetText("Гильдия")

    frame.spendHeader.lots = frame.spendHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spendHeader.lots:SetWidth(70)
    frame.spendHeader.lots:SetJustifyH("CENTER")
    frame.spendHeader.lots:SetText("Лотов")

    frame.spendHeader.amount = frame.spendHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.spendHeader.amount:SetPoint("RIGHT", -18, 0)
    frame.spendHeader.amount:SetText("Потратил")

    frame.spendListPanel = CreateFrame("Frame", nil, frame.spendView)
    frame.spendListPanel:SetPoint("TOPLEFT", frame.spendHeader, "BOTTOMLEFT", 0, -6)
    frame.spendListPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    createBackdrop(frame.spendListPanel, { 0.05, 0.05, 0.08, 0.75 }, { 0.25, 0.08, 0.08, 0.8 })

    frame.spendScrollFrame = CreateFrame("ScrollFrame", "GoldBidSpendScrollFrame", frame.spendListPanel, "UIPanelScrollFrameTemplate")
    frame.spendScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.spendScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    frame.spendContent = CreateFrame("Frame", nil, frame.spendScrollFrame)
    frame.spendContent:SetWidth(620)
    frame.spendContent:SetHeight(1)
    frame.spendScrollFrame:SetScrollChild(frame.spendContent)

    frame.spendEmptyText = frame.spendContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.spendEmptyText:SetPoint("TOPLEFT", 12, -10)
    frame.spendEmptyText:SetText("Покупок пока нет")

    frame.lootStatsBar = CreateFrame("Frame", nil, frame.lootView)
    frame.lootStatsBar:SetPoint("TOPLEFT", 0, 0)
    frame.lootStatsBar:SetPoint("TOPRIGHT", 0, 0)
    frame.lootStatsBar:SetHeight(28)
    createBackdrop(frame.lootStatsBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    frame.lootTotalText = frame.lootStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lootTotalText:SetPoint("LEFT", 10, 0)
    frame.lootTotalText:SetWidth(220)
    frame.lootTotalText:SetJustifyH("LEFT")
    frame.lootTotalText:SetTextColor(0.95, 0.82, 0.28)

    frame.lootBossText = frame.lootStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lootBossText:SetPoint("CENTER", 0, 0)
    frame.lootBossText:SetWidth(180)
    frame.lootBossText:SetJustifyH("CENTER")
    frame.lootBossText:SetTextColor(0.95, 0.82, 0.28)

    frame.lootUrgentText = frame.lootStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lootUrgentText:SetPoint("RIGHT", -10, 0)
    frame.lootUrgentText:SetWidth(220)
    frame.lootUrgentText:SetJustifyH("RIGHT")
    frame.lootUrgentText:SetTextColor(0.95, 0.82, 0.28)

    frame.lootHeader = CreateFrame("Frame", nil, frame.lootView)
    frame.lootHeader:SetPoint("TOPLEFT", frame.lootStatsBar, "BOTTOMLEFT", 0, -8)
    frame.lootHeader:SetPoint("TOPRIGHT", frame.lootStatsBar, "BOTTOMRIGHT", 0, -8)
    frame.lootHeader:SetHeight(24)
    createBackdrop(frame.lootHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.lootHeader.item = frame.lootHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lootHeader.item:SetPoint("LEFT", 40, 0)
    frame.lootHeader.item:SetText("Лут")

    frame.lootHeader.time = frame.lootHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lootHeader.time:SetText("Осталось")

    frame.lootHeader.action = frame.lootHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lootHeader.action:SetText("В слот")

    frame.lootListPanel = CreateFrame("Frame", nil, frame.lootView)
    frame.lootListPanel:SetPoint("TOPLEFT", frame.lootHeader, "BOTTOMLEFT", 0, -6)
    frame.lootListPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    createBackdrop(frame.lootListPanel, { 0.05, 0.05, 0.08, 0.75 }, { 0.25, 0.08, 0.08, 0.8 })

    frame.lootScrollFrame = CreateFrame("ScrollFrame", "GoldBidLootScrollFrame", frame.lootListPanel, "UIPanelScrollFrameTemplate")
    frame.lootScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.lootScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    frame.lootContent = CreateFrame("Frame", nil, frame.lootScrollFrame)
    frame.lootContent:SetWidth(620)
    frame.lootContent:SetHeight(1)
    frame.lootScrollFrame:SetScrollChild(frame.lootContent)

    frame.lootEmptyText = frame.lootContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.lootEmptyText:SetPoint("TOPLEFT", 12, -10)
    frame.lootEmptyText:SetText("Лут пока не отслежен")

    frame.damageStatsBar = CreateFrame("Frame", nil, frame.damageView)
    frame.damageStatsBar:SetPoint("TOPLEFT", 0, 0)
    frame.damageStatsBar:SetPoint("TOPRIGHT", 0, 0)
    frame.damageStatsBar:SetHeight(32)
    createBackdrop(frame.damageStatsBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    frame.damageBossLabel = frame.damageStatsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageBossLabel:SetPoint("LEFT", 10, 0)
    frame.damageBossLabel:SetText("Босс")

    frame.damageDropDown = CreateFrame("Frame", "GoldBidDamageDropDown", frame.damageStatsBar, "UIDropDownMenuTemplate")
    frame.damageDropDown:SetPoint("LEFT", frame.damageBossLabel, "RIGHT", -6, -3)
    UIDropDownMenu_SetWidth(frame.damageDropDown, 210)
    UIDropDownMenu_SetText(frame.damageDropDown, "Выберите босса")

    frame.damagePlayersText = frame.damageStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.damagePlayersText:SetWidth(90)
    frame.damagePlayersText:SetJustifyH("RIGHT")
    frame.damagePlayersText:SetTextColor(0.95, 0.82, 0.28)

    frame.damageTimeText = frame.damageStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.damageTimeText:SetWidth(100)
    frame.damageTimeText:SetJustifyH("RIGHT")
    frame.damageTimeText:SetTextColor(0.95, 0.82, 0.28)

    frame.damageTotalText = frame.damageStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.damageTotalText:SetWidth(160)
    frame.damageTotalText:SetJustifyH("RIGHT")
    frame.damageTotalText:SetTextColor(0.95, 0.82, 0.28)

    frame.damageHeader = CreateFrame("Frame", nil, frame.damageView)
    frame.damageHeader:SetPoint("TOPLEFT", frame.damageStatsBar, "BOTTOMLEFT", 0, -8)
    frame.damageHeader:SetPoint("TOPRIGHT", frame.damageStatsBar, "BOTTOMRIGHT", 0, -8)
    frame.damageHeader:SetHeight(24)
    createBackdrop(frame.damageHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.damageHeader.index = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.index:SetPoint("LEFT", 12, 0)
    frame.damageHeader.index:SetText("#")

    frame.damageHeader.player = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.player:SetText("Игрок")

    frame.damageHeader.class = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.class:SetText("Спек")

    frame.damageHeader.amount = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.amount:SetText("Урон")

    frame.damageHeader.dps = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.dps:SetText("DPS")

    frame.damageHeader.percent = frame.damageHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.damageHeader.percent:SetText("%")

    frame.damageListPanel = CreateFrame("Frame", nil, frame.damageView)
    frame.damageListPanel:SetPoint("TOPLEFT", frame.damageHeader, "BOTTOMLEFT", 0, -6)
    frame.damageListPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    createBackdrop(frame.damageListPanel, { 0.05, 0.05, 0.08, 0.75 }, { 0.25, 0.08, 0.08, 0.8 })

    frame.damageScrollFrame = CreateFrame("ScrollFrame", "GoldBidDamageScrollFrame", frame.damageListPanel, "UIPanelScrollFrameTemplate")
    frame.damageScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.damageScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    frame.damageContent = CreateFrame("Frame", nil, frame.damageScrollFrame)
    frame.damageContent:SetWidth(620)
    frame.damageContent:SetHeight(1)
    frame.damageScrollFrame:SetScrollChild(frame.damageContent)

    frame.damageEmptyText = frame.damageContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.damageEmptyText:SetPoint("TOPLEFT", 12, -10)
    frame.damageEmptyText:SetText("Вкладка требует аддон Details")

    frame.splitStatsBar = CreateFrame("Frame", nil, frame.splitView)
    frame.splitStatsBar:SetPoint("TOPLEFT", 0, 0)
    frame.splitStatsBar:SetPoint("TOPRIGHT", 0, 0)
    frame.splitStatsBar:SetHeight(30)
    createBackdrop(frame.splitStatsBar, { 0.12, 0.03, 0.03, 0.88 }, { 0.45, 0.1, 0.1, 0.8 })

    frame.splitGrossText = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.splitGrossText:SetPoint("LEFT", 10, 0)
    frame.splitGrossText:SetWidth(210)
    frame.splitGrossText:SetJustifyH("LEFT")
    frame.splitGrossText:SetTextColor(0.95, 0.82, 0.28)
    frame.splitGrossText:Hide()

    frame.splitLeaderPercentLabel = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitLeaderPercentLabel:SetPoint("LEFT", 228, 0)
    frame.splitLeaderPercentLabel:SetText("Доля РЛ %")
    frame.splitLeaderPercentLabel:Hide()

    frame.splitLeaderPercentBox = CreateFrame("EditBox", nil, frame.splitStatsBar)
    frame.splitLeaderPercentBox:SetPoint("LEFT", frame.splitLeaderPercentLabel, "RIGHT", 8, 0)
    setupInputBox(frame.splitLeaderPercentBox, 48, "20")
    frame.splitLeaderPercentBox:SetScript("OnEnterPressed", function(selfBox)
        addon:SetLeaderSharePercent(selfBox:GetText())
        selfBox:ClearFocus()
    end)
    frame.splitLeaderPercentBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    frame.splitLeaderPercentBox:SetScript("OnEditFocusLost", function(selfBox)
        addon:SetLeaderSharePercent(selfBox:GetText())
    end)
    frame.splitLeaderPercentBox:Hide()

    frame.splitLeaderShareText = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.splitLeaderShareText:SetPoint("LEFT", 10, 0)
    frame.splitLeaderShareText:SetWidth(220)
    frame.splitLeaderShareText:SetJustifyH("LEFT")
    frame.splitLeaderShareText:SetTextColor(0.95, 0.82, 0.28)
    frame.splitLeaderShareText:Hide()

    frame.splitBaseText = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.splitBaseText:SetPoint("RIGHT", -10, 0)
    frame.splitBaseText:SetWidth(190)
    frame.splitBaseText:SetJustifyH("RIGHT")
    frame.splitBaseText:SetTextColor(0.95, 0.82, 0.28)
    frame.splitBaseText:Hide()

    frame.splitHeader = CreateFrame("Frame", nil, frame.splitView)
    frame.splitHeader:SetPoint("TOPLEFT", frame.splitStatsBar, "BOTTOMLEFT", 0, -8)
    frame.splitHeader:SetPoint("TOPRIGHT", frame.splitStatsBar, "BOTTOMRIGHT", 0, -8)
    frame.splitHeader:SetHeight(24)
    createBackdrop(frame.splitHeader, { 0.18, 0.03, 0.03, 0.95 }, { 0.55, 0.1, 0.1, 1 })

    frame.splitHeader.index = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.index:SetPoint("LEFT", 10, 0)
    frame.splitHeader.index:SetWidth(18)
    frame.splitHeader.index:SetJustifyH("CENTER")
    frame.splitHeader.index:SetText("#")
    frame.splitHeader.index:Hide()

    frame.splitHeader.player = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.player:SetPoint("LEFT", 8, 0)
    frame.splitHeader.player:SetWidth(118)
    frame.splitHeader.player:SetJustifyH("CENTER")
    frame.splitHeader.player:SetText("Игрок")

    frame.splitHeader.spec = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.spec:SetPoint("LEFT", 130, 0)
    frame.splitHeader.spec:SetWidth(72)
    frame.splitHeader.spec:SetJustifyH("CENTER")
    frame.splitHeader.spec:SetText("Спек")

    frame.splitHeader.role = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.role:SetPoint("LEFT", 208, 0)
    frame.splitHeader.role:SetWidth(54)
    frame.splitHeader.role:SetJustifyH("CENTER")
    frame.splitHeader.role:SetText("Роль")

    frame.splitHeader.percent = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.percent:SetPoint("LEFT", 268, 0)
    frame.splitHeader.percent:SetWidth(50)
    frame.splitHeader.percent:SetJustifyH("CENTER")
    frame.splitHeader.percent:SetText("%")

    frame.splitHeader.penaltyNote = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.penaltyNote:SetPoint("LEFT", 320, 0)
    frame.splitHeader.penaltyNote:SetWidth(70)
    frame.splitHeader.penaltyNote:SetJustifyH("CENTER")
    frame.splitHeader.penaltyNote:SetText("Косяки")

    frame.splitHeader.bonusNote = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.bonusNote:SetPoint("LEFT", 398, 0)
    frame.splitHeader.bonusNote:SetWidth(70)
    frame.splitHeader.bonusNote:SetJustifyH("CENTER")
    frame.splitHeader.bonusNote:SetText("Плюсики")

    frame.splitHeader.debt = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.debt:SetPoint("LEFT", 520, 0)
    frame.splitHeader.debt:SetWidth(60)
    frame.splitHeader.debt:SetJustifyH("CENTER")
    frame.splitHeader.debt:SetText("Долг")

    frame.splitHeader.net = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.net:SetPoint("RIGHT", -18, 0)
    frame.splitHeader.net:SetWidth(72)
    frame.splitHeader.net:SetJustifyH("CENTER")
    frame.splitHeader.net:SetText("К выплате")

    frame.splitListPanel = CreateFrame("Frame", nil, frame.splitView)
    frame.splitListPanel:SetPoint("TOPLEFT", frame.splitHeader, "BOTTOMLEFT", 0, -6)
    frame.splitListPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    createBackdrop(frame.splitListPanel, { 0.05, 0.05, 0.08, 0.75 }, { 0.25, 0.08, 0.08, 0.8 })

    frame.splitScrollFrame = CreateFrame("ScrollFrame", "GoldBidSplitScrollFrame", frame.splitListPanel, "UIPanelScrollFrameTemplate")
    frame.splitScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.splitScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    frame.splitContent = CreateFrame("Frame", nil, frame.splitScrollFrame)
    frame.splitContent:SetWidth(648)
    frame.splitContent:SetHeight(1)
    frame.splitScrollFrame:SetScrollChild(frame.splitContent)

    frame.splitEmptyText = frame.splitContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.splitEmptyText:SetPoint("TOPLEFT", 12, -10)
    frame.splitEmptyText:SetText("Соберите группу или рейд для расчёта делёжки")

    resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetButton:SetSize(90, 24)
    resetButton:SetPoint("LEFT", footerPanel, "LEFT", 12, 0)
    resetButton:SetText("Сброс")
    resetButton:SetScript("OnClick", function()
        if not addon:IsPlayerController() and (UnitInRaid("player") or GetNumPartyMembers() > 0) then
            addon:Print("Только мастер лутер может сбросить данные рейда.")
            return
        end

        StaticPopup_Show("GOLDBID_RESET_CONFIRM")
    end)

    splitMailButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    splitMailButton:SetSize(132, 22)
    splitMailButton:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)
    splitMailButton:SetText("Раздать почтой")
    splitMailButton:SetScript("OnClick", function()
        addon:StartMailPayout(false)
    end)
    splitMailButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("Почтовая раздача")
        GameTooltip:AddLine("Автозаполняет получателя и сумму", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("После отправки письма готовит следующего", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    splitMailButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footerText:SetPoint("RIGHT", footerPanel, "RIGHT", -12, 0)
    frame.footerText:SetJustifyH("RIGHT")
    frame.footerText:SetText("ПКМ по слоту для очистки")

    frame.header = header
    frame.closeButton = closeButton
    frame.compactCloseButton = compactCloseButton
    frame.compactSkipButton = compactSkipButton
    frame.settingsButton = settingsButton
    frame.leaderText = leaderText
    frame.statusText = statusText
    frame.itemButton = itemButton
    frame.itemText = itemText
    frame.infoBar = infoBar
    frame.controlsPanel = controlsPanel
    frame.tablesPanel = tablesPanel
    frame.footerPanel = footerPanel
    frame.minBidBox = minBidBox
    frame.incrementBox = incrementBox
    frame.durationBox = durationBox
    frame.bidBox = bidBox
    frame.addStepButton = addStepButton
    frame.modeLabel = modeLabel
    frame.modeDropDown = modeDropDown
    frame.startButton = startButton
    frame.endButton = endButton
    frame.bidButton = bidButton
    frame.passButton = passButton
    frame.syncButton = syncButton
    frame.exportButton = settingsButton
    frame.payoutButton = nil
    frame.mailPayoutButton = splitMailButton
    frame.resetButton = resetButton
    frame.rows = rows
    frame.passRows = passRows
    frame.historyRows = historyRows
    frame.summaryRows = summaryRows
    frame.spendingRows = spendingRows
    frame.lootRows = lootRows
    frame.damageRows = damageRows
    frame.splitRows = splitRows

    self.frame = frame
    self:SetMainTab("auction")
    return frame
end

function addon:ShowMainWindow(force)
    local frame = self:CreateMainWindow()

    if not force and not frame:IsShown() and not self:HasFullInterfaceAccess() and self:IsAuctionWindowSuppressed() then
        return frame
    end

    if not frame:IsShown() then
        if self:HasFullInterfaceAccess() then
            frame.compactSectionOpen = true
            frame.activeTab = frame.activeTab or "auction"
        else
            frame.compactSectionOpen = false
            frame.activeTab = frame.activeTab or "auction"
        end
    end

    frame:Show()
    self:UpdateMainWindowLayout()
    self:RefreshMainWindow()
end

function addon:RefreshSplitView(frame)
    local split = self:ComputeDetailedSplit()
    local sourceRows = split and split.rows or {}
    local rows = {}
    local canEdit = self:IsPlayerController()
    local contentWidth = math.max(648, math.floor(((frame.splitListPanel and frame.splitListPanel:GetWidth()) or 684) - 36))
    local indexLeft = 10
    local indexWidth = 18
    local playerLeft = 8
    local playerWidth = 104
    local specLeft = 118
    local specWidth = 66
    local roleLeft = 190
    local roleWidth = 46
    local percentLeft = 242
    local percentWidth = 50
    local debtWidth = 60
    local netWidth = 60
    local sentWidth = 24
    local toggleWidth = 34
    local presetWidth = 20
    local sentLeft = contentWidth - sentWidth - 18
    local netLeft = sentLeft - 8 - netWidth
    local debtLeft = netLeft - 8 - debtWidth
    local toggleLeft = debtLeft - 8 - toggleWidth
    local notesStartLeft = percentLeft + percentWidth + 8
    local noteAreaWidth = math.max(90, toggleLeft - notesStartLeft - 8)
    local noteColumnWidth = math.max(40, math.floor((noteAreaWidth - presetWidth * 2 - 10) / 2))
    local penaltyNoteLeft = notesStartLeft
    local penaltyButtonLeft = penaltyNoteLeft + noteColumnWidth + 2
    local bonusNoteLeft = penaltyButtonLeft + presetWidth + 6
    local bonusButtonLeft = bonusNoteLeft + noteColumnWidth + 2
    local rowCount
    local insertedSubstitutesHeader = false
    local index

    for index = 1, table.getn(sourceRows) do
        local data = sourceRows[index]

        if data.isSubstitute and not insertedSubstitutesHeader then
            table.insert(rows, {
                separator = true,
                title = "Замены",
            })
            insertedSubstitutesHeader = true
        end

        table.insert(rows, data)
    end

    rowCount = table.getn(rows)
    frame.splitContent:SetWidth(contentWidth)

    if not frame.splitLeaderPercentBox:HasFocus() then
        frame.splitLeaderPercentBox:SetText("0")
    end

    frame.splitLeaderPercentBox:EnableMouse(false)
    frame.splitLeaderPercentLabel:Hide()
    frame.splitLeaderPercentBox:Hide()
    frame.splitGrossText:SetText("")
    frame.splitLeaderShareText:SetText("")
    frame.splitBaseText:SetText("")
    frame.splitEmptyText:SetShown(rowCount == 0)

    if frame.mailPayoutButton then
        frame.mailPayoutButton:SetShown(canEdit and frame.activeTab == "split")
        frame.mailPayoutButton:SetEnabled(canEdit)
        frame.mailPayoutButton:SetText(self:GetMailPayoutButtonText())
    end

    frame.splitHeader.index:ClearAllPoints()
    frame.splitHeader.index:SetPoint("LEFT", indexLeft, 0)
    frame.splitHeader.index:SetWidth(indexWidth)
    frame.splitHeader.index:SetJustifyH("CENTER")
    frame.splitHeader.index:Hide()

    frame.splitHeader.player:ClearAllPoints()
    frame.splitHeader.player:SetPoint("LEFT", playerLeft, 0)
    frame.splitHeader.player:SetWidth(playerWidth)
    frame.splitHeader.player:SetJustifyH("CENTER")

    frame.splitHeader.spec:ClearAllPoints()
    frame.splitHeader.spec:SetPoint("LEFT", specLeft, 0)
    frame.splitHeader.spec:SetWidth(specWidth)
    frame.splitHeader.spec:SetJustifyH("CENTER")

    frame.splitHeader.role:ClearAllPoints()
    frame.splitHeader.role:SetPoint("LEFT", roleLeft, 0)
    frame.splitHeader.role:SetWidth(roleWidth)
    frame.splitHeader.role:SetJustifyH("CENTER")

    frame.splitHeader.percent:ClearAllPoints()
    frame.splitHeader.percent:SetPoint("LEFT", percentLeft, 0)
    frame.splitHeader.percent:SetWidth(percentWidth)
    frame.splitHeader.percent:SetJustifyH("CENTER")

    frame.splitHeader.penaltyNote:ClearAllPoints()
    frame.splitHeader.penaltyNote:SetPoint("LEFT", penaltyNoteLeft, 0)
    frame.splitHeader.penaltyNote:SetWidth(noteColumnWidth)
    frame.splitHeader.penaltyNote:SetJustifyH("CENTER")

    frame.splitHeader.bonusNote:ClearAllPoints()
    frame.splitHeader.bonusNote:SetPoint("LEFT", bonusNoteLeft, 0)
    frame.splitHeader.bonusNote:SetWidth(noteColumnWidth)
    frame.splitHeader.bonusNote:SetJustifyH("CENTER")

    frame.splitHeader.debt:ClearAllPoints()
    frame.splitHeader.debt:SetPoint("LEFT", debtLeft, 0)
    frame.splitHeader.debt:SetWidth(debtWidth)
    frame.splitHeader.debt:SetJustifyH("CENTER")

    frame.splitHeader.net:ClearAllPoints()
    frame.splitHeader.net:SetPoint("LEFT", netLeft, 0)
    frame.splitHeader.net:SetWidth(netWidth)
    frame.splitHeader.net:SetJustifyH("CENTER")

    if not frame.splitHeader.sent then
        frame.splitHeader.sent = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.splitHeader.sent:SetText("OK")
    end

    frame.splitHeader.sent:ClearAllPoints()
    frame.splitHeader.sent:SetPoint("LEFT", sentLeft, 0)
    frame.splitHeader.sent:SetWidth(sentWidth)
    frame.splitHeader.sent:SetJustifyH("CENTER")

    for index = 1, rowCount do
        local data = rows[index]
        local row = frame.splitRows[index]

        if not row then
            row = CreateFrame("Frame", nil, frame.splitContent)
            row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
            createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

            row.separatorLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.separatorLabel:SetPoint("LEFT", 12, 0)
            row.separatorLabel:SetWidth(220)
            row.separatorLabel:SetJustifyH("LEFT")
            row.separatorLabel:SetTextColor(0.95, 0.82, 0.28)

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.index:SetPoint("LEFT", indexLeft, 0)
            row.index:SetWidth(indexWidth)
            row.index:SetJustifyH("CENTER")
            row.index:Hide()

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("LEFT", playerLeft, 0)
            row.name:SetWidth(playerWidth)
            row.name:SetJustifyH("CENTER")

            row.spec = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.spec:SetPoint("LEFT", specLeft, 0)
            row.spec:SetWidth(specWidth)
            row.spec:SetJustifyH("CENTER")
            row.spec:SetTextColor(0.95, 0.82, 0.28)

            row.roleBox = CreateFrame("EditBox", nil, row)
            row.roleBox:SetPoint("LEFT", roleLeft, 0)
            setupTextBox(row.roleBox, roleWidth, "")
            row.roleBox:SetJustifyH("CENTER")
            row.roleBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "role", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.roleBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
            end)
            row.roleBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "role", selfBox:GetText())
            end)

            row.percentBox = CreateFrame("EditBox", nil, row)
            row.percentBox:SetPoint("LEFT", percentLeft, 0)
            setupInputBox(row.percentBox, 50, "100")
            row.percentBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "percent", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.percentBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
            end)
            row.percentBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "percent", selfBox:GetText())
            end)

            row.penaltyNoteBox = CreateFrame("EditBox", nil, row)
            row.penaltyNoteBox:SetPoint("LEFT", penaltyNoteLeft, 0)
            setupTextBox(row.penaltyNoteBox, noteColumnWidth, "")
            row.penaltyNoteBox:SetJustifyH("LEFT")
            row.penaltyNoteBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "penaltyNote", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.penaltyNoteBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
                if selfBox.SetCursorPosition then
                    selfBox:SetCursorPosition(0)
                end
            end)
            row.penaltyNoteBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "penaltyNote", selfBox:GetText())
                if selfBox.SetCursorPosition then
                    selfBox:SetCursorPosition(0)
                end
            end)

            row.penaltyButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.penaltyButton, 20, 18, "-")
            row.penaltyButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.penaltyButton:SetScript("OnClick", function()
                addon:ApplySplitPreset(row.playerName, "penalty")
            end)

            row.bonusNoteBox = CreateFrame("EditBox", nil, row)
            row.bonusNoteBox:SetPoint("LEFT", bonusNoteLeft, 0)
            setupTextBox(row.bonusNoteBox, noteColumnWidth, "")
            row.bonusNoteBox:SetJustifyH("LEFT")
            row.bonusNoteBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "bonusNote", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.bonusNoteBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
                if selfBox.SetCursorPosition then
                    selfBox:SetCursorPosition(0)
                end
            end)
            row.bonusNoteBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "bonusNote", selfBox:GetText())
                if selfBox.SetCursorPosition then
                    selfBox:SetCursorPosition(0)
                end
            end)

            row.bonusButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.bonusButton, 20, 18, "+")
            row.bonusButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.bonusButton:SetScript("OnClick", function()
                addon:ApplySplitPreset(row.playerName, "bonus")
            end)

            row.modeButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.modeButton, toggleWidth, 18, "Зам")
            row.modeButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.modeButton:SetScript("OnClick", function()
                addon:ApplySplitPreset(row.playerName, row.isSubstitute and "main" or "substitute")
            end)

            row.debtBox = CreateFrame("EditBox", nil, row)
            row.debtBox:SetPoint("LEFT", debtLeft, 0)
            setupInputBox(row.debtBox, 60, "0")
            row.debtBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "debt", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.debtBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
            end)
            row.debtBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "debt", selfBox:GetText())
            end)

            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.net:SetPoint("LEFT", netLeft, 0)
            row.net:SetWidth(netWidth)
            row.net:SetJustifyH("CENTER")

            row.sentCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.sentCheck:SetSize(18, 18)
            row.sentCheck:EnableMouse(false)
            if row.sentCheck.SetDisabledCheckedTexture then
                row.sentCheck:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            end

            local sentTexture = nil

            if row.sentCheck.GetCheckedTexture then
                sentTexture = row.sentCheck:GetCheckedTexture()
            end

            if sentTexture and sentTexture.SetVertexColor then
                sentTexture:SetVertexColor(0.15, 1, 0.15)
            end

            frame.splitRows[index] = row
        end

        row:SetSize(contentWidth, data.separator and 20 or 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))

        row.index:ClearAllPoints()
        row.index:SetPoint("LEFT", indexLeft, 0)
        row.index:SetWidth(indexWidth)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", playerLeft, 0)
        row.name:SetWidth(playerWidth)
        row.spec:ClearAllPoints()
        row.spec:SetPoint("LEFT", specLeft, 0)
        row.spec:SetWidth(specWidth)
        row.roleBox:ClearAllPoints()
        row.roleBox:SetPoint("LEFT", roleLeft, 0)
        row.roleBox:SetWidth(roleWidth)
        row.percentBox:ClearAllPoints()
        row.percentBox:SetPoint("LEFT", percentLeft, 0)
        row.percentBox:SetWidth(percentWidth)
        row.penaltyNoteBox:ClearAllPoints()
        row.penaltyNoteBox:SetPoint("LEFT", penaltyNoteLeft, 0)
        row.penaltyNoteBox:SetWidth(noteColumnWidth)
        row.penaltyButton:ClearAllPoints()
        row.penaltyButton:SetPoint("LEFT", penaltyButtonLeft, 0)
        row.bonusNoteBox:ClearAllPoints()
        row.bonusNoteBox:SetPoint("LEFT", bonusNoteLeft, 0)
        row.bonusNoteBox:SetWidth(noteColumnWidth)
        row.bonusButton:ClearAllPoints()
        row.bonusButton:SetPoint("LEFT", bonusButtonLeft, 0)
        row.modeButton:ClearAllPoints()
        row.modeButton:SetPoint("LEFT", toggleLeft, 0)
        row.debtBox:ClearAllPoints()
        row.debtBox:SetPoint("LEFT", debtLeft, 0)
        row.debtBox:SetWidth(debtWidth)
        row.net:ClearAllPoints()
        row.net:SetPoint("LEFT", netLeft, 0)
        row.net:SetWidth(netWidth)
        row.sentCheck:ClearAllPoints()
        row.sentCheck:SetPoint("LEFT", sentLeft - 2, -1)

        if data.separator then
            row:SetBackdropColor(0.13, 0.05, 0.05, 0.92)
            row:SetBackdropBorderColor(0.55, 0.1, 0.1, 0.9)
            row.separatorLabel:SetText(data.title or "Замены")
            row.separatorLabel:Show()
            row.index:Hide()
            row.name:Hide()
            row.spec:Hide()
            row.roleBox:Hide()
            row.percentBox:Hide()
            row.penaltyNoteBox:Hide()
            row.penaltyButton:Hide()
            row.bonusNoteBox:Hide()
            row.bonusButton:Hide()
            row.modeButton:Hide()
            row.debtBox:Hide()
            row.net:Hide()
            row.sentCheck:Hide()
            row:Show()
        else
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
            row:SetBackdropBorderColor(0.25, 0.08, 0.08, 0.8)
            row.separatorLabel:Hide()
            row.index:Hide()
            row.name:Show()
            row.spec:Show()
            row.roleBox:Show()
            row.percentBox:Show()
            row.penaltyNoteBox:Show()
            row.penaltyButton:Show()
            row.bonusNoteBox:Show()
            row.bonusButton:Show()
            row.modeButton:Show()
            row.debtBox:Show()
            row.net:Show()
            row.sentCheck:Show()
        end

        if not data.separator then
            row.playerName = data.name
            row.isSubstitute = data.isSubstitute
            row.name:SetText(data.name)
            row.spec:SetText(data.spec ~= "" and tostring(data.spec) or "...")

            if not row.roleBox:HasFocus() then
                row.roleBox:SetText(tostring(data.role or ""))
            end

            if not row.percentBox:HasFocus() then
                row.percentBox:SetText(tostring(data.percent or 0))
            end

            if not row.penaltyNoteBox:HasFocus() then
                row.penaltyNoteBox:SetText(tostring(data.penaltyNote or ""))
                if row.penaltyNoteBox.SetCursorPosition then
                    row.penaltyNoteBox:SetCursorPosition(0)
                end
            end

            if not row.bonusNoteBox:HasFocus() then
                row.bonusNoteBox:SetText(tostring(data.bonusNote or ""))
                if row.bonusNoteBox.SetCursorPosition then
                    row.bonusNoteBox:SetCursorPosition(0)
                end
            end

            if not row.debtBox:HasFocus() then
                row.debtBox:SetText(tostring(data.debt or 0))
            end

            row.roleBox:EnableMouse(canEdit)
            row.percentBox:EnableMouse(canEdit)
            row.penaltyNoteBox:EnableMouse(canEdit)
            row.penaltyButton:SetEnabled(canEdit)
            row.bonusNoteBox:EnableMouse(canEdit)
            row.bonusButton:SetEnabled(canEdit)
            row.modeButton:SetEnabled(canEdit)
            row.debtBox:EnableMouse(canEdit)
            row.modeButton:SetText(data.isSubstitute and "Осн" or "Зам")
            row.net:SetText(formatGold(data.net or 0))
            row.sentCheck:SetChecked(data.sent and true or false)

            if (data.net or 0) < 0 then
                row.net:SetTextColor(1, 0.35, 0.35)
            else
                row.net:SetTextColor(1, 0.82, 0)
            end

            row:Show()
        end
    end

    for index = rowCount + 1, table.getn(frame.splitRows) do
        frame.splitRows[index]:Hide()
    end

    frame.splitContent:SetHeight(math.max(rowCount * 24, 28))
end

function addon:CommitSplitViewEdits()
    local frame = self.frame
    local index

    if not frame or not frame.splitRows then
        return
    end

    for index = 1, table.getn(frame.splitRows) do
        local row = frame.splitRows[index]

        if row and row.playerName and row:IsShown() and not row.separator then
            self:UpdateSplitEntryField(row.playerName, "role", row.roleBox and row.roleBox:GetText() or "", true)
            self:UpdateSplitEntryField(row.playerName, "percent", row.percentBox and row.percentBox:GetText() or "", true)
            self:UpdateSplitEntryField(row.playerName, "penaltyNote", row.penaltyNoteBox and row.penaltyNoteBox:GetText() or "", true)
            self:UpdateSplitEntryField(row.playerName, "bonusNote", row.bonusNoteBox and row.bonusNoteBox:GetText() or "", true)
            self:UpdateSplitEntryField(row.playerName, "debt", row.debtBox and row.debtBox:GetText() or "", true)
        end
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:RefreshSpendingView(frame, spending)
    local data = spending or self:BuildSpendingSummary()
    local rows = data and data.rows or {}
    local rowCount = table.getn(rows)
    local contentWidth = math.max(620, math.floor(((frame.spendListPanel and frame.spendListPanel:GetWidth()) or 656) - 36))
    local guildWidth = 160
    local lotsWidth = 70
    local amountWidth = 96
    local amountLeft = contentWidth - amountWidth - 18
    local lotsLeft = amountLeft - 18 - lotsWidth
    local guildLeft = lotsLeft - 12 - guildWidth
    local playerWidth = math.max(120, guildLeft - 50)
    local index

    frame.spendContent:SetWidth(contentWidth)
    frame.spendTotalText:SetText("Потрачено всего: " .. formatGold(data.totalSpent or 0))
    frame.spendBuyersText:SetText("Покупателей: " .. tostring(data.buyerCount or 0))
    frame.spendLotsText:SetText("Лотов: " .. tostring(data.totalLots or 0))
    frame.spendEmptyText:SetShown(rowCount == 0)

    frame.spendHeader.player:ClearAllPoints()
    frame.spendHeader.player:SetPoint("LEFT", 42, 0)
    frame.spendHeader.player:SetWidth(playerWidth)
    frame.spendHeader.player:SetJustifyH("LEFT")

    frame.spendHeader.guild:ClearAllPoints()
    frame.spendHeader.guild:SetPoint("LEFT", guildLeft, 0)
    frame.spendHeader.guild:SetWidth(guildWidth)
    frame.spendHeader.guild:SetJustifyH("LEFT")

    frame.spendHeader.lots:ClearAllPoints()
    frame.spendHeader.lots:SetPoint("LEFT", lotsLeft, 0)

    frame.spendHeader.amount:ClearAllPoints()
    frame.spendHeader.amount:SetPoint("LEFT", amountLeft, 0)
    frame.spendHeader.amount:SetWidth(amountWidth)
    frame.spendHeader.amount:SetJustifyH("RIGHT")

    for index = 1, rowCount do
        local rowData = rows[index]
        local row = frame.spendingRows[index]

        if not row then
            row = CreateFrame("Frame", nil, frame.spendContent)
            createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.index:SetPoint("LEFT", 12, 0)
            row.index:SetWidth(20)
            row.index:SetJustifyH("LEFT")

            row.player = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.player:SetPoint("LEFT", 42, 0)
            row.player:SetJustifyH("LEFT")

            row.guild = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.guild:SetJustifyH("LEFT")
            row.guild:SetTextColor(0.95, 0.82, 0.28)

            row.lots = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.lots:SetWidth(lotsWidth)
            row.lots:SetJustifyH("CENTER")

            row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.amount:SetWidth(amountWidth)
            row.amount:SetJustifyH("RIGHT")

            frame.spendingRows[index] = row
        end

        row:SetSize(contentWidth, 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row.player:SetWidth(playerWidth)
        row.guild:ClearAllPoints()
        row.guild:SetPoint("LEFT", guildLeft, 0)
        row.guild:SetWidth(guildWidth)
        row.lots:ClearAllPoints()
        row.lots:SetPoint("LEFT", lotsLeft, 0)
        row.amount:ClearAllPoints()
        row.amount:SetPoint("LEFT", amountLeft, 0)

        row.index:SetText(index)
        row.player:SetText(tostring(rowData.name or "-"))
        row.guild:SetText((rowData.guildName and rowData.guildName ~= "") and tostring(rowData.guildName) or "-")
        row.lots:SetText(tostring(rowData.lots or 0))
        row.amount:SetText(formatGold(rowData.total or 0))
        row:Show()
    end

    for index = rowCount + 1, table.getn(frame.spendingRows) do
        frame.spendingRows[index]:Hide()
    end

    frame.spendContent:SetHeight(math.max(rowCount * 24, 28))
end

function addon:RefreshLootView(frame, lootSummary)
    local data = lootSummary or self:BuildLootSummary()
    local rows = data and data.rows or {}
    local rowCount = table.getn(rows)
    local contentWidth = math.max(620, math.floor(((frame.lootListPanel and frame.lootListPanel:GetWidth()) or 656) - 36))
    local iconLeft = 8
    local iconSize = 18
    local actionWidth = 56
    local timeWidth = 92
    local actionLeft = contentWidth - actionWidth - 18
    local timeLeftPos = actionLeft - 12 - timeWidth
    local itemLeft = iconLeft + iconSize + 10
    local itemWidth = math.max(180, timeLeftPos - itemLeft - 12)
    local canSelectAny = self:IsPlayerController() and not self:IsAuctionActive()
    local selectedItemIdentity = getItemIdentity(self.pendingItemLink or (self.currentAuction and self.currentAuction.itemLink))
    local index

    frame.lootContent:SetWidth(contentWidth)
    frame.lootTotalText:SetText("Предметов: " .. tostring(data.totalCount or 0))
    frame.lootBossText:SetText("Боссов: " .. tostring(data.bossCount or 0))
    frame.lootUrgentText:SetText("Срочно: " .. tostring(data.urgentCount or 0))
    frame.lootEmptyText:SetShown(rowCount == 0)

    frame.lootHeader.item:ClearAllPoints()
    frame.lootHeader.item:SetPoint("LEFT", itemLeft, 0)
    frame.lootHeader.item:SetWidth(itemWidth)
    frame.lootHeader.item:SetJustifyH("LEFT")

    frame.lootHeader.time:ClearAllPoints()
    frame.lootHeader.time:SetPoint("LEFT", timeLeftPos, 0)
    frame.lootHeader.time:SetWidth(timeWidth)
    frame.lootHeader.time:SetJustifyH("CENTER")

    frame.lootHeader.action:ClearAllPoints()
    frame.lootHeader.action:SetPoint("LEFT", actionLeft, 0)
    frame.lootHeader.action:SetWidth(actionWidth)
    frame.lootHeader.action:SetJustifyH("CENTER")

    for index = 1, rowCount do
        local rowData = rows[index]
        local row = frame.lootRows[index]

        if not row then
            row = CreateFrame("Frame", nil, frame.lootContent)
            createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

            row.separatorLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.separatorLabel:SetPoint("LEFT", 12, 0)
            row.separatorLabel:SetWidth(280)
            row.separatorLabel:SetJustifyH("LEFT")
            row.separatorLabel:SetTextColor(0.95, 0.82, 0.28)

            row.iconButton = CreateFrame("Button", nil, row)
            row.iconButton:SetSize(20, 20)
            createBackdrop(row.iconButton, { 0.1, 0.1, 0.1, 0.95 }, { 0.8, 0.35, 0.05, 0.9 })

            row.icon = row.iconButton:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("TOPLEFT", 3, -3)
            row.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            row.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")

            row.itemLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.itemLabel:SetJustifyH("LEFT")

            row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.time:SetJustifyH("CENTER")

            row.actionButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            setupMiniActionButton(row.actionButton, 56, 18, "В слот")
            row.actionButton:SetScript("OnClick", function()
                if row.entryId then
                    addon:SelectLootEntryForAuction(row.entryId)
                end
            end)
            row.actionButton:SetScript("OnEnter", function(selfButton)
                GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
                if row.canSelect then
                    GameTooltip:AddLine("Перенести в слот")
                    GameTooltip:AddLine("Подставляет предмет в верхний блок для следующего бида", 0.9, 0.9, 0.9)
                elseif not addon:IsPlayerController() then
                    GameTooltip:AddLine("Только мастер лутер может выбрать предмет", 1, 0.2, 0.2)
                elseif addon:IsAuctionActive() then
                    GameTooltip:AddLine("Сначала завершите текущий аукцион", 1, 0.2, 0.2)
                else
                    GameTooltip:AddLine("Предмет больше нельзя передать", 1, 0.2, 0.2)
                end
                GameTooltip:Show()
            end)
            row.actionButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row.iconButton:SetScript("OnClick", function()
                if row.entryId and row.canSelect then
                    addon:SelectLootEntryForAuction(row.entryId)
                end
            end)
            row.iconButton:SetScript("OnEnter", function(selfButton)
                if row.itemLink and row.itemLink ~= "" then
                    GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(row.itemLink)
                    GameTooltip:AddLine("Босс: " .. tostring(row.bossName or "Прочее"), 0.95, 0.82, 0.28)
                    GameTooltip:AddLine("До передачи: " .. tostring(row.timeText or "-"), 0.9, 0.9, 0.9)
                    if row.canSelect then
                        GameTooltip:AddLine("ЛКМ: перенести в слот бида", 0.7, 1, 0.7)
                    end
                    GameTooltip:Show()
                end
            end)
            row.iconButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            frame.lootRows[index] = row
        end

        row:SetSize(contentWidth, 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))

        if rowData.separator then
            row.entryId = nil
            row.itemLink = nil
            row.bossName = nil
            row.timeText = nil
            row.canSelect = false
            row.separator = true
            row:SetBackdropColor(0.12, 0.03, 0.03, 0.88)
            row:SetBackdropBorderColor(0.45, 0.1, 0.1, 0.82)
            row.separatorLabel:SetText(tostring(rowData.title or "Прочее"))
            row.separatorLabel:Show()
            row.iconButton:Hide()
            row.itemLabel:Hide()
            row.time:Hide()
            row.actionButton:Hide()
            row:Show()
        else
            local itemName = rowData.itemName
            local itemTexture = nil
            local timeLeft = self:GetLootTransferTimeLeft(rowData)
            local timeText = self:FormatLootTimeLeft(timeLeft)
            local isSelected = selectedItemIdentity and getItemIdentity(rowData.itemLink) == selectedItemIdentity
            local canSelect = canSelectAny and timeLeft > 0

            if rowData.itemLink and GetItemInfo then
                local _, _, _, _, _, _, _, _, _, fetchedTexture = GetItemInfo(rowData.itemLink)
                itemTexture = fetchedTexture
            end

            row.entryId = rowData.id
            row.itemLink = rowData.itemLink
            row.bossName = rowData.bossName
            row.timeText = timeText
            row.canSelect = canSelect
            row.separator = false

            if not itemName or itemName == "" then
                itemName = (GetItemInfo and GetItemInfo(rowData.itemLink)) or rowData.itemLink or "Неизвестный предмет"
            end

            row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
            if isSelected then
                row:SetBackdropBorderColor(1, 0.82, 0, 1)
            elseif timeLeft <= 0 then
                row:SetBackdropBorderColor(0.45, 0.08, 0.08, 0.8)
            elseif timeLeft <= 1200 then
                row:SetBackdropBorderColor(0.9, 0.35, 0.08, 0.95)
            elseif timeLeft <= 3600 then
                row:SetBackdropBorderColor(0.65, 0.28, 0.08, 0.9)
            else
                row:SetBackdropBorderColor(0.25, 0.08, 0.08, 0.8)
            end

            row.separatorLabel:Hide()
            row.iconButton:Show()
            row.iconButton:ClearAllPoints()
            row.iconButton:SetPoint("LEFT", iconLeft, 0)
            row.icon:SetTexture(itemTexture or "Interface/Icons/INV_Misc_QuestionMark")

            row.itemLabel:Show()
            row.itemLabel:ClearAllPoints()
            row.itemLabel:SetPoint("LEFT", itemLeft, 0)
            row.itemLabel:SetWidth(itemWidth)
            row.itemLabel:SetTextColor(1, 1, 1)
            if rowData.itemLink and rowData.itemLink ~= "" then
                row.itemLabel:SetText(rowData.itemLink)
            else
                row.itemLabel:SetText(itemName)
            end

            row.time:Show()
            row.time:ClearAllPoints()
            row.time:SetPoint("LEFT", timeLeftPos, 0)
            row.time:SetWidth(timeWidth)
            row.time:SetText(timeText)
            if timeLeft <= 0 then
                row.time:SetTextColor(1, 0.25, 0.25)
            elseif timeLeft <= 1200 then
                row.time:SetTextColor(1, 0.45, 0.2)
            elseif timeLeft <= 3600 then
                row.time:SetTextColor(1, 0.8, 0.2)
            else
                row.time:SetTextColor(0.95, 0.95, 0.85)
            end

            row.actionButton:Show()
            row.actionButton:ClearAllPoints()
            row.actionButton:SetPoint("LEFT", actionLeft, 0)
            row.actionButton:SetEnabled(canSelect)
            row.actionButton:SetText("В слот")
            row:Show()
        end
    end

    for index = rowCount + 1, table.getn(frame.lootRows) do
        frame.lootRows[index]:Hide()
    end

    frame.lootContent:SetHeight(math.max(rowCount * 24, 28))
end

function addon:RefreshDamageEncounterDropdown(damageSummary)
    local frame = self.frame or self:CreateMainWindow()
    local dropdown = frame.damageDropDown
    local data = damageSummary or self:BuildDamageSummary()
    local segments = data and data.segments or {}
    local selectedKey = data and data.selectedKey or nil
    local signatureParts = { tostring(selectedKey or ""), tostring(table.getn(segments)) }
    local index

    if not dropdown or not UIDropDownMenu_Initialize then
        return
    end

    for index = 1, table.getn(segments) do
        table.insert(signatureParts, tostring(segments[index].key or ""))
    end

    if frame.lastDamageDropdownSignature ~= table.concat(signatureParts, "|") then
        UIDropDownMenu_Initialize(dropdown, function(selfDropDown, level)
            local info
            local itemIndex

            if level ~= 1 then
                return
            end

            for itemIndex = 1, table.getn(segments) do
                info = UIDropDownMenu_CreateInfo()
                info.text = tostring(segments[itemIndex].label or segments[itemIndex].name or "Бой")
                info.value = tostring(segments[itemIndex].key or "")
                info.checked = selectedKey and selectedKey == segments[itemIndex].key
                info.disabled = false
                info.func = function()
                    addon:SetSelectedDamageSegmentKey(segments[itemIndex].key)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        frame.lastDamageDropdownSignature = table.concat(signatureParts, "|")
    end

    UIDropDownMenu_SetWidth(dropdown, 210)
    UIDropDownMenu_SetSelectedValue(dropdown, selectedKey or "")
    UIDropDownMenu_SetText(dropdown, data.selectedLabel or data.message or "Выберите босса")

    if table.getn(segments) > 0 and UIDropDownMenu_EnableDropDown then
        UIDropDownMenu_EnableDropDown(dropdown)
    elseif UIDropDownMenu_DisableDropDown then
        UIDropDownMenu_DisableDropDown(dropdown)
    end

    frame.lastDamageDropdownValue = selectedKey
end

function addon:RefreshDamageView(frame, damageSummary)
    local data = damageSummary or self:BuildDamageSummary()
    local rows = data and data.rows or {}
    local rowCount = table.getn(rows)
    local contentWidth = math.max(620, math.floor(((frame.damageListPanel and frame.damageListPanel:GetWidth()) or 656) - 36))
    local indexWidth = 20
    local classWidth = 118
    local amountWidth = 112
    local dpsWidth = 88
    local percentWidth = 56
    local percentLeft = contentWidth - percentWidth - 18
    local dpsLeft = percentLeft - 10 - dpsWidth
    local amountLeft = dpsLeft - 10 - amountWidth
    local classLeft = amountLeft - 12 - classWidth
    local playerLeft = 42
    local playerWidth = math.max(120, classLeft - playerLeft - 12)
    local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {}
    local index

    self:RefreshDamageEncounterDropdown(data)

    frame.damageContent:SetWidth(contentWidth)
    frame.damageTotalText:ClearAllPoints()
    frame.damageTotalText:SetPoint("RIGHT", -10, 0)
    frame.damageTotalText:SetText("Всего: " .. formatAmount(data.totalDamage or 0))

    frame.damageTimeText:ClearAllPoints()
    frame.damageTimeText:SetPoint("RIGHT", frame.damageTotalText, "LEFT", -12, 0)
    frame.damageTimeText:SetText("Время: " .. formatClock(data.combatTime or 0))

    frame.damagePlayersText:ClearAllPoints()
    frame.damagePlayersText:SetPoint("RIGHT", frame.damageTimeText, "LEFT", -12, 0)
    frame.damagePlayersText:SetText("Игроков: " .. tostring(data.playerCount or 0))

    frame.damageHeader.player:ClearAllPoints()
    frame.damageHeader.player:SetPoint("LEFT", playerLeft, 0)
    frame.damageHeader.player:SetWidth(playerWidth)
    frame.damageHeader.player:SetJustifyH("LEFT")

    frame.damageHeader.class:ClearAllPoints()
    frame.damageHeader.class:SetPoint("LEFT", classLeft, 0)
    frame.damageHeader.class:SetWidth(classWidth)
    frame.damageHeader.class:SetJustifyH("LEFT")

    frame.damageHeader.amount:ClearAllPoints()
    frame.damageHeader.amount:SetPoint("LEFT", amountLeft, 0)
    frame.damageHeader.amount:SetWidth(amountWidth)
    frame.damageHeader.amount:SetJustifyH("RIGHT")

    frame.damageHeader.dps:ClearAllPoints()
    frame.damageHeader.dps:SetPoint("LEFT", dpsLeft, 0)
    frame.damageHeader.dps:SetWidth(dpsWidth)
    frame.damageHeader.dps:SetJustifyH("RIGHT")

    frame.damageHeader.percent:ClearAllPoints()
    frame.damageHeader.percent:SetPoint("LEFT", percentLeft, 0)
    frame.damageHeader.percent:SetWidth(percentWidth)
    frame.damageHeader.percent:SetJustifyH("RIGHT")

    if data.message and rowCount == 0 then
        frame.damageEmptyText:SetText(tostring(data.message))
    elseif data.selectedLabel then
        frame.damageEmptyText:SetText("Для выбранного боя в Details нет игроков с уроном")
    else
        frame.damageEmptyText:SetText("Нет данных по урону")
    end
    frame.damageEmptyText:SetShown(rowCount == 0)

    for index = 1, rowCount do
        local rowData = rows[index]
        local row = frame.damageRows[index]
        local classToken = tostring(rowData.class or "")
        local classColor = classColors[classToken]
        local specLabel = tostring(rowData.specName or "")

        if not row then
            row = CreateFrame("Frame", nil, frame.damageContent)
            createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.index:SetPoint("LEFT", 12, 0)
            row.index:SetWidth(indexWidth)
            row.index:SetJustifyH("LEFT")

            row.player = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.player:SetJustifyH("LEFT")

            row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.class:SetJustifyH("LEFT")

            row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.amount:SetJustifyH("RIGHT")

            row.dps = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.dps:SetJustifyH("RIGHT")

            row.percent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.percent:SetJustifyH("RIGHT")

            frame.damageRows[index] = row
        end

        row:SetSize(contentWidth, 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))

        row.player:ClearAllPoints()
        row.player:SetPoint("LEFT", playerLeft, 0)
        row.player:SetWidth(playerWidth)

        row.class:ClearAllPoints()
        row.class:SetPoint("LEFT", classLeft, 0)
        row.class:SetWidth(classWidth)

        row.amount:ClearAllPoints()
        row.amount:SetPoint("LEFT", amountLeft, 0)
        row.amount:SetWidth(amountWidth)

        row.dps:ClearAllPoints()
        row.dps:SetPoint("LEFT", dpsLeft, 0)
        row.dps:SetWidth(dpsWidth)

        row.percent:ClearAllPoints()
        row.percent:SetPoint("LEFT", percentLeft, 0)
        row.percent:SetWidth(percentWidth)

        row.index:SetText(tostring(rowData.rank or index))
        row.player:SetText(tostring(rowData.name or "-"))
        if specLabel == "" then
            specLabel = "..."
        end
        row.class:SetText(specLabel)
        row.amount:SetText(formatAmount(rowData.total or 0))
        row.dps:SetText(formatRate(rowData.dps or 0))
        row.percent:SetText(string.format("%.1f%%", tonumber(rowData.percent) or 0))

        if classColor then
            row.player:SetTextColor(classColor.r or 1, classColor.g or 1, classColor.b or 1)
            row.class:SetTextColor(classColor.r or 1, classColor.g or 1, classColor.b or 1)
        else
            row.player:SetTextColor(1, 1, 1)
            row.class:SetTextColor(0.95, 0.82, 0.28)
        end

        row.amount:SetTextColor(1, 0.82, 0)
        row.dps:SetTextColor(0.92, 0.88, 0.72)
        row.percent:SetTextColor(0.92, 0.88, 0.72)
        row:Show()
    end

    for index = rowCount + 1, table.getn(frame.damageRows) do
        frame.damageRows[index]:Hide()
    end

    frame.damageContent:SetHeight(math.max(rowCount * 24, 28))
end

function addon:RefreshMainWindow()
    local frame = self.frame or self:CreateMainWindow()
    local auction = self.currentAuction or {}
    local rows = self:GetSortedBids()
    local passes = self:GetSortedPasses()
    local auctionMode = self:GetCurrentAuctionMode()
    local isRollMode = auctionMode == "roll"
    local split = self:ComputeDetailedSplit()
    local itemLink = self.pendingItemLink or auction.itemLink
    local itemName = itemLink
    local texture = "Interface/Icons/INV_Misc_QuestionMark"
    local payout = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.payout
    local sales = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.sales or {}
    local spending = self:BuildSpendingSummary()
    local lootSummary = self:BuildLootSummary()
    local damageSummary = self:BuildDamageSummary()
    local saleCount = table.getn(sales)
    local isController = self:IsPlayerController()
    local hasFullAccess = self:HasFullInterfaceAccess()
    local canChangeMode = isController and not self:IsAuctionActive()
    local playerName = self:GetPlayerName()
    local hasPassed = auction.passes and auction.passes[playerName] or false
    local hasRolled = auction.bids and auction.bids[playerName] ~= nil or false
    local isEligibleForRoll = self:IsPlayerEligibleForCurrentRoll(playerName)
    local maxAuctionRows = hasFullAccess and table.getn(frame.rows) or 4
    local auctionWidth = math.floor((frame.auctionView and frame.auctionView:GetWidth()) or 704)
    local historyWidth
    local leftWidth
    local passWidth
    local summaryContentWidth = math.floor(((frame.summaryListPanel and frame.summaryListPanel:GetWidth()) or 656) - 36)
    local summaryWinnerLeft
    local timeLeft = self:GetTimeLeft()
    local index

    if itemLink and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        itemName = GetItemInfo(itemLink) or itemLink
        texture = itemTexture or texture
    end

    self:ApplySuggestedMinBidForPendingItem(frame, itemLink)
    if (not itemLink or itemLink == "") and not self:IsAuctionActive() then
        self:ApplyDefaultAuctionInputs(frame, false)
    end

    if frame.activeAuctionId ~= auction.id then
        frame.activeAuctionId = auction.id
        frame.bidManualOverride = false
        frame.incrementManualOverride = false
        frame.lastSuggestedBid = nil
        frame.bidPreviewBase = nil
        frame.bidPreviewValue = nil
    end

    frame.leaderText:SetText("Мастер лутер: " .. tostring(self:GetLeaderName() or "неизвестно"))
    if self:IsAuctionActive() then
        if isRollMode and self:IsRollRerollActive() then
            frame.statusText:SetText("Статус: Переролл #" .. tostring((auction.rerollRound or 1)) .. " | " .. tostring(timeLeft) .. "s")
        else
            frame.statusText:SetText("Статус: " .. self:GetAuctionModeDisplayName(auctionMode) .. " | " .. tostring(timeLeft) .. "s")
        end
    else
        frame.statusText:SetText("Статус: " .. tostring(auction.status or "idle") .. " | " .. self:GetAuctionModeDisplayName(auctionMode))
    end
    frame.itemText:SetText(itemName or "Перетащите предмет")
    frame.itemButton.icon:SetTexture(texture)
    frame.tableHeader.amount:SetText(isRollMode and "Roll" or "Ставка")
    frame.bidLabel:SetText(isRollMode and "Ваш roll" or "Ваша ставка")
    frame.bidButton:SetText(isRollMode and "Roll" or "Ставка")
    frame.startButton:SetText(isRollMode and "Старт Roll" or "Старт")

    if hasFullAccess then
        leftWidth = 340
        passWidth = 140
        historyWidth = math.max(180, auctionWidth - leftWidth - passWidth - 24)
    else
        local compactContentWidth = math.max(280, auctionWidth - 12)

        leftWidth = math.floor(compactContentWidth * 0.64)
        historyWidth = compactContentWidth - leftWidth
        passWidth = 0
    end

    if summaryContentWidth < 320 then
        summaryContentWidth = 320
    end

    summaryWinnerLeft = math.max(180, summaryContentWidth - 150)

    frame.tableHeader:SetWidth(leftWidth)
    frame.passHeader:SetShown(hasFullAccess)
    frame.historyHeader:SetWidth(historyWidth)
    frame.historyHeader.title:SetText(hasFullAccess and "Продажи" or "ПАС")
    frame.historyHeader:ClearAllPoints()
    if hasFullAccess then
        frame.historyHeader:SetPoint("TOPLEFT", frame.passHeader, "TOPRIGHT", 12, 0)
    else
        frame.historyHeader:SetPoint("TOPLEFT", frame.tableHeader, "TOPRIGHT", 12, 0)
    end
    frame.summaryContent:SetWidth(summaryContentWidth)
    frame.summaryHeader.winner:ClearAllPoints()
    frame.summaryHeader.winner:SetPoint("LEFT", summaryWinnerLeft, 0)

    frame.tableHeader.player:SetWidth(math.max(90, leftWidth - 160))
    frame.tableHeader.amount:ClearAllPoints()
    frame.tableHeader.amount:SetPoint("RIGHT", -16, 0)

    for index = 1, table.getn(frame.rows) do
        frame.rows[index].player:SetWidth(math.max(90, leftWidth - 160))
        frame.rows[index].amount:SetWidth(90)
    end

    if self:IsAuctionActive() and not self:IsPlayerController() and not isRollMode and auction.minBid and auction.minBid > 0 and not frame.minBidBox:HasFocus() then
        frame.minBidBox:SetText(formatGroupedInteger(auction.minBid))
    end

    if self:IsAuctionActive() and not self:IsPlayerController() and not isRollMode and auction.increment and auction.increment > 0 and not frame.incrementBox:HasFocus() then
        self:NormalizeClientRaiseStep()
    end

    if self:IsAuctionActive() and not frame.durationBox:HasFocus() then
        frame.durationBox:SetText(tostring(timeLeft))
    elseif not self:IsAuctionActive() and not frame.durationBox:HasFocus() and auction.duration and auction.duration > 0 then
        frame.durationBox:SetText(tostring(auction.duration))
    end

    if self:IsAuctionActive() and isRollMode and not frame.bidBox:HasFocus() then
        frame.bidBox:SetText(auction.bids and tostring(auction.bids[playerName] or "") or "")
    elseif self:IsAuctionActive() and not frame.bidBox:HasFocus() then
        local suggestedBid = self:GetSuggestedBidBase()
        if frame.bidPreviewValue and frame.bidPreviewBase == suggestedBid then
            frame.bidBox:SetText(tostring(frame.bidPreviewValue))
        else
            frame.bidPreviewBase = nil
            frame.bidPreviewValue = nil
            frame.bidBox:SetText(tostring(suggestedBid))
        end
        frame.lastSuggestedBid = suggestedBid
    end

    for index = 1, table.getn(frame.rows) do
        local row = frame.rows[index]
        local bid = rows[index]

        if index > maxAuctionRows then
            row:Hide()
        elseif bid then
            row.rank:SetText(index)
            row.player:SetText(bid.name)
            row.amount:SetText(isRollMode and tostring(bid.amount) or formatGold(bid.amount))
            if index == 1 then
                row:SetBackdropBorderColor(1, 0.82, 0, 1)
                row.player:SetTextColor(1, 0.82, 0)
                row.amount:SetTextColor(1, 0.82, 0)
            else
                row:SetBackdropBorderColor(0.25, 0.08, 0.08, 0.8)
                row.player:SetTextColor(1, 1, 1)
                row.amount:SetTextColor(1, 1, 1)
            end
            row:Show()
        else
            row:SetBackdropBorderColor(0.25, 0.08, 0.08, 0.8)
            row.rank:SetText("")
            row.player:SetText(index == 1 and "Ставок нет" or "")
            row.amount:SetText("")
            row.player:SetTextColor(1, 1, 1)
            row.amount:SetTextColor(1, 1, 1)
            row:Show()
        end
    end

    for index = 1, table.getn(frame.passRows) do
        local row = frame.passRows[index]

        if hasFullAccess and index <= maxAuctionRows then
            row:SetWidth(140)
            row.name:SetWidth(118)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.passHeader, "BOTTOMLEFT", 0, -((index - 1) * 26) - 6)
            row.name:SetText(passes[index] or "")
            row:Show()
        else
            row:Hide()
        end
    end

    for index = 1, table.getn(frame.historyRows) do
        local row = frame.historyRows[index]
        local sale = sales[table.getn(sales) - index + 1]
        local passName = passes[index]

        if index > maxAuctionRows then
            row:Hide()
        else
            row:SetWidth(historyWidth)
            row.item:SetWidth(historyWidth - 20)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.historyHeader, "BOTTOMLEFT", 0, -((index - 1) * 26) - 6)

            if hasFullAccess then
                if sale then
                    row.item:SetText(tostring(sale.winner or "?") .. " - " .. formatGold(sale.amount or 0))
                else
                    row.item:SetText(index == 1 and "Продаж нет" or "")
                end
            else
                row.item:SetText(passName or (index == 1 and "Пасов нет" or ""))
            end
            row:Show()
        end
    end

    frame.summaryPotText:SetText("Касса рейда: " .. formatGold(GoldBidDB.ledger.pot or 0))
    frame.summaryLotsText:SetText("Лотов продано: " .. tostring(saleCount))
    if payout then
        frame.summarySplitText:SetText("Сплит: " .. formatGold(payout.perPlayer or 0))
    else
        frame.summarySplitText:SetText("Сплит: не рассчитан")
    end

    frame.summaryEmptyText:SetShown(saleCount == 0)
    for index = 1, saleCount do
        local sale = sales[index]
        local row = frame.summaryRows[index]
        local itemLabel

        if not row then
            row = CreateFrame("Frame", nil, frame.summaryContent)
            createBackdrop(row, { 0.08, 0.08, 0.08, 0.8 }, { 0.25, 0.08, 0.08, 0.8 })

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.index:SetPoint("LEFT", 12, 0)
            row.index:SetWidth(20)
            row.index:SetJustifyH("LEFT")

            row.item = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.item:SetPoint("LEFT", 42, 0)
            row.item:SetJustifyH("LEFT")

            row.winner = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.winner:SetWidth(120)
            row.winner:SetJustifyH("LEFT")

            row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.amount:SetPoint("RIGHT", -28, 0)
            row.amount:SetWidth(72)
            row.amount:SetJustifyH("RIGHT")

            row.deleteButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.deleteButton, 18, 18, "X")
            row.deleteButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.deleteButton:SetScript("OnClick", function()
                addon:ConfirmDeleteSale(row.saleIndex)
            end)
            row.deleteButton:SetScript("OnEnter", function(selfButton)
                GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
                GameTooltip:AddLine("Удалить лот")
                GameTooltip:AddLine("Удаляет запись из сводки и вычитает сумму из банка", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            row.deleteButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            frame.summaryRows[index] = row
        end

        row:SetSize(summaryContentWidth, 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row.item:SetWidth(summaryWinnerLeft - 58)
        row.winner:ClearAllPoints()
        row.winner:SetPoint("LEFT", summaryWinnerLeft, 0)
        row.amount:ClearAllPoints()
        row.amount:SetPoint("RIGHT", -28, 0)
        row.deleteButton:ClearAllPoints()
        row.deleteButton:SetPoint("RIGHT", -4, 0)

        itemLabel = sale.itemLink or sale.itemName or "Неизвестный лот"
        row.saleIndex = index
        row.index:SetText(index)
        row.item:SetText(itemLabel)
        row.winner:SetText(tostring(sale.winner or "-"))
        row.amount:SetText(formatGold(sale.amount or 0))
        row.deleteButton:SetShown(isController)
        row.deleteButton:SetEnabled(isController)
        row:Show()
    end

    for index = saleCount + 1, table.getn(frame.summaryRows) do
        frame.summaryRows[index]:Hide()
    end

    frame.summaryContent:SetHeight(math.max(saleCount * 24, 28))
    self:RefreshSpendingView(frame, spending)
    self:RefreshLootView(frame, lootSummary)
    self:RefreshDamageView(frame, damageSummary)
    self:RefreshSplitView(frame)
    frame.compactPotText:SetText(self:GetAuctionModeDisplayName(auctionMode))

    if frame.activeTab == "split" then
        frame.footerText:SetText("Банк: " .. formatGold(GoldBidDB.ledger.pot or 0))
    elseif frame.activeTab == "spend" then
        frame.footerText:SetText("Банк: " .. formatGold(GoldBidDB.ledger.pot or 0) .. " | Потрачено: " .. formatGold(spending.totalSpent or 0))
    elseif frame.activeTab == "loot" then
        frame.footerText:SetText("Лут: " .. tostring(lootSummary.totalCount or 0) .. " | Срочно: " .. tostring(lootSummary.urgentCount or 0))
    elseif frame.activeTab == "damage" then
        frame.footerText:SetText("Босс: " .. tostring(damageSummary.segmentName or "-") .. " | Игроков: " .. tostring(damageSummary.playerCount or 0))
    elseif payout then
        frame.footerText:SetText("Режим: " .. self:GetAuctionModeDisplayName(auctionMode) .. " | Сплит: " .. formatGold(payout.perPlayer or 0))
    else
        frame.footerText:SetText("Режим: " .. self:GetAuctionModeDisplayName(auctionMode))
    end

    if frame.lastModeDropdownValue ~= auctionMode or frame.lastModeDropdownCanChange ~= canChangeMode then
        self:RefreshModeDropdown()
        frame.lastModeDropdownValue = auctionMode
        frame.lastModeDropdownCanChange = canChangeMode
    end
    self:UpdateMainWindowLayout()
    frame.startButton:SetEnabled(self:IsPlayerController())
    frame.endButton:SetEnabled(self:IsPlayerController() and self:IsAuctionActive())
    frame.compactSkipButton:SetEnabled(not hasFullAccess and self:IsAuctionActive() and not self:IsAuctionWindowSuppressed())
    if hasFullAccess then
        frame.resetButton:SetEnabled(self:IsPlayerController())
    else
        frame.resetButton:SetEnabled(not hasPassed)
    end
    frame.bidButton:SetEnabled(not hasPassed and (not isRollMode or (isEligibleForRoll and not hasRolled)))
    frame.passButton:SetEnabled(not hasPassed and (not isRollMode or (isEligibleForRoll and not hasRolled)))
    frame.bidBox:EnableMouse((not hasPassed) and (not isRollMode))
    frame.addStepButton:SetEnabled((not hasPassed) and (not isRollMode))
    self:SetMainTab(frame.activeTab or "auction", true)
end
