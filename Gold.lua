-- ApeTracksAlts | Gold.lua
-- Gold is tracked passively in Core.lua via PLAYER_MONEY / PLAYER_LOGIN.
-- This file exposes the account-wide gold summary used by the panel and /ata gold.

local ATA = ApeTracksAlts

-- Returns account-wide gold total (in copper) and a sorted list of
-- {name, class, gold, stale, lastSeen} entries, highest gold first.
function ATA.GetGoldSummary()
    if not ATA.realm or not ApeTracksAltsDB[ATA.realm] then return 0, {} end
    local list  = {}
    local total = 0
    for charName, data in pairs(ApeTracksAltsDB[ATA.realm]) do
        local g = data.gold or 0
        total = total + g
        table.insert(list, {
            name     = charName,
            class    = data.class,
            gold     = g,
            stale    = ATA.IsStale(data),
            lastSeen = data.lastSeen or 0,
        })
    end
    table.sort(list, function(a, b) return a.gold > b.gold end)
    return total, list
end
