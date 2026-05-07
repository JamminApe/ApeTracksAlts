-- ApeTracksAlts | Core.lua
-- Shared DB, utilities, scanning logic, events, and slash commands.
-- All other modules read from ApeTracksAltsDB and call functions exposed here.

print("|cff00ff00ApeTracksAlts v4.0 loaded|r")

-------------------------------------------------------------------------------
-- Saved variable & runtime state
-------------------------------------------------------------------------------

ApeTracksAltsDB = ApeTracksAltsDB or {}

ApeTracksAlts    = ApeTracksAlts or {}   -- global namespace shared by all modules
local ATA        = ApeTracksAlts
ATA.realm        = nil
ATA.player       = nil

-- Bank container IDs: -1 = main bank window, 5-11 = equipped bank bag slots
local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10, 11 }

-- How many days before a character's data is considered stale
local STALE_DAYS = 7

-------------------------------------------------------------------------------
-- DB helpers
-------------------------------------------------------------------------------

function ATA.EnsureDB()
    ApeTracksAltsDB[ATA.realm]             = ApeTracksAltsDB[ATA.realm] or {}
    ApeTracksAltsDB[ATA.realm][ATA.player] = ApeTracksAltsDB[ATA.realm][ATA.player] or {
        class        = select(2, UnitClass("player")),
        race         = UnitRace("player"),
        level        = UnitLevel("player"),
        gold         = 0,
        ilvl         = 0,
        honor        = 0,
        arena        = 0,
        runes        = 0,
        lastSeen     = 0,
        items        = {},
        lockouts     = {},
        professions  = {},
        recipes      = {},
    }
    local d = ApeTracksAltsDB[ATA.realm][ATA.player]
    if d.ilvl       == nil then d.ilvl       = 0  end
    if d.honor      == nil then d.honor      = 0  end
    if d.arena      == nil then d.arena      = 0  end
    if d.runes      == nil then d.runes      = 0  end
    if d.race       == nil then d.race       = UnitRace("player") end
    if d.lockouts   == nil then d.lockouts   = {}  end
    if d.professions== nil then d.professions= {}  end
    if d.recipes    == nil then d.recipes    = {}  end
end

function ATA.GetCharData()
    return ApeTracksAltsDB[ATA.realm][ATA.player]
end

-- Returns (or creates) the item entry for a given itemID on the current character.
function ATA.EnsureItem(charData, itemID)
    local entry = charData.items[itemID]
    if not entry then
        entry = { inv = 0, bnk = 0, mb = 0 }
        charData.items[itemID] = entry
    end
    return entry
end

