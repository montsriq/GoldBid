GoldBid = GoldBid or {}
GoldBid.prefix = "GBID"
GoldBid.version = "2.0.0"

local addon = GoldBid
local frame = CreateFrame("Frame")
local npcTypeFlag = COMBATLOG_OBJECT_TYPE_NPC or 0
local DEFAULT_GUILD_SHARE_PERCENT = 10
local DEFAULT_LEADER_SHARE_PERCENT = 10

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

local function clampPercent(value, fallback, maxValue)
    local percent = math.max(0, safenum(value, fallback or 0))

    if maxValue ~= nil then
        percent = math.min(percent, maxValue)
    end

    return percent
end

local function getEffectiveFixedSharePercents(splitSettings, leaderOverridePercent)
    local guildPercent = clampPercent(splitSettings and splitSettings.guildSharePercent, DEFAULT_GUILD_SHARE_PERCENT, 100)
    local leaderPercent = clampPercent(
        leaderOverridePercent ~= nil and leaderOverridePercent or (splitSettings and splitSettings.leaderSharePercent),
        DEFAULT_LEADER_SHARE_PERCENT,
        math.max(0, 100 - guildPercent)
    )

    return guildPercent, leaderPercent, math.max(0, 100 - guildPercent - leaderPercent)
end

local function ensureSplitSettingsDefaults(splitSettings)
    local normalizedRosterSnapshot = {}
    local key
    local value

    if type(splitSettings) ~= "table" then
        return
    end

    splitSettings.entries = splitSettings.entries or {}

    if type(splitSettings.rosterSnapshot) ~= "table" then
        splitSettings.rosterSnapshot = {}
    end

    for key, value in pairs(splitSettings.rosterSnapshot) do
        local name

        if type(key) == "number" then
            name = normalizeName(value)
        elseif value then
            name = normalizeName(key)
        end

        if name then
            normalizedRosterSnapshot[name] = true
        end
    end

    splitSettings.rosterSnapshot = normalizedRosterSnapshot

    if splitSettings.guildSharePercent == nil then
        splitSettings.guildSharePercent = DEFAULT_GUILD_SHARE_PERCENT

        if splitSettings.leaderSharePercent == nil or splitSettings.leaderSharePercent == 0 then
            splitSettings.leaderSharePercent = DEFAULT_LEADER_SHARE_PERCENT
        end

        splitSettings.fixedSharesMigrated = true
    elseif splitSettings.leaderSharePercent == nil then
        splitSettings.leaderSharePercent = DEFAULT_LEADER_SHARE_PERCENT
    end

    if splitSettings.substitutePercent == nil then
        splitSettings.substitutePercent = 100
    end
end

local function buildSplitPayoutKey(totalPot, guildPercent, leaderPercent, distributablePot, baseShare, rows)
    local parts = {
        "pot=" .. tostring(floorGold(totalPot)),
        "guild=" .. tostring(floorGold(guildPercent)),
        "leader=" .. tostring(floorGold(leaderPercent)),
        "pool=" .. tostring(floorGold(distributablePot)),
        "base=" .. tostring(floorGold(baseShare)),
    }
    local index

    for index = 1, table.getn(rows or {}) do
        local row = rows[index]

        parts[#parts + 1] = table.concat({
            tostring(row and row.name or ""),
            tostring(row and row.role or ""),
            tostring(row and row.isLeader and 1 or 0),
            tostring(row and row.isSubstitute and 1 or 0),
            tostring(floorGold((row and row.percent) or 0)),
            tostring(floorGold((row and row.debt) or 0)),
            tostring(floorGold((row and row.gross) or 0)),
            tostring(floorGold((row and row.net) or 0)),
        }, ":")
    end

    return table.concat(parts, ";")
end

local function formatGroupedNumber(value)
    local negative = false
    local formatted
    local changed

    value = floorGold(value)

    if value < 0 then
        negative = true
        value = math.abs(value)
    end

    formatted = tostring(value)

    repeat
        formatted, changed = string.gsub(formatted, "^([0-9]+)([0-9][0-9][0-9])", "%1 %2")
    until changed == 0

    if negative then
        return "-" .. formatted
    end

    return formatted
end

local function formatGoldAmount(value)
    return formatGroupedNumber(value) .. "g"
end

local function formatClockDuration(value)
    local totalSeconds = math.max(0, safenum(value, 0))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end

    return string.format("%d:%02d", minutes, seconds)
end

local randomRollPattern = nil
local lootItemSelfPattern = nil
local lootItemSelfMultiplePattern = nil

local function normalizeAuctionMode(mode)
    mode = string.lower(tostring(mode or "goldbid"))

    if mode == "roll" then
        return "roll"
    end

    return "goldbid"
end

