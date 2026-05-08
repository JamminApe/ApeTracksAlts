-- ApeTracksAlts | Panel.lua
-- Full character panel with sortable columns.
-- /ata show | /ata hide | /ata toggle

local ATA = ApeTracksAlts
local panel = nil
local realmText, footerLeft, footerRight, footerSep = nil, nil, nil, nil
local headerBtns = {}
local rowPool, activeRows = {}, {}

local COL = {
    { key="name",  label="Character", width=145, align="LEFT"   },
    { key="level", label="Lvl",       width=34,  align="CENTER" },
    { key="race",  label="Race",      width=85,  align="LEFT"   },
    { key="ilvl",  label="iLvl",      width=42,  align="CENTER" },
    { key="gold",  label="Gold",      width=118, align="RIGHT"  },
    { key="honor", label="Honor",     width=62,  align="RIGHT"  },
    { key="arena", label="Arena",     width=58,  align="RIGHT"  },
    { key="runes", label="Runes",     width=58,  align="RIGHT"  },
    { key="locks", label="Locks",     width=54,  align="CENTER" },
    { key="profs", label="Profs",     width=58,  align="CENTER" },
    { key="items", label="Items",     width=60,  align="RIGHT"  },
    { key="seen",  label="Last Seen", width=95,  align="RIGHT"  },
}

local ROW_H    = 22
local HEADER_H = 26
local TITLE_H  = 30
local FOOTER_H = 28
local PAD      = 10
local GAP      = 6
local PANEL_W = PAD*2
for _,c in ipairs(COL) do PANEL_W = PANEL_W + c.width + GAP end

local function FmtGold(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper/10000)
    local s = math.floor((copper%10000)/100)
    local c = copper%100
    return string.format("|cffd7a642%d|rg |cffc0c0c0%d|rs |cffb87333%d|rc", g, s, c)
end

local function FmtSeen(t)
    if not t or t==0 then return "-" end
    local d = math.floor((time()-t)/86400)
    if d<1 then return "Today" end
    if d<7  then return d.."d ago" end
    return d.."d ago(!)"
end

local function SortVal(data, name, key)
    if key=="name"  then return name:lower() end
    if key=="race"  then return (data.race or ""):lower() end
    if key=="level" then return data.level or 0 end
    if key=="ilvl"  then return data.ilvl  or 0 end
    if key=="gold"  then return data.gold  or 0 end
    if key=="honor" then return data.honor or 0 end
    if key=="arena" then return data.arena or 0 end
    if key=="runes" then return data.runes or 0 end
    if key=="locks" then return #(data.lockouts or {}) end
    if key=="seen"  then return data.lastSeen or 0 end
    if key=="items" then
        local n=0
        for _ in pairs(data.items or {}) do n=n+1 end
        return n
    end
    return 0
end

local function Dash(n)
    return (n and n>0) and tostring(n) or "-"
end

-- Font: use ElvUI's Expressway if ElvUI is loaded, otherwise WoW's default.
-- IsAddOnLoaded is the reliable runtime check — works regardless of load order.
local FONT_PATH = IsAddOnLoaded("ElvUI")
    and "Interface\\AddOns\\ElvUI\\Media\\Fonts\\Expressway.ttf"
    or  "Fonts\\FRIZQT__.TTF"
local FONT_SIZE  = 14

-- Private tooltip for panel row hover — completely independent of GameTooltip.
-- Using a separate frame means other addons (Questie, etc.) cannot interfere
-- with our tooltip by hiding or stealing GameTooltip ownership.
local ATA_Tooltip = CreateFrame("GameTooltip", "ATAPanelTooltip", UIParent, "GameTooltipTemplate")
ATA_Tooltip:SetFrameStrata("TOOLTIP")
-- Use raw texture instead of SetBackdrop so ElvUI/addons can't override our color.
-- Matches the panel's exact background: SetColorTexture(0.05, 0.05, 0.05, 0.92)
ATA_Tooltip:SetBackdrop(nil)
local _ttBg = ATA_Tooltip:CreateTexture(nil, "BACKGROUND")
_ttBg:SetAllPoints()
_ttBg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
ATA_Tooltip:Hide()

