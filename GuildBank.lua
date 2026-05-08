-- ApeTracksAlts | GuildBank.lua
-- Tracks items in manually registered guild banks.
--
-- DESIGN INTENT (important — document in README):
--   Registration is per-character. Each character only sees guild bank data
--   from guilds THEY personally registered via /ata guild add.
--   Scan data is stored globally (one scan updates for all) but display
--   is filtered per-character. This allows Shadowyforce to see both his
--   raiding guild bank AND personal bank, while alts only see the personal bank.
--
-- NOTE on tab loading: WoW only loads guild bank tab data when you physically
--   click each tab. The scan captures whatever tabs have been loaded so far.
--   Subsequent opens will have all tabs cached from previous visits.

local ATA = ApeTracksAlts

local function EnsureGuildDB(guildName)
    ApeTracksAltsDB.guildBanks = ApeTracksAltsDB.guildBanks or {}
    ApeTracksAltsDB.guildBanks[ATA.realm] = ApeTracksAltsDB.guildBanks[ATA.realm] or {}
    ApeTracksAltsDB.guildBanks[ATA.realm][guildName] = ApeTracksAltsDB.guildBanks[ATA.realm][guildName] or {}
    return ApeTracksAltsDB.guildBanks[ATA.realm][guildName]
end

local function EnsureCharGuilds()
    local g = ApeTracksAltsCfg.guild
    if not g then
        ApeTracksAltsCfg.guild = { autoRegister = false, chars = {} }
        g = ApeTracksAltsCfg.guild
    end
    g.chars = g.chars or {}
    g.chars[ATA.realm] = g.chars[ATA.realm] or {}
    g.chars[ATA.realm][ATA.player] = g.chars[ATA.realm][ATA.player] or {}
    return g.chars[ATA.realm][ATA.player]
end

local function IsRegisteredForChar(guildName, charName)
    charName = charName or ATA.player
    local g = ApeTracksAltsCfg.guild
    if not g or not g.chars then return false end
    if not g.chars[ATA.realm] then return false end
    if not g.chars[ATA.realm][charName] then return false end
    return g.chars[ATA.realm][charName][guildName] == true
end

local function GetCurrentGuild()
    return GetGuildInfo("player")
end

-- Scans whatever guild bank tab data is currently loaded in the client.
-- WoW only provides data for tabs that have been physically clicked/viewed.
local function ScanGuildBank()
    if not ATA.realm then return false end
    local guildName = GetCurrentGuild()
    if not guildName then return false end
    if not IsRegisteredForChar(guildName) then return false end

    local db = EnsureGuildDB(guildName)
    -- Do NOT clear existing data before scanning.
    -- WoW only loads tab data when physically clicked, so we accumulate
    -- results across multiple bank opens rather than wiping on each scan.
    -- This means previously seen tabs persist even if not re-clicked.
    local prevTotal = 0
    for _ in pairs(db) do prevTotal = prevTotal + 1 end

    local newItems = 0
    local numTabs = GetNumGuildBankTabs()
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then
            for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
                local link = GetGuildBankItemLink(tab, slot)
                if link then
                    local itemID = ATA.GetItemIDFromLink(link)
                    if itemID then
                        local _, count = GetGuildBankItemInfo(tab, slot)
                        if not db[itemID] then newItems = newItems + 1 end
                        db[itemID] = (count or 1)
                    end
                end
            end
        end
    end

    ATA.NotifyDataChanged()
    return true, guildName, newItems
end

function ATA.GetGuildBankCount(itemID)
    if not ATA.realm or not ATA.player then return {} end
    local myGuilds = ApeTracksAltsCfg.guild and ApeTracksAltsCfg.guild.chars
    if not myGuilds then return {} end
    local realmEntry = myGuilds[ATA.realm]
    if not realmEntry then return {} end
    local playerEntry = realmEntry[ATA.player]
    if not playerEntry then return {} end
    local guildBanks = ApeTracksAltsDB.guildBanks
    if not guildBanks or not guildBanks[ATA.realm] then return {} end
    local results = {}
    for guildName in pairs(playerEntry) do
        local db = guildBanks[ATA.realm][guildName]
        if db and db[itemID] and db[itemID] > 0 then
            table.insert(results, { guild = guildName, count = db[itemID] })
        end
    end
    return results