local function buildGlobalStringPattern(template)
    template = tostring(template or "")
    template = string.gsub(template, "%%s", "\001")
    template = string.gsub(template, "%%d", "\002")
    template = string.gsub(template, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    template = string.gsub(template, "\001", "(.+)")
    template = string.gsub(template, "\002", "(%%d+)")

    return "^" .. template .. "$"
end

local function getRandomRollPattern()
    local template

    if randomRollPattern then
        return randomRollPattern
    end

    template = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    randomRollPattern = buildGlobalStringPattern(template)

    return randomRollPattern
end

local function getLootItemSelfPattern()
    if not lootItemSelfPattern then
        lootItemSelfPattern = buildGlobalStringPattern(LOOT_ITEM_SELF or "You receive loot: %s.")
    end

    return lootItemSelfPattern
end

local function getLootItemSelfMultiplePattern()
    if not lootItemSelfMultiplePattern then
        lootItemSelfMultiplePattern = buildGlobalStringPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
    end

    return lootItemSelfMultiplePattern
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
        loot = {
            entries = {},
        },
        split = {
            guildSharePercent = DEFAULT_GUILD_SHARE_PERCENT,
            leaderSharePercent = DEFAULT_LEADER_SHARE_PERCENT,
            substitutePercent = 100,
            rosterSnapshot = {},
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
            distributionMode = "goldbid",
            damageSegmentKey = nil,
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
    GoldBidDB.loot = GoldBidDB.loot or {}
    GoldBidDB.loot.entries = GoldBidDB.loot.entries or {}
    GoldBidDB.split = GoldBidDB.split or {}
    ensureSplitSettingsDefaults(GoldBidDB.split)
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
    if GoldBidDB.ui.damageSegmentKey == "" then
        GoldBidDB.ui.damageSegmentKey = nil
    end
    GoldBidDB.ui.distributionMode = normalizeAuctionMode(GoldBidDB.ui.distributionMode)
end

function addon:EnsureLootDB()
    self:EnsureDB()
    GoldBidDB.loot = GoldBidDB.loot or {}
    GoldBidDB.loot.entries = GoldBidDB.loot.entries or {}
end

function addon:CreateLootEntryId()
    self.lootSequence = (self.lootSequence or 0) + 1
    return tostring(time()) .. "-loot-" .. tostring(self.lootSequence)
end

function addon:NormalizeLootEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    entry.id = tostring(entry.id or self:CreateLootEntryId())
    entry.itemLink = tostring(entry.itemLink or "")
    entry.itemName = tostring(entry.itemName or "")
    entry.bossName = tostring(entry.bossName or "Прочее")
    entry.sourceGuid = tostring(entry.sourceGuid or "")
    entry.lootedAt = safenum(entry.lootedAt, time())
    entry.expiresAt = safenum(entry.expiresAt, entry.lootedAt + 7200)
    entry.warned20 = entry.warned20 and true or false

    return entry
end

local MIN_TRACKED_LOOT_QUALITY = 4
local ATLASLOOT_ADDON_SIGNATURE_NAMES = {
    "AtlasLoot",
    "AtlasLoot_OriginalWoW",
    "AtlasLoot_BurningCrusade",
    "AtlasLoot_Crafting",
    "AtlasLoot_WorldEvents",
    "AtlasLoot_WrathoftheLichKing",
    "AtlasLoot_PVP",
    "Atlasloot_Nozdor",
}
local ATLASLOOT_NON_BOSS_TABLE_MARKERS = {
    "MENU",
    "TRASH",
    "PATTERN",
    "KEY",
    "QUEST",
    "TOKEN",
    "RUNE",
    "FILTER",
    "FALLBACK",
    "CRAFT",
    "PVP",
    "REP",
    "MOUNT",
    "PET",
}

local function normalizeItemColorHex(value)
    value = string.lower(tostring(value or ""))
    return string.gsub(value, "^ff", "")
end

local function getItemQualityFromLink(itemLink)
    local itemColor
    local qualityIndex

    if not itemLink or itemLink == "" then
        return nil
    end

    if GetItemInfo then
        local _, _, itemQuality = GetItemInfo(itemLink)

        if itemQuality ~= nil then
            return tonumber(itemQuality)
        end
    end

    itemColor = string.match(tostring(itemLink), "|c[fF][fF]([0-9A-Fa-f]+)|Hitem:")

    if not itemColor or type(ITEM_QUALITY_COLORS) ~= "table" then
        return nil
    end

    itemColor = normalizeItemColorHex(itemColor)

    for qualityIndex = 0, 7 do
        local colorData = ITEM_QUALITY_COLORS[qualityIndex]

        if colorData and normalizeItemColorHex(colorData.hex) == itemColor then
            return qualityIndex
        end
    end

    return nil
end

local function getItemIdFromLink(itemLink)
    local itemId

    if not itemLink or itemLink == "" then
        return nil
    end

    itemId = tonumber(string.match(tostring(itemLink), "item:(%d+)"))

    if itemId and itemId > 0 then
        return itemId
    end

    return nil
end

local function getAtlasLootItemId(value)
    local itemId

    if type(value) == "number" then
        if value > 0 then
            return value
        end

        return nil
    end

    if type(value) ~= "string" then
        return nil
    end

    itemId = tonumber(string.match(value, "item:(%d+)") or string.match(value, "^(%d+)$"))

    if itemId and itemId > 0 then
        return itemId
    end

    return nil
end

function addon:ShouldTrackLootItem(itemLink, quality)
    local itemQuality = tonumber(quality)
    local equipLoc = ""

    if not itemLink or itemLink == "" then
        return false
    end

    if GetItemInfo then
        local _, _, infoQuality, _, _, _, _, _, infoEquipLoc = GetItemInfo(itemLink)

        if infoQuality ~= nil then
            itemQuality = tonumber(infoQuality)
        end

        equipLoc = tostring(infoEquipLoc or "")
    end

    if itemQuality == nil then
        itemQuality = getItemQualityFromLink(itemLink)
    end

    if not itemQuality or itemQuality < MIN_TRACKED_LOOT_QUALITY then
        return false
    end

    if IsEquippableItem and IsEquippableItem(itemLink) then
        return true
    end

    return equipLoc ~= ""
end

function addon:GetLootEntries()
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries
    local filteredEntries = {}
    local index

    for index = 1, table.getn(entries) do
        local entry = self:NormalizeLootEntry(entries[index])

        if entry and self:ShouldTrackLootItem(entry.itemLink) then
            table.insert(filteredEntries, entry)
        end
    end

    return filteredEntries
end

function addon:GetLootTransferTimeLeft(entry)
    if not entry then
        return 0
    end

    return math.max(0, safenum(entry.expiresAt, 0) - time())
end

function addon:FormatLootTimeLeft(seconds)
    local hours
    local minutes

    seconds = math.max(0, safenum(seconds, 0))

    if seconds <= 0 then
        return "Истекло"
    end

    if seconds < 60 then
        return tostring(seconds) .. "с"
    end

    hours = math.floor(seconds / 3600)
    minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dч %02dм", hours, minutes)
    end

    return string.format("%dм", minutes)
end

function addon:CanUseAtlasLootBossData()
    return IsAddOnLoaded and IsAddOnLoaded("AtlasLoot") and type(_G.AtlasLoot_TableNames) == "table"
end

function addon:GetAtlasLootBossIndexSignature()
    local parts = {}
    local addonIndex
    local tableCount = 0

    if type(_G.AtlasLoot_Data) == "table" then
        for _ in pairs(_G.AtlasLoot_Data) do
            tableCount = tableCount + 1
        end
    end

    table.insert(parts, tostring(tableCount))

    for addonIndex = 1, table.getn(ATLASLOOT_ADDON_SIGNATURE_NAMES) do
        table.insert(parts, tostring((IsAddOnLoaded and IsAddOnLoaded(ATLASLOOT_ADDON_SIGNATURE_NAMES[addonIndex])) and 1 or 0))
    end

    return table.concat(parts, ":")
end

function addon:IsAtlasLootBossTable(dataId)
    local upperDataId
    local markerIndex

    if not dataId or dataId == "" then
        return false
    end

    upperDataId = string.upper(tostring(dataId))

    if string.match(upperDataId, "SET$") or string.find(upperDataId, "SETMENU", 1, true) then
        return false
    end

    for markerIndex = 1, table.getn(ATLASLOOT_NON_BOSS_TABLE_MARKERS) do
        if string.find(upperDataId, ATLASLOOT_NON_BOSS_TABLE_MARKERS[markerIndex], 1, true) then
            return false
        end
    end

    return true
end

function addon:CollectAtlasLootBossTableIds()
    local dataIds = {}
    local seen = {}
    local function collect(buttonTables)
        local zoneData
        local dataId

        if type(buttonTables) ~= "table" then
            return
        end

        for _, zoneData in pairs(buttonTables) do
            if type(zoneData) == "table" then
                for _, dataId in pairs(zoneData) do
                    if type(dataId) == "string" and dataId ~= "" and not seen[dataId] then
                        seen[dataId] = true
                        table.insert(dataIds, dataId)
                    end
                end
            end
        end
    end

    collect(_G.AtlasLootBossButtons)
    collect(_G.AtlasLootNewBossButtons)
    collect(_G.AtlasLootWBBossButtons)

    return dataIds
end

function addon:IndexAtlasLootBossTable(index, dataId, bossName)
    local lootTable
    local row
    local itemId
    local record

    if not bossName or bossName == "" or type(_G.AtlasLoot_Data) ~= "table" then
        return
    end

    lootTable = _G.AtlasLoot_Data[dataId]

    if type(lootTable) ~= "table" then
        return
    end

    for _, row in pairs(lootTable) do
        if type(row) == "table" then
            itemId = getAtlasLootItemId(row[2])

            if itemId then
                record = index[itemId]

                if not record then
                    record = {
                        bossNames = {},
                        count = 0,
                        firstBossName = nil,
                    }
                    index[itemId] = record
                end

                if not record.bossNames[bossName] then
                    record.bossNames[bossName] = true
                    record.count = safenum(record.count, 0) + 1

                    if not record.firstBossName then
                        record.firstBossName = bossName
                    end
                end
            end
        end
    end
end

function addon:EnsureAtlasLootBossIndex()
    local signature
    local dataIds
    local index = {}
    local dataId
    local tableInfo
    local bossName

    if not self:CanUseAtlasLootBossData() then
        return nil
    end

    signature = self:GetAtlasLootBossIndexSignature()

    if self.atlasLootBossIndex and self.atlasLootBossIndexSignature == signature then
        return self.atlasLootBossIndex
    end

    if type(_G.AtlasLoot_LoadAllModules) == "function" then
        pcall(_G.AtlasLoot_LoadAllModules)
    end

    dataIds = self:CollectAtlasLootBossTableIds()

    for _, dataId in ipairs(dataIds) do
        tableInfo = _G.AtlasLoot_TableNames and _G.AtlasLoot_TableNames[dataId] or nil
        bossName = tableInfo and tostring(tableInfo[1] or "") or ""

        if self:IsAtlasLootBossTable(dataId)
            and bossName ~= ""
            and type(_G.AtlasLoot_Data) == "table"
            and type(_G.AtlasLoot_Data[dataId]) == "table" then
            self:IndexAtlasLootBossTable(index, dataId, bossName)
        end
    end

    self.atlasLootBossIndex = index
    self.atlasLootBossIndexSignature = self:GetAtlasLootBossIndexSignature()
    return self.atlasLootBossIndex
end

function addon:GetAtlasLootBossNameForItem(itemLink)
    local itemId = getItemIdFromLink(itemLink)
    local index = self:EnsureAtlasLootBossIndex()
    local record
    local lastBossName

    if not itemId or not index then
        return nil
    end

    record = index[itemId]

    if not record then
        return nil
    end

    lastBossName = self.lastLootContext and tostring(self.lastLootContext.name or "") or ""

    if lastBossName ~= "" and record.bossNames[lastBossName] then
        return lastBossName
    end

    if safenum(record.count, 0) == 1 then
        return record.firstBossName
    end

    return nil
end

function addon:ResolveBossNameForLoot(itemLink, sourceGuid)
    local bossName = self:GetBossNameForLootSource(sourceGuid)

    if bossName and bossName ~= "" and bossName ~= "Прочее" then
        return bossName
    end

    return self:GetAtlasLootBossNameForItem(itemLink) or "Прочее"
end

function addon:RememberLootSource(sourceGuid, sourceName)
    if not sourceGuid or sourceGuid == "" or not sourceName or sourceName == "" then
        return
    end

    self.recentLootSources = self.recentLootSources or {}
    self.recentLootSources[tostring(sourceGuid)] = {
        name = tostring(sourceName),
        at = time(),
    }
    self.lastLootContext = {
        name = tostring(sourceName),
        at = time(),
    }
end

function addon:CleanupRecentLootSources()
    local now = time()
    local sourceGuid
    local sourceData

    self.recentLootSources = self.recentLootSources or {}

    for sourceGuid, sourceData in pairs(self.recentLootSources) do
        if not sourceData or (now - safenum(sourceData.at, 0)) > 600 then
            self.recentLootSources[sourceGuid] = nil
        end
    end

    if self.lastLootContext and (now - safenum(self.lastLootContext.at, 0)) > 600 then
        self.lastLootContext = nil
    end
end

function addon:GetBossNameForLootSource(sourceGuid)
    local sourceData

    self:CleanupRecentLootSources()
    self.recentLootSources = self.recentLootSources or {}

    if sourceGuid and sourceGuid ~= "" then
        sourceData = self.recentLootSources[tostring(sourceGuid)]

        if sourceData and sourceData.name and sourceData.name ~= "" then
            return tostring(sourceData.name)
        end
    end

    if self.lastLootContext and self.lastLootContext.name and self.lastLootContext.name ~= "" then
        return tostring(self.lastLootContext.name)
    end

    return "Прочее"
end

function addon:GetLootSourceGuidForSlot(slotIndex)
    local sourceGuid

    if not GetLootSourceInfo then
        return nil
    end

    sourceGuid = select(1, GetLootSourceInfo(slotIndex))

    if sourceGuid and sourceGuid ~= "" then
        return tostring(sourceGuid)
    end

    return nil
end

function addon:RegisterLootEntry(itemLink, bossName, sourceGuid, quality)
    self:EnsureLootDB()

    if not itemLink or itemLink == "" or not self:ShouldTrackLootItem(itemLink, quality) then
        return nil
    end

    local entry = self:NormalizeLootEntry({
        id = self:CreateLootEntryId(),
        itemLink = itemLink,
        itemName = (GetItemInfo and GetItemInfo(itemLink)) or itemLink,
        bossName = bossName or "Прочее",
        sourceGuid = sourceGuid or "",
        lootedAt = time(),
        expiresAt = time() + 7200,
        warned20 = false,
    })

    if not entry then
        return nil
    end

    table.insert(GoldBidDB.loot.entries, entry)
    return entry
end

function addon:BuildLootTrackingKey(itemLink, bossName)
    return tostring(itemLink or "") .. "|" .. tostring(bossName or "Прочее")
end

function addon:TrackRecentLootWindowEntry(itemLink, bossName)
    local key
    local record

    if not itemLink or itemLink == "" then
        return
    end

    self.recentLootWindowEntries = self.recentLootWindowEntries or {}
    key = self:BuildLootTrackingKey(itemLink, bossName)
    record = self.recentLootWindowEntries[key] or { count = 0, at = time() }
    record.count = safenum(record.count, 0) + 1
    record.at = time()
    self.recentLootWindowEntries[key] = record
end

function addon:CleanupRecentLootWindowEntries()
    local now = time()
    local key
    local record

    self.recentLootWindowEntries = self.recentLootWindowEntries or {}

    for key, record in pairs(self.recentLootWindowEntries) do
        if not record or (now - safenum(record.at, 0)) > 15 then
            self.recentLootWindowEntries[key] = nil
        end
    end
end

function addon:ConsumeRecentLootWindowEntry(itemLink, bossName)
    local key
    local record

    if not itemLink or itemLink == "" then
        return false
    end

    self:CleanupRecentLootWindowEntries()
    key = self:BuildLootTrackingKey(itemLink, bossName)
    record = self.recentLootWindowEntries and self.recentLootWindowEntries[key] or nil

    if not record or safenum(record.count, 0) <= 0 then
        return false
    end

    record.count = record.count - 1

    if record.count <= 0 then
        self.recentLootWindowEntries[key] = nil
    else
        record.at = time()
        self.recentLootWindowEntries[key] = record
    end

    return true
end

function addon:CaptureLootWindowEntries()
    local slotCount
    local slotIndex
    local itemLink
    local slotQuality
    local sourceGuid
    local bossName
    local entry
    local capturedCount = 0

    if not GetNumLootItems then
        return 0
    end

    slotCount = GetNumLootItems() or 0

    for slotIndex = 1, slotCount do
        if LootSlotHasItem and LootSlotHasItem(slotIndex) and not (LootSlotIsCoin and LootSlotIsCoin(slotIndex)) then
            itemLink = GetLootSlotLink and GetLootSlotLink(slotIndex) or nil

            if itemLink and itemLink ~= "" then
                slotQuality = select(4, GetLootSlotInfo(slotIndex))
                sourceGuid = self:GetLootSourceGuidForSlot(slotIndex)
                bossName = self:ResolveBossNameForLoot(itemLink, sourceGuid)
                entry = self:RegisterLootEntry(itemLink, bossName, sourceGuid, slotQuality)

                if entry then
                    self:TrackRecentLootWindowEntry(itemLink, bossName)
                    capturedCount = capturedCount + 1
                end
            end
        end
    end

    return capturedCount
end

function addon:ScheduleLootWindowRetry(attempts)
    attempts = math.max(1, safenum(attempts, 3))
    self.pendingLootWindowRetryAt = (GetTime and GetTime() or 0) + 0.2
    self.pendingLootWindowRetryCount = math.max(safenum(self.pendingLootWindowRetryCount, 0), attempts)
    self.pendingLootChatUntil = time() + 15
end

function addon:ProcessPendingLootWindowRetry()
    local now
    local capturedCount

    if safenum(self.pendingLootWindowRetryCount, 0) <= 0 then
        return
    end

    now = GetTime and GetTime() or 0

    if now < safenum(self.pendingLootWindowRetryAt, 0) then
        return
    end

    capturedCount = self:CaptureLootWindowEntries()

    if capturedCount > 0 then
        self.pendingLootWindowRetryCount = 0
        self.pendingLootWindowRetryAt = nil

        if self.RefreshMainWindow then
            self:RefreshMainWindow()
        end
        return
    end

    self.pendingLootWindowRetryCount = self.pendingLootWindowRetryCount - 1

    if self.pendingLootWindowRetryCount <= 0 then
        self.pendingLootWindowRetryCount = 0
        self.pendingLootWindowRetryAt = nil
        return
    end

    self.pendingLootWindowRetryAt = now + 0.2
end

function addon:ExtractLootItemLinkFromMessage(message)
    local itemLink

    if not message or message == "" then
        return nil
    end

    itemLink = string.match(message, getLootItemSelfPattern())

    if itemLink and itemLink ~= "" then
        return itemLink
    end

    itemLink = string.match(message, getLootItemSelfMultiplePattern())

    if itemLink and itemLink ~= "" then
        return itemLink
    end

    return nil
end

function addon:HandleLootChatMessage(message)
    local itemLink
    local bossName

    if not self.pendingLootChatUntil or time() > self.pendingLootChatUntil then
        return
    end

    itemLink = self:ExtractLootItemLinkFromMessage(message)

    if not itemLink or itemLink == "" then
        return
    end

    bossName = self:ResolveBossNameForLoot(itemLink, nil)

    if self:ConsumeRecentLootWindowEntry(itemLink, bossName) then
        return
    end

    self:RegisterLootEntry(itemLink, bossName, nil)

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:HandleCombatLogEvent(...)
    local subEvent = select(2, ...)
    local destGUID = select(7, ...)
    local destName = select(8, ...)
    local destFlags = safenum(select(9, ...), 0)

    if subEvent ~= "PARTY_KILL" and subEvent ~= "UNIT_DIED" and subEvent ~= "UNIT_DESTROYED" then
        return
    end

    if not destGUID or not destName then
        return
    end

    if bit and bit.band and npcTypeFlag > 0 and bit.band(destFlags, npcTypeFlag) == 0 then
        return
    end

    self:RememberLootSource(destGUID, destName)
end

function addon:HandleLootOpened()
    local capturedCount = self:CaptureLootWindowEntries()

    self.pendingLootChatUntil = time() + 15

    if capturedCount <= 0 then
        self:ScheduleLootWindowRetry(5)
    else
        self.pendingLootWindowRetryCount = 0
        self.pendingLootWindowRetryAt = nil
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:BuildLootSummary()
    local entries = self:GetLootEntries()
    local groups = {}
    local rows = {}
    local groupOrder = {}
    local totalCount = 0
    local urgentCount = 0
    local index
    local group
    local bossName
    local timeLeft

    for index = 1, table.getn(entries) do
        local entry = entries[index]

        bossName = tostring(entry.bossName or "Прочее")
        group = groups[bossName]

        if not group then
            group = {
                title = bossName,
                entries = {},
                firstAt = safenum(entry.lootedAt, 0),
            }
            groups[bossName] = group
            table.insert(groupOrder, group)
        end

        table.insert(group.entries, entry)
        if safenum(entry.lootedAt, 0) > group.firstAt then
            group.firstAt = safenum(entry.lootedAt, 0)
        end

        totalCount = totalCount + 1
        timeLeft = self:GetLootTransferTimeLeft(entry)
        if timeLeft > 0 and timeLeft <= 1200 then
            urgentCount = urgentCount + 1
        end
    end

    table.sort(groupOrder, function(left, right)
        if left.firstAt == right.firstAt then
            return tostring(left.title or "") < tostring(right.title or "")
        end

        return left.firstAt > right.firstAt
    end)

    for index = 1, table.getn(groupOrder) do
        group = groupOrder[index]

        table.sort(group.entries, function(left, right)
            local leftTime = self:GetLootTransferTimeLeft(left)
            local rightTime = self:GetLootTransferTimeLeft(right)

            if leftTime == rightTime then
                return safenum(left.lootedAt, 0) > safenum(right.lootedAt, 0)
            end

            if leftTime <= 0 then
                return false
            end

            if rightTime <= 0 then
                return true
            end

            return leftTime < rightTime
        end)

        table.insert(rows, {
            separator = true,
            title = group.title,
        })

        for bossName = 1, table.getn(group.entries) do
            table.insert(rows, group.entries[bossName])
        end
    end

    return {
        rows = rows,
        totalCount = totalCount,
        urgentCount = urgentCount,
        bossCount = table.getn(groupOrder),
    }
end

function addon:ShowLootTransferWarning(entry)
    local itemLabel = tostring(entry and (entry.itemLink or entry.itemName) or "предмет")
    local bossLabel = tostring(entry and entry.bossName or "Прочее")
    local message = string.format("До передачи %s осталось меньше 20 минут. Источник: %s.", itemLabel, bossLabel)

    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2, 1)
    end

    self:Print(message)
end

function addon:CheckLootExpiryWarnings()
    local entries = self:GetLootEntries()
    local index
    local entry
    local timeLeft

    for index = 1, table.getn(entries) do
        entry = entries[index]
        timeLeft = self:GetLootTransferTimeLeft(entry)

        if not entry.warned20 and timeLeft > 0 and timeLeft <= 1200 then
            entry.warned20 = true
            self:ShowLootTransferWarning(entry)
        end
    end
end

function addon:SelectLootEntryForAuction(entryId)
    local entries = self:GetLootEntries()
    local index
    local entry

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может выбирать предмет из списка лута.")
        return false
    end

    if self:IsAuctionActive() then
        self:Print("Сначала завершите текущий аукцион.")
        return false
    end

    for index = 1, table.getn(entries) do
        if tostring(entries[index].id or "") == tostring(entryId or "") then
            entry = entries[index]
            break
        end
    end

    if not entry or not entry.itemLink or entry.itemLink == "" then
        return false
    end

    self:SetPendingItem(entry.itemLink)

    if self.SetMainTab then
        self:SetMainTab("auction")
    end

    return true
end

function addon:IsDetailsAvailable()
    local details = _G.Details or _G._detalhes

    return type(details) == "table" and type(details.GetCurrentCombat) == "function" and type(details.GetCombatSegments) == "function"
end

function addon:GetSelectedDamageSegmentKey()
    self:EnsureDB()

    return GoldBidDB.ui and GoldBidDB.ui.damageSegmentKey or nil
end

function addon:SetSelectedDamageSegmentKey(segmentKey)
    self:EnsureDB()
    GoldBidDB.ui.damageSegmentKey = (segmentKey and segmentKey ~= "") and tostring(segmentKey) or nil

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:BuildDamageSegmentKey(combat, sourceTag)
    local combatNumber = combat and combat.GetCombatNumber and combat:GetCombatNumber() or 0
    local combatId = combat and combat.GetCombatId and combat:GetCombatId() or 0
    local startTime = combat and combat.GetStartTime and combat:GetStartTime() or 0

    return table.concat({
        tostring(sourceTag or "history"),
        tostring(combatNumber or 0),
        tostring(combatId or 0),
        tostring(startTime or 0),
    }, ":")
end

function addon:BuildDamageSegmentLabel(segment)
    local name = tostring(segment and segment.name or "Неизвестный босс")
    local durationText = formatClockDuration(segment and segment.elapsed or 0)
    local suffix = nil

    if segment then
        if segment.isCurrent then
            suffix = "идёт бой"
        elseif segment.endDate and segment.endDate ~= "" then
            suffix = tostring(segment.endDate)
        elseif segment.startDate and segment.startDate ~= "" then
            suffix = tostring(segment.startDate)
        elseif segment.combatNumber and segment.combatNumber > 0 then
            suffix = "#" .. tostring(segment.combatNumber)
        end
    end

    if suffix and suffix ~= "" then
        return name .. " | " .. suffix .. " | " .. durationText
    end

    return name .. " | " .. durationText
end

function addon:GetDamageSpecName(playerName, classToken, specId)
    local detailsFramework = _G.DetailsFramework
    local splitEntries
    local splitEntry
    local specName = ""
    local infoId
    local infoName

    specId = tonumber(specId) or 0
    classToken = tostring(classToken or "")
    playerName = normalizeName(playerName)

    if specId > 0 and detailsFramework and type(detailsFramework.GetSpecializationInfoByID) == "function" then
        infoId, infoName = detailsFramework.GetSpecializationInfoByID(specId)
        specName = tostring(infoName or "")
    end

    if (not specName or specName == "") and GoldBidDB and GoldBidDB.split and GoldBidDB.split.entries and playerName then
        splitEntries = GoldBidDB.split.entries
        splitEntry = splitEntries[playerName]
        specName = splitEntry and tostring(splitEntry.spec or "") or ""
    end

    if specName ~= "" then
        return self:NormalizeSpecName(specName, classToken)
    end

    return ""
end

function addon:GetSuggestedMinBidForItem(itemLink)
    local gearScoreFunc = _G.GearScore_GetItemScore
    local itemLevel
    local equipLoc
    local gearScoreItemLevel
    local itemId
    local tokenInfo
    local ok

    if not itemLink or itemLink == "" or not GetItemInfo then
        return nil
    end

    _, _, _, itemLevel, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    itemLevel = tonumber(itemLevel)
    equipLoc = tostring(equipLoc or "")

    if type(gearScoreFunc) == "function" then
        ok, _, gearScoreItemLevel = pcall(gearScoreFunc, itemLink)
        if ok then
            gearScoreItemLevel = tonumber(gearScoreItemLevel)
        else
            gearScoreItemLevel = nil
        end
    end

    if (not gearScoreItemLevel or gearScoreItemLevel <= 0) and type(_G.GS_Tokens) == "table" then
        itemId = string.match(tostring(itemLink), "item:(%d+)")
        tokenInfo = itemId and _G.GS_Tokens[itemId] or nil
        gearScoreItemLevel = tokenInfo and tonumber(tokenInfo.ItemLevel) or gearScoreItemLevel
    end

    if itemLevel and itemLevel > 0 and gearScoreItemLevel and gearScoreItemLevel > 0 then
        itemLevel = math.max(itemLevel, gearScoreItemLevel)
    elseif (not itemLevel or itemLevel <= 0) and gearScoreItemLevel and gearScoreItemLevel > 0 then
        itemLevel = gearScoreItemLevel
    end

    if not itemLevel or itemLevel <= 0 then
        return nil
    end

    if itemLevel >= 239 and equipLoc == "INVTYPE_TRINKET" then
        return 5000
    end

    if itemLevel >= 239 then
        return 3000
    end

    if itemLevel >= 232 then
        return 2000
    end

    if itemLevel >= 226 then
        return 1000
    end

    return 100
end

function addon:GetSuggestedRaiseStepForMinBid(minBid)
    local bid = tonumber(minBid)

    if not bid then
        return nil
    end

    if bid >= 5000 then
        return 500
    end

    if bid >= 1000 then
        return 100
    end

    return 10
end

function addon:GetDefaultAuctionMinBid()
    return 1000
end

function addon:GetDefaultAuctionIncrement()
    return self:GetSuggestedRaiseStepForMinBid(self:GetDefaultAuctionMinBid()) or 100
end

function addon:GetDefaultAuctionDuration()
    return 30
end

function addon:IsBossDamageCombat(combat)
    local bossInfo
    local combatType

    if type(combat) ~= "table" then
        return false, nil, DETAILS_SEGMENTTYPE_GENERIC or 0
    end

    bossInfo = combat.GetBossInfo and combat:GetBossInfo() or combat.is_boss
    combatType = combat.GetCombatType and combat:GetCombatType() or safenum(combat.combat_type, DETAILS_SEGMENTTYPE_GENERIC or 0)

    if type(bossInfo) == "table" and next(bossInfo) ~= nil then
        return true, bossInfo, combatType
    end

    if combatType == DETAILS_SEGMENTTYPE_RAID_BOSS or combatType == DETAILS_SEGMENTTYPE_DUNGEON_BOSS then
        return true, bossInfo, combatType
    end

    return false, bossInfo, combatType
end

function addon:IsFallbackDamageCombat(combat, combatType)
    local instanceType
    local elapsed
    local isTrash = false

    if type(combat) ~= "table" then
        return false
    end

    combatType = tonumber(combatType) or (DETAILS_SEGMENTTYPE_GENERIC or 0)
    instanceType = tostring(combat.instance_type or "")
    elapsed = combat.GetCombatTime and combat:GetCombatTime() or 0

    if elapsed <= 0 then
        return false
    end

    if combatType == DETAILS_SEGMENTTYPE_OVERALL then
        return false
    end

    if type(combat.IsTrash) == "function" then
        isTrash = combat:IsTrash() and true or false
    elseif combat.is_trash then
        isTrash = true
    end

    if isTrash then
        return false
    end

    if combatType == DETAILS_SEGMENTTYPE_RAID_BOSS or combatType == DETAILS_SEGMENTTYPE_DUNGEON_BOSS then
        return true
    end

    return instanceType == "raid" or instanceType == "party"
end

function addon:GetAvailableDamageSegments()
    local segments = {}
    local fallbackSegments = {}
    local seen = {}
    local details = _G.Details or _G._detalhes
    local history
    local index

    if type(details) ~= "table" then
        return segments
    end

    local function addCombat(combat, sourceTag, isCurrent)
        local bossInfo
        local combatType
        local segment
        local startDate
        local endDate
        local isBossCombat

        if type(combat) ~= "table" or type(combat.GetActorList) ~= "function" or type(combat.GetCombatName) ~= "function" then
            return
        end

        isBossCombat, bossInfo, combatType = self:IsBossDamageCombat(combat)

        segment = {
            key = self:BuildDamageSegmentKey(combat, sourceTag),
            combat = combat,
            bossInfo = bossInfo,
            name = combat:GetCombatName(true),
            elapsed = combat.GetCombatTime and combat:GetCombatTime() or 0,
            combatNumber = combat.GetCombatNumber and combat:GetCombatNumber() or 0,
            combatId = combat.GetCombatId and combat:GetCombatId() or 0,
            isCurrent = isCurrent and true or false,
        }

        if not segment.name or segment.name == "" or segment.name == UNKNOWN then
            if type(bossInfo) == "table" then
                segment.name = bossInfo.encounter or bossInfo.name or segment.name
            end
        end

        if not segment.name or segment.name == "" or segment.name == UNKNOWN then
            segment.name = "Бой"
        end

        if seen[segment.key] then
            return
        end

        if combat.GetDate then
            startDate, endDate = combat:GetDate()
            segment.startDate = startDate
            segment.endDate = endDate
        end

        segment.label = self:BuildDamageSegmentLabel(segment)

        if isBossCombat then
            seen[segment.key] = true
            table.insert(segments, segment)
        elseif self:IsFallbackDamageCombat(combat, combatType) then
            seen[segment.key] = true
            table.insert(fallbackSegments, segment)
        end
    end

    if type(details.GetCurrentCombat) == "function" then
        addCombat(details:GetCurrentCombat(), "current", true)
    end

    if type(details.GetCombatSegments) == "function" then
        history = details:GetCombatSegments() or {}

        for index = 1, table.getn(history) do
            addCombat(history[index], "history", false)
        end
    end

    local function sortSegments(list)
        table.sort(list, function(left, right)
            local leftCurrent = left and left.isCurrent and 1 or 0
            local rightCurrent = right and right.isCurrent and 1 or 0
            local leftNumber = left and safenum(left.combatNumber, 0) or 0
            local rightNumber = right and safenum(right.combatNumber, 0) or 0
            local leftStart = left and left.combat and left.combat.GetStartTime and left.combat:GetStartTime() or 0
            local rightStart = right and right.combat and right.combat.GetStartTime and right.combat:GetStartTime() or 0

            if leftCurrent ~= rightCurrent then
                return leftCurrent > rightCurrent
            end

            if leftNumber ~= rightNumber then
                return leftNumber > rightNumber
            end

            if leftStart ~= rightStart then
                return leftStart > rightStart
            end

            return tostring(left.name or "") < tostring(right.name or "")
        end)
    end

    sortSegments(segments)

    if table.getn(segments) > 0 then
        return segments
    end

    sortSegments(fallbackSegments)
    return fallbackSegments
end

function addon:BuildDamageSummary()
    local summary = {
        available = self:IsDetailsAvailable(),
        segments = {},
        rows = {},
        selectedKey = nil,
        selectedLabel = nil,
        totalDamage = 0,
        combatTime = 0,
        playerCount = 0,
        message = nil,
    }
    local segments
    local selectedKey
    local selectedSegment
    local actors
    local actorIndex
    local totalDamage = 0

    self:EnsureDB()

    if not summary.available then
        summary.message = "Details не найден или ещё не загрузился."
        return summary
    end

    segments = self:GetAvailableDamageSegments()
    summary.segments = segments

    if table.getn(segments) == 0 then
        summary.message = "В Details пока нет сохранённых боёв с боссами."
        return summary
    end

    selectedKey = self:GetSelectedDamageSegmentKey()

    for actorIndex = 1, table.getn(segments) do
        if segments[actorIndex].key == selectedKey then
            selectedSegment = segments[actorIndex]
            break
        end
    end

    if not selectedSegment then
        selectedSegment = segments[1]
        selectedKey = selectedSegment and selectedSegment.key or nil
        GoldBidDB.ui.damageSegmentKey = selectedKey
    end

    if not selectedSegment or type(selectedSegment.combat) ~= "table" then
        summary.message = "Не удалось получить бой из Details."
        return summary
    end

    summary.selectedKey = selectedKey
    summary.selectedLabel = selectedSegment.label
    summary.combatTime = selectedSegment.combat.GetCombatTime and selectedSegment.combat:GetCombatTime() or 0
    summary.segmentName = selectedSegment.name
    summary.segment = selectedSegment

    actors = selectedSegment.combat.GetActorList and selectedSegment.combat:GetActorList(DETAILS_ATTRIBUTE_DAMAGE or 1) or {}

    for actorIndex = 1, table.getn(actors) do
        local actor = actors[actorIndex]
        local actorName
        local actorTotal
        local actorClass
        local actorSpecId
        local actorSpecName
        local isPlayer = false

        if actor then
            if type(actor.IsPlayer) == "function" then
                isPlayer = actor:IsPlayer()
            else
                isPlayer = actor.grupo and true or false
            end
        end

        if isPlayer and actor and actor.grupo then
            actorName = normalizeName(actor.nome or actor.name)
            actorTotal = safenum(actor.total, 0)
            actorClass = tostring(actor.classe or actor.class or "")
            actorSpecId = tonumber(actor.spec) or 0
            actorSpecName = self:GetDamageSpecName(actorName, actorClass, actorSpecId)

            if actorName and actorName ~= "" then
                totalDamage = totalDamage + actorTotal
                table.insert(summary.rows, {
                    name = actorName,
                    class = actorClass,
                    specId = actorSpecId,
                    specName = actorSpecName,
                    total = actorTotal,
                    dps = summary.combatTime > 0 and round2(actorTotal / summary.combatTime) or 0,
                    activeTime = type(actor.Tempo) == "function" and actor:Tempo() or 0,
                    spec = actor.spec or 0,
                })
            end
        end
    end

    table.sort(summary.rows, function(left, right)
        if safenum(left.total, 0) == safenum(right.total, 0) then
            return tostring(left.name or "") < tostring(right.name or "")
        end

        return safenum(left.total, 0) > safenum(right.total, 0)
    end)

    for actorIndex = 1, table.getn(summary.rows) do
        local row = summary.rows[actorIndex]

        row.rank = actorIndex
        row.percent = totalDamage > 0 and round2((safenum(row.total, 0) / totalDamage) * 100) or 0
    end

    summary.totalDamage = totalDamage
    summary.playerCount = table.getn(summary.rows)
    return summary
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
    local adjustmentsMissing = false

    if not entry then
        entry = {
            role = isLeader and "рл" or "дд",
            percent = self:GetDefaultPercentForRole(name, isLeader and "рл" or "дд"),
            penaltyNote = "",
            bonusNote = "",
            penaltyAdjust = 0,
            bonusAdjust = 0,
            debt = 0,
            spec = "",
            classToken = "",
            roleManual = false,
            sentAmount = nil,
            sentPayoutKey = nil,
        }
        entries[name] = entry
    end

    if entry.role == nil or entry.role == "" then
        entry.role = isLeader and "рл" or "дд"
    end

    if entry.percent == nil then
        entry.percent = self:GetDefaultPercentForRole(name, entry.role)
    end

    if isLeader and GoldBidDB.split.fixedSharesMigrated then
        if safenum(entry.percent, 0) == 0 then
            entry.percent = self:GetDefaultPercentForRole(name, "рл")
            self:ResetSplitAdjustments(entry)
        end

        GoldBidDB.split.fixedSharesMigrated = nil
    end

    if entry.penaltyNote == nil then
        if entry.note ~= nil and entry.note ~= "" then
            entry.penaltyNote = tostring(entry.note)
        else
            entry.penaltyNote = ""
        end
    end

    if entry.bonusNote == nil then
        entry.bonusNote = ""
    end

    adjustmentsMissing = entry.penaltyAdjust == nil and entry.bonusAdjust == nil

    if entry.penaltyAdjust == nil then
        entry.penaltyAdjust = 0
    end

    if entry.bonusAdjust == nil then
        entry.bonusAdjust = 0
    end

    if entry.debt == nil then
        entry.debt = 0
    end

    if entry.spec == nil then
        entry.spec = ""
    end

    if entry.classToken == nil then
        entry.classToken = ""
    end

    if entry.roleManual == nil then
        entry.roleManual = false
    end

    if entry.sentAmount ~= nil then
        entry.sentAmount = floorGold(entry.sentAmount)
    end

    if entry.sentPayoutKey == "" then
        entry.sentPayoutKey = nil
    end

    if adjustmentsMissing then
        self:SyncSplitAdjustmentsToPercent(name, entry)
    end

    return entry
end

function addon:GetAuctionModeDisplayName(mode)
    if normalizeAuctionMode(mode) == "roll" then
        return "Roll"
    end

    return "GoldBid"
end

function addon:GetSelectedAuctionMode()
    self:EnsureDB()
    return normalizeAuctionMode(GoldBidDB.ui and GoldBidDB.ui.distributionMode)
end

function addon:SetSelectedAuctionMode(mode)
    self:EnsureDB()
    GoldBidDB.ui.distributionMode = normalizeAuctionMode(mode)

    if self.RefreshModeDropdown then
        self:RefreshModeDropdown()
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:GetCurrentAuctionMode()
    self:EnsureAuctionState()

    if self.currentAuction and self.currentAuction.id and self.currentAuction.status == "running" then
        return normalizeAuctionMode(self.currentAuction.mode)
    end

    return self:GetSelectedAuctionMode()
end

function addon:IsRollAuction()
    return self:GetCurrentAuctionMode() == "roll"
end

function addon:HasPlayerRolled(name)
    self:EnsureAuctionState()
    name = normalizeName(name)

    return name and self.currentAuction.bids and self.currentAuction.bids[name] ~= nil or false
end

function addon:EncodeNameSet(values)
    local rows = {}
    local name

    if type(values) ~= "table" then
        return ""
    end

    for name in pairs(values) do
        if name and name ~= "" then
            table.insert(rows, tostring(name))
        end
    end

    table.sort(rows)
    return table.concat(rows, ",")
end

function addon:DecodeNameSet(serialized)
    local values = {}
    local index
    local entries = splitList(serialized, ",")

    for index = 1, table.getn(entries) do
        local name = normalizeName(entries[index])

        if name then
            values[name] = true
        end
    end

    return values
end

function addon:EnsureSplitDB()
    if type(GoldBidDB) ~= "table" then
        self:EnsureDB()
    end

    GoldBidDB.split = GoldBidDB.split or {}
    ensureSplitSettingsDefaults(GoldBidDB.split)
end

function addon:RefreshSplitRoster()
    self:EnsureSplitDB()
    local currentRoster = self:GetGroupRosterNames()
    local roster = {}
    local rosterSnapshot = GoldBidDB.split.rosterSnapshot or {}
    local seen = {}
    local index
    local name

    local function addName(value, remember)
        value = normalizeName(value)

        if not value then
            return
        end

        if remember then
            rosterSnapshot[value] = true
        end

        if not seen[value] then
            seen[value] = true
            table.insert(roster, value)
        end
    end

    for index = 1, table.getn(currentRoster) do
        addName(currentRoster[index], true)
    end

    addName(self:GetLeaderName() or self:GetPlayerName(), true)

    for name in pairs(rosterSnapshot) do
        addName(name, false)
    end

    GoldBidDB.split.rosterSnapshot = rosterSnapshot

    for index = 1, table.getn(roster) do
        self:EnsureSplitEntry(roster[index])
    end

    return roster
end

function addon:SetLeaderSharePercent(value)
    self:EnsureSplitDB()
    local leaderName
    local leaderEntry

    GoldBidDB.split.leaderSharePercent = clampPercent(
        value,
        GoldBidDB.split.leaderSharePercent or DEFAULT_LEADER_SHARE_PERCENT,
        100
    )

    leaderName = self:GetLeaderName() or self:GetPlayerName()

    if leaderName and leaderName ~= "" then
        leaderEntry = self:EnsureSplitEntry(leaderName)

        if leaderEntry then
            leaderEntry.percent = GoldBidDB.split.leaderSharePercent
            self:ResetSplitAdjustments(leaderEntry)
        end
    end

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

function addon:NormalizeSplitRoleValue(value)
    value = tostring(value or "")

    if value == "" then
        return ""
    end

    if value == "МТ" or value == "мт" or value == "MT" or value == "mt" then
        return "мт"
    end

    if value == "ОТ" or value == "от" or value == "OT" or value == "ot" then
        return "от"
    end

    if value == "ДД" or value == "дд" or value == "DD" or value == "dd" then
        return "дд"
    end

    if value == "РЛ" or value == "рл" then
        return "рл"
    end

    if value == "Зам" or value == "зам" or value == "замена" then
        return "замена"
    end

    if value == "Танк" or value == "танк" then
        return "танк"
    end

    if value == "Хил" or value == "хил" then
        return "хил"
    end

    return value
end

function addon:GetSplitRoleDisplayName(role, isLeader, isSubstitute)
    role = self:NormalizeSplitRoleValue(role)

    if isLeader or role == "рл" then
        return "РЛ"
    end

    if isSubstitute or role == "замена" then
        return "Зам"
    end

    if role == "мт" then
        return "МТ"
    end

    if role == "от" then
        return "ОТ"
    end

    if role == "танк" then
        return "Танк"
    end

    if role == "хил" then
        return "Хил"
    end

    if role == "дд" then
        return "ДД"
    end

    return role ~= "" and role or "-"
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

function addon:GetSplitAutoRole(name, specName)
    local unit
    local classToken

    if normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
        return "рл"
    end

    unit = self:GetUnitIdForName(name)
    classToken = unit and select(2, UnitClass(unit)) or nil

    return self:GetRoleForSpec(specName, classToken) or "дд"
end

function addon:GetSplitClassToken(name)
    local unit
    local entry
    local classToken

    if not name or name == "" then
        return ""
    end

    unit = self:GetUnitIdForName(name)
    classToken = unit and select(2, UnitClass(unit)) or nil
    entry = self:EnsureSplitEntry(name)

    if classToken and classToken ~= "" then
        entry.classToken = tostring(classToken)
        return tostring(classToken)
    end

    return tostring(entry.classToken or "")
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

function addon:SetSplitEntrySpec(name, specName, classTokenHint)
    self:EnsureSplitDB()
    local entry
    local unit
    local classToken
    local roleBySpec
    local previousRole
    local previousPercent
    local previousDefaultPercent

    if not name or name == "" then
        return
    end

    entry = self:EnsureSplitEntry(name)
    previousRole = tostring(entry.role or "")
    previousPercent = safenum(entry.percent, 0)
    entry.spec = tostring(specName or "")

    unit = self:GetUnitIdForName(name)
    classToken = classTokenHint

    if classToken == nil or classToken == "" then
        classToken = unit and select(2, UnitClass(unit)) or nil
    end

    if classToken and classToken ~= "" then
        entry.classToken = tostring(classToken)
    end

    roleBySpec = self:GetRoleForSpec(entry.spec, classToken)
    previousDefaultPercent = self:GetDefaultPercentForRole(name, previousRole)

    if roleBySpec and not entry.roleManual and entry.role ~= "рл" and entry.role ~= "замена" then
        entry.role = roleBySpec

        if previousPercent == previousDefaultPercent then
            entry.percent = self:GetDefaultPercentForRole(name, roleBySpec)
            self:ResetSplitAdjustments(entry)
        else
            self:SyncSplitAdjustmentsToPercent(name, entry)
        end
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

function addon:GetGuildNameForPlayer(name)
    local unit = self:GetUnitIdForName(name)
    local guildName

    if not unit or not GetGuildInfo then
        return nil
    end

    guildName = GetGuildInfo(unit)

    if guildName and guildName ~= "" then
        return tostring(guildName)
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

function addon:IsBlizzardInspectWindowOpen()
    return (InspectFrame and InspectFrame:IsShown())
        or (InspectPaperDollFrame and InspectPaperDollFrame:IsShown())
        or (InspectTalentFrame and InspectTalentFrame:IsShown())
end

function addon:ResetInspectRequest(clearInspectPlayer)
    self.inspectPendingName = nil
    self.inspectPendingUnit = nil
    self.inspectPendingClassToken = nil
    self.inspectPendingAt = nil

    if clearInspectPlayer and ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

function addon:ProcessInspectQueue()
    local nextRequest

    if self:IsBlizzardInspectWindowOpen() then
        if self.inspectPendingName then
            self:ResetInspectRequest(false)
        end
        return
    end

    if self.inspectPendingName then
        if self.inspectPendingAt and (time() - self.inspectPendingAt) > 4 then
            self:ResetInspectRequest(true)
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
    if self:IsBlizzardInspectWindowOpen() then
        if self.inspectPendingName then
            self:ResetInspectRequest(false)
        end
        return
    end

    if not self.inspectPendingName then
        return
    end

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
        self:SetSplitEntrySpec(inspectName, specName, classToken)
    end

    self:ResetInspectRequest(true)
end

function addon:GetDefaultPercentForRole(name, role)
    if normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
        return clampPercent(GoldBidDB.split and GoldBidDB.split.leaderSharePercent, DEFAULT_LEADER_SHARE_PERCENT, 100)
    end

    if role == "замена" then
        return math.max(0, safenum(GoldBidDB.split.substitutePercent, 50))
    end

    if role == "хил" then
        return 115
    end

    return 100
end

function addon:GetSplitRoleSortRank(role, isLeader, isSubstitute)
    role = self:NormalizeSplitRoleValue(role)

    if isLeader then
        return 0
    end

    if role == "мт" then
        return isSubstitute and 11 or 1
    end

    if role == "от" then
        return isSubstitute and 12 or 2
    end

    if role == "танк" then
        return isSubstitute and 13 or 3
    end

    if role == "хил" then
        return isSubstitute and 14 or 4
    end

    if role == "дд" then
        return isSubstitute and 15 or 5
    end

    if role == "замена" or isSubstitute then
        return 16
    end

    return 6
end

function addon:ResetSplitAdjustments(entry)
    if not entry then
        return
    end

    entry.penaltyAdjust = 0
    entry.bonusAdjust = 0
end

function addon:SyncSplitAdjustmentsToPercent(name, entry)
    local defaultPercent
    local percent
    local delta

    if not entry then
        return
    end

    defaultPercent = self:GetDefaultPercentForRole(name, entry.role)
    percent = math.max(0, safenum(entry.percent, defaultPercent))
    delta = percent - defaultPercent

    if delta > 0 then
        entry.bonusAdjust = delta
        entry.penaltyAdjust = 0
    elseif delta < 0 then
        entry.penaltyAdjust = math.abs(delta)
        entry.bonusAdjust = 0
    else
        self:ResetSplitAdjustments(entry)
    end
end

function addon:UpdateSplitEntryField(name, field, value, skipRefresh)
    self:EnsureSplitDB()
    local entry
    local previousRole
    local previousPercent
    local previousDefaultPercent

    if not name or name == "" then
        return
    end

    entry = self:EnsureSplitEntry(name)
    previousRole = tostring(entry.role or "")
    previousPercent = safenum(entry.percent, 0)
    previousDefaultPercent = self:GetDefaultPercentForRole(name, previousRole)

    if field == "percent" then
        entry.percent = math.max(0, safenum(value, entry.percent or 0))
        self:SyncSplitAdjustmentsToPercent(name, entry)
    elseif field == "debt" then
        entry.debt = safenum(value, entry.debt or 0)
    elseif field == "role" then
        entry.role = self:NormalizeSplitRoleValue(value)
        entry.roleManual = entry.role ~= ""

        if not entry.roleManual then
            entry.role = self:GetSplitAutoRole(name, entry.spec) or entry.role
        end

        if previousPercent == previousDefaultPercent then
            entry.percent = self:GetDefaultPercentForRole(name, entry.role)
            self:ResetSplitAdjustments(entry)
        else
            self:SyncSplitAdjustmentsToPercent(name, entry)
        end
    elseif field == "note" or field == "penaltyNote" then
        entry.penaltyNote = tostring(value or "")
    elseif field == "bonusNote" then
        entry.bonusNote = tostring(value or "")
    end

    if not skipRefresh and self.RefreshMainWindow then
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
        entry.bonusAdjust = math.max(0, safenum(entry.bonusAdjust, 0) + 5)
    elseif preset == "penalty" then
        entry.percent = math.max(0, safenum(entry.percent, 0) - 5)
        entry.penaltyAdjust = math.max(0, safenum(entry.penaltyAdjust, 0) + 5)
    elseif preset == "substitute" then
        entry.role = "замена"
        entry.roleManual = true
        entry.percent = self:GetDefaultPercentForRole(name, "замена")
        self:ResetSplitAdjustments(entry)
    elseif preset == "main" then
        if normalizeName(name) == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
            entry.role = "рл"
            entry.percent = self:GetDefaultPercentForRole(name, "рл")
            entry.roleManual = true
            self:ResetSplitAdjustments(entry)
        else
            entry.role = self:GetSplitAutoRole(name, entry.spec)
            entry.percent = self:GetDefaultPercentForRole(name, entry.role)
            entry.roleManual = false
            self:ResetSplitAdjustments(entry)
        end
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:GetSplitNoteText(penaltyNote, bonusNote)
    local lines = {}
    local penalty = tostring(penaltyNote or "")
    local bonus = tostring(bonusNote or "")

    if penalty ~= "" then
        table.insert(lines, "Косяки: " .. penalty)
    end

    if bonus ~= "" then
        table.insert(lines, "Плюсики: " .. bonus)
    end

    return table.concat(lines, "\n")
end

function addon:ComputeDetailedSplit()
    self:EnsureSplitDB()
    local roster = self:RefreshSplitRoster()
    local leaderName = normalizeName(self:GetLeaderName() or self:GetPlayerName())
    local leaderEntry = leaderName and self:EnsureSplitEntry(leaderName) or nil
    local requestedLeaderPercent = leaderEntry and safenum(leaderEntry.percent, GoldBidDB.split.leaderSharePercent) or GoldBidDB.split.leaderSharePercent
    local totalPot = floorGold(safenum(GoldBidDB.ledger.pot, 0))
    local guildPercent, leaderPercent, playerSharePercent = getEffectiveFixedSharePercents(GoldBidDB.split, requestedLeaderPercent)
    local guildShareAmount = floorGold(totalPot * (guildPercent / 100))
    local leaderShareAmount = floorGold(totalPot * (leaderPercent / 100))
    local distributablePot = math.max(0, totalPot - guildShareAmount - leaderShareAmount)
    local results = {}
    local totalWeight = 0
    local totalDebt = 0
    local totalNet = 0
    local mainCount = 0
    local substituteCount = 0
    local eligibleCount = 0
    local baseShare
    local payoutKey
    local index

    for index = 1, table.getn(roster) do
        local name = roster[index]
        local entry = self:EnsureSplitEntry(name)
        local isLeader = normalizeName(name) == leaderName
        local percent = math.max(0, safenum(entry.percent, 0))
        local debt = safenum(entry.debt, 0)
        local weight

        if isLeader then
            percent = leaderPercent
            weight = 0
        else
            weight = percent / 100
            totalWeight = totalWeight + weight

            if percent > 0 then
                eligibleCount = eligibleCount + 1
            end
        end

        totalDebt = totalDebt + debt

        table.insert(results, {
            index = index,
            name = name,
            spec = tostring(entry.spec or ""),
            classToken = self:GetSplitClassToken(name),
            role = tostring(entry.role or ""),
            roleManual = entry.roleManual and true or false,
            percent = percent,
            penaltyNote = tostring(entry.penaltyNote or ""),
            bonusNote = tostring(entry.bonusNote or ""),
            penaltyAdjust = math.max(0, safenum(entry.penaltyAdjust, 0)),
            bonusAdjust = math.max(0, safenum(entry.bonusAdjust, 0)),
            note = self:GetSplitNoteText(entry.penaltyNote, entry.bonusNote),
            debt = debt,
            weight = weight,
            sentAmount = entry.sentAmount,
            sentPayoutKey = entry.sentPayoutKey,
            isLeader = isLeader,
            isSubstitute = tostring(entry.role or "") == "замена",
        })
    end

    table.sort(results, function(left, right)
        local leftRank = self:GetSplitRoleSortRank(left.role, left.isLeader, left.isSubstitute)
        local rightRank = self:GetSplitRoleSortRank(right.role, right.isLeader, right.isSubstitute)

        if leftRank ~= rightRank then
            return leftRank < rightRank
        end

        return tostring(left.name or "") < tostring(right.name or "")
    end)

    baseShare = totalWeight > 0 and floorGold(distributablePot / totalWeight) or 0

    for index = 1, table.getn(results) do
        local row = results[index]

        if row.isLeader then
            row.gross = leaderShareAmount
        else
            row.gross = floorGold(baseShare * row.weight)
        end

        row.net = floorGold(row.gross - row.debt)
        totalNet = totalNet + row.net

        if row.isSubstitute then
            substituteCount = substituteCount + 1
        else
            mainCount = mainCount + 1
        end
    end

    payoutKey = buildSplitPayoutKey(totalPot, guildPercent, leaderPercent, distributablePot, baseShare, results)

    for index = 1, table.getn(results) do
        local row = results[index]

        row.sent = row.net > 0
            and row.sentAmount ~= nil
            and floorGold(row.sentAmount) == floorGold(row.net)
            and tostring(row.sentPayoutKey or "") == payoutKey
    end

    GoldBidDB.split.lastComputed = {
        totalPot = totalPot,
        guildSharePercent = guildPercent,
        guildShareAmount = floorGold(guildShareAmount),
        leaderSharePercent = leaderPercent,
        leaderShareAmount = floorGold(leaderShareAmount),
        playerSharePercent = playerSharePercent,
        distributablePot = distributablePot,
        baseShare = baseShare,
        eligibleCount = eligibleCount,
        totalWeight = round2(totalWeight),
        totalDebt = floorGold(totalDebt),
        totalNet = floorGold(totalNet),
        mainCount = mainCount,
        substituteCount = substituteCount,
        payoutKey = payoutKey,
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
                percent = math.max(0, safenum((row and row.percent) or 0, 0)),
                penaltyNote = tostring((row and row.penaltyNote) or ""),
                bonusNote = tostring((row and row.bonusNote) or ""),
                penaltyAdjust = math.max(0, safenum((row and row.penaltyAdjust) or 0, 0)),
                bonusAdjust = math.max(0, safenum((row and row.bonusAdjust) or 0, 0)),
                payoutKey = tostring(split and split.payoutKey or ""),
            })
        end
    end

    return queue
