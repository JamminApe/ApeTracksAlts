-- ApeTracksAlts | Config.lua
-- Persistent settings store. Loaded before all other modules so Panel.lua
-- and future phases can read config values safely on startup.

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

-- Expose config on the global namespace for other modules.
ApeTracksAlts = ApeTracksAlts or {}
ApeTracksAlts.cfg = ApeTracksAltsCfg