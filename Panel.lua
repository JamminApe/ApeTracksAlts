-- ApeTracksAlts | Panel.lua
print("|cff00ff00ApeTracksAlts|r Panel.lua executing...")

local ATA = ApeTracksAlts
print("|cff00ff00ApeTracksAlts|r ATA = " .. tostring(ATA))

local panel = nil

function ApeTracksAlts.PanelShow()
    print("|cff00ff00ApeTracksAlts|r PanelShow called")
    if not panel then
        print("|cff00ff00ApeTracksAlts|r Creating frame...")
        panel = CreateFrame("Frame", "ATAPanel", UIParent)
        panel:SetWidth(300)
        panel:SetHeight(150)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")

        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.9)

        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("CENTER")
        t:SetText("|cff00ff00ApeTracksAlts|r")

        print("|cff00ff00ApeTracksAlts|r Frame created: " .. tostring(panel))
    end
    panel:Show()
    print("|cff00ff00ApeTracksAlts|r IsShown: " .. tostring(panel:IsShown()))
end

function ApeTracksAlts.PanelHide()
    if panel then panel:Hide() end
end

function ApeTracksAlts.PanelToggle()
    if panel and panel:IsShown() then
        ApeTracksAlts.PanelHide()
    else
        ApeTracksAlts.PanelShow()
    end
end

function ATA.PanelRefresh() end
ATA.OnDataChanged = function() end
ATA.OnCoreReady = function()
    print("|cff00ff00ApeTracksAlts|r OnCoreReady fired")
end

print("|cff00ff00ApeTracksAlts|r Panel.lua done, PanelShow=" .. tostring(ApeTracksAlts.PanelShow))