end

function addon:BuildMailPayoutBody(entry)
    local lines = {}
    local percent = math.max(0, safenum(entry and entry.percent or 0, 0))
    local penaltyNote = tostring(entry and entry.penaltyNote or "")
    local bonusNote = tostring(entry and entry.bonusNote or "")
    local penaltyAdjust = math.max(0, safenum(entry and entry.penaltyAdjust or 0, 0))
    local bonusAdjust = math.max(0, safenum(entry and entry.bonusAdjust or 0, 0))

    table.insert(lines, "GoldBid GDKP выплата.")
    table.insert(lines, "")
    table.insert(lines, string.format("Процент доли: %d%%", percent))

    if penaltyNote ~= "" or penaltyAdjust > 0 then
        table.insert(lines, "")
        if penaltyNote ~= "" and penaltyAdjust > 0 then
            table.insert(lines, string.format("Косяки (-%d): %s", penaltyAdjust, penaltyNote))
        elseif penaltyAdjust > 0 then
            table.insert(lines, string.format("Косяки (-%d)", penaltyAdjust))
        else
            table.insert(lines, "Косяки: " .. penaltyNote)
        end
    end

    if bonusNote ~= "" or bonusAdjust > 0 then
        if penaltyNote == "" and penaltyAdjust == 0 then
            table.insert(lines, "")
        end

        if bonusNote ~= "" and bonusAdjust > 0 then
            table.insert(lines, string.format("Плюсики (+%d): %s", bonusAdjust, bonusNote))
        elseif bonusAdjust > 0 then
            table.insert(lines, string.format("Плюсики (+%d)", bonusAdjust))
        else
            table.insert(lines, "Плюсики: " .. bonusNote)
        end
    end

    return table.concat(lines, "\n")
