GoldBid = GoldBid or {}
GoldBid.prefix = "GBID"
GoldBid.version = "2.0.0"

local addon = GoldBid
local frame = CreateFrame("Frame")

local function splitMessage(message)
    local parts = {}
    local startIndex = 1
    local separatorStart, separatorEnd

    if not message or message == "" then
        return parts
    end

    while true do
        separatorStart, separatorEnd = string.find(message, ";", startIndex, true)

        if not separatorStart then
            table.insert(parts, string.sub(message, startIndex))
            break
        end

        table.insert(parts, string.sub(message, startIndex, separatorStart - 1))
        startIndex = separatorEnd + 1

        if startIndex > string.len(message) + 1 then
            table.insert(parts, "")
            break
        end
    end

    return parts
end

local function splitList(value, separator)
    local parts = {}
    local token

    if not value or value == "" then
        return parts
    end

    separator = separator or ","

    for token in string.gmatch(value, "([^" .. separator .. "]+)") do
        table.insert(parts, token)
    end

    return parts
end

local function normalizeName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "none")
    end

    return string.match(name, "^[^-]+")
end

local function safenum(value, fallback)
    local number = tonumber(value)

    if number then
        return number
    end

    return fallback or 0
end

local function round2(value)
    if not value then
        return 0
    end

    if value >= 0 then
        return math.floor((value * 100) + 0.5) / 100
    end

    return math.ceil((value * 100) - 0.5) / 100
end

local function floorGold(value)
    value = tonumber(value) or 0
    return math.floor(value)
end

local function getTalentTabNameAndPoints(index, isInspect, talentGroup)
    local first, second, third, fourth, fifth = GetTalentTabInfo(index, isInspect, false, talentGroup)

    if type(first) == "string" then
        return first, third or 0
    end

    return second, fifth or 0
end

local function isPlayerPartyLeader()
    local leaderIndex

    if GetPartyLeaderIndex then
        leaderIndex = GetPartyLeaderIndex()
        return leaderIndex == 0
    end

    if UnitIsPartyLeader then
        return UnitIsPartyLeader("player")
    end

    return false
end

local function isPlayerRaidLeader()
    local index

    if IsRaidLeader then
        return IsRaidLeader()
    end

    if not UnitInRaid("player") then
        return false
    end

    for index = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(index)

        if name and normalizeName(name) == normalizeName(UnitName("player")) and rank == 2 then
            return true
        end
    end

    return false
end

function addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0aGoldBid:|r " .. tostring(message))
end

function addon:GetPlayerName()
    return normalizeName(UnitName("player"))
end

function addon:CreateAuctionId()
    self.sequence = (self.sequence or 0) + 1
    return tostring(time()) .. "-" .. tostring(self.sequence)
end

function addon:CreateDefaultDB()
    return {
        ledger = {
            sales = {},
            pot = 0,
            payout = nil,
        },
        split = {
            leaderSharePercent = 20,
            substitutePercent = 100,
            entries = {},
            lastComputed = nil,
        },
        ui = {
            minimap = {
                minimapPos = 220,
                hide = false,
                radius = 80,
            },
            autoStartOnDrag = false,
            controllerOverride = nil,
        },
    }
end

function addon:EnsureDB()
    if type(GoldBidDB) ~= "table" then
        GoldBidDB = self:CreateDefaultDB()
    end

    GoldBidDB.ledger = GoldBidDB.ledger or {}
    GoldBidDB.ledger.sales = GoldBidDB.ledger.sales or {}
    GoldBidDB.ledger.pot = GoldBidDB.ledger.pot or 0
    GoldBidDB.split = GoldBidDB.split or {}
    GoldBidDB.split.entries = GoldBidDB.split.entries or {}
    if GoldBidDB.split.leaderSharePercent == nil then
        GoldBidDB.split.leaderSharePercent = 20
    end
    if GoldBidDB.split.substitutePercent == nil then
        GoldBidDB.split.substitutePercent = 100
    end
    GoldBidDB.ui = GoldBidDB.ui or {}
    GoldBidDB.ui.minimap = GoldBidDB.ui.minimap or {}
    if GoldBidDB.ui.minimap.minimapPos == nil then
        GoldBidDB.ui.minimap.minimapPos = GoldBidDB.ui.minimap.angle or 220
    end
    if GoldBidDB.ui.minimap.hide == nil then
        GoldBidDB.ui.minimap.hide = false
    end
    if GoldBidDB.ui.minimap.radius == nil then
        GoldBidDB.ui.minimap.radius = 80
    end
    if GoldBidDB.ui.autoStartOnDrag == nil then
        GoldBidDB.ui.autoStartOnDrag = false
    end
    if GoldBidDB.ui.controllerOverride == "" then
        GoldBidDB.ui.controllerOverride = nil
    end
end

function addon:GetGroupRosterNames()
    local names = {}
    local seen = {}
    local index

    local function addName(name)
        name = normalizeName(name)

        if name and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end

    if UnitInRaid("player") then
        for index = 1, GetNumRaidMembers() do
            addName(GetRaidRosterInfo(index))
        end
    elseif GetNumPartyMembers() > 0 then
        addName(UnitName("player"))

        for index = 1, GetNumPartyMembers() do
            addName(UnitName("party" .. index))
        end
    else
        addName(UnitName("player"))
    end

    return names
end

function addon:IsRosterMember(name)
    local roster = self:GetGroupRosterNames()
    local normalizedName = normalizeName(name)
    local index

    if not normalizedName then
        return false
    end

    for index = 1, table.getn(roster) do
        if normalizeName(roster[index]) == normalizedName then
            return true
        end
    end

    return false
end

function addon:GetControllerCandidates()
    return self:GetGroupRosterNames()
end

function addon:GetAutoControllerName()
    local lootMethod, mlPartyIndex, mlRaidIndex = GetLootMethod()
    local leaderName
    local leaderIndex
    local index

    if lootMethod == "master" then
        if mlRaidIndex and mlRaidIndex > 0 then
            leaderName = normalizeName(GetRaidRosterInfo(mlRaidIndex))
        elseif mlPartyIndex and mlPartyIndex > 0 then
            leaderName = normalizeName(UnitName("party" .. mlPartyIndex))
        elseif not UnitInRaid("player") and (UnitInParty("player") or GetNumPartyMembers() > 0) then
            if GetPartyLeaderIndex then
                leaderIndex = GetPartyLeaderIndex()

                if leaderIndex == 0 then
                    leaderName = self:GetPlayerName()
                elseif leaderIndex and leaderIndex > 0 then
                    leaderName = normalizeName(UnitName("party" .. leaderIndex))
                end
            end
        elseif UnitInParty("player") or UnitInRaid("player") then
            leaderName = normalizeName(UnitName("player"))
        end
    end

    if not leaderName and UnitInRaid("player") then
        for index = 1, GetNumRaidMembers() do
            local name, rank, _, _, _, _, _, _, _, _, isML = GetRaidRosterInfo(index)

            if name and (isML or rank == 2) then
                leaderName = normalizeName(name)
                break
            end
        end
    end

    if not leaderName and not UnitInRaid("player") and (UnitInParty("player") or GetNumPartyMembers() > 0) then
        if GetPartyLeaderIndex then
            leaderIndex = GetPartyLeaderIndex()

            if leaderIndex == 0 then
                leaderName = self:GetPlayerName()
            elseif leaderIndex and leaderIndex > 0 then
                leaderName = normalizeName(UnitName("party" .. leaderIndex))
            end
        end
    end

    if not leaderName then
        if isPlayerPartyLeader() or isPlayerRaidLeader() or not (UnitInRaid("player") or UnitInParty("player")) then
            leaderName = self:GetPlayerName()
        end
    end

    return leaderName
