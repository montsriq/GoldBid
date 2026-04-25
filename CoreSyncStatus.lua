local addon = GoldBid

local function normalizeName(name)
    if not name or name == "" then
        return nil
    end

    name = tostring(name)
    name = string.match(name, "^([^%-]+)") or name
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")

    if name == "" then
        return nil
    end

    return name
end

local function safenum(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback or 0
    end
    return value
end
function addon:GetStateRevision()
    self.stateRevision = math.max(0, math.floor(safenum(self.stateRevision, 0)))
    return self.stateRevision
end

function addon:BumpStateRevision()
    self.stateRevision = self:GetStateRevision() + 1
    return self.stateRevision
end

function addon:ShouldAcceptStateRevision(sender, revision)
    local normalizedSender = normalizeName(sender) or "?"
    local lastRevision

    revision = math.floor(safenum(revision, 0))

    if revision <= 0 then
        return true
    end

    self.lastStateRevisionBySender = self.lastStateRevisionBySender or {}
    lastRevision = safenum(self.lastStateRevisionBySender[normalizedSender], 0)

    if revision <= lastRevision then
        return false
    end

    self.lastStateRevisionBySender[normalizedSender] = revision
    return true
end

function addon:RecordAddonVersion(sender, version, stateRevision)
    sender = normalizeName(sender)

    if not sender then
        return
    end

    self.addonVersions = self.addonVersions or {}
    self.addonVersions[sender] = {
        version = tostring(version or "?"),
        stateRevision = math.max(0, math.floor(safenum(stateRevision, 0))),
        seenAt = time(),
    }
end

function addon:RequestVersionReport()
    local channel = self:GetDistributionChannel()

    self:RecordAddonVersion(self:GetPlayerName(), self.version, self:GetStateRevision())

    if channel then
        self:SendCommand("VERSION_REQUEST", { self.version, self:GetStateRevision() }, channel)
        self.pendingVersionReportAt = (GetTime and GetTime() or 0) + 2
        self:Print("Запрос версий отправлен. Итог появится через 2 сек.")
    else
        self:PrintVersionReport()
    end
end

function addon:PrintVersionReport()
    local roster = self:GetGroupRosterNames()
    local versions = self.addonVersions or {}
    local rows = {}
    local missing = {}
    local index
    local name
    local record

    for index = 1, table.getn(roster) do
        name = roster[index]
        record = versions[name]

        if record then
            table.insert(rows, name .. "=" .. tostring(record.version or "?") .. " r" .. tostring(record.stateRevision or 0))
        else
            table.insert(missing, name)
        end
    end

    self:Print("Версии GoldBid: " .. (table.getn(rows) > 0 and table.concat(rows, ", ") or "ответов нет."))

    if table.getn(missing) > 0 then
        self:Print("Нет ответа: " .. table.concat(missing, ", "))
    end
end

function addon:ProcessPendingVersionReport()
    if self.pendingVersionReportAt and (GetTime and GetTime() or 0) >= self.pendingVersionReportAt then
        self.pendingVersionReportAt = nil
        self:PrintVersionReport()
    end
end