-- Parses an itemID integer from a WoW item hyperlink.
function ATA.GetItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Returns a class-colored version of the given name string.
function ATA.ColorName(name, class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return name end
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

-- Returns true if the given character data is considered stale (not seen recently).
function ATA.IsStale(charData)
    if not charData.lastSeen or charData.lastSeen == 0 then return false end
    local days = (ApeTracksAltsCfg and ApeTracksAltsCfg.stale and ApeTracksAltsCfg.stale.days) or STALE_DAYS
    local daysSince = (time() - charData.lastSeen) / 86400
    return daysSince >= days
end

-- Formats a copper value into a "Xg Ys Zc" colored string.
function ATA.FormatGold(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. string.format("|cffd7a642%dg|r ", g) end
    if s > 0 then out = out .. string.format("|cffc0c0c0%ds|r ", s) end
    out = out .. string.format("|cffb87333%dc|r", c)
    return out
end

-- Removes items with a zero total across all locations for the current character.
-- Called on login to keep the DB lean.
local function PruneItems()
    local charData = ATA.GetCharData()
    local pruned = 0
    for itemID, data in pairs(charData.items) do
        if (data.inv + data.bnk + data.mb) == 0 then
            charData.items[itemID] = nil
            pruned = pruned + 1
        end
    end
end

-- Scans and stores all tracked currencies for the current character.
-- Honor and arena use dedicated API calls. Rune of Ascension is found
-- by scanning the currency list and matching by name (Ascension custom ID).
local function ScanCurrencies()
    local charData = ATA.GetCharData()

    -- Gold is handled by PLAYER_MONEY — skip here

    -- Honor: GetHonorCurrency() returns current honor points
    charData.honor = GetHonorCurrency() or 0

    -- Arena points: GetArenaCurrency() returns current arena points
    charData.arena = GetArenaCurrency() or 0

    -- Rune of Ascension: scan currency list by name match
    charData.runes = 0
    local numCurrencies = GetCurrencyListSize()
    for i = 1, numCurrencies do
        local name, isHeader, _, _, _, count = GetCurrencyListInfo(i)
        if not isHeader and name then
            local lower = name:lower()
            if lower:find("rune of ascension") or lower:find("runes of ascension") then
                charData.runes = count or 0
                break
            end
        end
    end

    -- Average equipped item level from character sheet
    -- GetAverageItemLevel returns: overall, equipped
    -- On Ascension the equipped value matches the character sheet
    local ilvl = 0
    if GetAverageItemLevel then
        local overall, equipped = GetAverageItemLevel()
        -- Use whichever is non-zero and smaller (equipped is usually lower)
        local v1 = tonumber(overall) or 0
        local v2 = tonumber(equipped) or 0
        -- Pick the one that matches character sheet (non-zero, take the decimal)
        if v2 > 0 then
            ilvl = v2
        elseif v1 > 0 then
            ilvl = v1
        end
    end
    -- Store with one decimal place so 34.13 shows as 34.1
    charData.ilvl = math.floor((ilvl * 10) + 0.5) / 10
end

-- Called by any module that wants to react to data changes (e.g. Panel refresh).
-- Modules assign a function to ATA.OnDataChanged to hook in.
function ATA.NotifyDataChanged()
    if ATA.OnDataChanged then ATA.OnDataChanged() end
end

-------------------------------------------------------------------------------
-- Scanning
-------------------------------------------------------------------------------

local function ScanBags()
    ATA.EnsureDB()
    local charData = ATA.GetCharData()
    for _, data in pairs(charData.items) do data.inv = 0 end

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
            local itemID = ATA.GetItemIDFromLink(link)
            if itemID then
                local entry = ATA.EnsureItem(charData, itemID)
                entry.inv = entry.inv + (count or 1)
            end
        end
    end
end

local function ScanBank()
    ATA.EnsureDB()
    local charData = ATA.GetCharData()
    for _, data in pairs(charData.items) do data.bnk = 0 end

    for _, bag in ipairs(BANK_BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
            local itemID = ATA.GetItemIDFromLink(link)
            if itemID then
                local entry = ATA.EnsureItem(charData, itemID)
                entry.bnk = entry.bnk + (count or 1)
            end
        end
    end
end

local function ScanMail()
    ATA.EnsureDB()
    local charData = ATA.GetCharData()
    for _, data in pairs(charData.items) do data.mb = 0 end

    -- On 3.3.5 the signature is: name, itemTexture, count, quality, canUse
    -- count is the 3rd return value. quality is bugged to return -1 since 2.3.3
    -- so select(4,...) was grabbing -1 per item — hence the negative totals.
    -- We also use GetInboxHeaderInfo to skip mails with no attachments entirely.
    local numMail = GetInboxNumItems()
    for i = 1, numMail do
        local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem and hasItem > 0 then
            for j = 1, 16 do
                local name, _, count = GetInboxItem(i, j)
                if name then
                    local link   = GetInboxItemLink(i, j)
                    local itemID = ATA.GetItemIDFromLink(link)
                    if itemID then
                        -- count of 0 means the attachment was already taken
                        local qty = (count and count > 0) and count or 0
                        if qty > 0 then
                            local entry = ATA.EnsureItem(charData, itemID)
                            entry.mb = entry.mb + qty
                        end
                    end
                end
            end
        end
    end
end

-- Profession icon texture mapping
ATA.ProfessionIcons = {
    ["Alchemy"]        = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]  = "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]     = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]    = "Interface\\Icons\\Trade_Engineering",
    ["Herbalism"]      = "Interface\\Icons\\Spell_Nature_Naturetouchgrow",
    ["Inscription"]    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["Jewelcrafting"]  = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"] = "Interface\\Icons\\Trade_Leatherworking",
    ["Mining"]         = "Interface\\Icons\\Trade_Mining",
    ["Skinning"]       = "Interface\\Icons\\INV_Weapon_ShortBlade_01",
    ["Tailoring"]      = "Interface\\Icons\\Trade_Tailoring",
}

local function ScanLockouts()
    if not ATA.realm then return end
    local charData = ATA.GetCharData()
    charData.lockouts = {}
    local numInstances = GetNumSavedInstances()
    for i = 1, numInstances do
        local name, id, reset, difficulty = GetSavedInstanceInfo(i)
        if name then
            table.insert(charData.lockouts, {
                name       = name,
                id         = id,
                reset      = reset,
                difficulty = difficulty,
                expires    = time() + reset,
            })
        end
    end
    ATA.NotifyDataChanged()
end

local function ScanProfessions()
    if not ATA.realm then return end
    local charData = ATA.GetCharData()
    charData.professions = {}

    -- GetProfessions() is Cataclysm+. In WotLK 3.3.5 we iterate skill lines.
    -- Primary professions have type "Secondary" = false in the skill header.
    local primaryProfs = {
        ["Alchemy"]        = true,
        ["Blacksmithing"]  = true,
        ["Enchanting"]     = true,
        ["Engineering"]    = true,
        ["Herbalism"]      = true,
        ["Inscription"]    = true,
        ["Jewelcrafting"]  = true,
        ["Leatherworking"] = true,
        ["Mining"]         = true,
        ["Skinning"]       = true,
        ["Tailoring"]      = true,
    }

    local numSkillLines = GetNumSkillLines()
    for i = 1, numSkillLines do
        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if skillName and not isHeader and primaryProfs[skillName] then
            local icon = ATA.ProfessionIcons[skillName]
            table.insert(charData.professions, {
                name    = skillName,
                icon    = icon or "",
                rank    = rank    or 0,
                maxRank = maxRank or 0,
            })
        end
    end
    ATA.NotifyDataChanged()
end

-- Scan recipes from an open profession window
local function ScanRecipes()
    if not ATA.realm then return end
    -- Guard: these APIs may not exist on all Ascension builds
    if not GetTradeSkillLine or not GetNumTradeSkills or not GetTradeSkillInfo then return end
    local charData = ATA.GetCharData()
    local profName = GetTradeSkillLine()
    if not profName or profName == "UNKNOWN" then return end
    charData.recipes = charData.recipes or {}
    charData.recipes[profName] = {}
    local lastScanKey = "lastRecipeScan_" .. profName
    charData[lastScanKey] = time()
    local numSkills = GetNumTradeSkills()
    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            charData.recipes[profName][skillName:lower()] = true
        end
    end
    ATA.NotifyDataChanged()
end

-- Expose ScanRecipes for the TRADE_SKILL_SHOW hook
ATA.ScanRecipes = ScanRecipes

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function RegisterSlashCommands()
    SLASH_APETRACKSALTS1 = "/ata"
    SLASH_APETRACKSALTS2 = "/apetracksalts"

    SlashCmdList["APETRACKSALTS"] = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")

        local realmDB = ApeTracksAltsDB[ATA.realm] or {}

        if msg == "show" then
            print("|cff00ff00ApeTracksAlts|r /ata show — PanelShow = " .. tostring(ApeTracksAlts.PanelShow))
            if ApeTracksAlts.PanelShow then
                ApeTracksAlts.PanelShow()
            else
                print("|cffff4444ApeTracksAlts|r Panel.lua did not load correctly — PanelShow is nil")
            end

        elseif msg == "hide" then
            if ApeTracksAlts.PanelHide then ApeTracksAlts.PanelHide() end

        elseif msg == "toggle" then
            if ApeTracksAlts.PanelToggle then ApeTracksAlts.PanelToggle() end

        elseif msg == "panel" then
            -- Debug: print frame state and force it visible at center
            local f = ATAPanel
            if not f then
                print("|cffff4444ApeTracksAlts|r ATAPanel frame does not exist!")
            else
                print(string.format("|cff00ff00ApeTracksAlts|r Panel debug:"))
                print(string.format("  Shown: %s", tostring(f:IsShown())))
                print(string.format("  Visible: %s", tostring(f:IsVisible())))
                print(string.format("  Size: %.0f x %.0f", f:GetWidth(), f:GetHeight()))
                print(string.format("  Alpha: %.2f", f:GetAlpha()))
                local l, t = f:GetLeft(), f:GetTop()
                print(string.format("  Position: left=%.0f top=%.0f", l or -1, t or -1))
                -- Force it to center and show
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                f:SetAlpha(1)
                f:Show()
                if ApeTracksAlts.PanelRefresh then ApeTracksAlts.PanelRefresh() end
                print("  Forced to center and shown.")
            end

        elseif msg == "debug" then
            local charCount, itemCount = 0, 0
            for _, c in pairs(realmDB) do
                charCount = charCount + 1
                for _ in pairs(c.items) do itemCount = itemCount + 1 end
            end
            print(string.format(
                "|cff00ff00ApeTracksAlts|r Debug — Realm: %s | Characters: %d | Unique Items: %d",
                ATA.realm, charCount, itemCount
            ))

        elseif msg == "list" then
            print("|cff00ff00ApeTracksAlts|r — Characters on " .. ATA.realm .. ":")
            for charName, data in pairs(realmDB) do
                local itemCount = 0
                for _ in pairs(data.items) do itemCount = itemCount + 1 end
                local staleTag = ATA.IsStale(data) and " |cffff4444[stale]|r" or ""
                print(string.format("  %s (Lvl %d %s | iLvl %d) — %d items  %s%s",
                    ATA.ColorName(charName, data.class),
                    data.level or 0,
                    data.class or "?",
                    data.ilvl  or 0,
                    itemCount,
                    ATA.FormatGold(data.gold),
                    staleTag
                ))
            end

        elseif msg == "gold" then
            local total = 0
            print("|cff00ff00ApeTracksAlts|r — Gold on " .. ATA.realm .. ":")
            for charName, data in pairs(realmDB) do
                local staleTag = ATA.IsStale(data) and " |cffff4444[stale]|r" or ""
                print(string.format("  %s: %s%s",
                    ATA.ColorName(charName, data.class),
                    ATA.FormatGold(data.gold),
                    staleTag
                ))
                total = total + (data.gold or 0)
            end
            print("  |cffffff00Account Total: " .. ATA.FormatGold(total) .. "|r")

        elseif msg:sub(1, 5) == "purge" then
            local target = msg:sub(7):match("^%s*(.-)%s*$")
            if target == "" then
                print("|cff00ff00ApeTracksAlts|r Usage: /ata purge CharacterName")
            else
                local realmDB = ApeTracksAltsDB[ATA.realm] or {}
                local matched = nil
                for charName in pairs(realmDB) do
                    if charName:lower() == target:lower() then
                        matched = charName
                        break
                    end
                end
                if not matched then
                    print(string.format("|cff00ff00ApeTracksAlts|r No character named '%s' found on %s.", target, ATA.realm))
                elseif matched == ATA.player then
                    print("|cff00ff00ApeTracksAlts|r You cannot purge the currently logged-in character.")
                else
                    ApeTracksAltsDB[ATA.realm][matched] = nil
                    print(string.format("|cff00ff00ApeTracksAlts|r Purged |cffffffff%s|r from the database.", matched))
                    ATA.NotifyDataChanged()
                end
            end

        elseif msg:sub(1, 4) == "find" then
            local query = msg:sub(6):match("^%s*(.-)%s*$")
            if query == "" then
                print("|cff00ff00ApeTracksAlts|r Usage: /ata find <item name>")
            else
                local realmDB = ApeTracksAltsDB[ATA.realm] or {}
                local results = {}
                local queryLower = query:lower()
                -- Collect all unique itemIDs that match the query
                local matchedIDs = {}
                for _, data in pairs(realmDB) do
                    for itemID, counts in pairs(data.items or {}) do
                        if not matchedIDs[itemID] then
                            local name = GetItemInfo(itemID)
                            if name and name:lower():find(queryLower, 1, true) then
                                matchedIDs[itemID] = name
                            end
                        end
                    end
                end
                -- For each matched item, find who has it
                local found = false
                for itemID, itemName in pairs(matchedIDs) do
                    found = true
                    print(string.format("|cff00ff00ApeTracksAlts|r |cffffff00%s|r (ID: %d)", itemName, itemID))
                    for charName, data in pairs(realmDB) do
                        local item = data.items and data.items[itemID]
                        if item then
                            local total = item.inv + item.bnk + item.mb
                            if total > 0 then
                                local parts = {}
                                if item.inv > 0 then parts[#parts+1] = "Bags: "..item.inv end
                                if item.bnk > 0 then parts[#parts+1] = "Bank: "..item.bnk end
                                if item.mb  > 0 then parts[#parts+1] = "Mail: "..item.mb  end
                                print(string.format("  %s — %s (Total: %d)",
                                    ATA.ColorName(charName, data.class),
                                    table.concat(parts, "  "),
                                    total))
                            end
                        end
                    end
                end
                if not found then
                    print(string.format("|cff00ff00ApeTracksAlts|r No items matching '%s' found.", query))
                end
            end

        elseif msg:sub(1, 6) == "ignore" then
            local target = msg:sub(8):match("^%s*(.-)%s*$")
            if target == "" then
                -- List currently ignored characters with class colors
                local ignored = ApeTracksAltsCfg.ignore or {}
                local list = {}
                local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
                for name in pairs(ignored) do
                    local class = realmDB2[name] and realmDB2[name].class
                    table.insert(list, ATA.ColorName(name, class))
                end
                if #list == 0 then
                    print("|cff00ff00ApeTracksAlts|r No characters are being ignored.")
                else
                    print("|cff00ff00ApeTracksAlts|r Ignored characters: " .. table.concat(list, ", "))
                end
            else
                if target == ATA.player:lower() then
                    print("|cff00ff00ApeTracksAlts|r You cannot ignore the currently logged-in character.")
                else
                    ApeTracksAltsCfg.ignore = ApeTracksAltsCfg.ignore or {}
                    -- Case-insensitive match
                    local realmDB = ApeTracksAltsDB[ATA.realm] or {}
                    local matched = nil
                    for charName in pairs(realmDB) do
                        if charName:lower() == target then matched = charName break end
                    end
                    local name = matched or target
                    ApeTracksAltsCfg.ignore[name] = true
                    local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
                    local class = realmDB2[name] and realmDB2[name].class
                    print(string.format("|cff00ff00ApeTracksAlts|r %s is now ignored in tooltips.", ATA.ColorName(name, class)))
                    ATA.NotifyDataChanged()
                end
            end

        elseif msg:sub(1, 8) == "unignore" then
            local target = msg:sub(10):match("^%s*(.-)%s*$")
            if target == "" then
                print("|cff00ff00ApeTracksAlts|r Usage: /ata unignore <name>")
            else
                ApeTracksAltsCfg.ignore = ApeTracksAltsCfg.ignore or {}
                local realmDB = ApeTracksAltsDB[ATA.realm] or {}
                local matched = nil
                for charName in pairs(realmDB) do
                    if charName:lower() == target then matched = charName break end
                end
                -- Also try direct match in ignore list
                if not matched then
                    for name in pairs(ApeTracksAltsCfg.ignore) do
                        if name:lower() == target then matched = name break end
                    end
                end
                if matched then
                    ApeTracksAltsCfg.ignore[matched] = nil
                    local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
                    local class = realmDB2[matched] and realmDB2[matched].class
                    print(string.format("|cff00ff00ApeTracksAlts|r %s removed from ignore list.", ATA.ColorName(matched, class)))
                    ATA.NotifyDataChanged()
                else
                    print(string.format("|cff00ff00ApeTracksAlts|r '%s' not found in ignore list.", target))
                end
            end

        elseif msg:sub(1, 6) == "toggle" then
            local what = msg:sub(8):match("^%s*(.-)%s*$")
            -- Ensure tooltip table exists
            ApeTracksAltsCfg.tooltip = ApeTracksAltsCfg.tooltip or { showBags=true, showBank=true, showMail=true }
            local ttCfg = ApeTracksAltsCfg.tooltip
            if what == "bags" then
                ttCfg.showBags = not (ttCfg.showBags ~= false)
                print("|cff00ff00ApeTracksAlts|r Bags in tooltip: " .. (ttCfg.showBags and "|cff00ff00on|r" or "|cffff4444off|r"))
            elseif what == "bank" then
                ttCfg.showBank = not (ttCfg.showBank ~= false)
                print("|cff00ff00ApeTracksAlts|r Bank in tooltip: " .. (ttCfg.showBank and "|cff00ff00on|r" or "|cffff4444off|r"))
            elseif what == "mail" then
                ttCfg.showMail = not (ttCfg.showMail ~= false)
                print("|cff00ff00ApeTracksAlts|r Mail in tooltip: " .. (ttCfg.showMail and "|cff00ff00on|r" or "|cffff4444off|r"))
            elseif what == "login" then
                ApeTracksAltsCfg.loginOpen = not (ApeTracksAltsCfg.loginOpen ~= false)
                print("|cff00ff00ApeTracksAlts|r Panel on login: " .. (ApeTracksAltsCfg.loginOpen and "|cff00ff00on|r" or "|cffff4444off|r"))
            else
                if ApeTracksAlts.PanelToggle then ApeTracksAlts.PanelToggle() end
            end

        elseif msg:sub(1, 3) == "set" then
            local args = msg:sub(5):match("^%s*(.-)%s*$")
            local key, val = args:match("^(%S+)%s+(.+)$")
            if key == "stale" then
                local days = tonumber(val)
                if days and days >= 0 then
                    ApeTracksAltsCfg.stale = ApeTracksAltsCfg.stale or {}
                    ApeTracksAltsCfg.stale.days = days
                    print(string.format("|cff00ff00ApeTracksAlts|r Stale threshold set to %d days.", days))
                else
                    print("|cff00ff00ApeTracksAlts|r Usage: /ata set stale <days>")
                end
            elseif key == "profstale" then
                local days = tonumber(val)
                if days and days >= 7 then
                    ApeTracksAltsCfg.stale = ApeTracksAltsCfg.stale or {}
                    ApeTracksAltsCfg.stale.profDays = days
                    print(string.format("|cff00ff00ApeTracksAlts|r Profession stale threshold set to %d days.", days))
                elseif days and days < 7 then
                    print("|cff00ff00ApeTracksAlts|r Profession stale minimum is 7 days.")
                else
                    print("|cff00ff00ApeTracksAlts|r Usage: /ata set profstale <days> (minimum 7)")
                end
            else
                print("|cff00ff00ApeTracksAlts|r Unknown setting. Available: stale, profstale")
            end

        elseif msg == "config" then
            ApeTracksAltsCfg.tooltip = ApeTracksAltsCfg.tooltip or { showBags=true, showBank=true, showMail=true }
            ApeTracksAltsCfg.stale   = ApeTracksAltsCfg.stale   or { days=7 }
            local ttCfg    = ApeTracksAltsCfg.tooltip
            local ignored  = ApeTracksAltsCfg.ignore or {}
            local ignoreList = {}
            for charName, _ in pairs(ignored) do
                local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
                local class = realmDB2[charName] and realmDB2[charName].class
                table.insert(ignoreList, ATA.ColorName(charName, class))
            end
            local function onoff(v) return (v ~= false) and "|cff00ff00on|r" or "|cffff4444off|r" end
            print("|cff00ff00ApeTracksAlts|r Current Settings:")
            print(string.format("  Stale threshold  : %d days  (/ata set stale <days>)", ApeTracksAltsCfg.stale.days or 7))
            print(string.format("  Prof stale       : %d days  (/ata set profstale <days>)", ApeTracksAltsCfg.stale.profDays or 30))
            print(string.format("  Panel on login   : %s  (/ata toggle login)", onoff(ApeTracksAltsCfg.loginOpen)))
            print(string.format("  Tooltip bags     : %s  (/ata toggle bags)",  onoff(ttCfg.showBags)))
            print(string.format("  Tooltip bank     : %s  (/ata toggle bank)",  onoff(ttCfg.showBank)))
            print(string.format("  Tooltip mail     : %s  (/ata toggle mail)",  onoff(ttCfg.showMail)))
            print(string.format("  Ignored chars    : %s", #ignoreList > 0 and table.concat(ignoreList, ", ") or "none"))

        elseif msg == "reset" then
            ApeTracksAltsDB = {}
            ATA.EnsureDB()
            local charData = ATA.GetCharData()
            charData.lastSeen = time()
            charData.level    = UnitLevel("player")
            charData.gold     = GetMoney()
            ScanBags()
            print("|cff00ff00ApeTracksAlts|r Database reset. Current character re-seeded.")

        elseif msg:sub(1, 4) == "want" then
            local args = msg:sub(5):match("^%s*(.-)%s*$") or ""
            if ATA.HandleWantCmd then
                ATA.HandleWantCmd(args)
            else
                print("|cffff4444ApeTracksAlts|r Wishlist module not loaded.")
            end

        elseif msg == "locks" then
            local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
            print("|cff00ff00ApeTracksAlts|r — Lockouts on " .. ATA.realm .. ":")
            for charName, data in pairs(realmDB2) do
                local locks = data.lockouts or {}
                if #locks > 0 then
                    print(string.format("  %s:", ATA.ColorName(charName, data.class)))
                    for _, lock in ipairs(locks) do
                        local remaining = lock.expires - time()
                        local hours = math.floor(remaining / 3600)
                        local mins  = math.floor((remaining % 3600) / 60)
                        print(string.format("    %s — resets in %dh %dm", lock.name, hours, mins))
                    end
                else
                    print(string.format("  %s: |cff888888no lockouts|r", ATA.ColorName(charName, data.class)))
                end
            end

        elseif msg == "prof" then
            local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
            print("|cff00ff00ApeTracksAlts|r — Professions on " .. ATA.realm .. ":")
            for charName, data in pairs(realmDB2) do
                local profs = data.professions or {}
                if #profs > 0 then
                    local parts = {}
                    for _, p in ipairs(profs) do
                        parts[#parts+1] = string.format("%s %d/%d", p.name, p.rank, p.maxRank)
                    end
                    print(string.format("  %s: %s", ATA.ColorName(charName, data.class), table.concat(parts, "  |cff888888·|r  ")))
                else
                    print(string.format("  %s: |cff888888not scanned yet — open profession book|r", ATA.ColorName(charName, data.class)))
                end
            end

        elseif msg:sub(1, 6) == "recipe" then
            local query = msg:sub(8):match("^%s*(.-)%s*$")
            if query == "" then
                print("|cff00ff00ApeTracksAlts|r Usage: /ata recipe <recipe name>")
            else
                local realmDB2 = ApeTracksAltsDB[ATA.realm] or {}
                local queryLower = query:lower()
                local found = false
                print(string.format("|cff00ff00ApeTracksAlts|r Recipes matching '|cffffff00%s|r':", query))
                for charName, data in pairs(realmDB2) do
                    local recipes = data.recipes or {}
                    for profName, profRecipes in pairs(recipes) do
                        for recipeName in pairs(profRecipes) do
                            if recipeName:find(queryLower, 1, true) then
                                local display = recipeName:gsub("^%l", string.upper)
                                print(string.format("  %s |cff888888(%s)|r — |cffffff00%s|r",
                                    ATA.ColorName(charName, data.class), profName, display))
                                found = true
                            end
                        end
                    end
                end
                if not found then
                    print(string.format("|cff00ff00ApeTracksAlts|r No recipe matching '%s' found.", query))
                end
            end

        elseif msg == "minimap" then
            if ATA.MinimapShow and ATA.MinimapHide then
                local btn = ATAMinimapButton
                if btn and btn:IsShown() then
                    ATA.MinimapHide()
                    print("|cff00ff00ApeTracksAlts|r Minimap button hidden. /ata minimap to restore.")
                else
                    ATA.MinimapShow()
                    print("|cff00ff00ApeTracksAlts|r Minimap button shown.")
                end
            else
                print("|cffff4444ApeTracksAlts|r Minimap module not loaded.")
            end

        else
            print("|cff00ff00ApeTracksAlts|r Commands:")
            print("  |cffffff00Panel:|r")
            print("    /ata show                — Open the character panel")
            print("    /ata hide                — Close the character panel")
            print("    /ata toggle              — Toggle the character panel")
            print("    /ata minimap             — Toggle the minimap button")
            print("  |cffffff00Database:|r")
            print("    /ata list                — All tracked characters")
            print("    /ata gold                — Gold summary across all alts")
            print("    /ata find <item>         — Search for an item across all alts")
            print("    /ata locks               — Show raid/dungeon lockouts for all alts")
            print("    /ata prof                — Show professions for all alts")
            print("    /ata recipe <name>       — Search learned recipes across all alts")
            print("    /ata purge <name>        — Remove a character from the database")
            print("    /ata reset               — Wipe the entire database")
            print("  |cffffff00Wishlist:|r")
            print("    /ata want [link or name] — Add item to current character's wishlist")
            print("    /ata want list           — Show current character's wishlist")
            print("    /ata want clear <item>   — Remove item from wishlist")
            print("    /ata want clear all      — Clear entire wishlist")
            print("  |cffffff00Settings:|r")
            print("    /ata config              — Show all current settings")
            print("    /ata set stale <days>    — Set stale threshold (default: 7)")
            print("    /ata set profstale <days>— Set profession stale threshold (default: 30)")
            print("    /ata toggle login        — Toggle panel auto-open on login")
            print("    /ata toggle bags         — Toggle bags in tooltips")
            print("    /ata toggle bank         — Toggle bank in tooltips")
            print("    /ata toggle mail         — Toggle mail in tooltips")
            print("    /ata ignore <name>       — Hide a character from tooltips")
            print("    /ata ignore              — List ignored characters")
            print("    /ata unignore <name>     — Remove from ignore list")
            print("  |cffffff00Other:|r")
            print("    /ata debug               — DB stats")
        end
    end
end

-------------------------------------------------------------------------------
-- Event frame
-------------------------------------------------------------------------------

-- Track whether the bank frame is currently open so BAG_UPDATE can
-- trigger a bank rescan while the player is actively moving items.
local bankIsOpen = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UPDATE_INSTANCE_INFO")
frame:RegisterEvent("TRADE_SKILL_SHOW")

-- Debounced bank scan: restarts on every slot change so the scan always
-- fires 0.3s after the last deposit/withdrawal, not just on open.
local bankScanTimer = nil
local function ScheduleBankScan()
    if bankScanTimer then
        bankScanTimer:Cancel()
        bankScanTimer = nil
    end
    bankScanTimer = C_Timer.NewTimer(0.3, function()
        bankScanTimer = nil
        if ATA.realm then ScanBank() end
    end)
end

-- Debounced mail scan: restarts the timer on every new event so the scan
-- always fires 0.5s after the LAST update, not the first one.
local mailScanTimer = nil
local function ScheduleMailScan()
    if mailScanTimer then
        mailScanTimer:Cancel()
        mailScanTimer = nil
    end
    mailScanTimer = C_Timer.NewTimer(0.5, function()
        mailScanTimer = nil
        if ATA.realm then ScanMail() end
    end)
end

-- Zero out all mb counts for the current character.
-- Called when the mailbox closes so stale mail counts don't linger.
local function ClearMailCounts()
    if not ATA.realm then return end
    local charData = ATA.GetCharData()
    for _, data in pairs(charData.items) do
        data.mb = 0
    end
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ATA.realm  = GetRealmName()
        ATA.player = UnitName("player")

        ATA.EnsureDB()

        local charData = ATA.GetCharData()
        charData.lastSeen = time()
        charData.level    = UnitLevel("player")
        charData.gold     = GetMoney()

        -- Delay currency/ilvl scan slightly so character data is fully loaded
        C_Timer.After(2, function()
            if ATA.realm then
                ScanCurrencies()
                ScanLockouts()
                ScanProfessions()
                ATA.NotifyDataChanged()
            end
        end)

        PruneItems()
        ScanBags()
        RegisterSlashCommands()

        if ApeTracksAlts.OnCoreReady then ApeTracksAlts.OnCoreReady() end

    elseif event == "BAG_UPDATE" then
        if ATA.realm then
            ScanBags()
            if bankIsOpen then ScanBank() end
            ATA.NotifyDataChanged()
        end

    elseif event == "BANKFRAME_OPENED" then
        bankIsOpen = true
        if ATA.realm then ScanBank() end

    elseif event == "BANKFRAME_CLOSED" then
        bankIsOpen = false

    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if ATA.realm then ScheduleBankScan() end

    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        if ATA.realm then ScheduleMailScan() end

    elseif event == "MAIL_CLOSED" then
        -- Cancel any pending scan but keep mb counts intact.
        -- Mail data remains valid until the next time the mailbox is opened.
        if mailScanTimer then
            mailScanTimer:Cancel()
            mailScanTimer = nil
        end

    elseif event == "PLAYER_MONEY" then
        if ATA.realm then
            ATA.GetCharData().gold = GetMoney()
            ATA.NotifyDataChanged()
        end

    elseif event == "PLAYER_LEVEL_UP" then
        if ATA.realm then
            ATA.GetCharData().level = UnitLevel("player")
            ATA.NotifyDataChanged()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if ATA.realm then
            C_Timer.After(0.5, function()
                if not ATA.realm then return end
                local ilvl = 0
                if GetAverageItemLevel then
                    local overall, equipped = GetAverageItemLevel()
                    local v1 = tonumber(overall) or 0
                    local v2 = tonumber(equipped) or 0
                    ilvl = v2 > 0 and v2 or v1
                end
                ATA.GetCharData().ilvl = math.floor((ilvl * 10) + 0.5) / 10
                ATA.NotifyDataChanged()
            end)
        end

    elseif event == "UPDATE_INSTANCE_INFO" then
        if ATA.realm then
            ScanCurrencies()
            ScanLockouts()
            ATA.NotifyDataChanged()
        end

    elseif event == "TRADE_SKILL_SHOW" then
        if ATA.realm then
            -- Small delay so the tradeskill window is fully populated
            C_Timer.After(0.5, function()
                if ATA.realm then ScanRecipes() end
            end)
        end
    end
end)

print("|cff00ff00ApeTracksAlts|r Core.lua fully loaded")