end

function addon:GetControllerOverrideName()
    local overrideName

    self:EnsureDB()
    overrideName = normalizeName(GoldBidDB.ui and GoldBidDB.ui.controllerOverride)

    if overrideName and self:IsRosterMember(overrideName) then
        return overrideName
    end

    if GoldBidDB.ui then
        GoldBidDB.ui.controllerOverride = nil
    end

    return nil
end

function addon:CanManageController(name)
    local normalizedName = normalizeName(name)
    local index
    local auctionLeader = normalizeName(self.currentAuction and self.currentAuction.leader)

    if not normalizedName then
        return false
    end

    if not (UnitInRaid("player") or UnitInParty("player") or GetNumPartyMembers() > 0) then
        return normalizedName == self:GetPlayerName()
    end

    if auctionLeader and normalizedName == auctionLeader then
        return true
    end

    if self.masterLooter and normalizedName == normalizeName(self.masterLooter) then
        return true
    end

    if UnitInRaid("player") then
        for index = 1, GetNumRaidMembers() do
            local raidName, rank = GetRaidRosterInfo(index)

            if normalizedName == normalizeName(raidName) then
                return rank == 2 or rank == 1
            end
        end
    end

    if UnitInParty("player") or GetNumPartyMembers() > 0 then
        return normalizedName == normalizeName(self:GetAutoControllerName())
    end

    return normalizedName == self:GetPlayerName()
end

function addon:SetControllerOverride(name, skipBroadcast)
    local normalizedName = normalizeName(name)
    local autoControllerName
    local playerName = self:GetPlayerName()
    local channel
    local wasController = self:IsPlayerController()

    self:EnsureDB()

    if not skipBroadcast and (UnitInRaid("player") or GetNumPartyMembers() > 0) and not self:CanManageController(playerName) then
        self:Print("Менять мастер лутера может лидер рейда, помощник или текущий мастер лутер.")
        return false
    end

    if normalizedName and not self:IsRosterMember(normalizedName) then
        self:Print("Выбранный игрок не найден в группе или рейде.")
        return false
    end

    autoControllerName = normalizeName(self:GetAutoControllerName())

    if normalizedName == autoControllerName then
        normalizedName = nil
    end

    GoldBidDB.ui.controllerOverride = normalizedName
    self.masterLooter = nil
    self:UpdateLeader()

    if self.currentAuction and self.currentAuction.id then
        self.currentAuction.leader = self:GetLeaderName()
    end

    if not skipBroadcast then
        channel = self:GetDistributionChannel()

        if channel and (UnitInRaid("player") or GetNumPartyMembers() > 0) then
            self:SendCommand("CONTROLLER", { normalizedName or "" }, channel)

            if wasController or self:IsPlayerController() then
                self:BroadcastState(nil, true)
                self:SendPayoutState()
            end
        end
    end

    if self.UpdateMainWindowLayout then
        self:UpdateMainWindowLayout()
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    if self.RefreshControllerDropdown then
        self:RefreshControllerDropdown()
    end

    return true
end

function addon:EnsureSplitEntry(name)
    self:EnsureSplitDB()
    local entries = GoldBidDB.split.entries
    local leaderName = self:GetLeaderName() or self:GetPlayerName()
    local isLeader = normalizeName(name) == normalizeName(leaderName)
    local entry = entries[name]

    if not entry then
        entry = {
            role = isLeader and "рл" or "дд",
            percent = isLeader and 0 or 100,
            note = "",
            debt = 0,
            spec = "",
            roleManual = false,
        }
        entries[name] = entry
    end

    if entry.role == nil or entry.role == "" then
        entry.role = isLeader and "рл" or "дд"
    end

    if entry.percent == nil then
        entry.percent = isLeader and 0 or 100
    end

    if entry.note == nil then
        entry.note = ""
    end

    if entry.debt == nil then
        entry.debt = 0
    end

    if entry.spec == nil then
        entry.spec = ""
    end

    if entry.roleManual == nil then
        entry.roleManual = false
    end

    return entry
end

function addon:EnsureSplitDB()
    if type(GoldBidDB) ~= "table" then
        self:EnsureDB()
    end

    GoldBidDB.split = GoldBidDB.split or {}
    GoldBidDB.split.entries = GoldBidDB.split.entries or {}

    if GoldBidDB.split.leaderSharePercent == nil then
        GoldBidDB.split.leaderSharePercent = 20
    end

    if GoldBidDB.split.substitutePercent == nil then
        GoldBidDB.split.substitutePercent = 100
    end
end

function addon:RefreshSplitRoster()
    self:EnsureSplitDB()
    local roster = self:GetGroupRosterNames()
    local index

    for index = 1, table.getn(roster) do
        self:EnsureSplitEntry(roster[index])
    end

    return roster
end

function addon:SetLeaderSharePercent(value)
    self:EnsureSplitDB()
    GoldBidDB.split.leaderSharePercent = math.max(0, math.min(100, safenum(value, 20)))

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:NormalizeSpecName(specName, classToken)
    if not specName or specName == "" then
        return ""
    end

    if classToken == "DRUID" and specName == "Feral Combat" then
        return "Feral"
    end

    return specName
end

function addon:GetRoleForSpec(specName, classToken)
    specName = tostring(specName or "")

    if specName == "" then
        return nil
    end

    if specName == "Holy"
        or specName == "Discipline"
        or specName == "Restoration"
        or specName == "Свет"
        or specName == "Послушание"
        or specName == "Исцеление" then
        return "хил"
    end

    if specName == "Protection"
        or specName == "Blood"
        or specName == "Защита"
        or specName == "Кровь"
        or ((specName == "Feral" or specName == "Сила зверя") and classToken == "DRUID") then
        return "танк"
    end

    if specName == "Balance"
        or specName == "Elemental"
        or specName == "Enhancement"
        or specName == "Shadow"
        or specName == "Assassination"
        or specName == "Combat"
        or specName == "Subtlety"
        or specName == "Arcane"
        or specName == "Fire"
        or specName == "Frost"
        or specName == "Affliction"
        or specName == "Demonology"
        or specName == "Destruction"
        or specName == "Arms"
        or specName == "Fury"
        or specName == "Retribution"
        or specName == "Beast Mastery"
        or specName == "Marksmanship"
        or specName == "Survival"
        or specName == "Unholy"
        or specName == "Баланс"
        or specName == "Стихии"
        or specName == "Совершенствование"
        or specName == "Тьма"
        or specName == "Ликвидация"
        or specName == "Бой"
        or specName == "Скрытность"
        or specName == "Тайная магия"
        or specName == "Огонь"
        or specName == "Лед"
        or specName == "Колдовство"
        or specName == "Демонология"
        or specName == "Разрушение"
        or specName == "Оружие"
        or specName == "Неистовство"
        or specName == "Воздаяние"
        or specName == "Повелитель зверей"
        or specName == "Стрельба"
        or specName == "Выживание"
        or specName == "Нечестивость" then
        return "дд"
    end

    return nil
