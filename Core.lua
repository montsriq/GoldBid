GoldBid = GoldBid or {}
GoldBid.prefix = "GBID"
GoldBid.version = "2.0.0"

local addon = GoldBid
local frame = CreateFrame("Frame")
addon.eventFrame = frame
local npcTypeFlag = COMBATLOG_OBJECT_TYPE_NPC or 0

-- WoW 3.3.5a не имеет hideCaster (arg3 = sourceGUID, string).
-- Некоторые сборки TrinityCore добавили hideCaster (bool) на позицию 3 — как в Cata+.
-- Определяем один раз по первому CLEU-событию: если arg3 — boolean → offset=1, иначе → 0.
local cleuHasCaster = nil
local DEFAULT_GUILD_SHARE_PERCENT = 10
local DEFAULT_LEADER_SHARE_PERCENT = 10
local DEFAULT_ANTISNIPE_THRESHOLD_SECONDS = 15
local DEFAULT_ANTISNIPE_EXTENSION_SECONDS = 15
local DEFAULT_ANTISNIPE_MAX_EXTENSIONS = 0
local DEFAULT_LOOT_TRANSFER_SECONDS = 7200
local LOOT_CANDIDATE_WINDOW_SECONDS = 8
local LOOT_BAG_SCAN_RETRY_DELAY = 0.5
local LOOT_BAG_SCAN_MAX_RETRIES = 8
local LOOT_TOOLTIP_CACHE_SECONDS = 5
local LOOT_TOOLTIP_NEGATIVE_CACHE_SECONDS = 1
local LOOT_EQUIPMENT_SLOT_IDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local LOOSE_LOOT_RECOVERY_COOLDOWN = 3
local TRADE_HELPER_SLOT_COUNT = 6
local TRADE_HELPER_COMPLETE_CHECK_DELAY = 0.35
local TRADE_HELPER_OFFER_TTL_SECONDS = 30

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
    local normalizedExcludedPlayers = {}
    local key
    local value

    if type(splitSettings) ~= "table" then
        return
    end

    splitSettings.entries = splitSettings.entries or {}
    splitSettings.excludedPlayers = splitSettings.excludedPlayers or {}

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

    if type(splitSettings.excludedPlayers) == "table" then
        for key, value in pairs(splitSettings.excludedPlayers) do
            local name

            if type(key) == "number" then
                name = normalizeName(value)
            elseif value then
                name = normalizeName(key)
            end

            if name then
                normalizedExcludedPlayers[name] = true
            end
        end
    end

    splitSettings.excludedPlayers = normalizedExcludedPlayers

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

-- Парсит сумму ставки из текста рейд-чата.
-- Поддерживаемые форматы:
--   1000        → 1000
--   1k / 1к     → 1000
--   1.5k / 1.5к → 1500
--   1.1         → 1100 (число < 1000 с точкой трактуется как тысячи)
--   1 100       → 1100 (русский разделитель тысяч пробелом)
-- minBid — текущая минимальная ставка аукциона (опционально).
-- Влияет на интерпретацию «голых» чисел < 1000:
--   minBid >= 1000 (или nil): 7 → 7 000g, 500 → 500 000g  (умножаем на 1000)
--   minBid <  1000           : 500 → 500g, 600 → 600g       (берём буквально)
-- k-суффикс и десятичная нотация (1.1) всегда означают тысячи независимо от minBid.
local function parseBidAmountFromText(text, minBid)
    -- убираем ссылки на предметы и цвета
    text = text:gsub("|c%x+|H.-|h.-|h|r", "")
    text = text:gsub("|H.-|h.-|h", "")
    text = text:gsub("|c%x+", ""):gsub("|r", "")
    text = text:match("^%s*(.-)%s*$") or ""

    if text == "" then
        return nil
    end

    local num

    -- нормализуем запятую как десятичный разделитель: "1,1" → "1.1"
    text = text:gsub(",", ".")

    -- нормализуем кириллические к/К → латинские k/K:
    -- Lua 5.1 матчит побайтово, а к в UTF-8 = 2 байта (0xD0 0xBA),
    -- поэтому [kкKК] в паттерне не ловит кириллическую к как целый символ
    text = text:gsub("\208\186", "k")  -- к (U+043A) → k
    text = text:gsub("\208\154", "K")  -- К (U+041A) → K

    -- "1.5k", "1к", "1.5к" и т.д. — всегда тысячи
    local kBase = text:match("^([%d%.]+)%s*[kK]$")
    if kBase then
        num = tonumber(kBase)
        if num and num > 0 then
            return math.floor(num * 1000)
        end
    end

    -- "1.1", "1.5" — десятичная нотация < 1000: всегда тысячи (явная запись)
    local decBase = text:match("^(%d+%.[%d]+)$")
    if decBase then
        num = tonumber(decBase)
        if num and num > 0 and num < 1000 then
            return math.floor(num * 1000)
        end
    end

    -- "1 100", "10 000" — пробел как разделитель тысяч (русский стиль)
    if text:find(" ") and text:match("^%d[%d ]*%d$") then
        local noSpaces = text:gsub(" +", "")
        num = tonumber(noSpaces)
        if num and num > 0 then
            return num
        end
    end

    -- Голое целое число.
    -- Если мин. ставка < 1 000 — берём буквально (500 → 500g).
    -- Иначе числа < 1 000 трактуем как тысячи (7 → 7 000g).
    num = tonumber(text)
    if num and num > 0 then
        local isSmall = num < 1000
        if isSmall and (not minBid or minBid >= 1000) then
            return num * 1000
        end
        return math.floor(num)
    end

    return nil
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

-- Возвращает true если игрок может отправить RAID_WARNING (rank >= 1: лидер или ассистент)
local function canPlayerSendRaidWarning()
    local index
    local playerName = UnitName("player")

    if not UnitInRaid("player") then
        return false
    end

    for index = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(index)
        if name and normalizeName(name) == normalizeName(playerName) then
            return rank >= 1
        end
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
            excludedPlayers = {},
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
            antiSnipeThreshold = DEFAULT_ANTISNIPE_THRESHOLD_SECONDS,
            antiSnipeExtension = DEFAULT_ANTISNIPE_EXTENSION_SECONDS,
            antiSnipeMaxExtensions = DEFAULT_ANTISNIPE_MAX_EXTENSIONS,
            antiSnipeAnnounce = false,
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
    if GoldBidDB.ui.antiSnipeThreshold == nil then
        GoldBidDB.ui.antiSnipeThreshold = DEFAULT_ANTISNIPE_THRESHOLD_SECONDS
    end
    if GoldBidDB.ui.antiSnipeExtension == nil then
        GoldBidDB.ui.antiSnipeExtension = DEFAULT_ANTISNIPE_EXTENSION_SECONDS
    end
    if GoldBidDB.ui.antiSnipeMaxExtensions == nil then
        GoldBidDB.ui.antiSnipeMaxExtensions = DEFAULT_ANTISNIPE_MAX_EXTENSIONS
    end
    if GoldBidDB.ui.antiSnipeAnnounce == nil then
        GoldBidDB.ui.antiSnipeAnnounce = false
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

function addon:CreateLootSessionId()
    self.lootSessionSequence = (self.lootSessionSequence or 0) + 1
    return tostring(time()) .. "-loot-session-" .. tostring(self.lootSessionSequence)
end

function addon:NormalizeLootEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    entry.id = tostring(entry.id or self:CreateLootEntryId())
    entry.itemLink = tostring(entry.itemLink or "")
    entry.itemName = tostring(entry.itemName or "")
    entry.itemId = tonumber(entry.itemId) or getItemIdFromLink(entry.itemLink) or 0
    entry.bossName = tostring(entry.bossName or "Прочее")
    entry.sourceGuid = tostring(entry.sourceGuid or "")
    entry.lootSessionId = tostring(entry.lootSessionId or "")
    entry.lootedAt = safenum(entry.lootedAt, time())
    entry.expiresAt = safenum(entry.expiresAt, entry.lootedAt + DEFAULT_LOOT_TRANSFER_SECONDS)
    entry.warned20 = entry.warned20 and true or false
    entry.status = tostring(entry.status or "pending")
    entry.locationType = tostring(entry.locationType or "")
    entry.bag = entry.bag ~= nil and tonumber(entry.bag) or nil
    entry.slot = entry.slot ~= nil and tonumber(entry.slot) or nil
    entry.equipSlot = entry.equipSlot ~= nil and tonumber(entry.equipSlot) or nil
    entry.hasTradeTimer = entry.hasTradeTimer and true or false
    entry.lastSeenAt = safenum(entry.lastSeenAt, entry.lootedAt)
    -- Сохраняем качество, чтобы ShouldTrackLootItem работал без GetItemInfo из кеша
    if entry.quality ~= nil then
        entry.quality = tonumber(entry.quality)
    end

    return entry
end

local MIN_TRACKED_LOOT_QUALITY = 3  -- Rare(3) и выше; было 4 (только Epic)
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

