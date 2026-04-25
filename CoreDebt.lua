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

local function floorGold(value)
    return math.floor(safenum(value, 0))
end
function addon:BuildDebtSummary()
    self:EnsureDB()

    local sales = GoldBidDB.ledger.sales or {}
    local rows = {}
    local totalDebt = 0
    local partialCount = 0
    local unpaidCount = 0
    local paidCount = 0
    local index

    for index = 1, table.getn(sales) do
        local sale = sales[index]
        local amount = math.max(0, floorGold(safenum(sale and sale.amount, 0)))
        local paid = self:GetSalePaidAmount(sale)
        local debt = self:GetSaleDebtAmount(sale)

        if amount > 0 then
            if debt > 0 then
                if paid > 0 then
                    partialCount = partialCount + 1
                else
                    unpaidCount = unpaidCount + 1
                end

                table.insert(rows, {
                    saleIndex = index,
                    auctionId = sale.auctionId,
                    itemLink = sale.itemLink,
                    itemName = sale.itemName,
                    winner = sale.winner,
                    amount = amount,
                    paid = paid,
                    debt = debt,
                    partial = paid > 0,
                })

                totalDebt = totalDebt + debt
            else
                paidCount = paidCount + 1
            end
        end
    end

    table.sort(rows, function(left, right)
        if safenum(left.debt, 0) == safenum(right.debt, 0) then
            return tostring(left.winner or "") < tostring(right.winner or "")
        end

        return safenum(left.debt, 0) > safenum(right.debt, 0)
    end)

    return {
        rows = rows,
        totalDebt = totalDebt,
        unpaidCount = unpaidCount,
        partialCount = partialCount,
        paidCount = paidCount,
    }
end

function addon:WhisperSaleDebt(index)
    self:EnsureDB()

    local sale = GoldBidDB.ledger.sales and GoldBidDB.ledger.sales[tonumber(index or 0)]
    local winner = normalizeName(sale and sale.winner)
    local debt = self:GetSaleDebtAmount(sale)

    if not sale or not winner or debt <= 0 then
        self:Print("Нет долга для напоминания.")
        return false
    end

    SendChatMessage(
        string.format("GoldBid: долг за %s — %dg. Подойдите для оплаты.", tostring(sale.itemLink or sale.itemName or "лот"), debt),
        "WHISPER",
        nil,
        winner
    )
    self:Print("Напоминание отправлено: " .. tostring(winner) .. " — " .. tostring(debt) .. "g.")
    return true
end