end

function addon:GetTalentSpecName(isInspect, classToken)
    local bestName = ""
    local bestPoints = -1
    local group = 1
    local tabCount = 0
    local index

    if GetActiveTalentGroup then
        group = GetActiveTalentGroup(isInspect, false) or 1
    end

    if GetNumTalentTabs then
        tabCount = GetNumTalentTabs(isInspect, false) or GetNumTalentTabs(isInspect) or 0
    end

    for index = 1, tabCount do
        local tabName, pointsSpent = getTalentTabNameAndPoints(index, isInspect, group)

        if pointsSpent > bestPoints then
            bestName = tabName or ""
            bestPoints = pointsSpent
        end
    end

    return self:NormalizeSpecName(bestName, classToken)
end

function addon:SetSplitEntrySpec(name, specName)
    self:EnsureSplitDB()
    local entry
    local unit
    local classToken
    local roleBySpec

    if not name or name == "" then
        return
    end

    entry = self:EnsureSplitEntry(name)
    entry.spec = tostring(specName or "")

    unit = self:GetUnitIdForName(name)
    classToken = unit and select(2, UnitClass(unit)) or nil
    roleBySpec = self:GetRoleForSpec(entry.spec, classToken)

    if roleBySpec and not entry.roleManual and entry.role ~= "рл" and entry.role ~= "замена" then
        entry.role = roleBySpec
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:SendPlayerSpec(target)
    local playerName = self:GetPlayerName()
    local unit = "player"
    local specName = self:GetTalentSpecName(false, select(2, UnitClass(unit)))
    local classToken = select(2, UnitClass(unit)) or ""
    local channel = target and "WHISPER" or self:GetDistributionChannel()

    if not playerName or playerName == "" then
        return
    end

    if not target and not (UnitInRaid("player") or UnitInParty("player")) then
        return
    end

    self:SetSplitEntrySpec(playerName, specName)
    self:SendCommand("SPEC", { playerName, specName or "", classToken }, channel, target)
end

function addon:GetUnitIdForName(name)
    local index

    name = normalizeName(name)

    if not name then
        return nil
    end

    if normalizeName(UnitName("player")) == name then
        return "player"
    end

    if UnitInRaid("player") then
        for index = 1, GetNumRaidMembers() do
            if normalizeName(UnitName("raid" .. index)) == name then
                return "raid" .. index
            end
        end
    else
        for index = 1, GetNumPartyMembers() do
            if normalizeName(UnitName("party" .. index)) == name then
                return "party" .. index
            end
        end
    end

    return nil
end

function addon:QueueSpecInspection(unit, force)
    local name
    local entry
    local now = time()

    if not unit or unit == "player" or not UnitExists(unit) then
        return
    end

    if not CanInspect or not CanInspect(unit) then
        return
    end

    name = normalizeName(UnitName(unit))

    if not name then
        return
    end

    entry = self:EnsureSplitEntry(name)
    self.inspectQueue = self.inspectQueue or {}
    self.inspectQueuedNames = self.inspectQueuedNames or {}
    self.inspectRequestedAt = self.inspectRequestedAt or {}

    if self.inspectQueuedNames[name] or self.inspectPendingName == name then
        return
    end

    if not force and entry.spec and entry.spec ~= "" then
        return
    end

    if not force and self.inspectRequestedAt[name] and (now - self.inspectRequestedAt[name]) < 30 then
        return
    end

    self.inspectQueuedNames[name] = true
    table.insert(self.inspectQueue, {
        unit = unit,
        name = name,
        classToken = select(2, UnitClass(unit)),
    })
end

function addon:QueueGroupSpecInspections(force)
    local index

    self:UpdatePlayerSpecialization()

    if UnitInRaid("player") then
        for index = 1, GetNumRaidMembers() do
            self:QueueSpecInspection("raid" .. index, force)
        end
    else
        for index = 1, GetNumPartyMembers() do
            self:QueueSpecInspection("party" .. index, force)
        end
    end
end

function addon:UpdatePlayerSpecialization()
    local specName = self:GetTalentSpecName(false, select(2, UnitClass("player")))

    self:SetSplitEntrySpec(self:GetPlayerName(), specName)
end

function addon:ProcessInspectQueue()
    local nextRequest

    if self.inspectPendingName then
        if self.inspectPendingAt and (time() - self.inspectPendingAt) > 4 then
            self.inspectPendingName = nil
            self.inspectPendingUnit = nil
            self.inspectPendingClassToken = nil
            self.inspectPendingAt = nil
            if ClearInspectPlayer then
                ClearInspectPlayer()
            end
        end
        return
    end

    self.inspectQueue = self.inspectQueue or {}
    self.inspectQueuedNames = self.inspectQueuedNames or {}

    if table.getn(self.inspectQueue) == 0 then
        return
    end

    if self.lastInspectDispatchAt and (time() - self.lastInspectDispatchAt) < 2 then
        return
    end

    nextRequest = table.remove(self.inspectQueue, 1)

    if not nextRequest then
        return
    end

    self.inspectQueuedNames[nextRequest.name] = nil

    if not nextRequest.unit or not UnitExists(nextRequest.unit) or not CanInspect or not CanInspect(nextRequest.unit) then
        return
    end

    NotifyInspect(nextRequest.unit)
    self.inspectPendingName = nextRequest.name
    self.inspectPendingUnit = nextRequest.unit
    self.inspectPendingClassToken = nextRequest.classToken
    self.inspectPendingAt = time()
    self.lastInspectDispatchAt = time()
    self.inspectRequestedAt[nextRequest.name] = time()
end

function addon:HandleInspectTalentReady(unit)
    local inspectUnit = unit or self.inspectPendingUnit
    local inspectName = self.inspectPendingName
    local classToken = self.inspectPendingClassToken
    local specName

    if inspectUnit and UnitExists(inspectUnit) then
        inspectName = normalizeName(UnitName(inspectUnit)) or inspectName
        classToken = select(2, UnitClass(inspectUnit)) or classToken
    end

    if inspectName then
        specName = self:GetTalentSpecName(true, classToken)
        self:SetSplitEntrySpec(inspectName, specName)
    end

    self.inspectPendingName = nil
    self.inspectPendingUnit = nil
    self.inspectPendingClassToken = nil
    self.inspectPendingAt = nil

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

function addon:GetDefaultPercentForRole(name, role)
    if normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
        return 0
    end

    if role == "замена" then
        return math.max(0, safenum(GoldBidDB.split.substitutePercent, 50))
    end

    return 100
