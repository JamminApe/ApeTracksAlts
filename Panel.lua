-- ApeTracksAlts | Panel.lua

local ATA = ApeTracksAlts

local panel = nil

local function BuildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "ATAPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(400)
    panel:SetHeight(200)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -10)
    title:SetTextColor(0.2, 1, 0.2)
    title:SetText("ApeTracksAlts")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        panel:Hide()
        if ATA.cfg and ATA.cfg.panel then
            ATA.cfg.panel.visible = false
        end
    end)

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("CENTER", panel, "CENTER", 0, 0)
    info:SetText("Panel loading...")
    panel.infoText = info

    panel:Hide()
    print("|cff00ff00ApeTracksAlts|r Panel frame created OK")
end

function ATA.PanelRefresh()
    if not panel or not panel:IsShown() then return end
    if not ATA.realm then return end
    local realmDB = ApeTracksAltsDB[ATA.realm] or {}
    local lines = {}
    for charName, data in pairs(realmDB) do
        table.insert(lines, charName .. " — Lvl " .. (data.level or 0) .. " — " .. math.floor((data.gold or 0)/10000) .. "g")
    end
    if panel.infoText then
        panel.infoText:SetText(table.concat(lines, "\n"))
    end
end

function ApeTracksAlts.PanelShow()
    print("|cff00ff00ApeTracksAlts|r PanelShow called")
    if not panel then BuildPanel() end
    if not panel then
        print("|cffff4444ApeTracksAlts|r panel still nil after BuildPanel")
        return
    end
    panel:Show()
    if ATA.cfg and ATA.cfg.panel then
        ATA.cfg.panel.visible = true
    end
    ATA.PanelRefresh()
    print("|cff00ff00ApeTracksAlts|r panel:Show() called, IsShown=" .. tostring(panel:IsShown()))
end

function ApeTracksAlts.PanelHide()
    if panel then panel:Hide() end
    if ATA.cfg and ATA.cfg.panel then
        ATA.cfg.panel.visible = false
    end
end

function ApeTracksAlts.PanelToggle()
    if panel and panel:IsShown() then
        ApeTracksAlts.PanelHide()
    else
        ApeTracksAlts.PanelShow()
    end
end

ATA.OnDataChanged = function()
    ATA.PanelRefresh()
end

ATA.OnCoreReady = function()
    print("|cff00ff00ApeTracksAlts|r OnCoreReady fired")
    BuildPanel()
    if ATA.cfg and ATA.cfg.panel and ATA.cfg.panel.visible then
        ApeTracksAlts.PanelShow()
    end
end

print("|cff00ff00ApeTracksAlts|r Panel.lua loaded, PanelShow=" .. tostring(ApeTracksAlts.PanelShow))