local panelHovered = false

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_H)
        row.cells = {}
        local x = 0
        for i,col in ipairs(COL) do
            local fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT_PATH, FONT_SIZE)
            fs:SetWidth(col.width)
            fs:SetHeight(ROW_H)
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            local j = col.align=="CENTER" and "CENTER" or (col.align=="RIGHT" and "RIGHT" or "LEFT")
            fs:SetJustifyH(j)
            row.cells[i] = fs
            x = x + col.width + GAP
        end
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(1,1,1,0.04)
        hl:Hide()
        row.hl = hl
        row:EnableMouse(true)

        row:SetScript("OnEnter", function(self)
            panelHovered = true
            self.hl:Show()
            local hasLocks = self.lockouts and #self.lockouts > 0
            local hasProfs = self.professions and #self.professions > 0
            local hasN     = self.charNotes and #self.charNotes > 0
            if not hasLocks and not hasProfs and not hasN then
                ATA_Tooltip:Hide()
                return
            end
            ATA_Tooltip:SetOwner(self, "ANCHOR_NONE")
            ATA_Tooltip:SetPoint("TOPLEFT", panel, "TOPRIGHT", 12, 0)
            ATA_Tooltip:ClearLines()
            ATA_Tooltip:AddLine(ATA.ColorName(self.charName, self.charClass))
            if hasN then
                ATA_Tooltip:AddLine(" ")
                ATA_Tooltip:AddLine("|cffffff00Notes:|r")
                for i, text in ipairs(self.charNotes) do
                    if #text <= 50 then
                        ATA_Tooltip:AddLine(string.format("  [%d] %s", i, text), 1, 1, 1)
                    else
                        ATA_Tooltip:AddLine(string.format("  [%d] %s", i, text:sub(1, 50)), 1, 1, 1)
                        local remaining = text:sub(51)
                        while #remaining > 0 do
                            ATA_Tooltip:AddLine("      "..remaining:sub(1,50), 1, 1, 1)
                            remaining = remaining:sub(51)
                        end
                    end
                end
            end
            if hasLocks then
                ATA_Tooltip:AddLine(" ")
                ATA_Tooltip:AddLine("|cffffff00Lockouts:|r")
                for _, lock in ipairs(self.lockouts) do
                    local remaining = lock.expires - time()
                    if remaining > 0 then
                        local h = math.floor(remaining / 3600)
                        local m = math.floor((remaining % 3600) / 60)
                        ATA_Tooltip:AddLine(string.format("  %s  %dh %dm", lock.name, h, m), 1, 0.5, 0.5)
                    end
                end
            end
            if hasProfs then
                ATA_Tooltip:AddLine(" ")
                ATA_Tooltip:AddLine("|cffffff00Professions:|r")
                for _, p in ipairs(self.professions) do
                    ATA_Tooltip:AddLine(string.format("  %s  %d/%d", p.name, p.rank, p.maxRank), 0.8, 0.8, 0.8)
                end
            end
            ATA_Tooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            panelHovered = false
            self.hl:Hide()
        end)
    end

    row:Show()
    row.charNotes   = {}
    row.lockouts    = {}
    row.professions = {}
    row.charName    = nil
    row.charClass   = nil
    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    table.insert(rowPool, row)
end