end

function addon:UpdateSplitEntryField(name, field, value)
    self:EnsureSplitDB()
    local entry

    if not name or name == "" then
        return
    end

    entry = self:EnsureSplitEntry(name)

    if field == "percent" then
        entry.percent = math.max(0, safenum(value, entry.percent or 0))
    elseif field == "debt" then
        entry.debt = safenum(value, entry.debt or 0)
    elseif field == "role" then
        entry.role = tostring(value or "")
        entry.roleManual = entry.role ~= ""

        if not entry.roleManual then
            local unit = self:GetUnitIdForName(name)
            local classToken = unit and select(2, UnitClass(unit)) or nil

            entry.role = self:GetRoleForSpec(entry.spec, classToken) or entry.role
        end
    elseif field == "note" then
        entry.note = tostring(value or "")
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:ApplySplitPreset(name, preset)
    self:EnsureSplitDB()
    local entry

    if not name or name == "" then
        return
    end

    entry = self:EnsureSplitEntry(name)

    if preset == "bonus" then
        entry.percent = math.max(0, safenum(entry.percent, 0) + 5)
    elseif preset == "penalty" then
        entry.percent = math.max(0, safenum(entry.percent, 0) - 5)
    elseif preset == "substitute" then
        entry.role = "замена"
        entry.roleManual = true
        entry.percent = self:GetDefaultPercentForRole(name, "замена")
        if entry.note == "" then
            entry.note = "Замена"
        end
    elseif preset == "main" then
        if normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
            entry.role = "рл"
            entry.percent = 0
            entry.roleManual = true
        else
            local unit = self:GetUnitIdForName(name)
            local classToken = unit and select(2, UnitClass(unit)) or nil

            entry.role = self:GetRoleForSpec(entry.spec, classToken) or "дд"
            entry.percent = self:GetDefaultPercentForRole(name, "дд")
            entry.roleManual = false
        end

        if entry.note == "Замена" then
            entry.note = ""
        end
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:ComputeDetailedSplit()
    self:EnsureSplitDB()
    local roster = self:RefreshSplitRoster()
    local leaderPercent = math.max(0, math.min(100, safenum(GoldBidDB.split.leaderSharePercent, 20)))
    local totalPot = safenum(GoldBidDB.ledger.pot, 0)
    local leaderShareAmount = floorGold(totalPot * (leaderPercent / 100))
    local distributablePot = floorGold(totalPot - leaderShareAmount)
    local results = {}
    local totalWeight = 0
    local totalDebt = 0
    local totalNet = 0
    local mainCount = 0
    local substituteCount = 0
    local baseShare
    local index

    for index = 1, table.getn(roster) do
        local name = roster[index]
        local entry = self:EnsureSplitEntry(name)
        local percent = math.max(0, safenum(entry.percent, 0))
        local debt = safenum(entry.debt, 0)
        local weight = percent / 100

        totalWeight = totalWeight + weight
        totalDebt = totalDebt + debt

        table.insert(results, {
            index = index,
            name = name,
            spec = tostring(entry.spec or ""),
            role = tostring(entry.role or ""),
            percent = percent,
            note = tostring(entry.note or ""),
            debt = debt,
            weight = weight,
            isLeader = normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()),
            isSubstitute = tostring(entry.role or "") == "замена",
        })
    end

    table.sort(results, function(left, right)
        if left.isLeader ~= right.isLeader then
            return left.isLeader
        end

        if left.isSubstitute ~= right.isSubstitute then
            return not left.isSubstitute
        end

        return tostring(left.name or "") < tostring(right.name or "")
    end)

    baseShare = totalWeight > 0 and floorGold(distributablePot / totalWeight) or 0

    for index = 1, table.getn(results) do
        local row = results[index]

        row.gross = floorGold(baseShare * row.weight)
        row.net = floorGold(row.gross - row.debt)
        totalNet = totalNet + row.net

        if row.isSubstitute then
            substituteCount = substituteCount + 1
        else
            mainCount = mainCount + 1
        end
    end

    GoldBidDB.split.lastComputed = {
        totalPot = totalPot,
        leaderSharePercent = leaderPercent,
        leaderShareAmount = floorGold(leaderShareAmount),
        distributablePot = distributablePot,
        baseShare = baseShare,
        totalWeight = round2(totalWeight),
        totalDebt = floorGold(totalDebt),
        totalNet = floorGold(totalNet),
        mainCount = mainCount,
        substituteCount = substituteCount,
        rows = results,
    }

    return GoldBidDB.split.lastComputed
end

function addon:IsMailOpen()
    if MailFrame and MailFrame.IsShown and MailFrame:IsShown() then
        return true
    end

    if SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() then
        return true
    end

    return false
end

function addon:GetMailPayoutState()
    if type(self.mailPayout) ~= "table" then
        self.mailPayout = {
            active = false,
            queue = {},
            index = 1,
            sent = 0,
            total = 0,
        }
    end

    return self.mailPayout
end

function addon:ResetMailPayoutState(skipRefresh)
    local state = self:GetMailPayoutState()

    state.active = false
    state.queue = {}
    state.index = 1
    state.sent = 0
    state.total = 0

    if not skipRefresh and self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:GetMailPayoutButtonText()
    local state = self:GetMailPayoutState()

    if not state.active or state.total <= 0 then
        return "Раздать почтой"
    end

    return string.format("Следующий %d/%d", math.min(state.index, state.total), state.total)
end

function addon:BuildMailPayoutQueue()
    local split = self:ComputeDetailedSplit()
    local queue = {}
    local playerName = normalizeName(self:GetPlayerName())
    local rows = (split and split.rows) or {}
    local index

    for index = 1, table.getn(rows) do
        local row = rows[index]
        local recipient = normalizeName(row and row.name)
        local amount = floorGold((row and row.net) or 0)

        if recipient and recipient ~= playerName and amount > 0 then
            table.insert(queue, {
                name = recipient,
                amount = amount,
            })
        end
    end

    return queue
end