local function getItemIdentity(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    return string.match(tostring(itemLink), "item:[%-0-9:]+") or tostring(itemLink)
end

local function isSameItemLink(leftLink, rightLink)
    local leftItemId = getItemIdFromLink(leftLink)
    local rightItemId = getItemIdFromLink(rightLink)

    if leftItemId and rightItemId then
        return leftItemId == rightItemId
    end

    return getItemIdentity(leftLink) == getItemIdentity(rightLink)
end

local function getContainerNumSlotsCompat(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end

    return 0
end

local function getContainerItemLinkCompat(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end

    if GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end

    return nil
end

local function getContainerItemQualityCompat(bag, slot)
    local itemInfo
    local quality
    local texture
    local itemCount
    local locked

    if C_Container and C_Container.GetContainerItemInfo then
        itemInfo = C_Container.GetContainerItemInfo(bag, slot)
        if type(itemInfo) == "table" then
            return tonumber(itemInfo.quality)
        end
    end

    if GetContainerItemInfo then
        texture, itemCount, locked, quality = GetContainerItemInfo(bag, slot)
        return tonumber(quality)
    end

    return nil
end

local function containsAnyText(value, needles)
    local rawText = tostring(value or "")
    local lowerText = string.lower(rawText)
    local index

    for index = 1, table.getn(needles) do
        local needle = tostring(needles[index] or "")

        if needle ~= "" and (
            string.find(rawText, needle, 1, true)
            or string.find(lowerText, string.lower(needle), 1, true)
        ) then
            return true
        end
    end

    return false
end

local function addTooltipTimeMatches(text, patterns, multiplier)
    local total = 0
    local patternIndex
    local value

    for patternIndex = 1, table.getn(patterns) do
        for value in string.gmatch(text, patterns[patternIndex]) do
            total = total + (tonumber(value) or 0) * multiplier
        end
    end

    return total
end

local function parseTradeTimerSecondsFromTooltipLine(text)
    local rawText = tostring(text or "")
    local lowerText = string.lower(rawText)
    local hasTradeText
    local hasTimeText
    local seconds

    if rawText == "" then
        return nil
    end

    hasTradeText = containsAnyText(rawText, {
        "trade",
        "tradable",
        "переда",
        "Переда",
        "обмен",
        "Обмен",
        "торг",
        "Торг",
        "можете отдать",
        "Можете отдать",
        "отдать этот предмет",
        "Отдать этот предмет",
        "право получить",
        "Право получить",
        "получить его",
        "Получить его",
    })

    hasTimeText = containsAnyText(rawText, {
        "hour",
        "hr",
        "min",
        "sec",
        "day",
        "час",
        "Час",
        "мин",
        "Мин",
        "сек",
        "Сек",
        "дн",
        "Дн",
    })

    if not hasTimeText then
        hasTimeText = string.match(lowerText, "%d+%s*h")
            or string.match(lowerText, "%d+%s*m")
            or string.match(rawText, "%d+%s*ч")
            or string.match(rawText, "%d+%s*м")
    end

    if not hasTradeText or not hasTimeText then
        return nil
    end

    seconds = 0
    seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*day", "(%d+)%s*д" }, 86400)
    seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*hour", "(%d+)%s*hr", "(%d+)%s*час" }, 3600)
    if not string.find(lowerText, "hour", 1, true) and not string.find(lowerText, "hr", 1, true) then
        seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*h" }, 3600)
    end
    if not string.find(rawText, "час", 1, true) and not string.find(rawText, "Час", 1, true) then
        seconds = seconds + addTooltipTimeMatches(rawText, { "(%d+)%s*ч" }, 3600)
    end
    seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*minute", "(%d+)%s*min", "(%d+)%s*мин" }, 60)
    if not string.find(lowerText, "min", 1, true) then
        seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*m" }, 60)
    end
    if not string.find(rawText, "мин", 1, true) and not string.find(rawText, "Мин", 1, true) then
        seconds = seconds + addTooltipTimeMatches(rawText, { "(%d+)%s*м" }, 60)
    end
    seconds = seconds + addTooltipTimeMatches(lowerText, { "(%d+)%s*second", "(%d+)%s*sec", "(%d+)%s*сек" }, 1)

    if seconds <= 0 then
        return DEFAULT_LOOT_TRANSFER_SECONDS
    end

    return math.min(seconds, DEFAULT_LOOT_TRANSFER_SECONDS)
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

function addon:IsLootEntryActive(entry)
    local status = tostring(entry and entry.status or "pending")

    return status ~= "sold"
        and status ~= "expired"
        and status ~= "missing"
        and status ~= "removed"
end

function addon:BuildLootLocationKey(locationType, bag, slot, equipSlot)
    locationType = tostring(locationType or "")

    if locationType == "bag" then
        return "bag:" .. tostring(bag or "") .. ":" .. tostring(slot or "")
    end

    if locationType == "equip" then
        return "equip:" .. tostring(equipSlot or "")
    end

    return ""
end

function addon:GetLootScanTooltip()
    if not self.lootScanTooltip then
        self.lootScanTooltip = CreateFrame("GameTooltip", "GoldBidLootScanTooltip", UIParent, "GameTooltipTemplate")
        self.lootScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    return self.lootScanTooltip
end

function addon:ReadLootTradeTimerSecondsFromTooltip()
    local tooltip = self.lootScanTooltip
    local tooltipName = tooltip and tooltip:GetName()
    local lineCount = tooltip and tooltip.NumLines and tooltip:NumLines() or 0
    local lineIndex
    local line
    local text
    local seconds

    if not tooltipName or lineCount <= 0 then
        return nil
    end

    for lineIndex = 1, lineCount do
        line = _G[tooltipName .. "TextLeft" .. tostring(lineIndex)]
        text = line and line.GetText and line:GetText() or nil
        seconds = parseTradeTimerSecondsFromTooltipLine(text)

        if seconds and seconds > 0 then
            return seconds
        end
    end

    return nil
end

function addon:GetCachedLootTradeTimer(locationKey, itemLink)
    local now = GetTime and GetTime() or 0
    local record
    local ttl

    self.lootTradeTimerCache = self.lootTradeTimerCache or {}
    record = self.lootTradeTimerCache[tostring(locationKey or "")]

    if not record or tostring(record.itemLink or "") ~= tostring(itemLink or "") then
        return nil, nil
    end

    ttl = record.hasTimer and LOOT_TOOLTIP_CACHE_SECONDS or LOOT_TOOLTIP_NEGATIVE_CACHE_SECONDS

    if (now - safenum(record.checkedAt, 0)) > ttl then
        return nil, nil
    end

    return record.hasTimer and true or false, tonumber(record.seconds)
end

function addon:SetCachedLootTradeTimer(locationKey, itemLink, seconds)
    self.lootTradeTimerCache = self.lootTradeTimerCache or {}
    self.lootTradeTimerCache[tostring(locationKey or "")] = {
        itemLink = tostring(itemLink or ""),
        hasTimer = seconds and seconds > 0 or false,
        seconds = tonumber(seconds) or 0,
        checkedAt = GetTime and GetTime() or 0,
    }
end

function addon:GetLootTradeTimerSecondsForBagSlot(bag, slot, itemLink)
    local locationKey = self:BuildLootLocationKey("bag", bag, slot, nil)
    local cached, cachedSeconds = self:GetCachedLootTradeTimer(locationKey, itemLink)
    local tooltip
    local seconds

    if cached ~= nil then
        return cached and cachedSeconds or nil
    end

    tooltip = self:GetLootScanTooltip()
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    if tooltip.SetBagItem then
        tooltip:SetBagItem(bag, slot)
    end

    seconds = self:ReadLootTradeTimerSecondsFromTooltip()
    tooltip:ClearLines()
    self:SetCachedLootTradeTimer(locationKey, itemLink, seconds)

    return seconds
end

function addon:GetLootTradeTimerSecondsForEquipSlot(equipSlot, itemLink)
    local locationKey = self:BuildLootLocationKey("equip", nil, nil, equipSlot)
    local cached, cachedSeconds = self:GetCachedLootTradeTimer(locationKey, itemLink)
    local tooltip
    local seconds

    if cached ~= nil then
        return cached and cachedSeconds or nil
    end

    tooltip = self:GetLootScanTooltip()
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")

    if tooltip.SetInventoryItem then
        tooltip:SetInventoryItem("player", equipSlot)
    end

    seconds = self:ReadLootTradeTimerSecondsFromTooltip()
    tooltip:ClearLines()
    self:SetCachedLootTradeTimer(locationKey, itemLink, seconds)

    return seconds
end

function addon:FindLootEntryAtLocation(locationType, bag, slot, equipSlot, itemId)
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries
    local locationKey = self:BuildLootLocationKey(locationType, bag, slot, equipSlot)
    local index
    local entry

    if locationKey == "" then
        return nil
    end

    for index = 1, table.getn(entries) do
        entry = self:NormalizeLootEntry(entries[index])

        if entry
            and self:IsLootEntryActive(entry)
            and entry.itemId == tonumber(itemId)
            and self:BuildLootLocationKey(entry.locationType, entry.bag, entry.slot, entry.equipSlot) == locationKey then
            return entry
        end
    end

    return nil
end

function addon:UpdateLootEntryFromLocation(entry, itemLink, quality, secondsLeft, locationType, bag, slot, equipSlot)
    if not entry then
        return nil
    end

    entry.itemLink = itemLink or entry.itemLink
    entry.itemName = (GetItemInfo and GetItemInfo(entry.itemLink)) or entry.itemName or entry.itemLink
    entry.itemId = tonumber(entry.itemId) or getItemIdFromLink(entry.itemLink) or 0
    entry.quality = tonumber(quality) or entry.quality
    entry.locationType = tostring(locationType or entry.locationType or "")
    entry.bag = bag ~= nil and tonumber(bag) or nil
    entry.slot = slot ~= nil and tonumber(slot) or nil
    entry.equipSlot = equipSlot ~= nil and tonumber(equipSlot) or nil
    entry.hasTradeTimer = true
    entry.lastSeenAt = time()
    entry.expiresAt = time() + math.max(1, safenum(secondsLeft, DEFAULT_LOOT_TRANSFER_SECONDS))

    if tostring(entry.status or "pending") == "expired" or tostring(entry.status or "pending") == "missing" then
        entry.status = "pending"
    end

    return entry
end

function addon:HasActiveTimedLootEntries()
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries
    local index
    local entry

    for index = 1, table.getn(entries) do
        entry = self:NormalizeLootEntry(entries[index])

        if entry and entry.hasTradeTimer and self:IsLootEntryActive(entry) and self:GetLootTransferTimeLeft(entry) > 0 then
            return true
        end
    end

    return false
end

function addon:CleanupPendingLootCandidates()
    local candidates = self.pendingLootCandidates or {}
    local now = time()
    local index
    local candidate

    for index = table.getn(candidates), 1, -1 do
        candidate = candidates[index]

        if not candidate
            or safenum(candidate.itemId, 0) <= 0
            or safenum(candidate.matchedCount, 0) >= safenum(candidate.count, 1)
            or now > safenum(candidate.expiresAt, 0) then
            table.remove(candidates, index)
        end
    end

    self.pendingLootCandidates = candidates
end

function addon:HasPendingLootCandidates()
    local candidates = self.pendingLootCandidates or {}
    local now = time()
    local index
    local candidate

    for index = 1, table.getn(candidates) do
        candidate = candidates[index]

        if candidate
            and now <= safenum(candidate.expiresAt, 0)
            and safenum(candidate.matchedCount, 0) < safenum(candidate.count, 1) then
            return true
        end
    end

    return false
end

function addon:TrackLootCandidate(itemLink, bossName, sourceGuid, quality, lootSessionId)
    local itemId = getItemIdFromLink(itemLink)
    local candidates
    local candidate
    local index

    if not itemId or not self:ShouldTrackLootItem(itemLink, quality) then
        return nil
    end

    self.pendingLootCandidates = self.pendingLootCandidates or {}
    candidates = self.pendingLootCandidates
    lootSessionId = tostring(lootSessionId or self.currentLootSessionId or self:CreateLootSessionId())

    for index = 1, table.getn(candidates) do
        candidate = candidates[index]

        if candidate
            and candidate.itemId == itemId
            and tostring(candidate.itemLink or "") == tostring(itemLink or "")
            and tostring(candidate.bossName or "") == tostring(bossName or "Прочее")
            and tostring(candidate.lootSessionId or "") == lootSessionId then
            candidate.count = safenum(candidate.count, 1) + 1
            candidate.expiresAt = time() + LOOT_CANDIDATE_WINDOW_SECONDS
            return candidate
        end
    end

    candidate = {
        itemId = itemId,
        itemLink = itemLink,
        bossName = bossName or "Прочее",
        sourceGuid = sourceGuid or "",
        quality = tonumber(quality),
        lootSessionId = lootSessionId,
        count = 1,
        matchedCount = 0,
        addedAt = time(),
        expiresAt = time() + LOOT_CANDIDATE_WINDOW_SECONDS,
    }
    table.insert(candidates, candidate)

    return candidate
end

function addon:GetPendingLootCandidateForItem(itemId)
    local candidates = self.pendingLootCandidates or {}
    local now = time()
    local index
    local candidate

    for index = 1, table.getn(candidates) do
        candidate = candidates[index]

        if candidate
            and candidate.itemId == tonumber(itemId)
            and now <= safenum(candidate.expiresAt, 0)
            and safenum(candidate.matchedCount, 0) < safenum(candidate.count, 1) then
            return candidate
        end
    end

    return nil
end

function addon:BuildLootScanItemSet(includeActive)
    local itemIds = {}
    local count = 0
    local candidates = self.pendingLootCandidates or {}
    local now = time()
    local index
    local candidate
    local entries
    local entry

    for index = 1, table.getn(candidates) do
        candidate = candidates[index]

        if candidate
            and now <= safenum(candidate.expiresAt, 0)
            and safenum(candidate.matchedCount, 0) < safenum(candidate.count, 1)
            and safenum(candidate.itemId, 0) > 0
            and not itemIds[candidate.itemId] then
            itemIds[candidate.itemId] = true
            count = count + 1
        end
    end

    if includeActive then
        self:EnsureLootDB()
        entries = GoldBidDB.loot.entries

        for index = 1, table.getn(entries) do
            entry = self:NormalizeLootEntry(entries[index])

            if entry
                and entry.hasTradeTimer
                and self:IsLootEntryActive(entry)
                and self:GetLootTransferTimeLeft(entry) > 0
                and safenum(entry.itemId, 0) > 0
                and not itemIds[entry.itemId] then
                itemIds[entry.itemId] = true
                count = count + 1
            end
        end
    end

    return itemIds, count
end

function addon:GetLootEntries()
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries
    local filteredEntries = {}
    local index

    for index = 1, table.getn(entries) do
        local entry = self:NormalizeLootEntry(entries[index])

        -- Передаём сохранённое quality, чтобы не зависеть от кеша GetItemInfo
        if entry
            and entry.hasTradeTimer
            and self:IsLootEntryActive(entry)
            and self:GetLootTransferTimeLeft(entry) > 0
            and self:ShouldTrackLootItem(entry.itemLink, entry.quality) then
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

function addon:RegisterLootEntry(itemLink, bossName, sourceGuid, quality, options)
    self:EnsureLootDB()
    options = type(options) == "table" and options or {}

    if not itemLink or itemLink == "" or not self:ShouldTrackLootItem(itemLink, quality) then
        return nil
    end

    if options.locationType then
        local existing = self:FindLootEntryAtLocation(
            options.locationType,
            options.bag,
            options.slot,
            options.equipSlot,
            options.itemId or getItemIdFromLink(itemLink)
        )

        if existing then
            return self:UpdateLootEntryFromLocation(
                existing,
                itemLink,
                quality,
                options.secondsLeft or DEFAULT_LOOT_TRANSFER_SECONDS,
                options.locationType,
                options.bag,
                options.slot,
                options.equipSlot
            )
        end
    end

    local entry = self:NormalizeLootEntry({
        id = self:CreateLootEntryId(),
        itemLink = itemLink,
        itemName = (GetItemInfo and GetItemInfo(itemLink)) or itemLink,
        itemId = options.itemId or getItemIdFromLink(itemLink),
        bossName = bossName or "Прочее",
        sourceGuid = sourceGuid or "",
        lootSessionId = options.lootSessionId or "",
        lootedAt = time(),
        expiresAt = time() + safenum(options.secondsLeft, DEFAULT_LOOT_TRANSFER_SECONDS),
        warned20 = false,
        status = options.status or "pending",
        locationType = options.locationType or "",
        bag = options.bag,
        slot = options.slot,
        equipSlot = options.equipSlot,
        hasTradeTimer = options.hasTradeTimer and true or false,
        lastSeenAt = time(),
        -- Сохраняем качество из слота лута; без него GetLootEntries
        -- фильтрует предмет, если GetItemInfo ещё не закешировал его.
        quality = tonumber(quality),
    })

    if not entry then
        return nil
    end

    table.insert(GoldBidDB.loot.entries, entry)
    return entry
end

function addon:ConsumeLootCandidate(candidate)
    if not candidate then
        return
    end

    candidate.matchedCount = safenum(candidate.matchedCount, 0) + 1
end

function addon:ScanLootBagSlot(bag, slot, itemIds)
    local itemLink = getContainerItemLinkCompat(bag, slot)
    local itemId = getItemIdFromLink(itemLink)
    local quality
    local secondsLeft
    local candidate
    local entry

    if not itemId or not itemIds[itemId] then
        return 0
    end

    quality = getContainerItemQualityCompat(bag, slot)

    if not self:ShouldTrackLootItem(itemLink, quality) then
        return 0
    end

    secondsLeft = self:GetLootTradeTimerSecondsForBagSlot(bag, slot, itemLink)

    if not secondsLeft or secondsLeft <= 0 then
        return 0
    end

    entry = self:FindLootEntryAtLocation("bag", bag, slot, nil, itemId)

    if entry then
        self:UpdateLootEntryFromLocation(entry, itemLink, quality, secondsLeft, "bag", bag, slot, nil)
        return 1
    end

    candidate = self:GetPendingLootCandidateForItem(itemId)

    if not candidate then
        return 0
    end

    entry = self:RegisterLootEntry(itemLink, candidate.bossName, candidate.sourceGuid, quality, {
        itemId = itemId,
        lootSessionId = candidate.lootSessionId,
        locationType = "bag",
        bag = bag,
        slot = slot,
        secondsLeft = secondsLeft,
        hasTradeTimer = true,
    })

    if entry then
        self:ConsumeLootCandidate(candidate)
        return 1
    end

    return 0
end

function addon:ScanLootEquipSlot(equipSlot, itemIds)
    local itemLink = GetInventoryItemLink and GetInventoryItemLink("player", equipSlot) or nil
    local itemId = getItemIdFromLink(itemLink)
    local quality = itemLink and getItemQualityFromLink(itemLink) or nil
    local secondsLeft
    local candidate
    local entry

    if not itemId or not itemIds[itemId] then
        return 0
    end

    if not self:ShouldTrackLootItem(itemLink, quality) then
        return 0
    end

    secondsLeft = self:GetLootTradeTimerSecondsForEquipSlot(equipSlot, itemLink)

    if not secondsLeft or secondsLeft <= 0 then
        return 0
    end

    entry = self:FindLootEntryAtLocation("equip", nil, nil, equipSlot, itemId)

    if entry then
        self:UpdateLootEntryFromLocation(entry, itemLink, quality, secondsLeft, "equip", nil, nil, equipSlot)
        return 1
    end

    candidate = self:GetPendingLootCandidateForItem(itemId)

    if not candidate then
        return 0
    end

    entry = self:RegisterLootEntry(itemLink, candidate.bossName, candidate.sourceGuid, quality, {
        itemId = itemId,
        lootSessionId = candidate.lootSessionId,
        locationType = "equip",
        equipSlot = equipSlot,
        secondsLeft = secondsLeft,
        hasTradeTimer = true,
    })

    if entry then
        self:ConsumeLootCandidate(candidate)
        return 1
    end

    return 0
end

function addon:ScanLootInventory(includeActive)
    local itemIds, itemIdCount = self:BuildLootScanItemSet(includeActive)
    local foundCount = 0
    local bag
    local slot
    local slotCount
    local index

    if itemIdCount <= 0 then
        return 0
    end

    for bag = 0, 4 do
        slotCount = getContainerNumSlotsCompat(bag)

        for slot = 1, slotCount do
            foundCount = foundCount + self:ScanLootBagSlot(bag, slot, itemIds)
        end
    end

    for index = 1, table.getn(LOOT_EQUIPMENT_SLOT_IDS) do
        foundCount = foundCount + self:ScanLootEquipSlot(LOOT_EQUIPMENT_SLOT_IDS[index], itemIds)
    end

    self:CleanupPendingLootCandidates()

    return foundCount
end

function addon:RecoverLooseTimedLootInventory()
    local foundCount = 0
    local bag
    local slot
    local slotCount
    local itemLink
    local itemId
    local quality
    local secondsLeft
    local equipSlot

    for bag = 0, 4 do
        slotCount = getContainerNumSlotsCompat(bag)

        for slot = 1, slotCount do
            itemLink = getContainerItemLinkCompat(bag, slot)
            itemId = getItemIdFromLink(itemLink)

            if itemId and not self:FindLootEntryAtLocation("bag", bag, slot, nil, itemId) then
                quality = getContainerItemQualityCompat(bag, slot)

                if self:ShouldTrackLootItem(itemLink, quality) then
                    secondsLeft = self:GetLootTradeTimerSecondsForBagSlot(bag, slot, itemLink)

                    if secondsLeft and secondsLeft > 0 then
                        if self:RegisterLootEntry(itemLink, self:ResolveBossNameForLoot(itemLink, nil), "", quality, {
                            itemId = itemId,
                            locationType = "bag",
                            bag = bag,
                            slot = slot,
                            secondsLeft = secondsLeft,
                            hasTradeTimer = true,
                        }) then
                            foundCount = foundCount + 1
                        end
                    end
                end
            end
        end
    end

    for equipSlotIndex = 1, table.getn(LOOT_EQUIPMENT_SLOT_IDS) do
        equipSlot = LOOT_EQUIPMENT_SLOT_IDS[equipSlotIndex]
        itemLink = GetInventoryItemLink and GetInventoryItemLink("player", equipSlot) or nil
        itemId = getItemIdFromLink(itemLink)

        if itemId and not self:FindLootEntryAtLocation("equip", nil, nil, equipSlot, itemId) then
            quality = itemLink and getItemQualityFromLink(itemLink) or nil

            if self:ShouldTrackLootItem(itemLink, quality) then
                secondsLeft = self:GetLootTradeTimerSecondsForEquipSlot(equipSlot, itemLink)

                if secondsLeft and secondsLeft > 0 then
                    if self:RegisterLootEntry(itemLink, self:ResolveBossNameForLoot(itemLink, nil), "", quality, {
                        itemId = itemId,
                        locationType = "equip",
                        equipSlot = equipSlot,
                        secondsLeft = secondsLeft,
                        hasTradeTimer = true,
                    }) then
                        foundCount = foundCount + 1
                    end
                end
            end
        end
    end

    return foundCount
end

function addon:TryRecoverLooseTimedLootEntries()
    local now = time()

    if self:HasPendingLootCandidates() or self:HasActiveTimedLootEntries() then
        return 0
    end

    if self.lastLooseLootRecoveryAt and (now - self.lastLooseLootRecoveryAt) < LOOSE_LOOT_RECOVERY_COOLDOWN then
        return 0
    end

    self.lastLooseLootRecoveryAt = now
    return self:RecoverLooseTimedLootInventory()
end

function addon:ScheduleLootInventoryScan(attempts, includeActive)
    attempts = math.max(1, safenum(attempts, LOOT_BAG_SCAN_MAX_RETRIES))
    self.pendingLootBagScanAt = GetTime and GetTime() or 0
    self.pendingLootBagScanCount = math.max(safenum(self.pendingLootBagScanCount, 0), attempts)
    self.pendingLootBagScanIncludeActive = self.pendingLootBagScanIncludeActive or includeActive and true or false
end

function addon:ProcessPendingLootInventoryScan()
    local now
    local foundCount

    if safenum(self.pendingLootBagScanCount, 0) <= 0 then
        return
    end

    now = GetTime and GetTime() or 0

    if now < safenum(self.pendingLootBagScanAt, 0) then
        return
    end

    foundCount = self:ScanLootInventory(self.pendingLootBagScanIncludeActive)

    if foundCount > 0 and self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    if not self:HasPendingLootCandidates() then
        self.pendingLootBagScanCount = 0
        self.pendingLootBagScanAt = nil
        self.pendingLootBagScanIncludeActive = nil
        return
    end

    self.pendingLootBagScanCount = self.pendingLootBagScanCount - 1

    if self.pendingLootBagScanCount <= 0 then
        self.pendingLootBagScanCount = 0
        self.pendingLootBagScanAt = nil
        self.pendingLootBagScanIncludeActive = nil
        self:CleanupPendingLootCandidates()
        return
    end

    self.pendingLootBagScanAt = now + LOOT_BAG_SCAN_RETRY_DELAY
end

function addon:HandleLootInventoryChanged()
    if self:HasPendingLootCandidates() then
        self:ScheduleLootInventoryScan(LOOT_BAG_SCAN_MAX_RETRIES, true)
    elseif self:HasActiveTimedLootEntries() then
        self:ScheduleLootInventoryScan(1, true)
    end
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
    local candidate
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
                candidate = self:TrackLootCandidate(itemLink, bossName, sourceGuid, slotQuality, self.currentLootSessionId)

                if candidate then
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
        self:ScheduleLootInventoryScan(LOOT_BAG_SCAN_MAX_RETRIES, true)

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
    local candidate

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

    candidate = self:TrackLootCandidate(itemLink, bossName, nil, nil, self.currentLootSessionId)

    if candidate then
        self:ScheduleLootInventoryScan(LOOT_BAG_SCAN_MAX_RETRIES, true)
    end

    if candidate and self.RefreshMainWindow then
        self:RefreshMainWindow()
    end
end

function addon:HandleCombatLogEvent(...)
    -- Авто-определение: есть ли hideCaster (boolean) на позиции 3.
    -- WoW 3.3.5a без патчей: arg3 = sourceGUID (string) → offset = 0.
    -- Сборки с hideCaster из Cata+:      arg3 = true/false   → offset = 1.
    if cleuHasCaster == nil then
        cleuHasCaster = (type(select(3, ...)) == "boolean")
    end

    local off      = cleuHasCaster and 1 or 0
    local subEvent = select(2, ...)
    local destGUID = select(6 + off, ...)
    local destName = select(7 + off, ...)
    local destFlags = safenum(select(8 + off, ...), 0)

    if subEvent ~= "PARTY_KILL" and subEvent ~= "UNIT_DIED" and subEvent ~= "UNIT_DESTROYED" then
        return
    end

    if not destGUID or not destName then
        return
    end

    -- Фильтруем не-NPC (игроки, питомцы и т.д.).
    -- Если destFlags = 0 — значит offset определён неверно или сервер не передаёт флаги;
    -- в этом случае пропускаем фильтр, чтобы не терять боссов.
    if bit and bit.band and npcTypeFlag > 0 and destFlags > 0 then
        if bit.band(destFlags, npcTypeFlag) == 0 then
            return
        end
    end

    self:RememberLootSource(destGUID, destName)
end

function addon:HandleLootOpened()
    self.currentLootSessionId = self:CreateLootSessionId()
    local capturedCount = self:CaptureLootWindowEntries()

    self.pendingLootChatUntil = time() + 15

    if capturedCount <= 0 then
        self:ScheduleLootWindowRetry(5)
    else
        self.pendingLootWindowRetryCount = 0
        self.pendingLootWindowRetryAt = nil
        self:ScheduleLootInventoryScan(LOOT_BAG_SCAN_MAX_RETRIES, true)
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

    if table.getn(entries) == 0 and self:TryRecoverLooseTimedLootEntries() > 0 then
        entries = self:GetLootEntries()
    end

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

    self:SetPendingItem(entry.itemLink, entry.id)

    if self.SetMainTab then
        self:SetMainTab("auction")
    end

    return true
end

function addon:SetLootEntryStatus(entryId, status, auctionId)
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries
    local index
    local entry

    if not entryId or entryId == "" then
        return false
    end

    for index = 1, table.getn(entries) do
        entry = self:NormalizeLootEntry(entries[index])

        if entry and tostring(entry.id or "") == tostring(entryId) then
            entry.status = tostring(status or entry.status or "pending")
            entry.auctionId = auctionId or entry.auctionId
            entry.lastStatusAt = time()
            return true
        end
    end

    return false
end

function addon:FinalizeLootEntryAuction(entryId, winner, amount, auctionId)
    if not entryId or entryId == "" then
        return false
    end

    if winner and amount and amount > 0 then
        return self:SetLootEntryStatus(entryId, "sold", auctionId)
    end

    return self:SetLootEntryStatus(entryId, "pending", auctionId)
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

    return self:GetDefaultAuctionMinBid()
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
    local excludedPlayers = GoldBidDB.split.excludedPlayers or {}
    local leaderName = normalizeName(self:GetLeaderName() or self:GetPlayerName())
    local seen = {}
    local index
    local name

    local function addName(value, remember)
        value = normalizeName(value)

        if not value then
            return
        end

        if excludedPlayers[value] and value ~= leaderName then
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

    addName(leaderName, true)

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

function addon:RemoveSplitPlayer(name)
    self:EnsureSplitDB()
    name = normalizeName(name)

    if not self:IsPlayerController() then
        self:Print("Удалять игроков из делёжки может только мастер лутер.")
        return false
    end

    if not name then
        return false
    end

    if name == normalizeName(self:GetLeaderName() or self:GetPlayerName()) then
        self:Print("РЛ нельзя удалить из делёжки.")
        return false
    end

    GoldBidDB.split.rosterSnapshot[name] = nil
    GoldBidDB.split.entries[name] = nil
    GoldBidDB.split.excludedPlayers[name] = true
    GoldBidDB.split.lastComputed = nil
    self.cachedSplit = nil

    if self.ResetMailPayoutState then
        self:ResetMailPayoutState(true)
    end

    if GoldBidDB.ledger and GoldBidDB.ledger.payout then
        self:ComputePayout()
    elseif self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    if UnitInRaid("player") or UnitInParty("player") then
        self:BroadcastState(nil, true)

        if GoldBidDB.ledger and GoldBidDB.ledger.payout then
            self:SendPayoutState()
        end
    end

    self:Print("Игрок удалён из делёжки: " .. tostring(name))
    return true
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
            mailFailed = entry.mailFailed,
            mailFailedPayoutKey = entry.mailFailedPayoutKey,
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
        row.mailFailed = row.net > 0
            and not row.sent
            and tostring(row.mailFailedPayoutKey or "") == payoutKey
            and tostring(row.mailFailed or "") ~= ""
        row.mailError = row.mailFailed and tostring(row.mailFailed or "") or ""
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
            lastError = nil,
            lastErrorAt = nil,
        }
    end

    return self.mailPayout
end

function addon:GetMailFailureMessage(...)
    local index

    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    return nil
end

function addon:IsMailboxFullError(message)
    local rawText = tostring(message or "")
    local text = string.lower(rawText)
    local capText = tostring(_G.ERR_MAIL_RECIPIENT_CAP or _G.ERR_MAIL_REACHED_CAP or "")

    if capText ~= "" and text == string.lower(capText) then
        return true
    end

    return (string.find(text, "mailbox", 1, true) and string.find(text, "full", 1, true))
        or (string.find(text, "mail", 1, true) and string.find(text, "cap", 1, true))
        or (string.find(text, "почт", 1, true) and (
            string.find(text, "заполн", 1, true)
            or string.find(text, "переполн", 1, true)
            or string.find(text, "полон", 1, true)
        ))
        or (string.find(rawText, "Почт", 1, true) and (
            string.find(rawText, "заполн", 1, true)
            or string.find(rawText, "Заполн", 1, true)
            or string.find(rawText, "переполн", 1, true)
            or string.find(rawText, "Переполн", 1, true)
            or string.find(rawText, "полон", 1, true)
            or string.find(rawText, "Полон", 1, true)
        ))
end

function addon:RememberMailError(...)
    local state = self:GetMailPayoutState()
    local message = self:GetMailFailureMessage(...)

    if not state.active or not self:IsMailOpen() or not message then
        return
    end

    state.lastError = message
    state.lastErrorAt = time()
end

function addon:ResetMailPayoutState(skipRefresh)
    local state = self:GetMailPayoutState()

    state.active = false
    state.queue = {}
    state.index = 1
    state.sent = 0
    state.total = 0
    state.lastError = nil
    state.lastErrorAt = nil

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
        state.lastError = nil
        state.lastErrorAt = nil

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
            splitEntry.mailFailed = nil
            splitEntry.mailFailedPayoutKey = nil
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

function addon:HandleMailSendFailed(...)
    local state = self:GetMailPayoutState()
    local entry
    local message = self:GetMailFailureMessage(...) or state.lastError
    local isMailboxFull = self:IsMailboxFullError(message)
    local splitEntry

    if not state.active then
        return
    end

    entry = state.queue[state.index]

    if entry then
        if isMailboxFull then
            splitEntry = self:EnsureSplitEntry(entry.name)

            if splitEntry then
                splitEntry.mailFailed = message or "Почта получателя заполнена"
                splitEntry.mailFailedPayoutKey = tostring(entry.payoutKey or "")
            end

            self:Print("Предупреждение: у " .. tostring(entry.name) .. " заполнена почта. Строка отмечена красным, перехожу к следующему получателю.")
            state.index = state.index + 1
        else
            self:Print("Ошибка отправки " .. tostring(entry.name) .. ". Проверьте почту и повторите отправку.")
        end
    else
        self:Print("Ошибка отправки письма.")
    end

    state.lastError = nil
    state.lastErrorAt = nil

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    if state.index > state.total then
        self:Print("Почтовая раздача завершена с предупреждениями.")
        self:ResetMailPayoutState()
        return
    end

    self:PrepareNextMailEntry(true)
end

function addon:ResetAuction()
    self.currentAuction = {
        id = nil,
        itemLink = nil,
        itemName = nil,
        lootEntryId = nil,
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
        extensionCount = 0,
    }
    self.skippedAuctionId = nil
    self.pendingSkipAuctionId = nil
    self.lastCountdownSecond = nil
    self.pendingAuctionReset = nil
    self.autoHideFrameAt = nil
    self.cachedSplit = nil

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
    self.currentAuction.extensionCount = math.max(0, math.floor(safenum(self.currentAuction.extensionCount, 0)))
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

    GoldBidDB.loot = {
        entries = {},
    }

    GoldBidDB.split = {
        guildSharePercent = splitSettings.guildSharePercent or DEFAULT_GUILD_SHARE_PERCENT,
        leaderSharePercent = splitSettings.leaderSharePercent or DEFAULT_LEADER_SHARE_PERCENT,
        substitutePercent = splitSettings.substitutePercent or 100,
        rosterSnapshot = {},
        excludedPlayers = {},
        entries = {},
        lastComputed = nil,
    }

    GoldBidDB.ui = ui or GoldBidDB.ui
    self.pendingItemLink = nil
    self.pendingLootEntryId = nil
    self.pendingLootCandidates = {}
    self.pendingLootBagScanCount = 0
    self.pendingLootBagScanAt = nil
    self.pendingLootBagScanIncludeActive = nil
    self.currentLootSessionId = nil
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

function addon:OpenAuction(itemLink, minBid, increment, duration, auctionId, leaderName, mode, lootEntryId)
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
    self.currentAuction.lootEntryId = lootEntryId
    self.currentAuction.minBid = math.max(self:GetDefaultAuctionMinBid(), safenum(minBid, self:GetDefaultAuctionMinBid()))
    self.currentAuction.increment = safenum(increment, self:GetDefaultAuctionIncrement())
    self.currentAuction.duration = activeDuration
    self.currentAuction.leader = normalizeName(leaderName) or self:GetLeaderName()
    self.currentAuction.startedAt = time()
    self.currentAuction.endsAt = self.currentAuction.startedAt + activeDuration
    self.currentAuction.status = "running"
    self.currentAuction.mode = auctionMode
    self.currentAuction.rerollRound = 0
    self.currentAuction.extensionCount = 0
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

function addon:GetSaleIndexByAuctionId(auctionId)
    local sales
    local index

    if not auctionId or auctionId == "" or not GoldBidDB or not GoldBidDB.ledger then
        return nil
    end

    sales = GoldBidDB.ledger.sales or {}

    for index = 1, table.getn(sales) do
        if tostring(sales[index].auctionId or "") == tostring(auctionId) then
            return index
        end
    end

    return nil
end

function addon:GetSalePaidAmount(sale)
    local amount = math.max(0, floorGold(safenum(sale and sale.amount, 0)))
    local paid = math.max(0, floorGold(safenum(sale and sale.paidAmount, 0)))

    return math.min(paid, amount)
end

function addon:GetSaleDebtAmount(sale)
    local amount = math.max(0, floorGold(safenum(sale and sale.amount, 0)))
    local paid = self:GetSalePaidAmount(sale)

    return math.max(0, amount - paid)
end

function addon:UpdateSalePaidAmount(index, paidAmount, skipBroadcast)
    self:EnsureDB()
    local sales = GoldBidDB.ledger.sales or {}
    local sale = sales[tonumber(index or 0)]
    local amount
    local paid

    if not sale then
        return false
    end

    amount = math.max(0, floorGold(safenum(sale.amount, 0)))
    paid = math.max(0, floorGold(safenum(paidAmount, 0)))
    sale.paidAmount = math.min(paid, amount)

    if not skipBroadcast and self:IsPlayerController() and sale.auctionId and sale.auctionId ~= "" then
        self:SendCommand("SALE_PAID", {
            sale.auctionId,
            sale.paidAmount,
        }, self:GetDistributionChannel())
    end

    if self.RefreshMainWindow then
        self:RefreshMainWindow()
    end

    return true
end

function addon:ApplySalePaidUpdate(auctionId, paidAmount)
    local saleIndex = self:GetSaleIndexByAuctionId(auctionId)

    if not saleIndex then
        return false
    end

    return self:UpdateSalePaidAmount(saleIndex, paidAmount, true)
end

function addon:EnsureTradeSaleRecord(auctionId, itemLink, winner, amount, paidAmount, lootEntryId)
    self:EnsureDB()
    local saleIndex = self:GetSaleIndexByAuctionId(auctionId)
    local sale
    local currentPaid
    local incomingPaid

    if saleIndex then
        sale = GoldBidDB.ledger.sales[saleIndex]
        currentPaid = self:GetSalePaidAmount(sale)
        incomingPaid = paidAmount ~= nil and math.max(0, floorGold(safenum(paidAmount, currentPaid))) or currentPaid

        sale.itemLink = (itemLink and itemLink ~= "") and itemLink or sale.itemLink
        sale.winner = (winner and winner ~= "") and normalizeName(winner) or sale.winner
        sale.amount = math.max(0, floorGold(safenum(amount, sale.amount or 0)))
        sale.paidAmount = self:GetSalePaidAmount({
            amount = sale.amount,
            paidAmount = math.max(currentPaid, incomingPaid),
        })
        sale.lootEntryId = (lootEntryId and lootEntryId ~= "") and lootEntryId or sale.lootEntryId
        return saleIndex, sale
    end

    if not auctionId or auctionId == "" or not itemLink or itemLink == "" or not winner or winner == "" then
        return nil, nil
    end

    sale = {
        timestamp = date("%Y-%m-%d %H:%M:%S"),
        itemLink = itemLink,
        winner = normalizeName(winner) or winner,
        guildName = self:GetGuildNameForPlayer(winner),
        amount = math.max(0, floorGold(safenum(amount, 0))),
        paidAmount = math.max(0, floorGold(safenum(paidAmount, 0))),
        auctionId = auctionId,
        lootEntryId = (lootEntryId and lootEntryId ~= "") and lootEntryId or nil,
    }
    sale.paidAmount = self:GetSalePaidAmount(sale)

    table.insert(GoldBidDB.ledger.sales, sale)
    GoldBidDB.ledger.pot = math.max(0, floorGold(safenum(GoldBidDB.ledger.pot, 0)) + floorGold(sale.amount or 0))
    self.cachedSplit = nil
    return table.getn(GoldBidDB.ledger.sales), sale
end

function addon:GetLootEntryById(entryId)
    self:EnsureLootDB()
    local entries = GoldBidDB.loot.entries or {}
    local index
    local entry

    if not entryId or entryId == "" then
        return nil
    end

    for index = 1, table.getn(entries) do
        entry = self:NormalizeLootEntry(entries[index])

        if entry and tostring(entry.id or "") == tostring(entryId) then
            return entry
        end
    end

    return nil
end

function addon:GetTradeTargetName()
    local unitTokens = { "target", "npc", "NPC" }
    local frameNames = {
        "TradeFrameRecipientNameText",
        "TradeFrameRecipientName",
        "TradeFrameRecipient",
    }
    local index
    local name
    local object
    local text

    for index = 1, table.getn(unitTokens) do
        if UnitExists and UnitExists(unitTokens[index]) and (not UnitIsPlayer or UnitIsPlayer(unitTokens[index])) then
            name = UnitName(unitTokens[index])

            if normalizeName(name) then
                return normalizeName(name)
            end
        end
    end

    if self.pendingTradeRequestName and self.pendingTradeRequestName ~= "" then
        return normalizeName(self.pendingTradeRequestName)
    end

    for index = 1, table.getn(frameNames) do
        object = _G[frameNames[index]]
        text = object and object.GetText and object:GetText() or nil

        if normalizeName(text) then
            return normalizeName(text)
        end
    end

    return nil
end

function addon:FindUnpaidSaleForWinner(winnerName, auctionId)
    self:EnsureDB()
    local normalizedWinner = normalizeName(winnerName)
    local sales = GoldBidDB.ledger.sales or {}
    local index
    local sale

    if not normalizedWinner then
        return nil, nil
    end

    for index = table.getn(sales), 1, -1 do
        sale = sales[index]

        if normalizeName(sale and sale.winner) == normalizedWinner
            and (not auctionId or auctionId == "" or tostring(sale.auctionId or "") == tostring(auctionId))
            and self:GetSaleDebtAmount(sale) > 0 then
            return index, sale
        end
    end

    return nil, nil
end

function addon:FindTradeSaleAsBuyer(targetName)
    local pendingOffer = self.pendingTradeOffer
    local playerName = self:GetPlayerName()
    local saleIndex
    local sale
    local hasFreshOffer = pendingOffer
        and pendingOffer.auctionId
        and (time() - safenum(pendingOffer.at, 0)) <= TRADE_HELPER_OFFER_TTL_SECONDS

    if targetName and not self:IsController(targetName) then
        return nil, nil
    end

    if not targetName and not hasFreshOffer then
        return nil, nil
    end

    if hasFreshOffer
        and (not targetName or normalizeName(pendingOffer.sender) == normalizeName(targetName)) then
        saleIndex, sale = self:FindUnpaidSaleForWinner(playerName, pendingOffer.auctionId)

        if sale then
            return saleIndex, sale
        end
    end

    return self:FindUnpaidSaleForWinner(playerName)
end

function addon:FindTradeItemSource(sale)
    local itemLink = sale and sale.itemLink
    local entry = self:GetLootEntryById(sale and sale.lootEntryId)
    local bag
    local slot
    local slotCount
    local link

    if not itemLink or itemLink == "" then
        return nil
    end

    if entry and tostring(entry.locationType or "") == "bag" and entry.bag ~= nil and entry.slot ~= nil then
        link = getContainerItemLinkCompat(entry.bag, entry.slot)

        if isSameItemLink(link, itemLink) then
            return {
                locationType = "bag",
                bag = entry.bag,
                slot = entry.slot,
                itemLink = link,
            }
        end
    end

    for bag = 0, 4 do
        slotCount = getContainerNumSlotsCompat(bag)

        for slot = 1, slotCount do
            link = getContainerItemLinkCompat(bag, slot)

            if isSameItemLink(link, itemLink) then
                return {
                    locationType = "bag",
                    bag = bag,
                    slot = slot,
                    itemLink = link,
                }
            end
        end
    end

    return nil
end

function addon:IsTradeSourceItemGone(source, itemLink)
    local link

    if not source or tostring(source.locationType or "") ~= "bag" then
        return false
    end

    link = getContainerItemLinkCompat(source.bag, source.slot)
    return not isSameItemLink(link, itemLink)
end

function addon:IsSaleItemInPlayerTrade(sale)
    local slot
    local link

    if not sale or not sale.itemLink or sale.itemLink == "" or not GetTradePlayerItemLink then
        return false
    end

    for slot = 1, TRADE_HELPER_SLOT_COUNT do
        link = GetTradePlayerItemLink(slot)

        if isSameItemLink(link, sale.itemLink) then
            return true
        end
    end

    return false
end

function addon:IsSaleItemInTargetTrade(sale)
    local slot
    local link

    if not sale or not sale.itemLink or sale.itemLink == "" or not GetTradeTargetItemLink then
        return false
    end

    for slot = 1, TRADE_HELPER_SLOT_COUNT do
        link = GetTradeTargetItemLink(slot)

        if isSameItemLink(link, sale.itemLink) then
            return true
        end
    end

    return false
end

function addon:PlaceSaleItemIntoTrade(sale, state)
    local emptySlot
    local slot
    local source
    local ok
    local err

    if self:IsSaleItemInPlayerTrade(sale) then
        return true
    end

    if state then
        state.itemAttempted = true
    end

    if not PickupContainerItem or not ClickTradeButton then
        self:Print("Автообмен недоступен: нет API для помещения предмета в трейд.")
        return false
    end

    for slot = 1, TRADE_HELPER_SLOT_COUNT do
        if not GetTradePlayerItemLink or not GetTradePlayerItemLink(slot) then
            emptySlot = slot
            break
        end
    end

    if not emptySlot then
        self:Print("В окне обмена нет свободного слота для лота.")
        return false
    end

    source = self:FindTradeItemSource(sale)

    if not source then
        self:Print("Не нашёл предмет для автообмена: " .. tostring(sale and (sale.itemLink or sale.itemName) or "лот"))
        return false
    end

    if CursorHasItem and CursorHasItem() and ClearCursor then
        ClearCursor()
    end

    ok, err = pcall(PickupContainerItem, source.bag, source.slot)

    if not ok then
        self:Print("Не удалось взять предмет из сумки: " .. tostring(err or "ошибка"))
        return false
    end

    ok, err = pcall(ClickTradeButton, emptySlot)

    if not ok then
        if ClearCursor then
            ClearCursor()
        end

        self:Print("Не удалось положить предмет в обмен: " .. tostring(err or "ошибка"))
        return false
    end

    if state then
        state.source = source
        state.itemPlaced = true
    end

    self:Print("В обмен добавлен лот: " .. tostring(sale.itemLink or sale.itemName or "предмет"))
    return true
end

function addon:SetSaleTradeMoney(sale, state)
    local debt = self:GetSaleDebtAmount(sale)
    local copper = debt * 10000
    local currentCopper = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
    local availableCopper = GetMoney and GetMoney() or copper
    local ok
    local err

    if debt <= 0 then
        return false
    end

    if currentCopper == copper then
        return true
    end

    if state then
        state.moneyAttempted = true
    end

    if availableCopper < copper then
        if state and not state.notEnoughMoneyPrinted then
            state.notEnoughMoneyPrinted = true
            self:Print(string.format("Недостаточно золота для оплаты лота: нужно %dg.", debt))
        end

        return false
    end

    if not SetTradeMoney then
        if not state or not state.moneyErrorPrinted then
            if state then
                state.moneyErrorPrinted = true
            end

            self:Print("Автообмен недоступен: нет API для установки золота в трейд.")
        end

        return false
    end

    ok, err = pcall(SetTradeMoney, copper)

    if not ok then
        if not state or not state.moneyErrorPrinted then
            if state then
                state.moneyErrorPrinted = true
            end

            self:Print("Не удалось выставить золото в обмен: " .. tostring(err or "ошибка"))
        end

        return false
    end

    if state then
        state.moneyPlaced = true
    end

    self:Print(string.format("В обмен добавлено золото за лот: %dg.", debt))
    return true
end

function addon:SendTradeOffer(sale, targetName)
    targetName = normalizeName(targetName)

    if not targetName or not sale or not sale.auctionId or sale.auctionId == "" then
        return
    end

    self:SendCommand("TRADE_OFFER", {
        sale.auctionId,
        sale.itemLink or "",
        sale.amount or 0,
        self:GetSalePaidAmount(sale),
        sale.lootEntryId or "",
    }, "WHISPER", targetName)
end

function addon:PrepareTradeHelper()
    local targetName = self:GetTradeTargetName()
    local saleIndex
    local sale
    local role

    if self:IsPlayerController() then
        saleIndex, sale = self:FindUnpaidSaleForWinner(targetName)
        role = "controller"
    else
        saleIndex, sale = self:FindTradeSaleAsBuyer(targetName)
        role = "buyer"
    end

    if not sale then
        return false
    end

    self.tradeHelper = {
        active = true,
        role = role,
        targetName = targetName,
        saleIndex = saleIndex,
        auctionId = tostring(sale.auctionId or ""),
        itemLink = sale.itemLink,
        amount = math.max(0, floorGold(safenum(sale.amount, 0))),
        debt = self:GetSaleDebtAmount(sale),
        paidBefore = self:GetSalePaidAmount(sale),
        moneyBefore = GetMoney and GetMoney() or 0,
    }

    if role == "controller" then
        self:SendTradeOffer(sale, targetName)
        self:PlaceSaleItemIntoTrade(sale, self.tradeHelper)
    else
        self:SetSaleTradeMoney(sale, self.tradeHelper)
    end

    self:RefreshTradeHelper()
    return true
end

function addon:RefreshTradeHelper()
    local state = self.tradeHelper
    local sale
    local debtCopper
    local targetCopper
    local playerCopper
    local itemReady

    if not state or not state.active then
        return
    end

    sale = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.sales and GoldBidDB.ledger.sales[state.saleIndex] or nil

    if not sale or self:GetSaleDebtAmount(sale) <= 0 then
        return
    end

    debtCopper = self:GetSaleDebtAmount(sale) * 10000

    if state.role == "controller" then
        if not self:IsSaleItemInPlayerTrade(sale) and not state.itemAttempted then
            self:PlaceSaleItemIntoTrade(sale, state)
        end

        itemReady = self:IsSaleItemInPlayerTrade(sale)
        targetCopper = GetTargetTradeMoney and GetTargetTradeMoney() or 0
        state.observedTargetCopper = targetCopper
        state.observedItemReady = itemReady

        state.readyForComplete = itemReady and targetCopper >= debtCopper

        if state.readyForComplete then
            if not state.readyPrinted then
                state.readyPrinted = true
                self:Print("Обмен готов: предмет и золото на месте. Проверьте окно и подтвердите обмен.")
            end
        end
    else
        playerCopper = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0

        if playerCopper < debtCopper and not state.moneyAttempted then
            self:SetSaleTradeMoney(sale, state)
            playerCopper = GetPlayerTradeMoney and GetPlayerTradeMoney() or playerCopper
        end

        itemReady = self:IsSaleItemInTargetTrade(sale)

        if itemReady and playerCopper >= debtCopper and not state.readyPrinted then
            state.readyPrinted = true
            self:Print("Обмен готов: лот и золото на месте. Проверьте окно и подтвердите обмен.")
        end
    end
end

function addon:HandleTradeRequest(playerName)
    self.pendingTradeRequestName = normalizeName(playerName)
end

function addon:HandleTradeShow()
    self:PrepareTradeHelper()
end

function addon:HandleTradeUpdate()
    if not self.tradeHelper or not self.tradeHelper.active then
        self:PrepareTradeHelper()
        return
    end

    self:RefreshTradeHelper()
end

function addon:HandleTradeClosed()
    local state = self.tradeHelper

    if state and state.role == "controller" and state.source then
        self.pendingTradeCompletionCheck = {
            at = (GetTime and GetTime() or 0) + TRADE_HELPER_COMPLETE_CHECK_DELAY,
            auctionId = state.auctionId,
            saleIndex = state.saleIndex,
            itemLink = state.itemLink,
            source = state.source,
            paidAmount = state.amount,
            debt = state.debt,
            paidBefore = state.paidBefore,
            moneyBefore = state.moneyBefore,
            readyForComplete = state.readyForComplete and true or false,
            attempts = 0,
        }
    end

    self.tradeHelper = nil
    self.pendingTradeRequestName = nil
    self.pendingTradeOffer = nil
end

function addon:ProcessPendingTradeCompletionCheck()
    local check = self.pendingTradeCompletionCheck
    local now = GetTime and GetTime() or 0
    local saleIndex
    local sale
    local previousPaid
    local itemGone
    local currentMoney
    local moneyDeltaCopper
    local moneyDeltaGold
    local newPaidAmount

    if not check or now < safenum(check.at, 0) then
        return
    end

    saleIndex = self:GetSaleIndexByAuctionId(check.auctionId) or check.saleIndex
    sale = GoldBidDB and GoldBidDB.ledger and GoldBidDB.ledger.sales and GoldBidDB.ledger.sales[saleIndex] or nil

    if not sale then
        self.pendingTradeCompletionCheck = nil
        return
    end

    previousPaid = self:GetSalePaidAmount(sale)
    itemGone = self:IsTradeSourceItemGone(check.source, check.itemLink)
    currentMoney = GetMoney and GetMoney() or 0
    moneyDeltaCopper = math.max(0, currentMoney - safenum(check.moneyBefore, currentMoney))
    moneyDeltaGold = floorGold(moneyDeltaCopper / 10000)

    if itemGone and moneyDeltaGold <= 0 and not check.readyForComplete and safenum(check.attempts, 0) < 3 then
        check.at = now + TRADE_HELPER_COMPLETE_CHECK_DELAY
        check.attempts = safenum(check.attempts, 0) + 1
        return
    end

    self.pendingTradeCompletionCheck = nil

    if itemGone then
        if moneyDeltaGold > 0 then
            newPaidAmount = math.min(
                math.max(0, floorGold(safenum(sale.amount, 0))),
                math.max(0, floorGold(safenum(check.paidBefore, previousPaid))) + moneyDeltaGold
            )
        elseif check.readyForComplete then
            newPaidAmount = math.min(
                math.max(0, floorGold(safenum(sale.amount, 0))),
                math.max(0, floorGold(safenum(check.paidBefore, previousPaid))) + math.max(0, floorGold(safenum(check.debt, 0)))
            )
        end
    end

    if newPaidAmount and newPaidAmount > previousPaid then
        self:UpdateSalePaidAmount(saleIndex, newPaidAmount)
        self:Print(string.format(
            "Оплата отмечена: %s передал %dg за %s.",
            tostring(sale.winner or "-"),
            floorGold(newPaidAmount - previousPaid),
            tostring(sale.itemLink or sale.itemName or "лот")
        ))
    end
end

function addon:HandleTradeOffer(fields, sender)
    local auctionId = tostring(fields[2] or "")
    local itemLink = tostring(fields[3] or "")
    local amount = safenum(fields[4], 0)
    local paidAmount = safenum(fields[5], 0)
    local lootEntryId = tostring(fields[6] or "")

    if not self:AcceptControllerSender(sender) then
        return
    end

    self:EnsureTradeSaleRecord(auctionId, itemLink, self:GetPlayerName(), amount, paidAmount, lootEntryId)
    self.pendingTradeOffer = {
        sender = normalizeName(sender),
        auctionId = auctionId,
        at = time(),
    }

    if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then
        self:PrepareTradeHelper()
    end
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
                paidAmount = 0,
                auctionId = auction.id,
                lootEntryId = auction.lootEntryId,
            })

            GoldBidDB.ledger.pot = (GoldBidDB.ledger.pot or 0) + amount
            self.cachedSplit = nil  -- банк изменился — сбрасываем кеш делёжки
            self:Print(string.format("%s выиграл %s за %dg.", tostring(winner), tostring(auction.itemLink or auction.itemName or "лот"), amount))

            if self:IsPlayerController() and normalizeName(winner) then
                self:SendCommand("TRADE_SALE", {
                    auction.id,
                    auction.itemLink or "",
                    winner,
                    amount,
                    auction.lootEntryId or "",
                }, "WHISPER", normalizeName(winner))
            end
        end
    elseif mode == "roll" and winner and amount and amount > 0 then
        self:Print(string.format("%s выиграл %s по роллу %d.", tostring(winner), tostring(auction.itemLink or auction.itemName or "лот"), amount))
    elseif mode == "roll" then
        self:Print(string.format("Ролл на %s завершён без бросков.", tostring(auction.itemLink or auction.itemName or "лот")))
    else
        self:Print(string.format("Торги по %s завершены без ставок.", tostring(auction.itemLink or auction.itemName or "лот")))
    end

    self:FinalizeLootEntryAuction(auction.lootEntryId, winner, amount, auction.id)

    if self:IsPlayerController() then
        -- Контроллер: сбрасываем и обновляем UI сразу — ему нужно готовить следующий лот.
        self:ResetAuction()
        if self.RefreshMainWindow then
            self:RefreshMainWindow()
        end
    else
        -- Остальные игроки: откладываем сброс и обновление UI до момента скрытия окна.
        -- pendingAuctionReset блокирует RefreshMainWindow в OnUpdate, чтобы финальное
        -- состояние торгов (итоговые ставки, победитель) оставалось видимым 3 секунды.
        self.pendingAuctionReset = true
        self.autoHideFrameAt = (GetTime and GetTime() or 0) + 3
    end