local function BuildPanel()
    if panel then return end

    if not ApeTracksAltsCfg or not ApeTracksAltsCfg.panel then
        print("|cffff4444ApeTracksAlts|r BuildPanel: ApeTracksAltsCfg not ready")
        return
    end

    panel = CreateFrame("Frame", "ATAPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(PANEL_W)
    panel:SetHeight(200)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnLeave", function()
        ATA_Tooltip:Hide()
    end)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ApeTracksAltsCfg.panel.x = math.floor(self:GetLeft() or 0)
        ApeTracksAltsCfg.panel.y = math.floor(self:GetTop() or 0)
        print(string.format("|cff00ff00ApeTracksAlts|r Position saved: x=%d y=%d",
            ApeTracksAltsCfg.panel.x, ApeTracksAltsCfg.panel.y))
    end)

    -- Background
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)

    -- Title
    local titleFs = panel:CreateFontString(nil, "OVERLAY")
    titleFs:SetFont(FONT_PATH, 14)
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -8)
    titleFs:SetTextColor(0.2, 1, 0.2)
    titleFs:SetText("ApeTracksAlts")

    realmText = panel:CreateFontString(nil, "OVERLAY")
    realmText:SetFont(FONT_PATH, FONT_SIZE - 1)
    realmText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -28, -10)
    realmText:SetJustifyH("RIGHT")
    realmText:SetTextColor(0.6, 0.6, 0.6)

    local titleSep = panel:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, -TITLE_H)
    titleSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -TITLE_H)
    titleSep:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetWidth(24)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
        ApeTracksAltsCfg.panel.visible = false
    end)

    -- Column headers
    local x = 0
    for i, col in ipairs(COL) do
        local btn = CreateFrame("Button", nil, panel)
        btn:SetWidth(col.width)
        btn:SetHeight(HEADER_H)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD+x, -(TITLE_H+2))
        local j = col.align=="CENTER" and "CENTER" or (col.align=="RIGHT" and "RIGHT" or "LEFT")
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FONT_PATH, FONT_SIZE)
        fs:SetAllPoints()
        fs:SetJustifyH(j)
        fs:SetText(col.label)
        btn.fs = fs
        btn:SetScript("OnClick", function()
            local c = ApeTracksAltsCfg.panel
            if c.sortCol == col.key then
                c.sortDesc = not c.sortDesc
            else
                c.sortCol  = col.key
                c.sortDesc = (col.key ~= "name")
            end
            ATA.PanelRefresh()
        end)
        btn:SetScript("OnEnter", function() fs:SetTextColor(1,0.82,0) end)
        btn:SetScript("OnLeave", function() ATA.PanelRefresh() end)
        headerBtns[i] = btn
        x = x + col.width + GAP
    end

    local headerSep = panel:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  -(TITLE_H+HEADER_H+2))
    headerSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(TITLE_H+HEADER_H+2))
    headerSep:SetColorTexture(0.35, 0.35, 0.35, 0.8)

    -- Footer
    footerSep = panel:CreateTexture(nil, "ARTWORK")
    footerSep:SetHeight(1)
    footerSep:SetColorTexture(0.35, 0.35, 0.35, 0.8)

    footerLeft = panel:CreateFontString(nil, "OVERLAY")
    footerLeft:SetFont(FONT_PATH, FONT_SIZE)
    footerLeft:SetJustifyH("LEFT")

    footerRight = panel:CreateFontString(nil, "OVERLAY")
    footerRight:SetFont(FONT_PATH, FONT_SIZE)
    footerRight:SetJustifyH("RIGHT")

    panel:Hide()
end