end

function addon:TriggerButtonClick(button)
    local onClick
    local ok

    if not button then
        return
    end

    if button.Click then
        ok = pcall(function()
            button:Click()
        end)

        if ok then
            return
        end
    end

    if button.GetScript then
        ok, onClick = pcall(function()
            return button:GetScript("OnClick")
        end)

        if not ok then
            onClick = nil
        end
    end

    if onClick then
        onClick(button)
    end
end

function addon:ApplySendMailMoneyFields(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100

    if MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, copper)
    end

    if SetSendMailMoney then
        SetSendMailMoney(copper)
    end

    if SendMailMoney and SendMailMoney.gold and SendMailMoney.silver and SendMailMoney.copper then
        SendMailMoney.gold:SetText(gold > 0 and tostring(gold) or "")
        SendMailMoney.silver:SetText((gold > 0 or silver > 0) and tostring(silver) or "")
        SendMailMoney.copper:SetText((gold > 0 or silver > 0 or bronze > 0) and tostring(bronze) or "")
    end

    if SendMailMoneyGold and SendMailMoneySilver and SendMailMoneyCopper then
        SendMailMoneyGold:SetText(gold > 0 and tostring(gold) or "")
        SendMailMoneySilver:SetText((gold > 0 or silver > 0) and tostring(silver) or "")
        SendMailMoneyCopper:SetText((gold > 0 or silver > 0 or bronze > 0) and tostring(bronze) or "")
    end
