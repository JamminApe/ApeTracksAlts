-- ApeTracksAlts | Gold.lua
-- Gold is tracked passively in Core.lua via PLAYER_MONEY / PLAYER_LOGIN.
-- This file exposes the account-wide gold summary for use by other modules
-- such as the character panel. Use /ata gold for a chat summary.

local ATA = ApeTracksAlts

-------------------------------------------------------------------------------
-- Public: returns account-wide gold total and a sorted list of {name, class, gold}
-------------------------------------------------------------------------------
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