end

function ATA.MigrateGuildConfig()
    local g = ApeTracksAltsCfg and ApeTracksAltsCfg.guild
    if not g or not g.banks then return end
    if not ATA.realm or not ATA.player then return end
    g.chars = g.chars or {}
    for realmName, realmBanks in pairs(g.banks) do
        if type(realmBanks) == "table" then
            g.chars[realmName] = g.chars[realmName] or {}
            g.chars[realmName][ATA.player] = g.chars[realmName][ATA.player] or {}
            for guildName, val in pairs(realmBanks) do
                if val == true then
                    g.chars[realmName][ATA.player][guildName] = true
                end
            end
        end
    end
    g.banks = nil
    print("|cff00ff00ApeTracksAlts|r Guild bank config migrated to per-character format.")
end

function ATA.HandleGuildCmd(args)
    if not ATA.realm then
        print("|cffff4444ApeTracksAlts|r Not yet initialized.")
        return
    end

    local sub = (args or ""):match("^%s*(.-)%s*$")
    ApeTracksAltsCfg.guild = ApeTracksAltsCfg.guild or { autoRegister = false, chars = {} }
    local guildCfg = ApeTracksAltsCfg.guild
    local myGuilds = EnsureCharGuilds()

    if sub == "add" then
        local guildName = GetCurrentGuild()
        if not guildName then print("|cff00ff00ApeTracksAlts|r You are not in a guild.") return end
        if IsRegisteredForChar(guildName) then
            print(string.format("|cff00ff00ApeTracksAlts|r |cff00cccc%s|r already registered for %s.",
                guildName, ATA.ColorName(ATA.player, ATA.GetCharData().class)))
            return
        end
        myGuilds[guildName] = true
        print(string.format("|cff00ff00ApeTracksAlts|r %s registered |cff00cccc%s|r. Open the guild bank to scan.",
            ATA.ColorName(ATA.player, ATA.GetCharData().class), guildName))

    elseif sub == "remove" then
        local guildName = GetCurrentGuild()
        if not guildName then print("|cff00ff00ApeTracksAlts|r You are not in a guild.") return end
        if not IsRegisteredForChar(guildName) then
            print(string.format("|cff00ff00ApeTracksAlts|r |cff00cccc%s|r not registered for %s.",
                guildName, ATA.ColorName(ATA.player, ATA.GetCharData().class)))
            return
        end
        myGuilds[guildName] = nil
        print(string.format("|cff00ff00ApeTracksAlts|r %s unregistered |cff00cccc%s|r.",
            ATA.ColorName(ATA.player, ATA.GetCharData().class), guildName))
        ATA.NotifyDataChanged()

    elseif sub == "scan" then
        if not ATAGuildBankOpen then
            print("|cff00ff00ApeTracksAlts|r Open the guild bank window first.")
            return
        end
        local guildName = GetCurrentGuild()
        if not IsRegisteredForChar(guildName) then
            print("|cff00ff00ApeTracksAlts|r This guild is not registered. Run /ata guild add first.")
            return
        end
        local ok, name = ScanGuildBank()
        if ok then
            local total = 0
            local db = ApeTracksAltsDB.guildBanks[ATA.realm][name] or {}
            for _ in pairs(db) do total = total + 1 end
            print(string.format("|cff00ff00ApeTracksAlts|r Scanned |cff00cccc%s|r — %d unique items.", name, total))
        end

    elseif sub == "list" then
        print(string.format("|cff00ff00ApeTracksAlts|r Guild banks for %s:",
            ATA.ColorName(ATA.player, ATA.GetCharData().class)))
        local any = false
        for guildName in pairs(myGuilds) do
            local db = ApeTracksAltsDB.guildBanks and
                       ApeTracksAltsDB.guildBanks[ATA.realm] and
                       ApeTracksAltsDB.guildBanks[ATA.realm][guildName] or {}
            local total = 0
            for _ in pairs(db) do total = total + 1 end
            local scanned = total > 0
                and ("|cff00ff00"..total.." items scanned|r")
                or  "|cffff4444not yet scanned — open guild bank|r"
            print(string.format("  |cff00cccc%s|r — %s", guildName, scanned))
            any = true
        end
        if not any then
            print("  |cff888888None. Run /ata guild add while at your guild bank.|r")
        end
        print(string.format("  Auto-register: %s", guildCfg.autoRegister and "|cff00ff00on|r" or "|cffff4444off|r"))

    elseif sub == "auto on" then
        guildCfg.autoRegister = true
        print("|cff00ff00ApeTracksAlts|r Guild bank auto-register: |cff00ff00on|r")

    elseif sub == "auto off" then
        guildCfg.autoRegister = false
        print("|cff00ff00ApeTracksAlts|r Guild bank auto-register: |cffff4444off|r")

    else
        print("|cff00ff00ApeTracksAlts|r Guild Bank Commands:")
        print("  /ata guild add        — Register current guild's bank for THIS character")
        print("  /ata guild remove     — Unregister current guild's bank for THIS character")
        print("  /ata guild scan       — Scan open guild bank now")
        print("  /ata guild list       — Show YOUR registered banks")
        print("  /ata guild auto on/off — Toggle auto-register (default: off)")
    end