end

function addon:BroadcastState(target, forceSend)
    self:EnsureAuctionState()
    local auction = self.currentAuction
    local revision

    if not forceSend and not self:IsPlayerController() then
        return
    end

    if not target and self:IsPlayerController() then
        revision = self:BumpStateRevision()
    else
        revision = self:GetStateRevision()
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
        auction.extensionCount or 0,
        revision,
        self.version,
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
    local extensionCount = safenum(fields[17], 0)
    local stateRevision = safenum(fields[18], 0)
    local senderVersion = fields[19]

    self:EnsureAuctionState()

    self:RecordAddonVersion(sender, senderVersion or "pre-2.1", stateRevision)

    if not self:ShouldAcceptStateRevision(sender, stateRevision) then
        return
    end

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
        self.currentAuction.minBid = math.max(self:GetDefaultAuctionMinBid(), minBid)
        self.currentAuction.increment = increment
        self.currentAuction.duration = duration
        self.currentAuction.startedAt = startedAt > 0 and startedAt or time()
        self.currentAuction.endsAt = endsAt > 0 and endsAt or (status == "running" and (time() + duration) or nil)
        self.currentAuction.leader = leaderName
        self.currentAuction.status = status
        self.currentAuction.mode = mode
        self.currentAuction.rerollPlayers = rerollPlayers
        self.currentAuction.rerollRound = rerollRound
        self.currentAuction.extensionCount = extensionCount
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
    local debtSummary = self:BuildDebtSummary()
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
        pushTableHeader(lines, { "#", "Лот", "Победитель", "Цена", "Отдано", "Должен" })

        for index = 1, table.getn(sales) do
            local sale = sales[index]
            local paid = self:GetSalePaidAmount(sale)
            local debt = self:GetSaleDebtAmount(sale)

            table.insert(lines, string.format(
                "| %d | %s | %s | %s | %s | %s |",
                index,
                cleanCell(sale.itemLink or "?"),
                cleanCell(sale.winner or "?"),
                formatGoldAmount(sale.amount or 0),
                formatGoldAmount(paid),
                formatGoldAmount(debt)
            ))
        end
    end

    if debtSummary and debtSummary.rows and table.getn(debtSummary.rows) > 0 then
        table.insert(lines, "")
        table.insert(lines, "Долги к оплате")
        table.insert(lines, "Всего: " .. formatGoldAmount(debtSummary.totalDebt or 0))
        pushTableHeader(lines, { "#", "Лот", "Игрок", "Цена", "Отдано", "Долг" })

        for index = 1, table.getn(debtSummary.rows) do
            local row = debtSummary.rows[index]

            table.insert(lines, string.format(
                "| %d | %s | %s | %s | %s | %s |",
                index,
                cleanCell(row.itemLink or row.itemName or "?"),
                cleanCell(row.winner or "?"),
                formatGoldAmount(row.amount or 0),
                formatGoldAmount(row.paid or 0),
                formatGoldAmount(row.debt or 0)
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

    -- Дублируем ставку в рейд-чат, чтобы игроки без аддона видели торги
    local distChannel = self:GetDistributionChannel()
    if distChannel then
        SendChatMessage(bidder .. " - " .. formatGoldAmount(amount), distChannel)
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

-- Обрабатывает ставку, написанную игроком напрямую в рейд-чат (без аддона).
-- Принимается только числовое сообщение в режиме GoldBid.
function addon:HandleRaidChatBid(message, sender)
    local amount
    local bidder
    local ok, reason

    if not self:IsPlayerController() then
        return
    end

    if not self:IsAuctionActive() then
        return
    end

    if normalizeAuctionMode(self.currentAuction.mode) ~= "goldbid" then
        return
    end

    bidder = normalizeName(sender)

    -- Принимаем только от участников рейда/группы.
    -- Для собственных сообщений контроллера (он сам бидается) проверку ростера пропускаем —
    -- CHAT_MSG_RAID для сообщений самого игрока может давать имя в другом формате.
    local isSelf = (bidder == normalizeName(UnitName("player")))
    if not isSelf and (UnitInRaid("player") or UnitInParty("player")) and not self:IsRosterMember(bidder) then
        return
    end

    -- "-" в чате = ПАС
    if message:match("^%s*-%s*$") then
        if self:RecordPass(bidder) then
            self:SendCommand("PASSACK", { self.currentAuction.id, bidder }, self:GetDistributionChannel())
            self:BroadcastState()
        end
        return
    end

    -- Эффективный порог для парсера: если уже есть биды ≥ 1 000 — маленькие числа
    -- трактуются как тысячи (2 → 2 000). Иначе порог = minBid аукциона.
    do
        local _auction   = self.currentAuction
        local _, _top    = self:GetHighestBid()
        local _threshold = _auction and _auction.minBid or nil
        if _top and _top > 0 then
            _threshold = _top + math.max((_auction and _auction.increment or 0), 1)
        end
        amount = parseBidAmountFromText(message, _threshold)
    end
    if not amount or amount <= 0 then
        return
    end

    ok, reason = self:CanBid(amount, bidder)
    if not ok then
        SendChatMessage("GoldBid: " .. (reason or "Ставка не принята."), "WHISPER", nil, sender)
        return
    end

    self:ApplyAcceptedBid(bidder, amount)
    self:SendCommand("ACCEPT", { self.currentAuction.id, bidder, amount }, self:GetDistributionChannel())
    if self:ExtendAuctionForLateBid() then
        self:BroadcastState()
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
        self:RecordAddonVersion(sender, fields[2] or "pre-2.1", 0)

        if self:IsPlayerController() then
            self:SendCommand("CONTROLLER", { (GoldBidDB and GoldBidDB.ui and GoldBidDB.ui.controllerOverride) or "" }, "WHISPER", sender)
            self:BroadcastState(sender)
            self:SendPayoutState(sender)
        else
            self:SendPlayerSpec()
        end
        return
    end

    if command == "VERSION_REQUEST" then
        self:RecordAddonVersion(sender, fields[2] or "pre-2.1", fields[3])
        self:SendCommand("VERSION", { self.version, self:GetStateRevision() }, "WHISPER", sender)
        return
    end

    if command == "VERSION" then
        self:RecordAddonVersion(sender, fields[2] or "pre-2.1", fields[3])
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

    if command == "TRADE_SALE" then
        if self:AcceptControllerSender(sender) then
            self:EnsureTradeSaleRecord(fields[2], fields[3], fields[4], fields[5], 0, fields[6])
        end
        return
    end

    if command == "TRADE_OFFER" then
        self:HandleTradeOffer(fields, sender)
        return
    end

    if command == "SALE_PAID" then
        if self:AcceptControllerSender(sender) then
            self:ApplySalePaidUpdate(fields[2], fields[3])
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
    local lootEntryId

    if not self:IsPlayerController() then
        self:Print("Только мастер лутер может начать аукцион.")
        return
    end

    if not itemLink or itemLink == "" then
        self:Print("Сначала установите предмет (перетащите в окно или /gbid item [ссылка]).")
        return
    end

    mode = self:GetSelectedAuctionMode()
    lootEntryId = self.pendingLootEntryId
    self:OpenAuction(itemLink, minBid, increment, duration, self:CreateAuctionId(), self:GetPlayerName(), mode, lootEntryId)
    self:SetLootEntryStatus(lootEntryId, "auctioning", self.currentAuction.id)
    self.pendingLootEntryId = nil
    self:SendCommand("START", {
        self.currentAuction.id,
        self.currentAuction.itemLink,
        self.currentAuction.minBid,
        self.currentAuction.increment,
        self.currentAuction.duration,
        mode,
    }, self:GetDistributionChannel())
    self:BroadcastState()

    -- Объявляем аукцион для игроков без аддона. Текст зависит от режима.
    local announceMsg
    if normalizeAuctionMode(mode) == "roll" then
        announceMsg = string.format(
            "%s - Время: %s - Используйте /roll 1-100",
            self.currentAuction.itemLink,
            formatClockDuration(self.currentAuction.duration)
        )
    else
        announceMsg = string.format(
            "%s - Мин: %s - Шаг: %s - Время: %s - Ставки числом в рейд-чат",
            self.currentAuction.itemLink,
            formatGoldAmount(self.currentAuction.minBid),
            formatGoldAmount(self.currentAuction.increment),
            formatClockDuration(self.currentAuction.duration)
        )
    end
    if canPlayerSendRaidWarning() then
        SendChatMessage(announceMsg, "RAID_WARNING")
    else
        local fallbackChannel = self:GetDistributionChannel()
        if fallbackChannel then
            SendChatMessage(announceMsg, fallbackChannel)
        end
    end
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
        local itemLink = self.currentAuction.itemLink
        -- Захватываем режим ДО CloseAuction — контроллер сбрасывает currentAuction внутри него
        local auctionMode = normalizeAuctionMode(self.currentAuction.mode)

        self:CloseAuction(winner, amount)
        self:SendCommand("END", {
            auctionId,
            winner or "",
            amount or 0,
        }, self:GetDistributionChannel())
        self:BroadcastState()

        -- Объявляем победителя в рейд-чат (только в режиме GoldBid)
        if auctionMode ~= "roll" then
            local distChannel = self:GetDistributionChannel()
            if distChannel then
                if winner and amount and amount > 0 then
                    SendChatMessage(
                        "Победитель: " .. winner .. " - " .. (itemLink or "лот") .. " за " .. formatGoldAmount(amount),
                        distChannel
                    )
                else
                    SendChatMessage("Аукцион на " .. (itemLink or "лот") .. " завершён без ставок.", distChannel)
                end
            end
        end
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

function addon:SetPendingItem(itemLink, lootEntryId)
    self.pendingItemLink = itemLink
    self.pendingLootEntryId = itemLink and lootEntryId or nil

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