function addon:PrepareNextMailEntry(quiet)
    local state = self:GetMailPayoutState()
    local entry
    local copper
    local gold
    local silver
    local bronze

    if not state.active then
        return false
    end

    if state.index > state.total then
        self:Print("Почтовая раздача завершена.")
        self:ResetMailPayoutState()
        return false
    end

    if not self:IsMailOpen() then
        if not quiet then
            self:Print("Подойдите к почтовому ящику.")
        end
        return false
    end

    entry = state.queue[state.index]

    if not entry then
        self:Print("Очередь почтовой раздачи повреждена, запускаю пересборку.")
        self:ResetMailPayoutState()
        return false
    end

    if SendMailNameEditBox and SendMailNameEditBox.SetText then
        SendMailNameEditBox:SetText(entry.name)
    end

    if SendMailSubjectEditBox and SendMailSubjectEditBox.SetText then
        SendMailSubjectEditBox:SetText("GoldBid GDKP выплата")
    end

    copper = math.max(0, floorGold(entry.amount) * 10000)
    gold = math.floor(copper / 10000)
    silver = math.floor((copper % 10000) / 100)
    bronze = copper % 100

    if SendMailCODButton then
        if SendMailCODButton.SetChecked then
            SendMailCODButton:SetChecked(false)
        end
    end

    if SetSendMailCOD then
        SetSendMailCOD(0)
    elseif MoneyInputFrame_SetCopper and SendMailCOD then
        MoneyInputFrame_SetCopper(SendMailCOD, 0)
    end

    if SendMailMoneyButton then
        if SendMailMoneyButton.SetChecked then
            SendMailMoneyButton:SetChecked(true)
        end
    end

    if SendMailMoney and SendMailMoney.Show then
        SendMailMoney:Show()
    end

    if SendMailCOD and SendMailCOD.Hide then
        SendMailCOD:Hide()
    end

    if SetSendMailMoney then
        SetSendMailMoney(copper)
    elseif SendMailMoneyGold and SendMailMoneySilver and SendMailMoneyCopper then
        SendMailMoneyGold:SetText(tostring(gold))
        SendMailMoneySilver:SetText(tostring(silver))
        SendMailMoneyCopper:SetText(tostring(bronze))

        local h = SendMailMoneyGold:GetScript("OnTextChanged")
        if h then h(SendMailMoneyGold, true) end
        h = SendMailMoneySilver:GetScript("OnTextChanged")
        if h then h(SendMailMoneySilver, true) end
        h = SendMailMoneyCopper:GetScript("OnTextChanged")
        if h then h(SendMailMoneyCopper, true) end
    elseif MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, copper)
    elseif SendMailMoney and SendMailMoney.gold and SendMailMoney.silver and SendMailMoney.copper then
        SendMailMoney.gold:SetText(tostring(gold))
        SendMailMoney.silver:SetText(tostring(silver))
        SendMailMoney.copper:SetText(tostring(bronze))

        local h = SendMailMoney.gold:GetScript("OnTextChanged")
        if h then h(SendMailMoney.gold, true) end
        h = SendMailMoney.silver:GetScript("OnTextChanged")
        if h then h(SendMailMoney.silver, true) end
        h = SendMailMoney.copper:GetScript("OnTextChanged")
        if h then h(SendMailMoney.copper, true) end
    end

    if SendMailFrame_Update then
        SendMailFrame_Update()
    end

    if not quiet then
        self:Print(string.format(
            "Подготовлено: %s - %dg (%d/%d). Нажмите кнопку отправки письма.",
            tostring(entry.name),
            floorGold(entry.amount),
            state.index,
            state.total
        ))
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    return true
end

function addon:StartMailPayout(autoFromMailShow)
    local state = self:GetMailPayoutState()
    local queue

    if not self:IsPlayerController() then
        if not autoFromMailShow then
            self:Print("Почтовую раздачу запускает только мастер лутер.")
        end
        return false
    end

    if not state.active then
        queue = self:BuildMailPayoutQueue()

        if table.getn(queue) == 0 then
            if not autoFromMailShow then
                self:Print("Нет игроков для выплаты через почту.")
            end
            return false
        end

        state.queue = queue
        state.total = table.getn(queue)
        state.index = 1
        state.sent = 0
        state.active = true

        self:Print("Собрана почтовая очередь: " .. tostring(state.total) .. " получателей.")
    end

    if not self:IsMailOpen() then
        if not autoFromMailShow then
            self:Print("Подойдите к почтовому ящику для автозаполнения писем.")
        end
        if self.RefreshMainWindow then
            self:RefreshMainWindow()
        end
        return false
    end

    return self:PrepareNextMailEntry(autoFromMailShow)
end

function addon:HandleMailSendSuccess()
    local state = self:GetMailPayoutState()
    local entry = state.queue[state.index]

    if not state.active then
        return
    end

    if entry then
        state.sent = state.sent + 1
        self:Print(string.format(
            "Отправлено: %s - %dg (%d/%d)",
            tostring(entry.name),
            floorGold(entry.amount),
            state.sent,
            state.total
        ))
    end

    state.index = state.index + 1

    if state.index > state.total then
        self:Print("Почтовая раздача завершена.")
        self:ResetMailPayoutState()
        return
    end

    self:PrepareNextMailEntry(true)
end

function addon:HandleMailSendFailed()
    local state = self:GetMailPayoutState()
    local entry

    if not state.active then
        return
    end

    entry = state.queue[state.index]

    if entry then
        self:Print("Ошибка отправки " .. tostring(entry.name) .. ". Проверьте почту и повторите отправку.")
    else
        self:Print("Ошибка отправки письма.")
    end

    self:PrepareNextMailEntry(true)
end

function addon:ResetAuction()
    self.currentAuction = {
        id = nil,
        itemLink = nil,
        itemName = nil,
        minBid = 0,
        increment = 0,
        duration = 60,
        leader = nil,
        bids = {},
        passes = {},
        startedAt = nil,
        endsAt = nil,
        status = "idle",
    }
end

function addon:EnsureAuctionState()
    if type(self.currentAuction) ~= "table" then
        self:ResetAuction()
        return
    end

    self.currentAuction.bids = self.currentAuction.bids or {}
    self.currentAuction.passes = self.currentAuction.passes or {}

    if self.currentAuction.minBid == nil then
        self.currentAuction.minBid = 0
    end

    if self.currentAuction.increment == nil then
        self.currentAuction.increment = 0
    end

    if self.currentAuction.duration == nil then
        self.currentAuction.duration = 60
    end

    if self.currentAuction.status == nil then
        self.currentAuction.status = "idle"
    end
end

function addon:ResetAllData(skipBroadcast)
    local ui = GoldBidDB and GoldBidDB.ui
    local splitSettings = GoldBidDB and GoldBidDB.split or {}

    if not skipBroadcast and self:IsPlayerController() and (UnitInRaid("player") or GetNumPartyMembers() > 0) then
        self:SendCommand("RESET_ALL", { self.version }, self:GetDistributionChannel())
    end

    GoldBidDB.ledger = {
        sales = {},
        pot = 0,
        payout = nil,
    }

    GoldBidDB.split = {
        leaderSharePercent = splitSettings.leaderSharePercent or 20,
        substitutePercent = splitSettings.substitutePercent or 100,
        entries = {},
        lastComputed = nil,
    }

    GoldBidDB.ui = ui or GoldBidDB.ui
    self.pendingItemLink = nil
    self.inspectQueue = {}
    self.inspectQueuedNames = {}
    self.inspectRequestedAt = {}
    self.inspectPendingName = nil
    self.inspectPendingUnit = nil
    self.inspectPendingClassToken = nil
    self.inspectPendingAt = nil
    self:ResetMailPayoutState(true)
    self:ResetAuction()
    self:UpdatePlayerSpecialization()

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:WipeTable(target)
    if not target then
        return
    end

    for key in pairs(target) do
        target[key] = nil
    end
end

function addon:UpdateLeader()
    local leaderName = self:GetControllerOverrideName() or self:GetAutoControllerName()
    self.masterLooter = leaderName
    return leaderName