end

ATAGuildBankOpen = false

local gbFrame = CreateFrame("Frame")
gbFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
gbFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
gbFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")

gbFrame:SetScript("OnEvent", function(_, event)
    if event == "GUILDBANKFRAME_OPENED" then
        ATAGuildBankOpen = true
        if not ATA.realm then return end
        ATA.MigrateGuildConfig()
        local guildName = GetCurrentGuild()
        if not guildName then return end
        local guildCfg = ApeTracksAltsCfg.guild or {}

        if guildCfg.autoRegister and not IsRegisteredForChar(guildName) then
            local myGuilds = EnsureCharGuilds()
            myGuilds[guildName] = true
            print(string.format("|cff00ff00ApeTracksAlts|r Auto-registered |cff00cccc%s|r for %s.",
                guildName, ATA.ColorName(ATA.player, ATA.GetCharData().class)))
        end

        if IsRegisteredForChar(guildName) then
            C_Timer.After(1, function()
                if ATAGuildBankOpen then
                    local ok, name, newItems = ScanGuildBank()
                    if ok then
                        local total = 0
                        local db = ApeTracksAltsDB.guildBanks[ATA.realm][name] or {}
                        for _ in pairs(db) do total = total + 1 end
                        print(string.format("|cff00ff00ApeTracksAlts|r |cff00cccc%s|r scanned — %d unique items. Click remaining tabs to update.",
                            name, total))
                    end
                end
            end)
        end

    elseif event == "GUILDBANKFRAME_CLOSED" then
        ATAGuildBankOpen = false

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- Fires when tab data loads or items change — rescan after short delay
        if ATAGuildBankOpen and ATA.realm then
            C_Timer.After(0.5, function()
                if ATAGuildBankOpen then
                    local ok, name, newItems = ScanGuildBank()
                    if ok and newItems and newItems > 0 then
                        print(string.format("|cff00ff00ApeTracksAlts|r |cff00cccc%s|r updated — %d new items found.",
                            name, newItems))
                    end
                end
            end)
        end
    end
end)

print("|cff00ff00ApeTracksAlts|r GuildBank.lua loaded")