function ATA.PanelRefresh()
    if not panel or not panel:IsShown() then return end
    if not ATA.realm then return end

    local cfg = ApeTracksAltsCfg.panel
    local realmDB = ApeTracksAltsDB[ATA.realm] or {}
    if realmText then realmText:SetText(ATA.realm) end

    local pinned, others = {}, {}
    for charName, data in pairs(realmDB) do
        if charName == ATA.player then
            table.insert(pinned, {name=charName, data=data})
        else
            table.insert(others, {name=charName, data=data})
        end
    end

    table.sort(others, function(a,b)
        local av = SortVal(a.data, a.name, cfg.sortCol)
        local bv = SortVal(b.data, b.name, cfg.sortCol)
        if av == bv then return a.name < b.name end
        if cfg.sortDesc then return av > bv else return av < bv end
    end)

    local sorted = {}
    for _,e in ipairs(pinned) do table.insert(sorted, e) end
    for _,e in ipairs(others) do table.insert(sorted, e) end

    -- Release only rows we no longer need (character count shrank)
    -- Keep existing rows and update them in place to preserve hover state
    while #activeRows > #sorted do
        local row = table.remove(activeRows)
        ReleaseRow(row)
    end

    local topY = -(TITLE_H + HEADER_H + 6)
    local totalGold, totalItems = 0, 0

    for _, entry in ipairs(sorted) do
        local cn     = entry.name
        local d      = entry.data
        local isSelf = (cn == ATA.player)
        local stale  = ATA.IsStale(d)

        local itemCount = 0
        for _ in pairs(d.items or {}) do itemCount = itemCount+1 end

        -- Get notes for this character (now an array of up to 3)
        local notesCfg = ApeTracksAltsCfg.notes
        local charNotes = {}
        if notesCfg and notesCfg[ATA.realm] and notesCfg[ATA.realm][cn] then
            local n = notesCfg[ATA.realm][cn]
            charNotes = type(n) == "table" and n or { n }
        end
        local hasNote = #charNotes > 0

        local nameStr
        local prefix = hasNote and "|cffffff00* |r" or ""
        if isSelf then
            nameStr = prefix .. "[*] " .. ATA.ColorName(cn, d.class)
        elseif stale then
            nameStr = prefix .. "|cff777777"..cn.." [!]|r"
        else
            nameStr = prefix .. ATA.ColorName(cn, d.class)
        end

        local lockouts  = d.lockouts or {}
        local lockCount = #lockouts
        local lockStr   = lockCount > 0 and ("|cffff4444"..lockCount.."|r") or "|cff888888-|r"

        -- Profession display: show up to 2 icons using texture strings
        local profStr = ""
        local profs = d.professions or {}
        if #profs == 0 then
            profStr = "|cff888888-|r"
        else
            local parts = {}
            for _, p in ipairs(profs) do
                local icon = ApeTracksAlts.ProfessionIcons and ApeTracksAlts.ProfessionIcons[p.name]
                if icon then
                    parts[#parts+1] = "|T"..icon..":20:20|t"
                else
                    parts[#parts+1] = p.name:sub(1,3)
                end
            end
            profStr = table.concat(parts, " ")
        end

        local vals = {
            nameStr,
            tostring(d.level or 0),
            d.race or "-",
            (d.ilvl and d.ilvl>0) and string.format("%.1f", d.ilvl) or "-",
            FmtGold(d.gold),
            Dash(d.honor),
            Dash(d.arena),
            Dash(d.runes),
            lockStr,
            profStr,
            tostring(itemCount),
            FmtSeen(d.lastSeen),
        }

        local row = AcquireRow()
        row:SetWidth(PANEL_W - PAD*2)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, topY)
        for i, fs in ipairs(row.cells) do
            fs:SetText(vals[i] or "")
            fs:SetAlpha(stale and 0.5 or 1.0)
        end

        row.lockouts    = lockouts
        row.professions = d.professions or {}
        row.charName    = cn
        row.charClass   = d.class
        row.charNotes   = charNotes

        totalGold  = totalGold  + (d.gold or 0)
        totalItems = totalItems + itemCount
        topY = topY - ROW_H
        table.insert(activeRows, row)
    end

    -- Footer
    local footY = topY - 4
    if footerSep then
        footerSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  footY)
        footerSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, footY)
    end
    if footerLeft then
        footerLeft:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  footY-4)
        footerLeft:SetText("|cffffff00Gold:|r "..FmtGold(totalGold))
    end
    if footerRight then
        footerRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, footY-4)
        footerRight:SetText("|cffffff00Items: "..totalItems.."|r")
    end

    -- Header sort indicators
    for i, btn in ipairs(headerBtns) do
        local col = COL[i]
        if col.key == cfg.sortCol then
            btn.fs:SetTextColor(1, 0.82, 0)
            btn.fs:SetText(col.label..(cfg.sortDesc and " v" or " ^"))
        else
            btn.fs:SetTextColor(0.75, 0.75, 0.75)
            btn.fs:SetText(col.label)
        end
    end

    local h = TITLE_H + HEADER_H + (#sorted*ROW_H) + FOOTER_H + PAD*2 + 12
    panel:SetHeight(h)
end

function ApeTracksAlts.PanelShow()
    if not panel then BuildPanel() end
    if not panel then return end
    local x = ApeTracksAltsCfg.panel.x
    local y = ApeTracksAltsCfg.panel.y
    panel:ClearAllPoints()
    if x and y and y > 0 then
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -(UIParent:GetHeight() - y))
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    panel:Show()
    ApeTracksAltsCfg.panel.visible = true
    ATA.PanelRefresh()
end

function ApeTracksAlts.PanelHide()
    if panel then panel:Hide() end
    ApeTracksAltsCfg.panel.visible = false
end

function ApeTracksAlts.PanelToggle()
    if panel and panel:IsShown() then
        ApeTracksAlts.PanelHide()
    else
        ApeTracksAlts.PanelShow()
    end
end

ATA.OnDataChanged = function()
    if not panel or not panel:IsShown() then return end
    if panelHovered then
        C_Timer.After(0.5, function()
            if not panelHovered then
                ATA.PanelRefresh()
            end
        end)
        return
    end
    ATA.PanelRefresh()
end

-- Update only charNotes on active rows without releasing/rebuilding them.
-- Safe to call while hovering — doesn't touch row positions or scripts.
function ATA.UpdateNotesOnly()
    if not panel or not panel:IsShown() then return end
    local notesCfg = ApeTracksAltsCfg.notes
    local hoveredRow = nil
    for _, row in ipairs(activeRows) do
        if row.charName then
            local charNotes = {}
            if notesCfg and notesCfg[ATA.realm] and notesCfg[ATA.realm][row.charName] then
                local n = notesCfg[ATA.realm][row.charName]
                charNotes = type(n) == "table" and n or { n }
            end
            row.charNotes = charNotes
            -- Update * prefix on name cell
            local hasNote = #charNotes > 0
            local cn = row.charName
            local d = ApeTracksAltsDB[ATA.realm] and ApeTracksAltsDB[ATA.realm][cn]
            if d and row.cells[1] then
                local isSelf  = (cn == ATA.player)
                local stale   = ATA.IsStale(d)
                local prefix  = hasNote and "|cffffff00* |r" or ""
                local nameStr
                if isSelf then
                    nameStr = prefix .. "[*] " .. ATA.ColorName(cn, d.class)
                elseif stale then
                    nameStr = prefix .. "|cff777777"..cn.." [!]|r"
                else
                    nameStr = prefix .. ATA.ColorName(cn, d.class)
                end
                row.cells[1]:SetText(nameStr)
            end
            -- Track which row is currently hovered so we can refresh its tooltip
            if row:IsMouseOver() then hoveredRow = row end
        end
    end
    -- If a row is hovered, fire its OnEnter to refresh the tooltip immediately
    if hoveredRow then
        local script = hoveredRow:GetScript("OnEnter")
        if script then script(hoveredRow) end
    end
