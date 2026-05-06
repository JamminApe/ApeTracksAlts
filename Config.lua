-- ApeTracksAlts | Config.lua
-- Persistent settings store. Loaded before all other modules so Panel.lua
-- and future phases can read config values safely on startup.

print("|cff00ff00ApeTracksAlts|r Config.lua executing...")

ApeTracksAltsCfg = ApeTracksAltsCfg or {}

local defaults = {
    panel = {
        x        = 100,
        y        = -200,
        visible  = false,
        sortCol  = "level",   -- default sort column
        sortDesc = true,      -- descending by default
    },
    stale = {
        days = 7,
    },
}

-- Merge defaults into saved config without overwriting existing values.
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

-- Add config to the existing ApeTracksAlts namespace created by Core.lua
if ApeTracksAlts then
    ApeTracksAlts.cfg = ApeTracksAltsCfg
else
    print("|cffff4444ApeTracksAlts|r Config.lua: ApeTracksAlts global not found!")
end