end

function addon:GetLeaderName()
    if self.masterLooter and self:IsRosterMember(self.masterLooter) then
        return self.masterLooter
    end

    return self:UpdateLeader()
end

function addon:AcceptControllerSender(sender)
    local normalizedSender = normalizeName(sender)
    local auctionLeader = normalizeName(self.currentAuction and self.currentAuction.leader)

    if not normalizedSender then
        return false
    end

    if auctionLeader and normalizedSender == auctionLeader then
        return true
    end

    if self:IsController(normalizedSender) then
        return true
    end

    if not self.masterLooter then
        self.masterLooter = normalizedSender
        return true
    end

    return false
end

function addon:IsController(name)
    local leaderName = normalizeName((self.currentAuction and self.currentAuction.leader) or self:GetLeaderName())

    if not leaderName then
        return false
    end

    return normalizeName(name) == normalizeName(leaderName)
end

function addon:IsPlayerController()
    return self:IsController(self:GetPlayerName())
end

function addon:HasFullInterfaceAccess()
    return self:CanManageController(self:GetPlayerName())
end

function addon:IsAuctionActive()
    self:EnsureAuctionState()
    return self.currentAuction and self.currentAuction.id and self.currentAuction.status == "running"
end

function addon:GetDistributionChannel()
    if UnitInRaid("player") then
        return "RAID"
    end

    if UnitInParty("player") then
        return "PARTY"
    end

    if IsInGuild and IsInGuild() then
        return "GUILD"
    end

    return nil
end

function addon:SendCommand(command, fields, channel, target)
    local payload = command
    local distribution = channel or self:GetDistributionChannel()
    local index

    if not distribution then
        return
    end

    if fields then
        for index = 1, table.getn(fields) do
            payload = payload .. ";" .. tostring(fields[index] or "")
        end
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(self.prefix, payload, distribution, target)
    else
        SendAddonMessage(self.prefix, payload, distribution, target)
    end
end

function addon:EncodeBidList()
    local values = {}
    local rows = self:GetSortedBids()
    local index

    for index = 1, table.getn(rows) do
        values[index] = rows[index].name .. "=" .. tostring(rows[index].amount)
    end

    return table.concat(values, ",")
end

function addon:EncodePassList()
    local values = {}
    local name

    self:EnsureAuctionState()

    for name in pairs(self.currentAuction.passes) do
        table.insert(values, tostring(name))
    end

    table.sort(values)
    return table.concat(values, ",")
end

function addon:DecodeBidList(serialized)
    local bids = {}
    local index
    local entries = splitList(serialized, ",")

    for index = 1, table.getn(entries) do
        local name, amount = string.match(entries[index], "^([^=]+)=([0-9]+)$")

        if name and amount then
            bids[normalizeName(name)] = tonumber(amount)
        end
    end

    return bids
end

function addon:DecodePassList(serialized)
    local passes = {}
    local index
    local entries = splitList(serialized, ",")

    for index = 1, table.getn(entries) do
        local name = normalizeName(entries[index])

        if name then
            passes[name] = true
        end
    end

    return passes
end

function addon:GetSortedBids()
    local rows = {}
    local name

    self:EnsureAuctionState()

    for name in pairs(self.currentAuction.bids) do
        table.insert(rows, {
            name = name,
            amount = self.currentAuction.bids[name],
        })
    end

    table.sort(rows, function(left, right)
        if left.amount == right.amount then
            return left.name < right.name
        end

        return left.amount > right.amount
    end)

    return rows
end

function addon:GetSortedPasses()
    local rows = {}
    local name

    self:EnsureAuctionState()

    for name in pairs(self.currentAuction.passes) do
        table.insert(rows, name)
    end

    table.sort(rows)
    return rows
end

function addon:GetHighestBid()
    local rows = self:GetSortedBids()

    if rows[1] then
        return rows[1].name, rows[1].amount
    end
end

function addon:CanBid(amount, bidder)
    self:EnsureAuctionState()
    local auction = self.currentAuction
    local currentBid = auction.bids[bidder] or 0
    local _, topAmount = self:GetHighestBid()
    local minimum = auction.minBid

    if topAmount and topAmount > 0 then
        minimum = topAmount + math.max(auction.increment, 1)
    end

    if currentBid and currentBid >= amount then
        return false, "Новая ставка должна превышать текущую."
    end

    if auction.passes and auction.passes[bidder] then
        return false, "Вы уже нажали ПАС и больше не участвуете в торгах."
    end

    if amount < minimum then
        return false, "Минимальная ставка: " .. tostring(minimum) .. "g."
    end

    return true
end

function addon:ApplyAcceptedBid(bidder, amount)
    self:EnsureAuctionState()
    self.currentAuction.bids[bidder] = amount

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:ExtendAuctionForLateBid()
    local auction
    local timeLeft

    self:EnsureAuctionState()
    auction = self.currentAuction

    if not self:IsAuctionActive() or not auction.endsAt then
        return false
    end

    timeLeft = self:GetTimeLeft()
    if timeLeft > 15 then
        return false
    end

    auction.endsAt = auction.endsAt + 10
    auction.duration = safenum(auction.duration, 0) + 10
    return true
end

function addon:RecordPass(bidder)
    self:EnsureAuctionState()
    self.currentAuction.passes[bidder] = true

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:OpenAuction(itemLink, minBid, increment, duration, auctionId, leaderName)
    local itemName = itemLink
    local activeDuration = safenum(duration, 60)

    if GetItemInfo then
        itemName = GetItemInfo(itemLink) or itemLink
    end

    if activeDuration <= 0 then
        activeDuration = 60
    end

    self.currentAuction.id = auctionId or self:CreateAuctionId()
    self.currentAuction.itemLink = itemLink
    self.currentAuction.itemName = itemName
    self.currentAuction.minBid = safenum(minBid, 0)
    self.currentAuction.increment = safenum(increment, 0)
    self.currentAuction.duration = activeDuration
    self.currentAuction.leader = normalizeName(leaderName) or self:GetLeaderName()
    self.currentAuction.startedAt = time()
    self.currentAuction.endsAt = self.currentAuction.startedAt + activeDuration
    self.currentAuction.status = "running"
    self:WipeTable(self.currentAuction.bids)
    self:WipeTable(self.currentAuction.passes)

    if self.ShowMainWindow then
        self:ShowMainWindow()
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:GetTimeLeft()
    if not self:IsAuctionActive() or not self.currentAuction.endsAt then
        return 0
    end

    return math.max(0, self.currentAuction.endsAt - time())
end