end

function addon:HideSendMailCostDisplay()
    local frameNames = {
        "SendMailCostMoneyFrame",
        "SendMailCostMoney",
    }
    local textNames = {
        "SendMailCostMoneyFrameText",
        "SendMailCostMoneyText",
    }
    local index
    local frame
    local text

    for index = 1, table.getn(frameNames) do
        frame = _G[frameNames[index]]

        if frame and frame.Hide then
            frame:Hide()
        end
    end

    for index = 1, table.getn(textNames) do
        text = _G[textNames[index]]

        if text and text.SetText then
            text:SetText("")
        end

        if text and text.Hide then
            text:Hide()
        end
    end
end

function addon:PrepareNextMailEntry(quiet)
    local state = self:GetMailPayoutState()
    local entry
    local copper
    local bodyText

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

    bodyText = self:BuildMailPayoutBody(entry)

    if SendMailBodyEditBox and SendMailBodyEditBox.SetText then
        SendMailBodyEditBox:SetText(bodyText)
    end

    copper = math.max(0, floorGold(entry.amount) * 10000)
    gold = math.floor(copper / 10000)
    silver = math.floor((copper % 10000) / 100)
    bronze = copper % 100

    if SendMailCODButton then
        if SendMailCODButton.SetChecked then
            SendMailCODButton:SetChecked(false)
        end
        self:TriggerButtonClick(SendMailCODButton)
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
        self:TriggerButtonClick(SendMailMoneyButton)
    end

    if SendMailMoney and SendMailMoney.Show then
        SendMailMoney:Show()
    end

    if SendMailCOD and SendMailCOD.Hide then
        SendMailCOD:Hide()
    end

    self:ApplySendMailMoneyFields(copper)

    if SendMailFrame_Update then
        SendMailFrame_Update()
    end

    self:ApplySendMailMoneyFields(copper)
    self:HideSendMailCostDisplay()

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

    if self.CommitSplitViewEdits then
        self:CommitSplitViewEdits()
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
    local splitEntry

    if not state.active then
        return
    end

    if entry and GoldBidDB and GoldBidDB.split and GoldBidDB.split.entries then
        splitEntry = self:EnsureSplitEntry(entry.name)

        if splitEntry then
            splitEntry.sentAmount = floorGold(entry.amount or 0)
            splitEntry.sentPayoutKey = tostring(entry.payoutKey or "")
        end
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
        minBid = self:GetDefaultAuctionMinBid(),
        increment = self:GetDefaultAuctionIncrement(),
        duration = self:GetDefaultAuctionDuration(),
        leader = nil,
        bids = {},
        passes = {},
        startedAt = nil,
        endsAt = nil,
        status = "idle",
        mode = "goldbid",
        rerollPlayers = {},
        rerollRound = 0,
    }
    self.skippedAuctionId = nil
    self.pendingSkipAuctionId = nil

    if self.frame then
        self.frame.idleDefaultsApplied = false
    end
