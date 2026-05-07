-- ApeTracksAlts | Tooltip.lua
-- Hooks GameTooltip to display per-character item counts.
-- Respects ignore list and per-location toggle settings.

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

    local ttCfg    = ApeTracksAltsCfg and ApeTracksAltsCfg.tooltip or {}
    local ignored  = ApeTracksAltsCfg and ApeTracksAltsCfg.ignore  or {}
    local showBags = ttCfg.showBags ~= false
    local showBank = ttCfg.showBank ~= false
    local showMail = ttCfg.showMail ~= false

    local list         = {}
    local accountTotal = 0
    local realmDB      = ApeTracksAltsDB[ATA.realm]

    for charName, data in pairs(realmDB) do
        if not ignored[charName] or charName == ATA.player then
            local item  = data.items and data.items[itemID]
            local inv   = (showBags and item and item.inv) or 0
            local bnk   = (showBank and item and item.bnk) or 0
            local mb    = (showMail and item and item.mb)  or 0
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
    end

    -- Wishlist highlight — shown before the count section
    local wl = ApeTracksAltsCfg and ApeTracksAltsCfg.wishlist
    if wl and wl[ATA.realm] then
        local wantedBy = {}
        for charName, items in pairs(wl[ATA.realm]) do
            if items[itemID] then
                local class = realmDB[charName] and realmDB[charName].class
                table.insert(wantedBy, ATA.ColorName(charName, class))
            end
        end
        if #wantedBy > 0 then
            tt:AddLine("|cffffff00* Wanted by: |r" .. table.concat(wantedBy, ", "))
        end
    end

    if #list == 0 then return end

    table.sort(list, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        if a.stale  ~= b.stale  then return not a.stale end
        return a.total > b.total
    end)

    tt:AddLine(" ")
    tt:AddLine("|cff00ff00ApeTracksAlts|r")

    for _, e in ipairs(list) do
        local staleTag = e.stale and " |cffff4444[stale]|r" or ""
        local parts = {}
        if e.inv > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bags:|r %d", e.inv) end
        if e.bnk > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bank:|r %d", e.bnk) end
        if e.mb  > 0 then parts[#parts+1] = string.format("|cffaaaaaa Mail:|r %d", e.mb)  end

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