function addon:CloseAuction(winner, amount)
    local auction = self.currentAuction

    if not auction.id or auction.status == "ended" then
        return
    end

    auction.status = "ended"

    if winner and amount and amount > 0 then
        table.insert(GoldBidDB.ledger.sales, {
            timestamp = date("%Y-%m-%d %H:%M:%S"),
            itemLink = auction.itemLink,
            winner = winner,
            amount = amount,
            auctionId = auction.id,
        })

        GoldBidDB.ledger.pot = (GoldBidDB.ledger.pot or 0) + amount
        self:Print(string.format("%s выиграл %s за %dg.", tostring(winner), tostring(auction.itemLink or auction.itemName or "лот"), amount))
    else
        self:Print(string.format("Торги по %s завершены без ставок.", tostring(auction.itemLink or auction.itemName or "лот")))
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:BroadcastState(target, forceSend)
    self:EnsureAuctionState()
    local auction = self.currentAuction

    if not forceSend and not self:IsPlayerController() then
        return
    end

    self:SendCommand("STATE", {
        auction.id or "",
        auction.itemLink or "",
        auction.minBid or 0,
        auction.increment or 0,
        auction.duration or 20,
        auction.startedAt or 0,
        auction.endsAt or 0,
        self:GetLeaderName() or "",
        auction.status or "idle",
        self:EncodeBidList(),
        self:EncodePassList(),
        GoldBidDB.ledger.pot or 0,
    }, target and "WHISPER" or self:GetDistributionChannel(), target)
end

function addon:SendPayoutState(target)
    local payout = GoldBidDB.ledger.payout

    if not payout then
        return
    end

    self:SendCommand("PAYOUT", {
        payout.totalPot or 0,
        payout.eligibleCount or 0,
        payout.perPlayer or 0,
    }, target and "WHISPER" or self:GetDistributionChannel(), target)
end

function addon:ApplyState(fields, sender)
    local auctionId = fields[2]
    local itemLink = fields[3]
    local minBid = safenum(fields[4], 0)
    local increment = safenum(fields[5], 0)
    local duration = safenum(fields[6], 60)
    local startedAt = safenum(fields[7], 0)
    local endsAt = safenum(fields[8], 0)
    local leaderName = normalizeName(fields[9]) or normalizeName(sender)
    local status = fields[10] or "idle"
    local bids = self:DecodeBidList(fields[11] or "")
    local passes = self:DecodePassList(fields[12] or "")
    local pot = safenum(fields[13], GoldBidDB.ledger.pot or 0)

    self:EnsureAuctionState()

    if GoldBidDB and GoldBidDB.ui then
        local autoControllerName = normalizeName(self:GetAutoControllerName())

        if leaderName and leaderName ~= autoControllerName and self:IsRosterMember(leaderName) then
            GoldBidDB.ui.controllerOverride = leaderName
        else
            GoldBidDB.ui.controllerOverride = nil
        end
    end

    self.masterLooter = leaderName

    if auctionId and auctionId ~= "" then
        self.currentAuction.id = auctionId
        self.currentAuction.itemLink = itemLink ~= "" and itemLink or nil
        self.currentAuction.itemName = itemLink ~= "" and ((GetItemInfo and GetItemInfo(itemLink)) or itemLink) or nil
        self.currentAuction.minBid = minBid
        self.currentAuction.increment = increment
        self.currentAuction.duration = duration
        self.currentAuction.startedAt = startedAt > 0 and startedAt or time()
        self.currentAuction.endsAt = endsAt > 0 and endsAt or (status == "running" and (time() + duration) or nil)
        self.currentAuction.leader = leaderName
        self.currentAuction.status = status
        self.currentAuction.bids = bids
        self.currentAuction.passes = passes
    else
        self:ResetAuction()
    end

    GoldBidDB.ledger.pot = pot

    if self.RefreshMainWindow then
        if self.currentAuction.status == "running" and self.ShowMainWindow then
            self:ShowMainWindow()
        end
        self:RefreshMainWindow()
    end
end

function addon:ComputePayout()
    local split = self:ComputeDetailedSplit()

    GoldBidDB.ledger.payout = {
        totalPot = split.totalPot,
        eligibleCount = table.getn(split.rows),
        perPlayer = split.baseShare,
        leaderShareAmount = split.leaderShareAmount,
        distributablePot = split.distributablePot,
        totalDebt = split.totalDebt,
        totalNet = split.totalNet,
    }

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    return GoldBidDB.ledger.payout
end

function addon:BuildExportText()
    local function cleanCell(value)
        local text = tostring(value or "")

        text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
        text = string.gsub(text, "|r", "")
        text = string.gsub(text, "|H.-|h(.-)|h", "%1")
        text = string.gsub(text, "[\r\n\t]", " ")
        text = string.gsub(text, "%s+", " ")
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")

        if text == "" then
            return "-"
        end

        return text
    end

    local function pushTableHeader(lines, columns)
        local separators = {}
        local index

        table.insert(lines, "| " .. table.concat(columns, " | ") .. " |")

        for index = 1, table.getn(columns) do
            separators[index] = "---"
        end

        table.insert(lines, "| " .. table.concat(separators, " | ") .. " |")
    end

    local lines = {
        "==============================",
        "      Экспорт GoldBid GDKP",
        "==============================",
        "Версия: " .. cleanCell(self.version),
        "Лидер: " .. cleanCell(self:GetLeaderName() or "неизвестно"),
        "Дата: " .. date("%Y-%m-%d %H:%M:%S"),
        "Пот: " .. tostring(floorGold(GoldBidDB.ledger.pot or 0)) .. "g",
        "",
        "Продажи",
    }
    local sales = GoldBidDB.ledger.sales
    local split = self:ComputeDetailedSplit()
    local payout = GoldBidDB.ledger.payout
    local index

    if table.getn(sales) == 0 then
        table.insert(lines, "Нет продаж")
    else
        pushTableHeader(lines, { "#", "Лот", "Победитель", "Цена" })

        for index = 1, table.getn(sales) do
            local sale = sales[index]

            table.insert(lines, string.format(
                "| %d | %s | %s | %dg |",
                index,
                cleanCell(sale.itemLink or "?"),
                cleanCell(sale.winner or "?"),
                floorGold(sale.amount or 0)
            ))
        end
    end

    if payout then
        table.insert(lines, "")
        table.insert(lines, "Итоги делёжки")
        table.insert(lines, string.format("Участников: %d", payout.eligibleCount or 0))
        table.insert(lines, string.format("База 100%%: %dg", floorGold(payout.perPlayer or 0)))
        table.insert(lines, string.format("Доля РЛ: %dg", floorGold(payout.leaderShareAmount or 0)))
        table.insert(lines, string.format("К распределению: %dg", floorGold(payout.distributablePot or 0)))
        table.insert(lines, string.format("Долги всего: %dg", floorGold(payout.totalDebt or 0)))
        table.insert(lines, string.format("Итого к выплате: %dg", floorGold(payout.totalNet or 0)))
    end

    if split and split.rows and table.getn(split.rows) > 0 then
        table.insert(lines, "")
        table.insert(lines, "Детальная делёжка")
        table.insert(lines, string.format("Основа: %d | Замены: %d", split.mainCount or 0, split.substituteCount or 0))
        pushTableHeader(lines, { "#", "Игрок", "Спек", "Роль", "%", "Долг", "К выплате", "Примечание" })

        for index = 1, table.getn(split.rows) do
            local row = split.rows[index]

            table.insert(lines, string.format(
                "| %d | %s | %s | %s | %d | %dg | %dg | %s |",
                index,
                cleanCell(row.name or "?"),
                cleanCell(row.spec or ""),
                cleanCell(row.role or "-"),
                floorGold(row.percent or 0),
                floorGold(row.debt or 0),
                floorGold(row.net or 0),
                cleanCell(row.note or "")
            ))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "==============================")

    return table.concat(lines, "\n")