end

function addon:EnsureAuctionState()
    if type(self.currentAuction) ~= "table" then
        self:ResetAuction()
        return
    end

    self.currentAuction.bids = self.currentAuction.bids or {}
    self.currentAuction.passes = self.currentAuction.passes or {}

    if self.currentAuction.minBid == nil then
        self.currentAuction.minBid = self:GetDefaultAuctionMinBid()
    end

    if self.currentAuction.increment == nil then
        self.currentAuction.increment = self:GetDefaultAuctionIncrement()
    end

    if self.currentAuction.duration == nil then
        self.currentAuction.duration = self:GetDefaultAuctionDuration()
    end

    if self.currentAuction.status == nil then
        self.currentAuction.status = "idle"
    end

    self.currentAuction.mode = normalizeAuctionMode(self.currentAuction.mode)
    self.currentAuction.rerollPlayers = self.currentAuction.rerollPlayers or {}
    self.currentAuction.rerollRound = safenum(self.currentAuction.rerollRound, 0)
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
        guildSharePercent = splitSettings.guildSharePercent or DEFAULT_GUILD_SHARE_PERCENT,
        leaderSharePercent = splitSettings.leaderSharePercent or DEFAULT_LEADER_SHARE_PERCENT,
        substitutePercent = splitSettings.substitutePercent or 100,
        rosterSnapshot = {},
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

