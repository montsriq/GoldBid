local addon = GoldBid

local function createBackdrop(frame, bgColor, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(bgColor or { 0, 0, 0, 0.85 }))
    frame:SetBackdropBorderColor(unpack(borderColor or { 0.7, 0.08, 0.08, 1 }))
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