end

function addon:HandleBidMessage(fields, sender)
    local auctionId = fields[2]
    local amount = safenum(fields[3], 0)
    local bidder = normalizeName(sender)
    local ok, reason

    if not self:IsPlayerController() then
        return
    end

    if not self:IsAuctionActive() or auctionId ~= self.currentAuction.id then
        return
    end

    ok, reason = self:CanBid(amount, bidder)

    if not ok then
        self:SendCommand("ERROR", { reason or "Invalid bid." }, "WHISPER", sender)
        return
    end

    self:ApplyAcceptedBid(bidder, amount)
    self:SendCommand("ACCEPT", { auctionId, bidder, amount }, self:GetDistributionChannel())
    if self:ExtendAuctionForLateBid() then
        self:BroadcastState()
    end
end

function addon:HandlePassMessage(fields, sender)
    local auctionId = fields[2]
    local bidder = normalizeName(sender)

    if not self:IsPlayerController() then
        return
    end

    if not self:IsAuctionActive() or auctionId ~= self.currentAuction.id then
        return
    end

    self:RecordPass(bidder)
    self:SendCommand("PASSACK", { auctionId, bidder }, self:GetDistributionChannel())
end

function addon:HandleAddonMessage(prefix, message, channel, sender)
    local fields
    local command

    if prefix ~= self.prefix then
        return
    end

    fields = splitMessage(message)
    command = fields[1]
    sender = normalizeName(sender)

    if command == "REQUEST_SYNC" then
        if self:IsPlayerController() then
            self:SendCommand("CONTROLLER", { (GoldBidDB and GoldBidDB.ui and GoldBidDB.ui.controllerOverride) or "" }, "WHISPER", sender)
            self:BroadcastState(sender)
            self:SendPayoutState(sender)
        else
            self:SendPlayerSpec()
        end
        return
    end

    if command == "SPEC" then
        if self:IsPlayerController() then
            self:SetSplitEntrySpec(normalizeName(fields[2]) or sender, fields[3] or "")
        end
        return
    end

    if command == "CONTROLLER" then
        if self:CanManageController(sender) then
            self:SetControllerOverride(fields[2], true)
        end
        return
    end

    if command == "STATE" then
        if self:AcceptControllerSender(sender) then
            self:ApplyState(fields, sender)
        end
        return
    end

    if command == "PAYOUT" then
        if self:AcceptControllerSender(sender) then
            GoldBidDB.ledger.payout = {
                totalPot = safenum(fields[2], 0),
                eligibleCount = safenum(fields[3], 0),
                perPlayer = safenum(fields[4], 0),
            }

            if self.RefreshMainWindow then
                self:RefreshMainWindow()
            end
        end
        return
    end

    if command == "START" then
        if self:AcceptControllerSender(sender) then
            self:OpenAuction(fields[3], fields[4], fields[5], fields[6], fields[2], sender)
        end
        return
    end

    if command == "BID" then
        self:HandleBidMessage(fields, sender)
        return
    end

    if command == "ACCEPT" then
        if self:AcceptControllerSender(sender) and self.currentAuction.id == fields[2] then
            self:ApplyAcceptedBid(normalizeName(fields[3]), safenum(fields[4], 0))
        end
        return
    end

    if command == "PASS" then
        self:HandlePassMessage(fields, sender)
        return
    end

    if command == "PASSACK" then
        if self:AcceptControllerSender(sender) and self.currentAuction.id == fields[2] then
            self:RecordPass(normalizeName(fields[3]))
        end
        return
    end

    if command == "END" then
        if self:AcceptControllerSender(sender) and self.currentAuction.id == fields[2] then
            self:CloseAuction(normalizeName(fields[3]), safenum(fields[4], 0))
        end
        return
    end

    if command == "ERROR" and fields[2] then
        self:Print(fields[2])
        return
    end

    if command == "RESET_ALL" then
        if self:AcceptControllerSender(sender) then
            self:ResetAllData(true)
            self:Print("Данные GoldBid были сброшены.")
        end
    end
end

function addon:StartAuction(itemLink, minBid, increment, duration)
    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может начать аукцион.")
        return
    end

    if not itemLink or itemLink == "" then
        self:Print("Сначала установите предмет (перетащите в окно или /gbid item [ссылка]).")
        return
    end

    self:OpenAuction(itemLink, minBid, increment, duration, self:CreateAuctionId(), self:GetPlayerName())
    self:SendCommand("START", {
        self.currentAuction.id,
        self.currentAuction.itemLink,
        self.currentAuction.minBid,
        self.currentAuction.increment,
        self.currentAuction.duration,
    }, self:GetDistributionChannel())
    self:BroadcastState()
end

function addon:EndAuction()
    local winner, amount

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может завершить аукцион.")
        return
    end

    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    winner, amount = self:GetHighestBid()

    self:CloseAuction(winner, amount)
    self:SendCommand("END", {
        self.currentAuction.id,
        winner or "",
        amount or 0,
    }, self:GetDistributionChannel())
    self:BroadcastState()
end

function addon:SubmitBid(amount)
    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    amount = safenum(amount, 0)

    if amount <= 0 then
        self:Print("Ставка должна быть больше нуля.")
        return
    end

    self:SendCommand("BID", { self.currentAuction.id, amount }, self:GetDistributionChannel())
end

function addon:SubmitPass()
    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    self:SendCommand("PASS", { self.currentAuction.id }, self:GetDistributionChannel())
end

function addon:SetPendingItem(itemLink)
    self.pendingItemLink = itemLink

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:RequestSync()
    self.lastSyncRequestAt = time()
    self:SendCommand("REQUEST_SYNC", { self.version }, self:GetDistributionChannel())
end

frame:RegisterEvent("CHAT_MSG_ADDON")
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
frame:SetScript("OnUpdate", function(_, elapsed)
    addon.updateThrottle = (addon.updateThrottle or 0) + elapsed
    addon.syncThrottle = (addon.syncThrottle or 0) + elapsed

    if addon.updateThrottle < 0.2 then
        if addon.syncThrottle < 2 then
            return
        end
    else
        addon.updateThrottle = 0

        if addon:IsPlayerController() and addon:IsAuctionActive() and addon:GetTimeLeft() <= 0 then
            addon:EndAuction()
            return
        end

        if addon.RefreshMainWindow then
            addon:RefreshMainWindow()
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

    addon:ProcessInspectQueue()
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        addon:HandleAddonMessage(...)
        return
    end

    if event == "INSPECT_TALENT_READY" then
        addon:HandleInspectTalentReady(...)
        return
    end

    if event == "MAIL_SHOW" then
        if addon:IsPlayerController() then
            addon:StartMailPayout(true)
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
        addon:HandleMailSendFailed()
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