function addon:GetRollTiePlayers()
    local topAmount
    local tiedNames = {}
    local rows = self:GetSortedBids()
    local index

    if normalizeAuctionMode(self.currentAuction and self.currentAuction.mode) ~= "roll" then
        return nil, tiedNames
    end

    topAmount = rows[1] and rows[1].amount or nil

    if not topAmount then
        return nil, tiedNames
    end

    for index = 1, table.getn(rows) do
        if rows[index].amount ~= topAmount then
            break
        end

        table.insert(tiedNames, rows[index].name)
    end

    return topAmount, tiedNames
end

function addon:IsRollRerollActive()
    self:EnsureAuctionState()
    return normalizeAuctionMode(self.currentAuction.mode) == "roll"
        and self.currentAuction.rerollPlayers
        and next(self.currentAuction.rerollPlayers) ~= nil
end

function addon:IsPlayerEligibleForCurrentRoll(name)
    local normalizedName = normalizeName(name)

    if not normalizedName then
        return false
    end

    if not self:IsRollRerollActive() then
        return true
    end

    return self.currentAuction.rerollPlayers[normalizedName] == true
end

function addon:BuildRerollAnnouncement(players, topRoll)
    local text = table.concat(players, ", ")

    if topRoll and topRoll > 0 then
        return string.format("Ничья по /roll (%d): %s. Переролл между ними, /roll 1-100.", topRoll, text)
    end

    return string.format("Ничья по /roll: %s. Переролл между ними, /roll 1-100.", text)
end

function addon:AnnounceRollReroll(players, topRoll)
    local channel = self:GetDistributionChannel()
    local message = self:BuildRerollAnnouncement(players, topRoll)

    self:Print(message)

    if channel then
        SendChatMessage(message, channel)
    end
end

function addon:StartRollReroll(players, topRoll)
    local index

    if normalizeAuctionMode(self.currentAuction.mode) ~= "roll" then
        return false
    end

    self.currentAuction.rerollRound = safenum(self.currentAuction.rerollRound, 0) + 1
    self.currentAuction.startedAt = time()
    self.currentAuction.endsAt = self.currentAuction.startedAt + math.max(10, safenum(self.currentAuction.duration, 20))
    self.currentAuction.status = "running"
    self.currentAuction.rerollPlayers = {}

    for index = 1, table.getn(players) do
        self.currentAuction.rerollPlayers[normalizeName(players[index])] = true
    end

    self:WipeTable(self.currentAuction.bids)
    self:WipeTable(self.currentAuction.passes)
    self:AnnounceRollReroll(players, topRoll)

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    self:BroadcastState()
    return true
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

    if normalizeAuctionMode(auction.mode) == "roll" then
        return false, "В режиме Roll используйте кнопку Roll или /roll 1-100."
    end

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
        return false, "Минимальная ставка: " .. formatGoldAmount(minimum) .. "."
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
    local newEndsAt

    self:EnsureAuctionState()
    auction = self.currentAuction

    if not self:IsAuctionActive() or not auction.endsAt then
        return false
    end

    if normalizeAuctionMode(auction.mode) ~= "goldbid" then
        return false
    end

    timeLeft = self:GetTimeLeft()
    if timeLeft >= 15 then
        return false
    end

    newEndsAt = time() + 15
    auction.endsAt = newEndsAt

    if auction.startedAt then
        auction.duration = math.max(safenum(auction.duration, 0), newEndsAt - auction.startedAt)
    else
        auction.duration = 15
    end

    return true
end

function addon:RecordPass(bidder)
    self:EnsureAuctionState()

    if normalizeAuctionMode(self.currentAuction.mode) == "roll" and not self:IsPlayerEligibleForCurrentRoll(bidder) then
        return false
    end

    if normalizeAuctionMode(self.currentAuction.mode) == "roll" and self.currentAuction.bids[bidder] then
        return false
    end

    if self.currentAuction.passes[bidder] then
        return false
    end

    self.currentAuction.passes[bidder] = true

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    return true
end

function addon:OpenAuction(itemLink, minBid, increment, duration, auctionId, leaderName, mode)
    local itemName = itemLink
    local activeDuration = safenum(duration, self:GetDefaultAuctionDuration())
    local auctionMode = normalizeAuctionMode(mode or self:GetSelectedAuctionMode())

    if GetItemInfo then
        itemName = GetItemInfo(itemLink) or itemLink
    end

    if activeDuration <= 0 then
        activeDuration = self:GetDefaultAuctionDuration()
    end

    self.currentAuction.id = auctionId or self:CreateAuctionId()
    self.currentAuction.itemLink = itemLink
    self.currentAuction.itemName = itemName
    self.currentAuction.minBid = safenum(minBid, self:GetDefaultAuctionMinBid())
    self.currentAuction.increment = safenum(increment, self:GetDefaultAuctionIncrement())
    self.currentAuction.duration = activeDuration
    self.currentAuction.leader = normalizeName(leaderName) or self:GetLeaderName()
    self.currentAuction.startedAt = time()
    self.currentAuction.endsAt = self.currentAuction.startedAt + activeDuration
    self.currentAuction.status = "running"
    self.currentAuction.mode = auctionMode
    self.currentAuction.rerollRound = 0
    self:WipeTable(self.currentAuction.rerollPlayers)
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

function addon:HasRecordedSaleForAuction(auctionId)
    local sales
    local index

    if not auctionId or auctionId == "" or not GoldBidDB or not GoldBidDB.ledger then
        return false
    end

    sales = GoldBidDB.ledger.sales or {}

    for index = 1, table.getn(sales) do
        if tostring(sales[index].auctionId or "") == tostring(auctionId) then
            return true
        end
    end

    return false
end

function addon:CloseAuction(winner, amount)
    local auction = self.currentAuction
    local mode = normalizeAuctionMode(auction.mode)

    if not auction.id or auction.status == "ended" then
        return
    end

    auction.status = "ended"

    if mode == "goldbid" and winner and amount and amount > 0 then
        if not self:HasRecordedSaleForAuction(auction.id) then
            table.insert(GoldBidDB.ledger.sales, {
                timestamp = date("%Y-%m-%d %H:%M:%S"),
                itemLink = auction.itemLink,
                winner = winner,
                guildName = self:GetGuildNameForPlayer(winner),
                amount = amount,
                auctionId = auction.id,
            })

            GoldBidDB.ledger.pot = (GoldBidDB.ledger.pot or 0) + amount
            self:Print(string.format("%s выиграл %s за %dg.", tostring(winner), tostring(auction.itemLink or auction.itemName or "лот"), amount))
        end
    elseif mode == "roll" and winner and amount and amount > 0 then
        self:Print(string.format("%s выиграл %s по роллу %d.", tostring(winner), tostring(auction.itemLink or auction.itemName or "лот"), amount))
    elseif mode == "roll" then
        self:Print(string.format("Ролл на %s завершён без бросков.", tostring(auction.itemLink or auction.itemName or "лот")))
    else
        self:Print(string.format("Торги по %s завершены без ставок.", tostring(auction.itemLink or auction.itemName or "лот")))
    end

    self:ResetAuction()

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
        normalizeAuctionMode(auction.mode),
        self:EncodeNameSet(auction.rerollPlayers),
        auction.rerollRound or 0,
    }, target and "WHISPER" or self:GetDistributionChannel(), target)
end

function addon:SendPayoutState(target)
    local split = self:ComputeDetailedSplit()
    local payout = {
        totalPot = split.totalPot,
        eligibleCount = split.eligibleCount,
        perPlayer = split.baseShare,
        guildSharePercent = split.guildSharePercent,
        guildShareAmount = split.guildShareAmount,
        leaderSharePercent = split.leaderSharePercent,
        leaderShareAmount = split.leaderShareAmount,
        playerSharePercent = split.playerSharePercent,
        distributablePot = split.distributablePot,
        totalDebt = split.totalDebt,
        totalNet = split.totalNet,
    }

    GoldBidDB.ledger.payout = payout

    self:SendCommand("PAYOUT", {
        payout.totalPot or 0,
        payout.eligibleCount or 0,
        payout.perPlayer or 0,
        payout.guildShareAmount or 0,
        payout.leaderShareAmount or 0,
        payout.distributablePot or 0,
        payout.guildSharePercent or 0,
        payout.leaderSharePercent or 0,
        payout.playerSharePercent or 0,
    }, target and "WHISPER" or self:GetDistributionChannel(), target)
end

function addon:ApplyState(fields, sender)
    local auctionId = fields[2]
    local itemLink = fields[3]
    local minBid = safenum(fields[4], 0)
    local increment = safenum(fields[5], 0)
    local duration = safenum(fields[6], self:GetDefaultAuctionDuration())
    local startedAt = safenum(fields[7], 0)
    local endsAt = safenum(fields[8], 0)
    local leaderName = normalizeName(fields[9]) or normalizeName(sender)
    local status = fields[10] or "idle"
    local bids = self:DecodeBidList(fields[11] or "")
    local passes = self:DecodePassList(fields[12] or "")
    local pot = safenum(fields[13], GoldBidDB.ledger.pot or 0)
    local mode = normalizeAuctionMode(fields[14])
    local rerollPlayers = self:DecodeNameSet(fields[15] or "")
    local rerollRound = safenum(fields[16], 0)

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
        self.currentAuction.mode = mode
        self.currentAuction.rerollPlayers = rerollPlayers
        self.currentAuction.rerollRound = rerollRound
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
        eligibleCount = split.eligibleCount,
        perPlayer = split.baseShare,
        guildSharePercent = split.guildSharePercent,
        guildShareAmount = split.guildShareAmount,
        leaderSharePercent = split.leaderSharePercent,
        leaderShareAmount = split.leaderShareAmount,
        playerSharePercent = split.playerSharePercent,
        distributablePot = split.distributablePot,
        totalDebt = split.totalDebt,
        totalNet = split.totalNet,
    }

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    return GoldBidDB.ledger.payout
end

function addon:RemoveSaleAt(index)
    self:EnsureDB()
    local sales = GoldBidDB.ledger.sales or {}
    local sale = sales[index]
    local amount

    if not sale then
        return false
    end

    amount = math.max(0, floorGold(safenum(sale.amount, 0)))
    table.remove(sales, index)
    GoldBidDB.ledger.sales = sales
    GoldBidDB.ledger.pot = math.max(0, floorGold(safenum(GoldBidDB.ledger.pot, 0) - amount))

    if self.ResetMailPayoutState then
        self:ResetMailPayoutState(true)
    end

    if GoldBidDB.ledger.payout then
        self:ComputePayout()
    elseif self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    if self:IsPlayerController() and (UnitInRaid("player") or UnitInParty("player")) then
        self:BroadcastState(nil, true)

        if GoldBidDB.ledger.payout then
            self:SendPayoutState()
        end
    end

    self:Print(string.format(
        "Удалён лот из сводки: %s, %s, %dg.",
        tostring(sale.itemLink or sale.itemName or "Неизвестный лот"),
        tostring(sale.winner or "-"),
        amount
    ))

    return true
