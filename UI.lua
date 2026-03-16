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
    value = tonumber(value) or 0
    return string.format("%dg", math.floor(value))
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
    local configuredStep = tonumber(frame.incrementBox:GetText()) or 0

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
    local configuredStep = tonumber(frame.incrementBox:GetText()) or 0

    if configuredStep <= 0 then
        configuredStep = auctionStep > 0 and auctionStep or 1
    end

    if not self:IsPlayerController() and auctionStep > 0 and configuredStep < auctionStep then
        configuredStep = auctionStep
    end

    frame.incrementBox:SetText(tostring(configuredStep))
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

    frame.bidBox:SetText(tostring(currentBid + step))
    frame.bidManualOverride = true
end

function addon:ToggleMainWindow()
    local frame = self:CreateMainWindow()

    if frame:IsShown() then
        frame:Hide()
    else
        self:ShowMainWindow()
    end
end

function addon:UpdateMainWindowLayout()
    local frame = self.frame or self:CreateMainWindow()
    local hasFullAccess = self:HasFullInterfaceAccess()
    local isExpanded = hasFullAccess or frame.compactSectionOpen
    local compactHeight

    if not hasFullAccess and frame.activeTab == "split" then
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
    frame.infoBar:SetShown(hasFullAccess)
    frame.leaderText:SetShown(hasFullAccess)
    frame.statusText:SetShown(hasFullAccess)
    frame.auctionTabButton:SetShown(hasFullAccess)
    frame.summaryTabButton:SetShown(hasFullAccess)
    frame.splitTabButton:SetShown(hasFullAccess)
    frame.splitView:SetShown(hasFullAccess and frame.activeTab == "split")
    frame.tablesPanel:SetShown(isExpanded)
    frame.footerPanel:SetShown(hasFullAccess and isExpanded)
    frame.resetButton:SetShown(self:IsPlayerController())
    frame.resizeHandle:SetShown(hasFullAccess)

    frame.startButton:SetShown(hasFullAccess)
    frame.endButton:SetShown(hasFullAccess)
    frame.settingsActionButton:SetShown(hasFullAccess)

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
        frame.itemButton:SetSize(50, 50)
        frame.itemButton:SetPoint("TOPLEFT", 54, -44)
        frame.itemText:Show()
        frame.itemText:SetPoint("TOP", frame.itemButton, "BOTTOM", 0, -8)
        frame.itemText:SetWidth(120)
        frame.itemText:SetJustifyH("CENTER")
        frame.compactPotText:SetWidth(260)
        frame.minBidBox:SetWidth(90)
        frame.incrementBox:SetWidth(90)
        frame.durationBox:SetWidth(90)
        frame.bidBox:SetWidth(90)
        frame.minBidBox:EnableMouse(true)
        frame.incrementBox:EnableMouse(true)
        frame.durationBox:EnableMouse(true)
        frame.bidBox:EnableMouse(true)
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
        -- Две колонки полей: слева Мин. ставка / Время, справа Шаг / Ваша ставка
        frame.minBidBox:SetWidth(60)
        frame.incrementBox:SetWidth(60)
        frame.durationBox:SetWidth(60)
        frame.bidBox:SetWidth(60)
        frame.minBidBox:EnableMouse(false)
        frame.incrementBox:EnableMouse(true)
        frame.durationBox:EnableMouse(false)
        frame.bidBox:EnableMouse(true)
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
        frame.compactPotText:SetWidth(110)
    end
end

