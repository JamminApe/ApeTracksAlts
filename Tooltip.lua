-- ApeTracksAlts | Tooltip.lua
-- Hooks GameTooltip to display per-character item counts, wishlist highlights,
-- and guild bank counts for banks registered by the current character.

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

    -- Character counts
    for charName, data in pairs(realmDB) do
        if not ignored[charName] or charName == ATA.player then
            local item  = data.items and data.items[itemID]
            local inv   = (showBags and item and item.inv) or 0
            local bnk   = (showBank and item and item.bnk) or 0
            local mb    = (showMail and item and item.mb)  or 0
            local total = inv + bnk + mb
            if total > 0 then
                accountTotal = accountTotal + total
                table.insert(list, {
                    name   = charName,
                    class  = data.class,
                    inv    = inv,
                    bnk    = bnk,
                    mb     = mb,
                    total  = total,
                    stale  = ATA.IsStale(data),
                    isSelf = (charName == ATA.player),
                })
            end
        end
    end

    -- Guild bank counts — per character registration
    -- Use ApeTracksAlts global directly to ensure GuildBank.lua's function is found
    local gbFunc = ApeTracksAlts.GetGuildBankCount
    if gbFunc then
        for _, gc in ipairs(gbFunc(itemID)) do
            accountTotal = accountTotal + gc.count
            table.insert(list, {
                name    = gc.guild,
                class   = nil,
                inv     = 0, bnk = 0, mb = 0,
                total   = gc.count,
                stale   = false,
                isSelf  = false,
                isGuild = true,
            })
        end
    end

    -- Wishlist highlight
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

    -- Sort: self first, guild banks last, stale to bottom, then by count desc
    table.sort(list, function(a, b)
        if a.isGuild ~= b.isGuild then return not a.isGuild end
        if a.isSelf  ~= b.isSelf  then return a.isSelf end
        if a.stale   ~= b.stale   then return not a.stale end
        return a.total > b.total
    end)

    tt:AddLine(" ")
    tt:AddLine("|cff00ff00ApeTracksAlts|r")

    local shownGuildSep = false
    for _, e in ipairs(list) do
        -- Blank line before first guild bank entry
        if e.isGuild and not shownGuildSep then
            tt:AddLine(" ")
            shownGuildSep = true
        end

        local staleTag = e.stale and " |cffff4444[stale]|r" or ""
        local leftStr

        if e.isGuild then
            leftStr = "|cff00cccc Guild Bank|r |cff00aaaa(" .. e.name .. ")|r"
        else
            leftStr = ATA.ColorName(e.name, e.class) .. staleTag
        end

        local parts = {}
        if e.inv > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bags:|r %d", e.inv) end
        if e.bnk > 0 then parts[#parts+1] = string.format("|cffaaaaaa Bank:|r %d", e.bnk) end
        if e.mb  > 0 then parts[#parts+1] = string.format("|cffaaaaaa Mail:|r %d", e.mb)  end
        if e.isGuild then
            parts[#parts+1] = string.format("|cffaaaaaa Items:|r %d", e.total)
        end

        local rightStr
        if #parts > 0 then
            rightStr = table.concat(parts, "  ") ..
                       string.format("  |cffffff00Total: %d|r", e.total)
        else
            rightStr = "|cff555555none|r"
        end

        tt:AddDoubleLine(leftStr, rightStr, 1, 1, 1, 1, 1, 1)
    end

    tt:AddLine(" ")
    tt:AddDoubleLine(
        "|cffffff00Account Total|r",
        "|cffffff00" .. accountTotal .. "|r",
        1, 1, 1, 1, 1, 1
    )
end)
