-- ApeTracksAlts | Config.lua
-- Persistent settings store. Loaded before all other modules.

ApeTracksAltsCfg = ApeTracksAltsCfg or {}

local defaults = {
    panel = {
        x        = 200,
        y        = 400,
        visible  = false,
        sortCol  = "level",
        sortDesc = true,
    },
    tooltip = {
        showBags  = true,
        showBank  = true,
        showMail  = true,
    },
    ignore   = {},
    wishlist = {},   -- [realm][charName][itemID] = itemName
    stale = {
        days     = 7,
        profDays = 30,
    },
    minimap = {
        angle = 45,
        hide  = false,
    },
    loginOpen = true,
}

local function ApplyDefaults(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            target[k] = target[k] or {}
            ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

ApplyDefaults(ApeTracksAltsCfg, defaults)

if ApeTracksAlts then
    ApeTracksAlts.cfg = ApeTracksAltsCfg
else
    print("|cffff4444ApeTracksAlts|r Config.lua: ApeTracksAlts global not found!")
end
