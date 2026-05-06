-- ApeTracksAlts | Core.lua
-- Shared DB, utilities, scanning logic, events, and slash commands.
-- All other modules read from ApeTracksAltsDB and call functions exposed here.

print("|cff00ff00ApeTracksAlts v1.1 loaded|r")

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
        class    = select(2, UnitClass("player")),
        level    = UnitLevel("player"),
        gold     = 0,
        lastSeen = 0,
        items    = {},
    }
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
    local daysSince = (time() - charData.lastSeen) / 86400
    return daysSince >= STALE_DAYS
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
    -- Silent prune; uncomment for debug feedback:
    -- if pruned > 0 then
    --     print(string.format("|cff00ff00ApeTracksAlts|r Pruned %d empty item entries.", pruned))
    -- end
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

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function RegisterSlashCommands()
    SLASH_APETRACKSALTS1 = "/ata"
    SLASH_APETRACKSALTS2 = "/apetracksalts"

    SlashCmdList["APETRACKSALTS"] = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")

        -- Safe accessor — realm table may be nil after /ata reset
        local realmDB = ApeTracksAltsDB[ATA.realm] or {}

        -- /ata debug
        if msg == "debug" then
            local charCount, itemCount = 0, 0
            for _, c in pairs(realmDB) do
                charCount = charCount + 1
                for _ in pairs(c.items) do itemCount = itemCount + 1 end
            end
            print(string.format(
                "|cff00ff00ApeTracksAlts|r Debug — Realm: %s | Characters: %d | Unique Items: %d",
                ATA.realm, charCount, itemCount
            ))

        -- /ata list
        elseif msg == "list" then
            print("|cff00ff00ApeTracksAlts|r — Characters on " .. ATA.realm .. ":")
            for charName, data in pairs(realmDB) do
                local itemCount = 0
                for _ in pairs(data.items) do itemCount = itemCount + 1 end
                local staleTag = ATA.IsStale(data) and " |cffff4444[stale]|r" or ""
                print(string.format("  %s (Lvl %d %s) — %d items  %s%s",
                    ATA.ColorName(charName, data.class),
                    data.level or 0,
                    data.class or "?",
                    itemCount,
                    ATA.FormatGold(data.gold),
                    staleTag
                ))
            end

        -- /ata gold
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

        -- /ata reset
        elseif msg == "reset" then
            ApeTracksAltsDB = {}
            -- Immediately re-seed so the current session stays functional
            ATA.EnsureDB()
            local charData = ATA.GetCharData()
            charData.lastSeen = time()
            charData.level    = UnitLevel("player")
            charData.gold     = GetMoney()
            ScanBags()
            print("|cff00ff00ApeTracksAlts|r Database reset. Current character re-seeded.")

        -- /ata help or anything unrecognized
        else
            print("|cff00ff00ApeTracksAlts|r Commands:")
            print("  /ata list   — All tracked characters (level, class, gold, stale flag)")
            print("  /ata gold   — Gold summary across all alts")
            print("  /ata debug  — DB stats (character + item counts)")
            print("  /ata reset  — Wipe the database (current char re-seeded immediately)")
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

        -- Refresh login timestamp, level, and gold on every login
        local charData = ATA.GetCharData()
        charData.lastSeen = time()
        charData.level    = UnitLevel("player")
        charData.gold     = GetMoney()

        PruneItems()
        ScanBags()
        RegisterSlashCommands()

        -- Notify other modules that core is ready
        if ApeTracksAlts.OnCoreReady then ApeTracksAlts.OnCoreReady() end

    elseif event == "BAG_UPDATE" then
        if ATA.realm then
            ScanBags()
            -- If the bank is open, any bag change also means the bank contents
            -- may have changed (deposit/withdrawal). Rescan both together.
            if bankIsOpen then ScanBank() end
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
        if mailScanTimer then
            mailScanTimer:Cancel()
            mailScanTimer = nil
        end
        ClearMailCounts()

    elseif event == "PLAYER_MONEY" then
        if ATA.realm then
            ATA.GetCharData().gold = GetMoney()
        end

    elseif event == "PLAYER_LEVEL_UP" then
        if ATA.realm then
            ATA.GetCharData().level = UnitLevel("player")
        end
    end
end)