end

function addon:BuildSpendingSummary()
    self:EnsureDB()
    local sales = GoldBidDB.ledger.sales or {}
    local totalsByPlayer = {}
    local rows = {}
    local totalSpent = 0
    local totalLots = 0
    local buyerCount = 0
    local index
    local winner
    local amount
    local entry

    for index = 1, table.getn(sales) do
        winner = normalizeName(sales[index].winner) or tostring(sales[index].winner or "")
        amount = math.max(0, floorGold(safenum(sales[index].amount, 0)))

        if winner and winner ~= "" and amount > 0 then
            local guildName = tostring(sales[index].guildName or self:GetGuildNameForPlayer(winner) or "")

            if guildName ~= "" and (sales[index].guildName == nil or sales[index].guildName == "") then
                sales[index].guildName = guildName
            end

            entry = totalsByPlayer[winner]

            if not entry then
                entry = {
                    name = winner,
                    guildName = guildName,
                    total = 0,
                    lots = 0,
                }
                totalsByPlayer[winner] = entry
            end

            if guildName ~= "" then
                entry.guildName = guildName
            end

            entry.total = entry.total + amount
            entry.lots = entry.lots + 1
            totalSpent = totalSpent + amount
            totalLots = totalLots + 1
        end
    end

    for winner in pairs(totalsByPlayer) do
        table.insert(rows, totalsByPlayer[winner])
    end

    table.sort(rows, function(left, right)
        if left.total == right.total then
            return tostring(left.name or "") < tostring(right.name or "")
        end

        return left.total > right.total
    end)

    buyerCount = table.getn(rows)

    return {
        rows = rows,
        totalSpent = totalSpent,
        totalLots = totalLots,
        buyerCount = buyerCount,
    }
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
        "Пот: " .. formatGoldAmount(GoldBidDB.ledger.pot or 0),
        "",
        "Продажи",
    }
    local sales = GoldBidDB.ledger.sales
    local split = self:ComputeDetailedSplit()
    local payout = {
        totalPot = split.totalPot,
        eligibleCount = split.eligibleCount,
        perPlayer = split.baseShare,
        guildSharePercent = split.guildSharePercent,
        guildShareAmount = split.guildShareAmount,
        leaderSharePercent = split.leaderSharePercent,
        leaderShareAmount = split.leaderShareAmount,
        playerSharePercent = split.playerSharePercent,
        distributablePot = split.distributablePot,
        totalDebt = split.totalDebt,
        totalNet = split.totalNet,
    }
    local index

    if table.getn(sales) == 0 then
        table.insert(lines, "Нет продаж")
    else
        pushTableHeader(lines, { "#", "Лот", "Победитель", "Цена" })

        for index = 1, table.getn(sales) do
            local sale = sales[index]

            table.insert(lines, string.format(
                "| %d | %s | %s | %s |",
                index,
                cleanCell(sale.itemLink or "?"),
                cleanCell(sale.winner or "?"),
                formatGoldAmount(sale.amount or 0)
            ))
        end
    end

    if payout then
        table.insert(lines, "")
        table.insert(lines, "Итоги делёжки")
        table.insert(lines, string.format("Участников: %d", payout.eligibleCount or 0))
        table.insert(lines, string.format("Гильдия %d%%: %dg", floorGold(payout.guildSharePercent or 0), floorGold(payout.guildShareAmount or 0)))
        table.insert(lines, string.format("РЛ %d%%: %dg", floorGold(payout.leaderSharePercent or 0), floorGold(payout.leaderShareAmount or 0)))
        table.insert(lines, string.format("Игрокам %d%%: %dg", floorGold(payout.playerSharePercent or 0), floorGold(payout.distributablePot or 0)))
        table.insert(lines, string.format("База 100%%: %dg", floorGold(payout.perPlayer or 0)))
        table.insert(lines, string.format("Долги всего: %dg", floorGold(payout.totalDebt or 0)))
        table.insert(lines, string.format("Итого к выплате: %dg", floorGold(payout.totalNet or 0)))
    end

    if split and split.rows and table.getn(split.rows) > 0 then
        table.insert(lines, "")
        table.insert(lines, "Детальная делёжка")
        table.insert(lines, string.format("Основа: %d | Замены: %d", split.mainCount or 0, split.substituteCount or 0))
        pushTableHeader(lines, { "#", "Игрок", "Спек", "Роль", "%", "Долг", "К выплате", "Косяки", "Плюсики" })

        for index = 1, table.getn(split.rows) do
            local row = split.rows[index]

            table.insert(lines, string.format(
                "| %d | %s | %s | %s | %d | %dg | %dg | %s | %s |",
                index,
                cleanCell(row.name or "?"),
                cleanCell(row.spec or ""),
                cleanCell(row.role or "-"),
                floorGold(row.percent or 0),
                floorGold(row.debt or 0),
                floorGold(row.net or 0),
                cleanCell(row.penaltyNote or ""),
                cleanCell(row.bonusNote or "")
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

    if normalizeAuctionMode(self.currentAuction.mode) == "roll" then
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

    if self:RecordPass(bidder) then
        self:SendCommand("PASSACK", { auctionId, bidder }, self:GetDistributionChannel())
    end
end

function addon:HandleRollSystemMessage(message)
    local name
    local roll
    local low
    local high
    local normalizedName

    if not self:IsPlayerController() or not self:IsAuctionActive() then
        return
    end

    if normalizeAuctionMode(self.currentAuction.mode) ~= "roll" then
        return
    end

    name, roll, low, high = string.match(tostring(message or ""), getRandomRollPattern())
    normalizedName = normalizeName(name)
    roll = safenum(roll, 0)
    low = safenum(low, 0)
    high = safenum(high, 0)

    if not normalizedName or low ~= 1 or high ~= 100 or roll <= 0 then
        return
    end

    if (UnitInRaid("player") or UnitInParty("player")) and not self:IsRosterMember(normalizedName) then
        return
    end

    if not self:IsPlayerEligibleForCurrentRoll(normalizedName) then
        return
    end

    if self.currentAuction.passes and self.currentAuction.passes[normalizedName] then
        return
    end

    if self.currentAuction.bids and self.currentAuction.bids[normalizedName] ~= nil then
        return
    end

    self:ApplyAcceptedBid(normalizedName, roll)
    self:SendCommand("ACCEPT", { self.currentAuction.id, normalizedName, roll }, self:GetDistributionChannel())

    if self:ExtendAuctionForLateBid() then
        self:BroadcastState()
    end
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
            self:SetSplitEntrySpec(normalizeName(fields[2]) or sender, fields[3] or "", fields[4] or "")
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
                guildShareAmount = safenum(fields[5], 0),
                leaderShareAmount = safenum(fields[6], 0),
                distributablePot = safenum(fields[7], 0),
                guildSharePercent = safenum(fields[8], DEFAULT_GUILD_SHARE_PERCENT),
                leaderSharePercent = safenum(fields[9], DEFAULT_LEADER_SHARE_PERCENT),
                playerSharePercent = safenum(fields[10], math.max(0, 100 - DEFAULT_GUILD_SHARE_PERCENT - DEFAULT_LEADER_SHARE_PERCENT)),
            }

            if self.RefreshMainWindow then
                self:RefreshMainWindow()
            end
        end
        return
    end

    if command == "START" then
        if self:AcceptControllerSender(sender) then
            self:OpenAuction(fields[3], fields[4], fields[5], fields[6], fields[2], sender, fields[7])
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
    local mode

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может начать аукцион.")
        return
    end

    if not itemLink or itemLink == "" then
        self:Print("Сначала установите предмет (перетащите в окно или /gbid item [ссылка]).")
        return
    end

    mode = self:GetSelectedAuctionMode()
    self:OpenAuction(itemLink, minBid, increment, duration, self:CreateAuctionId(), self:GetPlayerName(), mode)
    self:SendCommand("START", {
        self.currentAuction.id,
        self.currentAuction.itemLink,
        self.currentAuction.minBid,
        self.currentAuction.increment,
        self.currentAuction.duration,
        mode,
    }, self:GetDistributionChannel())
    self:BroadcastState()
end

function addon:EndAuction()
    local winner, amount
    local auctionId
    local activeAuctionId
    local topRoll, tiedPlayers
    local ok, err

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может завершить аукцион.")
        return
    end

    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    activeAuctionId = self.currentAuction.id

    if self.endingAuctionId and self.endingAuctionId == activeAuctionId then
        return
    end

    self.endingAuctionId = activeAuctionId
    ok, err = pcall(function()
        if normalizeAuctionMode(self.currentAuction.mode) == "roll" then
            topRoll, tiedPlayers = self:GetRollTiePlayers()

            if table.getn(tiedPlayers) > 1 then
                self:StartRollReroll(tiedPlayers, topRoll)
                return
            end
        end

        winner, amount = self:GetHighestBid()
        auctionId = self.currentAuction.id

        self:CloseAuction(winner, amount)
        self:SendCommand("END", {
            auctionId,
            winner or "",
            amount or 0,
        }, self:GetDistributionChannel())
        self:BroadcastState()
    end)
    self.endingAuctionId = nil

    if not ok then
        error(err)
    end
end

function addon:SubmitBid(amount)
    local playerName

    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    if normalizeAuctionMode(self.currentAuction.mode) == "roll" then
        playerName = self:GetPlayerName()

        if not self:IsPlayerEligibleForCurrentRoll(playerName) then
            self:Print("Сейчас переролл только для игроков с одинаковым максимальным роллом.")
            return
        end

        if self.currentAuction.passes and self.currentAuction.passes[playerName] then
            self:Print("Вы уже нажали ПАС и больше не участвуете в розыгрыше.")
            return
        end

        if self.currentAuction.bids and self.currentAuction.bids[playerName] ~= nil then
            self:Print("Ваш ролл уже засчитан.")
            return
        end

        RandomRoll(1, 100)
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
    local playerName

    if not self:IsAuctionActive() then
        self:Print("Нет активного аукциона.")
        return
    end

    playerName = self:GetPlayerName()

    if normalizeAuctionMode(self.currentAuction.mode) == "roll" and self.currentAuction.bids and self.currentAuction.bids[playerName] ~= nil then
        self:Print("Ваш ролл уже засчитан.")
        return
    end

    self:SendCommand("PASS", { self.currentAuction.id }, self:GetDistributionChannel())
end

function addon:SetPendingItem(itemLink)
    self.pendingItemLink = itemLink

    if self.frame then
        self.frame.lastAutoMinBidItemLink = nil
        self.frame.idleDefaultsApplied = false
        self.frame.minBidManualOverride = false
        self.frame.incrementManualOverride = false
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:RequestSync()
    self.lastSyncRequestAt = time()
    self:SendCommand("REQUEST_SYNC", { self.version }, self:GetDistributionChannel())
end

frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("LOOT_OPENED")
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
    addon.lootWarningThrottle = (addon.lootWarningThrottle or 0) + elapsed

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

    if addon.lootWarningThrottle >= 5 then
        addon.lootWarningThrottle = 0
        addon:CheckLootExpiryWarnings()
    end

    addon:ProcessPendingLootWindowRetry()
    addon:ProcessInspectQueue()
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

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        addon:HandleCombatLogEvent(...)
        return
    end

    if event == "LOOT_OPENED" then
        addon:HandleLootOpened(...)
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
