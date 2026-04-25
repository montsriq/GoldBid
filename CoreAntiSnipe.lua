local addon = GoldBid

local DEFAULT_ANTISNIPE_THRESHOLD_SECONDS = 15
local DEFAULT_ANTISNIPE_EXTENSION_SECONDS = 15
local DEFAULT_ANTISNIPE_MAX_EXTENSIONS = 0

local function safenum(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback or 0
    end
    return value
end

local function normalizeAuctionMode(mode)
    mode = tostring(mode or "goldbid")
    if mode == "roll" then
        return "roll"
    end
    return "goldbid"
end
function addon:GetAntiSnipeSettings()
    local ui

    self:EnsureDB()
    ui = GoldBidDB.ui or {}

    return {
        threshold = math.max(0, safenum(ui.antiSnipeThreshold, DEFAULT_ANTISNIPE_THRESHOLD_SECONDS)),
        extension = math.max(0, safenum(ui.antiSnipeExtension, DEFAULT_ANTISNIPE_EXTENSION_SECONDS)),
        maxExtensions = math.max(0, math.floor(safenum(ui.antiSnipeMaxExtensions, DEFAULT_ANTISNIPE_MAX_EXTENSIONS))),
        announce = ui.antiSnipeAnnounce and true or false,
    }
end

function addon:SetAntiSnipeSettings(threshold, extension, maxExtensions, announce)
    self:EnsureDB()

    GoldBidDB.ui.antiSnipeThreshold = math.max(0, math.floor(safenum(threshold, DEFAULT_ANTISNIPE_THRESHOLD_SECONDS)))
    GoldBidDB.ui.antiSnipeExtension = math.max(0, math.floor(safenum(extension, DEFAULT_ANTISNIPE_EXTENSION_SECONDS)))
    GoldBidDB.ui.antiSnipeMaxExtensions = math.max(0, math.floor(safenum(maxExtensions, DEFAULT_ANTISNIPE_MAX_EXTENSIONS)))
    GoldBidDB.ui.antiSnipeAnnounce = announce and true or false
end

function addon:ExtendAuctionForLateBid()
    local auction
    local settings
    local timeLeft
    local newEndsAt
    local maxExtensions
    local extensionCount
    local distChannel

    self:EnsureAuctionState()
    auction = self.currentAuction

    if not self:IsAuctionActive() or not auction.endsAt then
        return false
    end

    if normalizeAuctionMode(auction.mode) ~= "goldbid" then
        return false
    end

    settings = self:GetAntiSnipeSettings()
    if settings.threshold <= 0 or settings.extension <= 0 then
        return false
    end

    timeLeft = self:GetTimeLeft()
    if timeLeft >= settings.threshold then
        return false
    end

    maxExtensions = settings.maxExtensions or 0
    extensionCount = safenum(auction.extensionCount, 0)
    if maxExtensions > 0 and extensionCount >= maxExtensions then
        return false
    end

    newEndsAt = time() + settings.extension
    if auction.endsAt and newEndsAt <= auction.endsAt then
        return false
    end

    auction.endsAt = newEndsAt
    auction.extensionCount = extensionCount + 1

    if auction.startedAt then
        auction.duration = math.max(safenum(auction.duration, 0), newEndsAt - auction.startedAt)
    else
        auction.duration = settings.extension
    end

    if settings.announce then
        distChannel = self:GetDistributionChannel()
        if distChannel then
            SendChatMessage("GoldBid: торги продлены, осталось " .. tostring(settings.extension) .. " сек.", distChannel)
        end
    end

    return true
end

