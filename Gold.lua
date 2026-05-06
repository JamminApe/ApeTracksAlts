-- ApeTracksAlts | Gold.lua
-- Passive module: gold is tracked in Core.lua via PLAYER_MONEY / PLAYER_LOGIN.
-- This file provides the account-wide gold summary injected into the tooltip
-- for coin items (Gold Coin, Silver Coin, Copper Coin, etc.) and a few
-- convenience functions other modules can call.

local ATA = ApeTracksAlts

-------------------------------------------------------------------------------
-- Coin item IDs that should show the account gold summary in their tooltip.
-- Add any Ascension-specific currency item IDs here as needed.
-------------------------------------------------------------------------------
local COIN_ITEMS = {
    [2073]  = true,   -- Copper Coin
    [2074]  = true,   -- Silver Coin
    [2592]  = true,   -- Gold Coin
    [19182] = true,   -- Darkmoon Faire Prize Ticket (example currency)
}

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

-------------------------------------------------------------------------------
-- Tooltip hook: adds account gold summary to coin / currency item tooltips
-------------------------------------------------------------------------------
-- Reset the per-show guard at the top level — same pattern as Tooltip.lua.
-- Never call HookScript("OnHide") inside OnTooltipSetItem; it stacks infinitely.
GameTooltip:HookScript("OnHide", function(self)
    self.__ATAGoldShown = nil
end)

GameTooltip:HookScript("OnTooltipSetItem", function(tt)
    if tt.__ATAGoldShown then return end
    tt.__ATAGoldShown = true

    local _, link = tt:GetItem()
    local itemID  = ATA.GetItemIDFromLink(link)
    if not itemID or not COIN_ITEMS[itemID] then return end

    local total, list = ATA.GetGoldSummary()
    if #list == 0 then return end

    tt:AddLine(" ")
    tt:AddLine("|cff00ff00ApeTracksAlts|r — Account Gold")

    for _, e in ipairs(list) do
        local staleTag = e.stale and " |cffff4444[stale]|r" or ""
        tt:AddLine(string.format("%s: %s%s",
            ATA.ColorName(e.name, e.class),
            ATA.FormatGold(e.gold),
            staleTag
        ), 1, 1, 1)
    end

    tt:AddLine(" ")
    tt:AddLine("|cffffff00Account Total: " .. ATA.FormatGold(total) .. "|r")
end)