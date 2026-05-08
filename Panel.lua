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
    { key="honor", label="Honor",     width=56,  align="RIGHT"  },
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

local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE  = 14

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

        -- Set scripts ONCE on creation — always read from self at hover time
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            local hasLocks = self.lockouts and #self.lockouts > 0
            local hasProfs = self.professions and #self.professions > 0
            local hasN     = self.charNotes and #self.charNotes > 0
            if not hasLocks and not hasProfs and not hasN then
                GameTooltip:Hide()
                return
            end
            -- Always re-anchor to THIS row so tooltip follows as you move between rows
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ATA.ColorName(self.charName, self.charClass))
            if hasN then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffff00Notes:|r")
                for i, text in ipairs(self.charNotes) do
                    if #text <= 50 then
                        GameTooltip:AddLine(string.format("  [%d] %s", i, text), 1, 1, 1)
                    else
                        GameTooltip:AddLine(string.format("  [%d] %s", i, text:sub(1, 50)), 1, 1, 1)
                        local remaining = text:sub(51)
                        while #remaining > 0 do
                            GameTooltip:AddLine("      "..remaining:sub(1,50), 1, 1, 1)
                            remaining = remaining:sub(51)
                        end
                    end
                end
            end
            if hasLocks then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffff00Lockouts:|r")
                for _, lock in ipairs(self.lockouts) do
                    local remaining = lock.expires - time()
                    if remaining > 0 then
                        local h = math.floor(remaining / 3600)
                        local m = math.floor((remaining % 3600) / 60)
                        GameTooltip:AddLine(string.format("  %s  %dh %dm", lock.name, h, m), 1, 0.5, 0.5)
                    end
                end
            end
            if hasProfs then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffff00Professions:|r")
                for _, p in ipairs(self.professions) do
                    GameTooltip:AddLine(string.format("  %s  %d/%d", p.name, p.rank, p.maxRank), 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:Show()
        end)
        -- Only hide tooltip when mouse leaves the row AND doesn't enter another row
        -- We use the panel's OnLeave to do the final hide instead
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
        end)
    end

    row:Show()
    -- Reset per-refresh data
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
        GameTooltip:Hide()
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

    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    activeRows = {}

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
        if cfg.sortDesc then
            return av > bv
        else
            return av < bv
        end
    end)

    local sorted = {}
    for _,e in ipairs(pinned) do table.insert(sorted, e) end
    for _,e in ipairs(others) do table.insert(sorted, e) end

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
        -- Pencil icon LEFT of name if note exists
        local prefix = hasNote and "|cffffff00*|r " or "  "
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
    -- Don't refresh while hovering a row — would destroy the open tooltip
    if GameTooltip:IsShown() and GameTooltip:GetOwner() and
       GameTooltip:GetOwner():GetParent() == panel then
        return
    end
    ATA.PanelRefresh()
end

ATA.OnCoreReady = function()
    BuildPanel()
    -- Open panel on login if loginOpen is enabled (default: true)
    local loginOpen = ApeTracksAltsCfg and ApeTracksAltsCfg.loginOpen
    if loginOpen == nil then loginOpen = true end
    if loginOpen then
        ApeTracksAlts.PanelShow()
    end
end