end

ATA.OnCoreReady = function()
    BuildPanel()
    local loginOpen = ApeTracksAltsCfg and ApeTracksAltsCfg.loginOpen
    if loginOpen == nil then loginOpen = true end
    if loginOpen then
        ApeTracksAlts.PanelShow()
    end
end

-------------------------------------------------------------------------------
-- ATA Tabbed Window
-- Three tabs: Results (slash command output), Help (command reference),
-- Config (current settings). Tabs sit top-right. Active tab highlighted.
-- Content persists until Clear is clicked or /reload.
-------------------------------------------------------------------------------

local ataWindow    = nil
local activeTab    = "Results"
local outputBuffer = {}
local MAX_LINES    = 200  -- max lines the ScrollingMessageFrame retains

-- Tab colors
local TAB_ACTIVE   = { r=0.2,  g=1.0,  b=0.2,  a=1.0 }  -- green, matches title
local TAB_INACTIVE = { r=0.5,  g=0.5,  b=0.5,  a=1.0 }  -- grey
local TAB_BG_ACT   = { r=0.15, g=0.15, b=0.15, a=1.0 }  -- slightly lighter bg
local TAB_BG_INACT = { r=0.05, g=0.05, b=0.05, a=0.0 }  -- transparent

-- Help content — sectioned command reference
local HELP_SECTIONS = {
    { header = "Search & Database",
      cmds = {
        { cmd="/ata find <item>",        desc="Search for an item across all alts" },
        { cmd="/ata recipe <name>",      desc="Search learned recipes across alts" },
        { cmd="/ata locks",              desc="Show lockouts for all alts" },
        { cmd="/ata prof",               desc="Show professions for all alts" },
        { cmd="/ata gold",               desc="Gold summary across all alts" },
        { cmd="/ata list",               desc="List all tracked characters" },
    }},
    { header = "Wishlist",
      cmds = {
        { cmd="/ata want [link/name]",   desc="Add item to wishlist" },
        { cmd="/ata want list [name]",   desc="Show wishlist (all or specific char)" },
        { cmd="/ata want clear <item>",  desc="Remove item from wishlist" },
        { cmd="/ata want clear all",     desc="Clear entire wishlist" },
    }},
    { header = "Notes  (max 3 per character)",
      cmds = {
        { cmd="/ata note <text>",        desc="Add note for current character" },
        { cmd="/ata note <Name> <text>", desc="Add note for any character" },
        { cmd="/ata note list",          desc="Show all notes numbered" },
        { cmd="/ata note clear <#>",     desc="Remove note by number" },
        { cmd="/ata note clear all",     desc="Clear all notes for current char" },
    }},
    { header = "Guild Bank",
      cmds = {
        { cmd="/ata guild add",          desc="Register guild bank for this character" },
        { cmd="/ata guild remove",       desc="Unregister guild bank" },
        { cmd="/ata guild scan",         desc="Scan open guild bank now" },
        { cmd="/ata guild list",         desc="Show registered banks" },
        { cmd="/ata guild auto on|off",  desc="Toggle auto-register" },
    }},
    { header = "Settings",
      cmds = {
        { cmd="/ata config",             desc="Show all current settings" },
        { cmd="/ata set stale <days>",   desc="Set stale threshold (default: 7)" },
        { cmd="/ata set profstale <d>",  desc="Set profession stale (default: 30)" },
        { cmd="/ata toggle login",       desc="Toggle panel auto-open on login" },
        { cmd="/ata toggle bags|bank|mail", desc="Toggle locations in tooltips" },
        { cmd="/ata ignore <name>",      desc="Hide character from tooltips" },
        { cmd="/ata unignore <name>",    desc="Remove from ignore list" },
        { cmd="/ata minimap",            desc="Toggle minimap button" },
        { cmd="/ata output",             desc="Toggle this window" },
    }},
    { header = "Database Management",
      cmds = {
        { cmd="/ata purge <name>",       desc="Remove character from database" },
        { cmd="/ata reset",              desc="Wipe entire database" },
        { cmd="/ata debug",              desc="Show DB stats" },
    }},
}

