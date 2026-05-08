-- ApeTracksAlts | Minimap.lua
-- Minimap button using the same construction as LibGPIMinimapButton.
-- Left-click: toggle panel. Right-click: /ata help.

print("|cff00ff00ApeTracksAlts|r Minimap.lua executing...")

local ATA = ApeTracksAlts

local MinimapBtn = CreateFrame("Button", "ATAMinimapButton", Minimap)
MinimapBtn:SetFrameStrata("MEDIUM")
MinimapBtn:SetWidth(31)
MinimapBtn:SetHeight(31)
MinimapBtn:SetFrameLevel(8)
MinimapBtn:RegisterForClicks("anyUp")
MinimapBtn:RegisterForDrag("LeftButton")
MinimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Textures in exact same order and position as LibGPIMinimapButton
local mmOverlay = MinimapBtn:CreateTexture(nil, "OVERLAY")
mmOverlay:SetWidth(53)
mmOverlay:SetHeight(53)
mmOverlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmOverlay:SetPoint("TOPLEFT")

local mmBg = MinimapBtn:CreateTexture(nil, "BACKGROUND")
mmBg:SetWidth(20)
mmBg:SetHeight(20)
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetPoint("TOPLEFT", 7, -5)

local mmIcon = MinimapBtn:CreateTexture(nil, "ARTWORK")
mmIcon:SetWidth(17)
mmIcon:SetHeight(17)
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
mmIcon:SetPoint("TOPLEFT", 7, -6)

-- Tooltip
MinimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, 0)
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cff00ff00ApeTracksAlts|r")
    GameTooltip:AddLine("Left-click: Toggle panel", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Help", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
MinimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Clicks
MinimapBtn:SetScript("OnClick", function(self, btn)
    GameTooltip:Hide()
    if btn == "LeftButton" then
        if ApeTracksAlts.PanelToggle then ApeTracksAlts.PanelToggle() end
    elseif btn == "RightButton" then
        if SlashCmdList["APETRACKSALTS"] then SlashCmdList["APETRACKSALTS"]("") end
    end
end)

-- Drag to reposition
MinimapBtn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
        local cx, cy   = GetCursorPosition()
        local scale    = Minimap:GetEffectiveScale()
        local mx, my   = Minimap:GetCenter()
        -- Both cursor and center must use the same scale
        local dx = (cx / scale) - mx
        local dy = (cy / scale) - my
        local pos = math.deg(math.atan2(dy, dx)) % 360
        ApeTracksAltsCfg.minimap = ApeTracksAltsCfg.minimap or {}
        ApeTracksAltsCfg.minimap.position = pos
        UpdateMinimapPos()
    end)
end)

MinimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
    -- Final position commit on drag end
    local cx, cy = GetCursorPosition()
    local scale  = Minimap:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    local pos    = math.deg(math.atan2((cy/scale)-my, (cx/scale)-mx)) % 360
    -- Write directly to the global saved variable so it persists to disk
    if not ApeTracksAltsCfg.minimap then ApeTracksAltsCfg.minimap = {} end
    ApeTracksAltsCfg.minimap.position = pos
    UpdateMinimapPos()
    print(string.format("|cff00ff00ApeTracksAlts|r Minimap position saved: %.1f", pos))
end)

-- Position function — mirrors LibGPIMinimapButton.UpdatePosition
function UpdateMinimapPos()
    local cfg   = ApeTracksAltsCfg and ApeTracksAltsCfg.minimap
    local pos   = (cfg and cfg.position) or 225
    local w     = (Minimap:GetWidth()  / 2) + 10
    local h     = (Minimap:GetHeight() / 2) + 10
    local angle = math.rad(pos)
    MinimapBtn:ClearAllPoints()
    MinimapBtn:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * w,
        math.sin(angle) * h)
end

function ATA.MinimapShow()
    ApeTracksAltsCfg.minimap = ApeTracksAltsCfg.minimap or {}
    ApeTracksAltsCfg.minimap.hide = false
    UpdateMinimapPos()
    MinimapBtn:Show()
end

function ATA.MinimapHide()
    ApeTracksAltsCfg.minimap = ApeTracksAltsCfg.minimap or {}
    ApeTracksAltsCfg.minimap.hide = true
    MinimapBtn:Hide()
end

-- Initial state — defer position restore until OnCoreReady so
-- ApeTracksAltsCfg is fully loaded from disk before we read it
local mmFrame = CreateFrame("Frame")
mmFrame:RegisterEvent("PLAYER_LOGIN")
mmFrame:SetScript("OnEvent", function()
    local mmCfg = ApeTracksAltsCfg and ApeTracksAltsCfg.minimap
    if mmCfg and mmCfg.hide then
        MinimapBtn:Hide()
    else
        UpdateMinimapPos()
        MinimapBtn:Show()
    end
    mmFrame:UnregisterEvent("PLAYER_LOGIN")
end)

print("|cff00ff00ApeTracksAlts|r Minimap button initialized")
