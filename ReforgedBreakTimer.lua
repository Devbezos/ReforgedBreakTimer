local addonName, ns = ...

local FALLBACK_IMAGE = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACCENT_COLOR = { 0.20, 0.85, 0.35 }

ns.images = ns.images or {} -- populated by Images.lua

local currentImagePath
local endTime = 0
local wasBreakActive = false
local imageSwitchInterval = 0
local nextImageSwitchTime = 0

--------------------------------------------------------------------------
-- Image selection
--------------------------------------------------------------------------

-- Returns the list of images the user has not disabled in the options panel.
function ns.GetEnabledImages()
    local enabled = {}
    for _, entry in ipairs(ns.images) do
        if not ReforgedBreakTimerDB.disabledImages[entry.path] then
            enabled[#enabled + 1] = entry
        end
    end
    return enabled
end

function ns.IsImageEnabled(path)
    return not ReforgedBreakTimerDB.disabledImages[path]
end

function ns.SetImageEnabled(path, isEnabled)
    if isEnabled then
        ReforgedBreakTimerDB.disabledImages[path] = nil
    else
        ReforgedBreakTimerDB.disabledImages[path] = true
    end
end

function ns.SetAllImagesEnabled(isEnabled)
    for _, entry in ipairs(ns.images) do
        ns.SetImageEnabled(entry.path, isEnabled)
    end
end

function ns.ChooseRandomImage()
    local enabled = ns.GetEnabledImages()

    if #enabled == 0 then
        currentImagePath = nil
        ReforgedBreakTimerFrame.image:SetTexture(FALLBACK_IMAGE)
        return
    end

    local choice = enabled[math.random(#enabled)]
    if #enabled > 1 and choice.path == currentImagePath then
        -- Avoid showing the same picture twice in a row when there's a choice.
        local others = {}
        for _, entry in ipairs(enabled) do
            if entry.path ~= currentImagePath then
                others[#others + 1] = entry
            end
        end
        choice = others[math.random(#others)]
    end

    currentImagePath = choice.path
    ReforgedBreakTimerFrame.image:SetTexture(choice.path)
end

--------------------------------------------------------------------------
-- Frame position persistence
--------------------------------------------------------------------------

local function saveFramePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    ReforgedBreakTimerDB.framePos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function ns.ResetFramePosition()
    local frame = ReforgedBreakTimerFrame
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    ReforgedBreakTimerDB.framePos = nil
end

--------------------------------------------------------------------------
-- Break display
--------------------------------------------------------------------------

local function formatTime(seconds)
    seconds = math.max(0, seconds)
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d", minutes, remainder)
end

local function updateDisplay(remaining, total)
    ReforgedBreakTimerFrame.time:SetText(formatTime(remaining))
    local progress = total > 0 and (total - remaining) / total or 0
    ReforgedBreakTimerFrame.progressBar:SetValue(progress)
end

-- Runs every ~0.2s while the frame is shown (WoW skips OnUpdate on hidden frames).
local function onBreakUpdate(self, elapsed)
    self.tick = (self.tick or 0) + elapsed
    if self.tick < 0.2 then
        return
    end
    self.tick = 0

    local remaining = endTime - GetTime()
    if remaining <= 0 then
        ns.HideBreak()
        return
    end
    updateDisplay(remaining, self.totalDuration)

    if imageSwitchInterval > 0 and GetTime() >= nextImageSwitchTime then
        ns.ChooseRandomImage()
        nextImageSwitchTime = GetTime() + imageSwitchInterval
    end
end

-- Shows the break frame with a random image and starts its countdown.
-- `remaining`/`total` are seconds, as reported by BigWigs.
function ns.ShowBreak(remaining, total)
    local frame = ReforgedBreakTimerFrame
    endTime = GetTime() + remaining
    frame.totalDuration = total
    frame.tick = 0

    -- Cycle through every enabled picture over the course of the break,
    -- roughly once each: switch interval = break length / picture count.
    local enabledCount = #ns.GetEnabledImages()
    if enabledCount > 1 and total > 0 then
        imageSwitchInterval = math.max(2, total / enabledCount)
        nextImageSwitchTime = GetTime() + imageSwitchInterval
    else
        imageSwitchInterval = 0
    end

    ns.ChooseRandomImage()
    frame.status:SetText("Break in progress")
    updateDisplay(remaining, total)
    frame:Show()
    frame:Raise()
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

function ns.HideBreak()
    local frame = ReforgedBreakTimerFrame
    frame:Hide()
    frame.status:SetText("Waiting for next break")
    imageSwitchInterval = 0
end

--------------------------------------------------------------------------
-- BigWigs break detection
--------------------------------------------------------------------------
-- BigWigs_Plugins/Break.lua stores the active break in BigWigs3DB.breakTime:
--   { time(), totalSeconds, nick, isDBM }
-- BigWigs writes this the instant a break starts, so any lag between its bar
-- appearing and ours is purely how often we poll -- poll fast (5x/sec) so the
-- popup and countdown stay tight to BigWigs' own timing instead of trailing
-- by up to a full second. No AceEvent dependency, no load-order issues.

local function checkBreak()
    local tbl = BigWigs3DB and BigWigs3DB.breakTime
    if tbl then
        local startTime, totalSeconds = tbl[1], tbl[2]
        local remaining = totalSeconds - (time() - startTime)
        if remaining > 0 then
            if not wasBreakActive then
                wasBreakActive = true
                ns.ShowBreak(remaining, totalSeconds)
            end
            return
        end
    end

    if wasBreakActive then
        wasBreakActive = false
        ns.HideBreak()
    end
end

--------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------

local function createFrame()
    local frame = CreateFrame("Frame", "ReforgedBreakTimerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 210)
    frame:SetPoint("CENTER", 0, 100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePosition(self)
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.06, 0.08, 1)
    frame:SetBackdropBorderColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -6, -6)
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

    frame.optionsButton = CreateFrame("Button", nil, frame)
    frame.optionsButton:SetSize(20, 20)
    frame.optionsButton:SetPoint("RIGHT", frame.closeButton, "LEFT", 2, 0)
    frame.optionsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    frame.optionsButton:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
    frame.optionsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.optionsButton:SetScript("OnClick", function() ns.OpenOptions() end)
    frame.optionsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reforged Break Timer Options")
        GameTooltip:Show()
    end)
    frame.optionsButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Image display
    frame.imageBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.imageBorder:SetSize(178, 178)
    frame.imageBorder:SetPoint("TOPLEFT", 16, -16)
    frame.imageBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    frame.imageBorder:SetBackdropBorderColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)

    frame.image = frame.imageBorder:CreateTexture(nil, "ARTWORK")
    frame.image:SetPoint("TOPLEFT", 4, -4)
    frame.image:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.image:SetTexture(FALLBACK_IMAGE)

    -- Time + status
    frame.time = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    frame.time:SetPoint("TOPLEFT", 210, -30)
    frame.time:SetTextColor(1, 1, 1)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.status:SetPoint("TOPLEFT", 210, -70)
    frame.status:SetTextColor(0.72, 0.76, 0.8)
    frame.status:SetText("Waiting for next break")

    -- Progress bar
    frame.progressBar = CreateFrame("StatusBar", nil, frame)
    frame.progressBar:SetPoint("TOPLEFT", 210, -100)
    frame.progressBar:SetSize(194, 16)
    frame.progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progressBar:SetStatusBarColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)
    frame.progressBar:SetMinMaxValues(0, 1)
    frame.progressBar:SetValue(0)

    frame.progressBarBg = frame.progressBar:CreateTexture(nil, "BACKGROUND")
    frame.progressBarBg:SetAllPoints()
    frame.progressBarBg:SetColorTexture(0, 0, 0, 0.5)

    frame:SetScript("OnUpdate", onBreakUpdate)

    return frame
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end

    ReforgedBreakTimerDB = ReforgedBreakTimerDB or {}
    ReforgedBreakTimerDB.disabledImages = ReforgedBreakTimerDB.disabledImages or {}

    local frame = createFrame()

    if ReforgedBreakTimerDB.framePos then
        local pos = ReforgedBreakTimerDB.framePos
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 100)
    end

    -- Stay out of the way until BigWigs actually calls a break; the frame
    -- only appears on its own when checkBreak() detects one.
    frame:Hide()

    C_Timer.NewTicker(0.2, checkBreak)
end)
