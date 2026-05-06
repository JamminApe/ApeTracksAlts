-- ApeTracksAlts | Panel.lua
-- Moveable character panel showing all tracked alts with sortable columns.

local ATA = ApeTracksAlts

-------------------------------------------------------------------------------
-- Layout constants
-------------------------------------------------------------------------------

local COL = {
    { key = "name",  label = "Character", width = 110, align = "LEFT"   },
    { key = "level", label = "Lvl",       width = 30,  align = "CENTER" },
    { key = "ilvl",  label = "iLvl",      width = 36,  align = "CENTER" },
    { key = "gold",  label = "Gold",      width = 85,  align = "RIGHT"  },
    { key = "honor", label = "Honor",     width = 50,  align = "RIGHT"  },
    { key = "arena", label = "Arena",     width = 42,  align = "RIGHT"  },
    { key = "runes", label = "Runes",     width = 48,  align = "RIGHT"  },
    { key = "items", label = "Items",     width = 42,  align = "RIGHT"  },
    { key = "seen",  label = "Last Seen", width = 68,  align = "RIGHT"  },
}

local ROW_H    = 16
local HEADER_H = 20
local TITLE_H  = 22
local FOOTER_H = 20
local PAD      = 10
local COL_GAP  = 4

local PANEL_W = PAD * 2
for _, c in ipairs(COL) do PANEL_W = PANEL_W + c.width + COL_GAP end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function FormatLastSeen(t)
    if not t or t == 0 then return "-" end
    local d = math.floor((time() - t) / 86400)
    if d < 1 then return "Today" end
    if d < 7  then return d .. "d ago" end
    return d .. "d ago (!)"
end

local function FormatGoldShort(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return g .. "g " .. s .. "s" end
    if s > 0 then return s .. "s " .. c .. "c" end
    return c .. "c"
end

local function GetSortValue(data, charName, key)
    if key == "name"  then return charName:lower() end
    if key == "level" then return data.level or 0 end
    if key == "ilvl"  then return data.ilvl  or 0 end
    if key == "gold"  then return data.gold  or 0 end
    if key == "honor" then return data.honor or 0 end
    if key == "arena" then return data.arena or 0 end
    if key == "runes" then return data.runes or 0 end
    if key == "seen"  then return data.lastSeen or 0 end
    if key == "items" then
        local n = 0
        for _ in pairs(data.items or {}) do n = n + 1 end
        return n
    end
    return 0
end

local function Dash(n)
    return (n and n > 0) and tostring(n) or "-"
end

-------------------------------------------------------------------------------
-- Panel — built inside a function called from OnCoreReady
-- so cfg is guaranteed to exist before any frame code runs
-------------------------------------------------------------------------------

local panel       = nil
local headerBtns  = {}
local rowPool     = {}
local activeRows  = {}
local realmText   = nil
local footerLeft  = nil
local footerRight = nil
local footerSep   = nil

local function BuildPanel()
    if panel then return end  -- already built

    local cfg = ATA.cfg and ATA.cfg.panel
    if not cfg then
        print("|cffff4444ApeTracksAlts|r Panel error: cfg.panel is nil")
        return
    end

    -- Main frame
    panel = CreateFrame("Frame", "ATAPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(PANEL_W)
    panel:SetHeight(200)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        cfg.x = math.floor(self:GetLeft() or 0)
        cfg.y = math.floor((self:GetTop() or 0) - UIParent:GetHeight())
    end)

    -- Background using solid textures — no SetBackdrop needed
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    bg:SetAlpha(0.95)

    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetAllPoints(panel)
    edge:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")

    -- Title
    local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -6)
    titleText:SetTextColor(0.2, 1, 0.2)
    titleText:SetText("ApeTracksAlts")

    realmText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    realmText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -28, -8)
    realmText:SetJustifyH("RIGHT")
    realmText:SetText("")

    local titleSep = panel:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  -TITLE_H)
    titleSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -TITLE_H)
    titleSep:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetWidth(24)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
        cfg.visible = false
    end)

    -- Column headers
    local x = 0
    for i, col in ipairs(COL) do
        local btn = CreateFrame("Button", nil, panel)
        btn:SetWidth(col.width)
        btn:SetHeight(HEADER_H)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + x, -(TITLE_H + 2))

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetAllPoints()
        local j = col.align == "CENTER" and "CENTER" or (col.align == "RIGHT" and "RIGHT" or "LEFT")
        fs:SetJustifyH(j)
        fs:SetText(col.label)
        btn.fs = fs

        btn:SetScript("OnClick", function()
            if cfg.sortCol == col.key then
                cfg.sortDesc = not cfg.sortDesc
            else
                cfg.sortCol  = col.key
                cfg.sortDesc = (col.key ~= "name")
            end
            ATA.PanelRefresh()
        end)
        btn:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
        btn:SetScript("OnLeave", function() ATA.PanelRefresh() end)

        headerBtns[i] = btn
        x = x + col.width + COL_GAP
    end

    local headerSep = panel:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  -(TITLE_H + HEADER_H + 2))
    headerSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(TITLE_H + HEADER_H + 2))
    headerSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Footer elements
    footerSep = panel:CreateTexture(nil, "ARTWORK")
    footerSep:SetHeight(1)
    footerSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    footerLeft = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerLeft:SetJustifyH("LEFT")

    footerRight = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerRight:SetJustifyH("RIGHT")

    panel:Hide()