function addon:SetMainTab(tabName, preserveState)
    local frame = self.frame or self:CreateMainWindow()
    local activeTab = "auction"
    local hasFullAccess = self:HasFullInterfaceAccess()

    if tabName == "summary" or (hasFullAccess and tabName == "split") then
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

    if frame.splitView then
        frame.splitView:SetShown(hasFullAccess and frame.activeTab == "split")
    end

    setTabButtonState(frame.auctionTabButton, frame.activeTab == "auction")
    setTabButtonState(frame.summaryTabButton, frame.activeTab == "summary")
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
    local frame, header, itemButton, itemText, statusText, leaderText, closeButton, compactCloseButton, settingsButton
    local controlsPanel, tablesPanel, footerPanel, infoBar
    local minBidBox, incrementBox, durationBox, bidBox, addStepButton
    local startButton, endButton, bidButton, passButton, syncButton, resetButton, splitMailButton
    local rows = {}
    local historyRows = {}
    local passRows = {}
    local summaryRows = {}
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

    frame.splitTabButton = CreateFrame("Button", nil, tablesPanel, "UIPanelButtonTemplate")
    frame.splitTabButton:SetSize(84, 22)
    frame.splitTabButton:SetPoint("LEFT", frame.summaryTabButton, "RIGHT", 8, 0)
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
    setupInputBox(minBidBox, 90, "100")

    frame.incrementLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.incrementLabel:SetPoint("TOPLEFT", 346, -44)
    frame.incrementLabel:SetWidth(90)
    frame.incrementLabel:SetJustifyH("CENTER")
    frame.incrementLabel:SetText("Шаг")

    incrementBox = CreateFrame("EditBox", nil, controlsPanel)
    incrementBox:SetPoint("TOPLEFT", frame.incrementLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(incrementBox, 90, "10")
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

    frame.durationLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.durationLabel:SetPoint("TOPLEFT", 236, -86)
    frame.durationLabel:SetWidth(90)
    frame.durationLabel:SetJustifyH("CENTER")
    frame.durationLabel:SetText("Время")

    durationBox = CreateFrame("EditBox", nil, controlsPanel)
    durationBox:SetPoint("TOPLEFT", frame.durationLabel, "BOTTOMLEFT", 0, -4)
    setupInputBox(durationBox, 90, "60")
    durationBox:SetScript("OnEnterPressed", function(selfBox)
        local value

        addon:EnsureAuctionState()
        value = math.max(1, tonumber(selfBox:GetText()) or addon.currentAuction.duration or 60)
        addon.currentAuction.duration = value
        selfBox:SetText(tostring(value))
        selfBox:ClearFocus()
    end)
    durationBox:SetScript("OnEditFocusLost", function(selfBox)
        local value

        addon:EnsureAuctionState()
        value = math.max(1, tonumber(selfBox:GetText()) or addon.currentAuction.duration or 60)
        addon.currentAuction.duration = value
        selfBox:SetText(tostring(value))
    end)
    durationBox:SetScript("OnEscapePressed", function(selfBox)
        addon:EnsureAuctionState()
        selfBox:SetText(tostring(addon.currentAuction.duration or 60))
        selfBox:ClearFocus()
    end)

    startButton = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
    startButton:SetSize(96, 22)
    startButton:SetPoint("TOPLEFT", 522, -48)
    startButton:SetText("Старт")
    startButton:SetScript("OnClick", function()
        addon:ConfirmOrStartAuction(
            addon.pendingItemLink or addon.currentAuction.itemLink,
            tonumber(minBidBox:GetText()) or 0,
            tonumber(incrementBox:GetText()) or 0,
            tonumber(durationBox:GetText()) or 60
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
        if userInput then
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

    frame.splitLeaderPercentLabel = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitLeaderPercentLabel:SetPoint("LEFT", 228, 0)
    frame.splitLeaderPercentLabel:SetText("Доля РЛ %")

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

    frame.splitLeaderShareText = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.splitLeaderShareText:SetPoint("LEFT", frame.splitLeaderPercentBox, "RIGHT", 16, 0)
    frame.splitLeaderShareText:SetWidth(150)
    frame.splitLeaderShareText:SetJustifyH("LEFT")
    frame.splitLeaderShareText:SetTextColor(0.95, 0.82, 0.28)

    frame.splitBaseText = frame.splitStatsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.splitBaseText:SetPoint("RIGHT", -10, 0)
    frame.splitBaseText:SetWidth(190)
    frame.splitBaseText:SetJustifyH("RIGHT")
    frame.splitBaseText:SetTextColor(0.95, 0.82, 0.28)

    splitMailButton = CreateFrame("Button", nil, frame.splitStatsBar, "UIPanelButtonTemplate")
    splitMailButton:SetSize(132, 22)
    splitMailButton:SetPoint("RIGHT", -10, 0)
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

    frame.splitBaseText:ClearAllPoints()
    frame.splitBaseText:SetPoint("RIGHT", splitMailButton, "LEFT", -8, 0)

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

    frame.splitHeader.player = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.player:SetPoint("LEFT", 34, 0)
    frame.splitHeader.player:SetWidth(108)
    frame.splitHeader.player:SetJustifyH("CENTER")
    frame.splitHeader.player:SetText("Игрок")

    frame.splitHeader.spec = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.spec:SetPoint("LEFT", 150, 0)
    frame.splitHeader.spec:SetWidth(72)
    frame.splitHeader.spec:SetJustifyH("CENTER")
    frame.splitHeader.spec:SetText("Спек")

    frame.splitHeader.role = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.role:SetPoint("LEFT", 232, 0)
    frame.splitHeader.role:SetWidth(54)
    frame.splitHeader.role:SetJustifyH("CENTER")
    frame.splitHeader.role:SetText("Роль")

    frame.splitHeader.percent = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.percent:SetPoint("LEFT", 296, 0)
    frame.splitHeader.percent:SetWidth(50)
    frame.splitHeader.percent:SetJustifyH("CENTER")
    frame.splitHeader.percent:SetText("%")

    frame.splitHeader.note = frame.splitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.splitHeader.note:SetPoint("LEFT", 350, 0)
    frame.splitHeader.note:SetWidth(150)
    frame.splitHeader.note:SetJustifyH("CENTER")
    frame.splitHeader.note:SetText("Косяки / плюсики")

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

    frame.footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footerText:SetPoint("RIGHT", footerPanel, "RIGHT", -12, 0)
    frame.footerText:SetJustifyH("RIGHT")
    frame.footerText:SetText("ПКМ по слоту для очистки")

    frame.header = header
    frame.closeButton = closeButton
    frame.compactCloseButton = compactCloseButton
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
    frame.splitRows = splitRows

    self.frame = frame
    self:SetMainTab("auction")
    return frame
end

function addon:ShowMainWindow()
    local frame = self:CreateMainWindow()

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
    local playerLeft = 34
    local playerWidth = 108
    local specLeft = 148
    local specWidth = 72
    local roleLeft = 230
    local roleWidth = 54
    local percentLeft = 294
    local percentWidth = 50
    local noteLeft = 348
    local debtWidth = 60
    local netWidth = 76
    local toggleWidth = 36
    local presetWidth = 20
    local debtLeft = contentWidth - netWidth - 18 - 8 - debtWidth
    local toggleLeft = debtLeft - 8 - toggleWidth
    local penaltyLeft = toggleLeft - 2 - presetWidth
    local bonusLeft = penaltyLeft - 2 - presetWidth
    local noteWidth = math.max(100, bonusLeft - noteLeft - 6)
    local netLeft = contentWidth - netWidth - 18
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
        frame.splitLeaderPercentBox:SetText(tostring(split.leaderSharePercent or 20))
    end

    frame.splitLeaderPercentBox:EnableMouse(canEdit)
    frame.splitGrossText:SetText("Банк: " .. formatGold(split.totalPot or 0) .. " | Основа: " .. tostring(split.mainCount or 0))
    frame.splitLeaderShareText:SetText("РЛ: " .. formatGold(split.leaderShareAmount or 0))
    frame.splitBaseText:SetText("Замены: " .. tostring(split.substituteCount or 0) .. " | 100% = " .. formatGold(split.baseShare or 0))
    frame.splitEmptyText:SetShown(rowCount == 0)

    if frame.mailPayoutButton then
        frame.mailPayoutButton:SetShown(canEdit)
        frame.mailPayoutButton:SetEnabled(canEdit)
        frame.mailPayoutButton:SetText(self:GetMailPayoutButtonText())
    end

    frame.splitHeader.index:ClearAllPoints()
    frame.splitHeader.index:SetPoint("LEFT", indexLeft, 0)
    frame.splitHeader.index:SetWidth(indexWidth)
    frame.splitHeader.index:SetJustifyH("CENTER")

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

    frame.splitHeader.note:ClearAllPoints()
    frame.splitHeader.note:SetPoint("LEFT", noteLeft, 0)
    frame.splitHeader.note:SetWidth(noteWidth)
    frame.splitHeader.note:SetJustifyH("CENTER")

    frame.splitHeader.debt:ClearAllPoints()
    frame.splitHeader.debt:SetPoint("LEFT", debtLeft, 0)
    frame.splitHeader.debt:SetWidth(debtWidth)
    frame.splitHeader.debt:SetJustifyH("CENTER")

    frame.splitHeader.net:ClearAllPoints()
    frame.splitHeader.net:SetPoint("LEFT", netLeft, 0)
    frame.splitHeader.net:SetWidth(netWidth)
    frame.splitHeader.net:SetJustifyH("CENTER")

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

            row.noteBox = CreateFrame("EditBox", nil, row)
            row.noteBox:SetPoint("LEFT", noteLeft, 0)
            setupTextBox(row.noteBox, noteWidth, "")
            row.noteBox:SetJustifyH("CENTER")
            row.noteBox:SetScript("OnEnterPressed", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "note", selfBox:GetText())
                selfBox:ClearFocus()
            end)
            row.noteBox:SetScript("OnEscapePressed", function(selfBox)
                selfBox:ClearFocus()
            end)
            row.noteBox:SetScript("OnEditFocusLost", function(selfBox)
                addon:UpdateSplitEntryField(row.playerName, "note", selfBox:GetText())
            end)

            row.bonusButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.bonusButton, 20, 18, "+")
            row.bonusButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.bonusButton:SetScript("OnClick", function()
                addon:ApplySplitPreset(row.playerName, "bonus")
            end)

            row.penaltyButton = CreateFrame("Button", nil, row)
            setupMiniActionButton(row.penaltyButton, 20, 18, "-")
            row.penaltyButton:SetFrameLevel(row:GetFrameLevel() + 4)
            row.penaltyButton:SetScript("OnClick", function()
                addon:ApplySplitPreset(row.playerName, "penalty")
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
        row.noteBox:ClearAllPoints()
        row.noteBox:SetPoint("LEFT", noteLeft, 0)
        row.noteBox:SetWidth(noteWidth)
        row.bonusButton:ClearAllPoints()
        row.bonusButton:SetPoint("LEFT", bonusLeft, 0)
        row.penaltyButton:ClearAllPoints()
        row.penaltyButton:SetPoint("LEFT", penaltyLeft, 0)
        row.modeButton:ClearAllPoints()
        row.modeButton:SetPoint("LEFT", toggleLeft, 0)
        row.debtBox:ClearAllPoints()
        row.debtBox:SetPoint("LEFT", debtLeft, 0)
        row.debtBox:SetWidth(debtWidth)
        row.net:ClearAllPoints()
        row.net:SetPoint("LEFT", netLeft, 0)
        row.net:SetWidth(netWidth)

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
            row.noteBox:Hide()
            row.bonusButton:Hide()
            row.penaltyButton:Hide()
            row.modeButton:Hide()
            row.debtBox:Hide()
            row.net:Hide()
            row:Show()
        else
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
            row:SetBackdropBorderColor(0.25, 0.08, 0.08, 0.8)
            row.separatorLabel:Hide()
            row.index:Show()
            row.name:Show()
            row.spec:Show()
            row.roleBox:Show()
            row.percentBox:Show()
            row.noteBox:Show()
            row.bonusButton:Show()
            row.penaltyButton:Show()
            row.modeButton:Show()
            row.debtBox:Show()
            row.net:Show()
        end

        if not data.separator then
            row.playerName = data.name
            row.isSubstitute = data.isSubstitute
            row.index:SetText(data.index or "")
            row.name:SetText(data.name)
            row.spec:SetText(data.spec ~= "" and tostring(data.spec) or "...")

            if not row.roleBox:HasFocus() then
                row.roleBox:SetText(tostring(data.role or ""))
            end

            if not row.percentBox:HasFocus() then
                row.percentBox:SetText(tostring(data.percent or 0))
            end

            if not row.noteBox:HasFocus() then
                row.noteBox:SetText(tostring(data.note or ""))
            end

            if not row.debtBox:HasFocus() then
                row.debtBox:SetText(tostring(data.debt or 0))
            end

            row.roleBox:EnableMouse(canEdit)
            row.percentBox:EnableMouse(canEdit)
            row.noteBox:EnableMouse(canEdit)
            row.bonusButton:SetEnabled(canEdit)
            row.penaltyButton:SetEnabled(canEdit)
            row.modeButton:SetEnabled(canEdit)
            row.debtBox:EnableMouse(canEdit)
            row.modeButton:SetText(data.isSubstitute and "Осн" or "Зам")
            row.net:SetText(formatGold(data.net or 0))

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

function addon:RefreshMainWindow()
    local frame = self.frame or self:CreateMainWindow()
    local auction = self.currentAuction or {}
    local rows = self:GetSortedBids()
    local passes = self:GetSortedPasses()
    local itemLink = auction.itemLink or self.pendingItemLink
    local itemName = itemLink
    local texture = "Interface/Icons/INV_Misc_QuestionMark"
    local payout = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.payout
    local sales = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.sales or {}
    local saleCount = table.getn(sales)
    local isController = self:IsPlayerController()
    local hasFullAccess = self:HasFullInterfaceAccess()
    local playerName = self:GetPlayerName()
    local hasPassed = auction.passes and auction.passes[playerName] or false
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

    if frame.activeAuctionId ~= auction.id then
        frame.activeAuctionId = auction.id
        frame.bidManualOverride = false
        frame.incrementManualOverride = false
        frame.lastSuggestedBid = nil
    end

    frame.leaderText:SetText("Мастер лутер: " .. tostring(self:GetLeaderName() or "неизвестно"))
    if self:IsAuctionActive() then
        frame.statusText:SetText("Статус: торги | " .. tostring(timeLeft) .. "s")
    else
        frame.statusText:SetText("Статус: " .. tostring(auction.status or "idle"))
    end
    frame.itemText:SetText(itemName or "Перетащите предмет")
    frame.itemButton.icon:SetTexture(texture)

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

    if self:IsAuctionActive() and not self:IsPlayerController() and auction.minBid and auction.minBid > 0 and not frame.minBidBox:HasFocus() then
        frame.minBidBox:SetText(tostring(auction.minBid))
    end

    if self:IsAuctionActive() and not self:IsPlayerController() and auction.increment and auction.increment > 0 and not frame.incrementBox:HasFocus() then
        self:NormalizeClientRaiseStep()
    end

    if self:IsAuctionActive() and not frame.durationBox:HasFocus() then
        frame.durationBox:SetText(tostring(timeLeft))
    elseif not self:IsAuctionActive() and not frame.durationBox:HasFocus() and auction.duration and auction.duration > 0 then
        frame.durationBox:SetText(tostring(auction.duration))
    end

    if self:IsAuctionActive() and not frame.bidBox:HasFocus() then
        local suggestedBid = self:GetSuggestedBidBase()
        local currentBid = tonumber(frame.bidBox:GetText())

        if (not frame.bidManualOverride) or currentBid == frame.lastSuggestedBid then
            frame.bidBox:SetText(tostring(suggestedBid))
            frame.lastSuggestedBid = suggestedBid
        end
    end

    for index = 1, table.getn(frame.rows) do
        local row = frame.rows[index]
        local bid = rows[index]

        if index > maxAuctionRows then
            row:Hide()
        elseif bid then
            row.rank:SetText(index)
            row.player:SetText(bid.name)
            row.amount:SetText(tostring(bid.amount) .. "g")
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
                    row.item:SetText(tostring(sale.winner or "?") .. " - " .. tostring(sale.amount or 0) .. "g")
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
            row.amount:SetPoint("RIGHT", -18, 0)
            row.amount:SetWidth(72)
            row.amount:SetJustifyH("RIGHT")

            frame.summaryRows[index] = row
        end

        row:SetSize(summaryContentWidth, 22)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row.item:SetWidth(summaryWinnerLeft - 58)
        row.winner:ClearAllPoints()
        row.winner:SetPoint("LEFT", summaryWinnerLeft, 0)

        itemLabel = sale.itemLink or sale.itemName or "Неизвестный лот"
        row.index:SetText(index)
        row.item:SetText(itemLabel)
        row.winner:SetText(tostring(sale.winner or "-"))
        row.amount:SetText(tostring(sale.amount or 0) .. "g")
        row:Show()
    end

    for index = saleCount + 1, table.getn(frame.summaryRows) do
        frame.summaryRows[index]:Hide()
    end

    frame.summaryContent:SetHeight(math.max(saleCount * 24, 28))
    self:RefreshSplitView(frame)
    frame.compactPotText:SetText("Пот: " .. formatGold(GoldBidDB.ledger.pot or 0))

    if payout then
        frame.footerText:SetText("Пот: " .. formatGold(GoldBidDB.ledger.pot or 0) .. " | Сплит: " .. formatGold(payout.perPlayer or 0))
    else
        frame.footerText:SetText("Пот: " .. formatGold(GoldBidDB.ledger.pot or 0))
    end

    frame.startButton:SetEnabled(self:IsPlayerController())
    frame.endButton:SetEnabled(self:IsPlayerController() and self:IsAuctionActive())
    if hasFullAccess then
        frame.resetButton:SetEnabled(self:IsPlayerController())
    else
        frame.resetButton:SetEnabled(not hasPassed)
    end
    frame.bidButton:SetEnabled(not hasPassed)
    frame.passButton:SetEnabled(not hasPassed)
    frame.bidBox:EnableMouse(not hasPassed)
    frame.addStepButton:SetEnabled(not hasPassed)
    self:UpdateMainWindowLayout()
    self:SetMainTab(frame.activeTab or "auction", true)
end