local function BuildWindow()
    if ataWindow then return end

    local W, H = 520, 360
    local f = CreateFrame("Frame", "ATAWindow", UIParent)
    f:SetSize(W, H)

    -- Restore saved position or default
    local owCfg = ApeTracksAltsCfg and ApeTracksAltsCfg.outputWindow
    if owCfg and owCfg.x and owCfg.y then
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", owCfg.x, -(UIParent:GetHeight() - owCfg.y))
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end

    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ApeTracksAltsCfg.outputWindow = ApeTracksAltsCfg.outputWindow or {}
        ApeTracksAltsCfg.outputWindow.x = math.floor(self:GetLeft() or 0)
        ApeTracksAltsCfg.outputWindow.y = math.floor(self:GetTop() or 0)
    end)

    -- Background — exact match to panel
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_PATH, 14)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -8)
    title:SetTextColor(0.2, 1, 0.2)
    title:SetText("ApeTracksAlts")

    -- Title separator
    local topLine = f:CreateTexture(nil, "ARTWORK")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -TITLE_H)
    topLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_H)
    topLine:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    -- Bottom separator
    local botLine = f:CreateTexture(nil, "ARTWORK")
    botLine:SetHeight(1)
    botLine:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 34)
    botLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 34)
    botLine:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Clear button (only relevant on Results tab)
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 6)
    clearBtn:SetText("Clear")
    f.clearBtn = clearBtn

    ---------------------------------------------------------------------------
    -- TABS — sit in the title bar, right-aligned before the close button
    ---------------------------------------------------------------------------
    local TAB_NAMES = { "Results", "Help", "Config" }
    local TAB_W, TAB_H = 64, TITLE_H
    local tabs = {}

    local function SetActiveTab(name)
        activeTab = name
        for _, t in ipairs(tabs) do
            if t.tabName == name then
                t.bg:SetColorTexture(0.18, 0.18, 0.18, 1.0)
                t.accent:SetColorTexture(0.2, 1.0, 0.2, 1.0)
                t.label:SetTextColor(0.2, 1.0, 0.2)
            else
                t.bg:SetColorTexture(0.05, 0.05, 0.05, 0.0)
                t.accent:SetColorTexture(0.2, 1.0, 0.2, 0.0)
                t.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        f.resultsFrame:SetShown(name == "Results")
        f.helpFrame:SetShown(name == "Help")
        f.configFrame:SetShown(name == "Config")
        clearBtn:SetShown(name == "Results")
        if name == "Config" then f:populateConfig() end
    end
    f.SetActiveTab = SetActiveTab

    -- Build tabs right-to-left: Config, Help, Results
    -- Leave 28px for close button on the right
    for i = #TAB_NAMES, 1, -1 do
        local name   = TAB_NAMES[i]
        local offset = -(28 + (#TAB_NAMES - i) * (TAB_W + 1))

        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(TAB_W, TAB_H)
        tab:SetPoint("TOPRIGHT", f, "TOPRIGHT", offset, 0)
        tab:EnableMouse(true)
        tab.tabName = name

        -- Background fill
        local tBg = tab:CreateTexture(nil, "BACKGROUND")
        tBg:SetAllPoints()
        tBg:SetColorTexture(0.05, 0.05, 0.05, 0.0)
        tab.bg = tBg

        -- Green accent line along the bottom of the active tab (above separator)
        local tAccent = tab:CreateTexture(nil, "ARTWORK")
        tAccent:SetHeight(2)
        tAccent:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT",  0, 0)
        tAccent:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tAccent:SetColorTexture(0.2, 1.0, 0.2, 0.0)
        tab.accent = tAccent

        -- Label
        local tLabel = tab:CreateFontString(nil, "OVERLAY")
        tLabel:SetFont(FONT_PATH, FONT_SIZE)
        tLabel:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tLabel:SetText(name)
        tLabel:SetTextColor(0.5, 0.5, 0.5)
        tab.label = tLabel

        tab:SetScript("OnClick", function() SetActiveTab(name) end)
        tab:SetScript("OnEnter", function()
            if activeTab ~= name then tLabel:SetTextColor(0.8, 0.8, 0.8) end
        end)
        tab:SetScript("OnLeave", function()
            if activeTab ~= name then tLabel:SetTextColor(0.5, 0.5, 0.5) end
        end)

        table.insert(tabs, tab)
    end

    ---------------------------------------------------------------------------
    -- RESULTS TAB — uses ScrollingMessageFrame to support clickable item links
    ---------------------------------------------------------------------------
    local rFrame = CreateFrame("Frame", nil, f)
    rFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -TITLE_H - 1)
    rFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 34)

    local smf = CreateFrame("ScrollingMessageFrame", "ATAResultsSMF", rFrame)
    smf:SetPoint("TOPLEFT",     rFrame, "TOPLEFT",     PAD,     -4)
    smf:SetPoint("BOTTOMRIGHT", rFrame, "BOTTOMRIGHT", -PAD,     2)
    smf:SetFont(FONT_PATH, FONT_SIZE)
    smf:SetFading(false)
    smf:SetMaxLines(MAX_LINES)
    smf:SetJustifyH("LEFT")
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    smf:SetHyperlinksEnabled(true)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if IsShiftKeyDown() then
            ChatFrame1:InsertLink(text)
        end
    end)
    smf:SetScript("OnHyperlinkEnter", function(self, link, text)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    smf:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)
    -- When shown, scroll to top so first result is visible with no dead space
    f:SetScript("OnShow", function()
        smf:SetScrollOffset(smf:GetNumMessages())
    end)

    clearBtn:SetScript("OnClick", function()
        resultLines = {}
        smf:Clear()
    end)

    f.resultsFrame = rFrame
    f.smf          = smf

    ---------------------------------------------------------------------------
    -- HELP TAB
    ---------------------------------------------------------------------------
    local hFrame = CreateFrame("Frame", nil, f)
    hFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -TITLE_H - 1)
    hFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 34)

    local hSF = CreateFrame("ScrollFrame", "ATAHelpScroll", hFrame, "UIPanelScrollFrameTemplate")
    hSF:SetPoint("TOPLEFT",     hFrame, "TOPLEFT",     PAD,      -4)
    hSF:SetPoint("BOTTOMRIGHT", hFrame, "BOTTOMRIGHT", -(PAD+18), 2)

    local hContent = CreateFrame("Frame", nil, hSF)
    hContent:SetWidth(hSF:GetWidth())
    hSF:SetScrollChild(hContent)

    -- Build help lines
    local hLines = {}
    for _, section in ipairs(HELP_SECTIONS) do
        -- Section header
        local hdr = hContent:CreateFontString(nil, "OVERLAY")
        hdr:SetFont(FONT_PATH, FONT_SIZE)
        hdr:SetTextColor(1.0, 1.0, 0.2)
        table.insert(hLines, hdr)
        hdr:SetText(section.header)
        -- Commands
        for _, entry in ipairs(section.cmds) do
            local cmdFS = hContent:CreateFontString(nil, "OVERLAY")
            cmdFS:SetFont(FONT_PATH, FONT_SIZE - 1)
            cmdFS:SetTextColor(0.2, 1.0, 0.5)
            cmdFS:SetWidth(160)
            cmdFS:SetJustifyH("LEFT")
            cmdFS:SetText(entry.cmd)
            local descFS = hContent:CreateFontString(nil, "OVERLAY")
            descFS:SetFont(FONT_PATH, FONT_SIZE - 1)
            descFS:SetTextColor(0.7, 0.7, 0.7)
            descFS:SetWidth(hSF:GetWidth() - 170)
            descFS:SetJustifyH("LEFT")
            descFS:SetText(entry.desc)
            table.insert(hLines, { cmd=cmdFS, desc=descFS })
        end
        -- Spacer between sections
        table.insert(hLines, "spacer")
    end

    -- Position help lines
    local LINE_H = ROW_H
    local y = -4
    for _, line in ipairs(hLines) do
        if line == "spacer" then
            y = y - (LINE_H * 0.5)
        elseif type(line) == "table" and line.cmd then
            line.cmd:SetPoint("TOPLEFT", hContent, "TOPLEFT", 8, y)
            line.desc:SetPoint("TOPLEFT", hContent, "TOPLEFT", 170, y)
            y = y - LINE_H
        else
            -- header
            line:SetPoint("TOPLEFT", hContent, "TOPLEFT", 4, y)
            y = y - LINE_H
        end
    end
    hContent:SetHeight(math.abs(y) + LINE_H)

    f.helpFrame = hFrame

    ---------------------------------------------------------------------------
    -- CONFIG TAB
    ---------------------------------------------------------------------------
    local cFrame = CreateFrame("Frame", nil, f)
    cFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -TITLE_H - 1)
    cFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 34)

    local cSF = CreateFrame("ScrollFrame", "ATAConfigScroll", cFrame, "UIPanelScrollFrameTemplate")
    cSF:SetPoint("TOPLEFT",     cFrame, "TOPLEFT",     PAD,      -4)
    cSF:SetPoint("BOTTOMRIGHT", cFrame, "BOTTOMRIGHT", -(PAD+18), 2)

    local cContent = CreateFrame("Frame", nil, cSF)
    cContent:SetWidth(cSF:GetWidth())
    cSF:SetScrollChild(cContent)

    -- Pre-create config lines (enough for all settings)
    local configPool = {}
    for i = 1, 30 do
        local fs = cContent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FONT_PATH, FONT_SIZE)
        fs:SetJustifyH("LEFT")
        fs:SetPoint("TOPLEFT", cContent, "TOPLEFT", 4, -(i-1)*ROW_H)
        fs:SetWidth(cSF:GetWidth() - 8)
        fs:SetText("")
        table.insert(configPool, fs)
    end
    cContent:SetHeight(30 * ROW_H)

    f.configFrame  = cFrame
    f.configPool   = configPool

    -- Populate config tab with current settings
    f.populateConfig = function()
        local cfg    = ApeTracksAltsCfg or {}
        local ttCfg  = cfg.tooltip or {}
        local stale  = cfg.stale or {}
        local function onoff(v) return (v ~= false) and "|cff00ff00on|r" or "|cffff4444off|r" end
        local myGuilds = cfg.guild and cfg.guild.chars and cfg.guild.chars[ATA.realm]
            and cfg.guild.chars[ATA.realm][ATA.player] or {}
        local guildList = {}
        for g in pairs(myGuilds) do
            table.insert(guildList, "|cff00cccc"..g.."|r")
        end
        local ignored = cfg.ignore or {}
        local ignoreList = {}
        for k in pairs(ignored) do table.insert(ignoreList, k) end

        local lines = {
            "|cffffff00— Current Settings ——————————————|r",
            "",
            string.format("  Stale threshold  : %d days", stale.days or 7),
            string.format("  Prof stale       : %d days", stale.profDays or 30),
            string.format("  Panel on login   : %s", onoff(cfg.loginOpen)),
            string.format("  Tooltip bags     : %s", onoff(ttCfg.showBags)),
            string.format("  Tooltip bank     : %s", onoff(ttCfg.showBank)),
            string.format("  Tooltip mail     : %s", onoff(ttCfg.showMail)),
            string.format("  Ignored chars    : %s", #ignoreList > 0 and table.concat(ignoreList, ", ") or "none"),
            string.format("  Guild banks      : %s", #guildList > 0 and table.concat(guildList, ", ") or "|cff888888NA|r"),
            string.format("  Guild auto-reg   : %s", onoff(cfg.guild and cfg.guild.autoRegister)),
            "",
            "|cffffff00— Change Settings ——————————————|r",
            "",
            "  /ata set stale <days>",
            "  /ata set profstale <days>",
            "  /ata toggle login|bags|bank|mail",
            "  /ata ignore|unignore <name>",
            "  /ata guild add|remove|auto on|off",
        }
        for i, fs in ipairs(configPool) do
            fs:SetText(lines[i] or "")
        end
    end

    f:Hide()
    ataWindow = f

    -- Init first tab
    SetActiveTab("Results")
end

-- Public: buffer a line for output. Call ATA.OutputFlush() when done.
function ATA.Output(text)
    BuildWindow()
    table.insert(outputBuffer, text or "")
end

-- Flushes buffered output lines to the Results tab in order.
-- Call this at the end of each slash command that uses ATA.Output().
function ATA.OutputFlush()
    if not ataWindow then BuildWindow() end
    if #outputBuffer == 0 then return end
    for i = 1, #outputBuffer do
        ataWindow.smf:AddMessage(outputBuffer[i])
    end
    outputBuffer = {}
    ataWindow.smf:SetScrollOffset(ataWindow.smf:GetNumMessages())
    ataWindow.SetActiveTab("Results")
    if not ataWindow:IsShown() then ataWindow:Show() end
end

-- Public: open the window on a specific tab
function ATA.ShowTab(tabName)
    BuildWindow()
    ataWindow.SetActiveTab(tabName or "Results")
    ataWindow:Show()
end

-- Public: toggle the window
function ATA.ToggleOutput()
    BuildWindow()
    if ataWindow:IsShown() then
        ataWindow:Hide()
    else
        ataWindow:Show()
    end
end