end

-------------------------------------------------------------------------------
-- Row pool
-------------------------------------------------------------------------------

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_H)
        row.cells = {}
        local x = 0
        for i, col in ipairs(COL) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(col.width)
            fs:SetHeight(ROW_H)
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            local j = col.align == "CENTER" and "CENTER" or (col.align == "RIGHT" and "RIGHT" or "LEFT")
            fs:SetJustifyH(j)
            row.cells[i] = fs
            x = x + col.width + COL_GAP
        end
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)
        hl:Hide()
        row.hl = hl
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self) self.hl:Show() end)
        row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    end
    row:Show()
    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    table.insert(rowPool, row)
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

function ATA.PanelRefresh()
    if not panel or not panel:IsShown() then return end
    if not ATA.realm then return end

    local cfg = ATA.cfg.panel
    local realmDB = ApeTracksAltsDB[ATA.realm] or {}
    if realmText then realmText:SetText(ATA.realm) end

    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    activeRows = {}

    local pinned, others = {}, {}
    for charName, data in pairs(realmDB) do
        if charName == ATA.player then
            table.insert(pinned, { name = charName, data = data })
        else
            table.insert(others, { name = charName, data = data })
        end
    end

    table.sort(others, function(a, b)
        local av = GetSortValue(a.data, a.name, cfg.sortCol)
        local bv = GetSortValue(b.data, b.name, cfg.sortCol)
        if av == bv then return a.name < b.name end
        return cfg.sortDesc and (av > bv) or (av < bv)
    end)

    local sorted = {}
    for _, e in ipairs(pinned) do table.insert(sorted, e) end
    for _, e in ipairs(others) do table.insert(sorted, e) end

    local topY = -(TITLE_H + HEADER_H + 6)
    local totalGold, totalItems = 0, 0

    for _, entry in ipairs(sorted) do
        local cn      = entry.name
        local d       = entry.data
        local isSelf  = (cn == ATA.player)
        local isStale = ATA.IsStale(d)

        local itemCount = 0
        for _ in pairs(d.items or {}) do itemCount = itemCount + 1 end

        local nameStr
        if isSelf then
            nameStr = "[*] " .. cn
        elseif isStale then
            nameStr = cn .. " [!]"
        else
            nameStr = cn
        end

        local vals = {
            nameStr,
            tostring(d.level or 0),
            (d.ilvl and d.ilvl > 0) and tostring(d.ilvl) or "-",
            FormatGoldShort(d.gold),
            Dash(d.honor),
            Dash(d.arena),
            Dash(d.runes),
            tostring(itemCount),
            FormatLastSeen(d.lastSeen),
        }

        local row = AcquireRow()
        row:SetWidth(PANEL_W - PAD * 2)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, topY)
        for i, fs in ipairs(row.cells) do
            fs:SetText(vals[i] or "")
            fs:SetAlpha(isStale and 0.5 or 1.0)
        end

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
        footerLeft:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  footY - 4)
        footerLeft:SetText("Gold: " .. FormatGoldShort(totalGold))
    end
    if footerRight then
        footerRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, footY - 4)
        footerRight:SetText("Items: " .. totalItems)
    end

    -- Header sort indicators
    for i, btn in ipairs(headerBtns) do
        local col = COL[i]
        if col.key == cfg.sortCol then
            btn.fs:SetTextColor(1, 0.82, 0)
            btn.fs:SetText(col.label .. (cfg.sortDesc and " v" or " ^"))
        else
            btn.fs:SetTextColor(0.75, 0.75, 0.75)
            btn.fs:SetText(col.label)
        end
    end

    -- Resize to fit
    local h = TITLE_H + HEADER_H + (#sorted * ROW_H) + FOOTER_H + PAD * 2 + 14
    panel:SetHeight(h)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function ApeTracksAlts.PanelShow()
    if not panel then BuildPanel() end
    if not panel then return end
    panel:Show()
    ATA.cfg.panel.visible = true
    ATA.PanelRefresh()
end

function ApeTracksAlts.PanelHide()
    if panel then panel:Hide() end
    ATA.cfg.panel.visible = false
end

function ApeTracksAlts.PanelToggle()
    if panel and panel:IsShown() then
        ApeTracksAlts.PanelHide()
    else
        ApeTracksAlts.PanelShow()
    end
end

ATA.OnDataChanged = function()
    if panel and panel:IsShown() then
        ATA.PanelRefresh()
    end
end

ATA.OnCoreReady = function()
    BuildPanel()
    if ATA.cfg and ATA.cfg.panel and ATA.cfg.panel.visible then
        ApeTracksAlts.PanelShow()
    end
end