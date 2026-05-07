-- ApeTracksAlts | Wishlist.lua
-- Per-character item wishlist management.

local ATA = ApeTracksAlts

local function EnsureWishlist()
    ApeTracksAltsCfg.wishlist = ApeTracksAltsCfg.wishlist or {}
    ApeTracksAltsCfg.wishlist[ATA.realm] = ApeTracksAltsCfg.wishlist[ATA.realm] or {}
    ApeTracksAltsCfg.wishlist[ATA.realm][ATA.player] = ApeTracksAltsCfg.wishlist[ATA.realm][ATA.player] or {}
    return ApeTracksAltsCfg.wishlist[ATA.realm][ATA.player]
end

function ATA.HandleWantCmd(args)
    if not ATA.realm then
        print("|cffff4444ApeTracksAlts|r Not yet initialized.")
        return
    end

    local sub = (args or ""):match("^%s*(.-)%s*$")

    -- /ata want list [charname]
    local listTarget = sub:match("^list%s*(.*)$")
    if listTarget ~= nil then
        listTarget = listTarget:match("^%s*(.-)%s*$")
        local realmDB = ApeTracksAltsDB[ATA.realm] or {}
        local wl      = ApeTracksAltsCfg.wishlist and ApeTracksAltsCfg.wishlist[ATA.realm]
        if not wl then
            print("|cff00ff00ApeTracksAlts|r No wishlists found.")
            return
        end

        -- If a character name was given, show just that character
        if listTarget ~= "" then
            -- Case-insensitive match
            local matched = nil
            for charName in pairs(wl) do
                if charName:lower() == listTarget:lower() then matched = charName break end
            end
            if not matched then
                print(string.format("|cff00ff00ApeTracksAlts|r No wishlist found for '%s'.", listTarget))
                return
            end
            local items = wl[matched] or {}
            local count = 0
            for _ in pairs(items) do count = count + 1 end
            local class = realmDB[matched] and realmDB[matched].class
            if count == 0 then
                print(string.format("|cff00ff00ApeTracksAlts|r %s's wishlist is empty.", ATA.ColorName(matched, class)))
            else
                print(string.format("|cff00ff00ApeTracksAlts|r %s's wishlist:", ATA.ColorName(matched, class)))
                for itemID, itemName in pairs(items) do
                    print(string.format("  |cffffff00%s|r (ID: %d)", itemName, itemID))
                end
            end
        else
            -- Show all characters' wishlists
            local anyFound = false
            for charName, items in pairs(wl) do
                local count = 0
                for _ in pairs(items) do count = count + 1 end
                if count > 0 then
                    anyFound = true
                    local class = realmDB[charName] and realmDB[charName].class
                    print(string.format("|cff00ff00ApeTracksAlts|r %s's wishlist:", ATA.ColorName(charName, class)))
                    for itemID, itemName in pairs(items) do
                        print(string.format("  |cffffff00%s|r (ID: %d)", itemName, itemID))
                    end
                end
            end
            if not anyFound then
                print("|cff00ff00ApeTracksAlts|r No wishlists found on this realm.")
            end
        end
        return
    end

    -- /ata want clear all
    if sub == "clear all" then
        ApeTracksAltsCfg.wishlist = ApeTracksAltsCfg.wishlist or {}
        ApeTracksAltsCfg.wishlist[ATA.realm] = ApeTracksAltsCfg.wishlist[ATA.realm] or {}
        ApeTracksAltsCfg.wishlist[ATA.realm][ATA.player] = {}
        print(string.format("|cff00ff00ApeTracksAlts|r %s's wishlist cleared.",
            ATA.ColorName(ATA.player, ATA.GetCharData().class)))
        return
    end

    -- /ata want clear [item link or name]
    local clearTarget = sub:match("^clear%s+(.+)$")
    if clearTarget then
        local wl = EnsureWishlist()
        -- Check if it's an item link first
        local linkID = ATA.GetItemIDFromLink(clearTarget)
        if linkID and wl[linkID] then
            local removedName = wl[linkID]
            wl[linkID] = nil
            print(string.format("|cff00ff00ApeTracksAlts|r Removed |cffffff00%s|r from wishlist.", removedName))
            return
        end
        -- Otherwise search by name
        local removedName = nil
        local clearLower  = clearTarget:lower()
        for itemID, itemName in pairs(wl) do
            if itemName:lower():find(clearLower, 1, true) then
                wl[itemID] = nil
                removedName = itemName
                break
            end
        end
        if removedName then
            print(string.format("|cff00ff00ApeTracksAlts|r Removed |cffffff00%s|r from wishlist.", removedName))
        else
            print(string.format("|cff00ff00ApeTracksAlts|r '%s' not found in wishlist.", clearTarget))
        end
        return
    end

    -- /ata want (no args)
    if sub == "" then
        print("|cff00ff00ApeTracksAlts|r Usage:")
        print("  /ata want [link or name]       — Add item to current character's wishlist")
        print("  /ata want list                 — Show all characters' wishlists")
        print("  /ata want list <name>          — Show specific character's wishlist")
        print("  /ata want clear [link or name] — Remove item from wishlist")
        print("  /ata want clear all            — Clear entire wishlist")
        return
    end

    -- /ata want [item link or name] — add to wishlist
    -- Try item link first
    local itemID  = ATA.GetItemIDFromLink(sub)
    local itemName

    if itemID then
        -- Direct link — add immediately
        itemName = GetItemInfo(itemID)
        if not itemName then
            print("|cff00ff00ApeTracksAlts|r Item not found in cache. Try hovering the item first.")
            return
        end
        local wl = EnsureWishlist()
        wl[itemID] = itemName
        print(string.format("|cff00ff00ApeTracksAlts|r Added |cffffff00%s|r to %s's wishlist.",
            itemName, ATA.ColorName(ATA.player, ATA.GetCharData().class)))
    else
        -- Name search — find all matches first, then add only if exactly one match
        local queryLower = sub:lower()
        local realmDB    = ApeTracksAltsDB[ATA.realm] or {}
        local matches    = {}
        local seen       = {}
        for _, data in pairs(realmDB) do
            for id in pairs(data.items or {}) do
                if not seen[id] then
                    local name = GetItemInfo(id)
                    if name and name:lower():find(queryLower, 1, true) then
                        table.insert(matches, { id = id, name = name })
                        seen[id] = true
                    end
                end
            end
        end

        if #matches == 0 then
            print(string.format("|cff00ff00ApeTracksAlts|r No items matching '%s' found. Try shift-clicking the item link.", sub))
        elseif #matches == 1 then
            local wl = EnsureWishlist()
            wl[matches[1].id] = matches[1].name
            print(string.format("|cff00ff00ApeTracksAlts|r Added |cffffff00%s|r to %s's wishlist.",
                matches[1].name, ATA.ColorName(ATA.player, ATA.GetCharData().class)))
        else
            -- Multiple matches — show clickable links so player can shift-click to add
            print(string.format("|cff00ff00ApeTracksAlts|r Found %d items matching '|cffffff00%s|r' — shift-click a link to add it:", #matches, sub))
            for _, m in ipairs(matches) do
                local link = GetItemLink(m.id) or ("|cffffff00" .. m.name .. "|r")
                print(string.format("  %s (ID: %d)", link, m.id))
            end
        end
    end
end

print("|cff00ff00ApeTracksAlts|r Wishlist.lua loaded")