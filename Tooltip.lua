-- ApeTracksAlts | Tooltip.lua
-- Hooks GameTooltip to display per-character item counts (bags/bank/mail)
-- for every item across all tracked alts on the current realm.
-- Loaded last so it can safely reference ATA helpers from Core.lua.

local ATA = ApeTracksAlts

GameTooltip:HookScript("OnHide", function(self)
    self.__ATAItemShown = nil
end)

GameTooltip:HookScript("OnTooltipSetItem", function(tt)
    if tt.__ATAItemShown then return end
    tt.__ATAItemShown = true

    local _, link = tt:GetItem()
    local itemID  = ATA.GetItemIDFromLink(link)
    if not itemID or not ApeTracksAltsDB[ATA.realm] then return end

    local list         = {}
    local accountTotal = 0
    local realmDB      = ApeTracksAltsDB[ATA.realm]

    for charName, data in pairs(realmDB) do
        local item  = data.items and data.items[itemID]
        local inv   = item and item.inv or 0
        local bnk   = item and item.bnk or 0
        local mb    = item and item.mb  or 0
        local total = inv + bnk + mb

        local isCurrentChar = (charName == ATA.player)
        if total > 0 or isCurrentChar then
            accountTotal = accountTotal + total
            table.insert(list, {
                name   = charName,
                class  = data.class,
                inv    = inv,
                bnk    = bnk,
                mb     = mb,
                total  = total,
                stale  = ATA.IsStale(data),
                isSelf = isCurrentChar,
            })
        end
    end

    if #list == 0 then return end

    -- Sort: current char first, then by count desc, stale to bottom
    table.sort(list, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        if a.stale  ~= b.stale  then return not a.stale end
        return a.total > b.total
    end)

    tt:AddLine(" ")
    tt:AddLine("|cff00ff00ApeTracksAlts|r")

    for _, e in ipairs(list) do
        local staleTag = e.stale and " |cffff4444[stale]|r" or ""

        -- Build a compact inline label string: only show non-zero buckets,
        -- always show Total. Color codes in AddDoubleLine right-side break
        -- column alignment, so we use a single AddLine with inline labels.
        local parts = {}
        if e.inv > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bags:|r %d", e.inv) end
        if e.bnk > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bank:|r %d", e.bnk) end
        if e.mb  > 0 then parts[#parts+1] = string.format("|cffaaaaaa Mail:|r %d", e.mb)  end

        -- Name left, counts right via AddDoubleLine using plain numbers only
        -- on the right side so spacing is predictable
        local rightStr
        if #parts > 0 then
            rightStr = table.concat(parts, "  ") ..
                       string.format("  |cffffff00Total: %d|r", e.total)
        else
            rightStr = "|cff555555no items|r"
        end

        tt:AddDoubleLine(
            ATA.ColorName(e.name, e.class) .. staleTag,
            rightStr,
            1, 1, 1, 1, 1, 1
        )
    end

    tt:AddLine(" ")
    tt:AddDoubleLine(
        "|cffffff00Account Total|r",
        "|cffffff00" .. accountTotal .. "|r",
        1, 1, 1, 1, 1, 1
    )
end)