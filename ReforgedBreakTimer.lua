local addonName, ns = ...

local FALLBACK_IMAGE = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACCENT_COLOR = { 0.20, 0.85, 0.35 }
local IMAGE_SIZE = 267 -- also the frame's width, so there's no side padding
local TOP_ROW_HEIGHT = 40 -- room above the image for the close/next-image buttons
local BUTTON_INSET = 6 -- keeps those buttons inside the box instead of flush on its edge
local PROGRESS_BAR_HEIGHT = 28

ns.images = ns.images or {} -- populated by Images.lua

local currentImagePath
local endTime = 0
local wasBreakActive = false

-- The (startTime, totalSeconds) pair from BigWigs3DB.breakTime that the poll
-- fallback last acted on, so it can tell a genuinely new/extended break
-- (BigWigs overwriting that table with new values while one's already
-- showing -- e.g. someone re-calling the break for a longer duration) apart
-- from re-polling the same still-active break tick after tick.
local lastPolledBreakStart, lastPolledBreakTotal

-- Shuffled "bag" of not-yet-shown images for the current cycle -- refilled
-- and reshuffled once it runs dry, so every enabled picture gets shown
-- once before any of them repeat, instead of a pure random pick that could
-- skip some entirely while repeating others.
local imageQueue = {}

-- Playback state for the current image, when it's an animated (GIF-sourced)
-- one: { entry = imageEntry, delay = secondsPerFrame, frameIndex, elapsed }.
-- nil whenever the current image is a plain static picture.
local currentAnimation

--------------------------------------------------------------------------
-- Image selection
--------------------------------------------------------------------------

-- An animated (GIF-sourced) image ships as a single sprite sheet: every
-- frame tiled left-to-right, top-to-bottom into a `columns` x `rows` grid
-- (see ConvertImages.ps1). Playback only moves the texcoords around that
-- one texture. Switching between dozens of separate frame files instead
-- made WoW stream each one in on demand, which is what showed up as
-- flicker no matter how they were preloaded.
--
-- Returns the (left, right, top, bottom) texcoords of 1-based frame `index`.
function ns.GetFrameTexCoords(entry, index)
    local column = (index - 1) % entry.columns
    local row = math.floor((index - 1) / entry.columns)
    -- Pulled in by half a texel so bilinear filtering never bleeds in an
    -- edge of the neighbouring cell.
    local insetU = 0.5 / (entry.columns * entry.frameWidth)
    local insetV = 0.5 / (entry.rows * entry.frameHeight)
    return column / entry.columns + insetU, (column + 1) / entry.columns - insetU,
        row / entry.rows + insetV, (row + 1) / entry.rows - insetV
end

-- Keeps every sprite sheet assigned to a tiny on-screen texture ahead of
-- time, so it's already loaded when a break picks it rather than
-- streaming in during the first moments of playback. These have to actually
-- be drawn -- an alpha 0 or hidden texture can skip the load entirely --
-- hence the near-invisible (but non-zero) alpha.
--
-- The sheets are big (several MB of video memory each), so they're only
-- held while a raid break can actually come up -- in a raid -- or while the
-- options panel is open, where Preview shows them. The rest of the time
-- the textures are cleared so the game can let them go.
local sheetPreloads = {}
local sheetsLoaded = false
local optionsOpen = false

local function updateSheetPreloads()
    local shouldLoad = IsInRaid() or optionsOpen
    if shouldLoad == sheetsLoaded then
        return
    end
    sheetsLoaded = shouldLoad
    for _, tex in ipairs(sheetPreloads) do
        tex:SetTexture(shouldLoad and tex.path or nil)
    end
end

local function createSheetPreloads()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(4, 4)
    holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -2, 2)
    holder:SetAlpha(0.02)

    for _, entry in ipairs(ns.images) do
        if entry.frames then
            local tex = holder:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            tex.path = entry.path
            sheetPreloads[#sheetPreloads + 1] = tex
        end
    end

    holder:RegisterEvent("GROUP_ROSTER_UPDATE")
    holder:RegisterEvent("PLAYER_ENTERING_WORLD")
    holder:SetScript("OnEvent", updateSheetPreloads)
end

-- Called by the options panel as it opens and closes.
function ns.SetOptionsOpen(isOpen)
    optionsOpen = isOpen
    updateSheetPreloads()
end

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

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

-- Refills imageQueue with every enabled image in a fresh random order.
local function refillImageQueue(enabled)
    imageQueue = {}
    for _, entry in ipairs(enabled) do
        imageQueue[#imageQueue + 1] = entry
    end
    shuffle(imageQueue)

    -- Images are popped off the end of the queue; avoid the picture that
    -- just finished the previous cycle immediately repeating as the first
    -- pick of this one.
    local last = #imageQueue
    if last > 1 and imageQueue[last].path == currentImagePath then
        local swapWith = math.random(last - 1)
        imageQueue[last], imageQueue[swapWith] = imageQueue[swapWith], imageQueue[last]
    end
end

local function displayImage(entry)
    currentImagePath = entry.path

    local image = ReforgedBreakTimerFrame.image
    image:SetTexture(entry.path)

    if entry.frames then
        -- Animated (GIF-sourced) image: play its frames in a loop, starting
        -- from the first one. See advanceAnimation, driven from onBreakUpdate.
        currentAnimation = {
            entry = entry,
            delay = math.max(entry.delay or 0.1, 0.02),
            frameIndex = 1,
            elapsed = 0,
        }
        image:SetTexCoord(ns.GetFrameTexCoords(entry, 1))
    else
        currentAnimation = nil
        image:SetTexCoord(0, 1, 0, 1)
    end
end


function ns.ChooseRandomImage()
    local enabled = ns.GetEnabledImages()

    if #enabled == 0 then
        currentImagePath = nil
        currentAnimation = nil
        imageQueue = {}
        ReforgedBreakTimerFrame.image:SetTexture(FALLBACK_IMAGE)
        ReforgedBreakTimerFrame.image:SetTexCoord(0, 1, 0, 1)
        return
    end

    -- Drop any queued image that got disabled since it was queued.
    for i = #imageQueue, 1, -1 do
        if ReforgedBreakTimerDB.disabledImages[imageQueue[i].path] then
            table.remove(imageQueue, i)
        end
    end

    if #imageQueue == 0 then
        refillImageQueue(enabled)
    end

    displayImage(table.remove(imageQueue))
end

-- Steps any currently-playing GIF animation forward by `elapsed` seconds,
-- looping back to the first frame once it reaches the end. A no-op when the
-- current image is a static picture (currentAnimation is nil).
local function advanceAnimation(elapsed)
    local anim = currentAnimation
    if not anim then
        return
    end

    anim.elapsed = anim.elapsed + elapsed
    local changed = false
    while anim.elapsed >= anim.delay do
        anim.elapsed = anim.elapsed - anim.delay
        anim.frameIndex = (anim.frameIndex % anim.entry.frames) + 1
        changed = true
    end

    if changed then
        ReforgedBreakTimerFrame.image:SetTexCoord(ns.GetFrameTexCoords(anim.entry, anim.frameIndex))
    end
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

function ns.GetFrameScale()
    return ReforgedBreakTimerDB.frameScale or 1
end

-- Rescales the popup around its current center, rather than letting it
-- drift (position offsets are in the frame's own, scaled, units).
function ns.SetFrameScale(scale)
    local frame = ReforgedBreakTimerFrame
    local oldScale = frame:GetScale()
    local centerX, centerY = frame:GetCenter()

    frame:SetScale(scale)
    ReforgedBreakTimerDB.frameScale = scale

    if centerX then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX * oldScale / scale, centerY * oldScale / scale)
        saveFramePosition(frame)
    end
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

-- Runs every rendered frame while the break frame is shown (WoW skips
-- OnUpdate on hidden frames). GIF playback needs that full granularity --
-- typical frame delays are well under 0.2s -- so it's driven unconditionally
-- here; the countdown text/progress bar below is still only refreshed
-- every ~0.2s since that's plenty for a once-a-second display.
local function onBreakUpdate(self, elapsed)
    advanceAnimation(elapsed)

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
end

-- Shows the break frame with a random image and starts its countdown. The
-- image stays static for the whole break unless someone hits the
-- next-image button. `remaining`/`total` are seconds, as reported by BigWigs.
function ns.ShowBreak(remaining, total)
    local frame = ReforgedBreakTimerFrame
    endTime = GetTime() + remaining
    frame.totalDuration = total
    frame.tick = 0

    ns.ChooseRandomImage()
    updateDisplay(remaining, total)
    frame:Show()
    frame:Raise()
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

function ns.HideBreak()
    local frame = ReforgedBreakTimerFrame
    frame:Hide()
end

function ns.IsBreakPopupEnabled()
    return ReforgedBreakTimerDB.breakPopup and true or false
end

-- The next-image button.
function ns.ShowNextImage()
    ns.ChooseRandomImage()
end

--------------------------------------------------------------------------
-- BigWigs break detection
--------------------------------------------------------------------------
-- Primary path: BigWigs' Break plugin fires "BigWigs_StartBreak" /
-- "BigWigs_StopBreak" on its message bus the instant a break starts/ends,
-- with full GetTime()-precision duration -- no rounding, no polling lag,
-- so our countdown starts in the same tick as BigWigs' own bar.
--
-- Fallback path: BigWigs_Plugins/Break.lua also stores the active break in
-- BigWigs3DB.breakTime: { time(), totalSeconds, nick, isDBM }. That's read
-- once at load, to pick up a break that was already running before we
-- hooked in (e.g. after a /reload), and polled (5x/sec) only if the message
-- path isn't reachable at all. It has whole-second precision (time(), not
-- GetTime()), so it's the one place a ~1s offset from BigWigs' own bar can
-- still show up.

-- When the break in progress ends (GetTime() based) and how long it was in
-- total, kept even with the popup switched off so turning it back on
-- mid-break can still show the right countdown.
local breakEndsAt, breakTotal = 0, 0

-- Set when the popup's close button is used during a real break: the popup
-- stays closed for the rest of that break and BigWigs' bar comes back, so
-- there's always a timer on screen. Cleared by the next break, or by
-- switching "Show break popup" back on.
local popupDismissed = false

-- BigWigs' Break plugin, the text of the bar it last started and the full
-- BigWigs_StartBar arguments it used, so the hide-bar option can stop that
-- exact bar -- and start it up again when the option (or the popup) is
-- switched back off mid-break.
local breakPlugin, breakBarText
local breakBarArgs, breakBarArgCount
local barHiddenByUs = false

-- Sends a message on whichever bus hookBigWigsMessages() registered with.
local sendBigWigsMessage

-- BigWigs' bar only goes away while our popup is there to replace it.
local function shouldHideBigWigsBar()
    return wasBreakActive and not popupDismissed
        and ns.IsBreakPopupEnabled() and ns.IsHideBigWigsBreakBarEnabled()
end

local function stopBigWigsBreakBar()
    if barHiddenByUs or not (sendBigWigsMessage and breakPlugin and breakBarText) then
        return
    end
    barHiddenByUs = true
    sendBigWigsMessage("BigWigs_StopBar", breakPlugin, breakBarText)
end

-- Replays the Break plugin's own BigWigs_StartBar with the time left now.
local function restoreBigWigsBreakBar(remaining)
    if not (barHiddenByUs and sendBigWigsMessage and breakBarArgs) then
        return
    end
    barHiddenByUs = false
    local count = math.max(breakBarArgCount, 4)
    local args = { unpack(breakBarArgs, 1, count) }
    args[4] = remaining -- (module, key, text, time, icon, ...)
    sendBigWigsMessage("BigWigs_StartBar", unpack(args, 1, count))
end

-- Brings the popup and BigWigs' bar in line with the current settings for
-- the break in progress, so flipping either option mid-break takes effect
-- right away, in both directions.
local function applyBreakSettings()
    local remaining = breakEndsAt - GetTime()
    if not wasBreakActive or remaining <= 0 then
        return
    end

    if not ns.IsBreakPopupEnabled() then
        ns.HideBreak()
    elseif not popupDismissed and not ReforgedBreakTimerFrame:IsShown() then
        ns.ShowBreak(remaining, breakTotal)
    end

    if shouldHideBigWigsBar() then
        stopBigWigsBreakBar()
    else
        restoreBigWigsBreakBar(remaining)
    end
end

function ns.SetBreakPopupEnabled(isEnabled)
    ReforgedBreakTimerDB.breakPopup = isEnabled
    if isEnabled then
        popupDismissed = false
    else
        ns.HideBreak() -- also closes an options preview
    end
    applyBreakSettings()
end

-- The popup's close button.
function ns.DismissBreak()
    ns.HideBreak()
    if wasBreakActive then
        popupDismissed = true
        applyBreakSettings()
    end
end

function ns.IsHideBigWigsBreakBarEnabled()
    return ReforgedBreakTimerDB.hideBigWigsBreakBar and true or false
end

function ns.SetHideBigWigsBreakBar(isEnabled)
    ReforgedBreakTimerDB.hideBigWigsBreakBar = isEnabled
    applyBreakSettings()
end

-- A real BigWigs break (never the options preview). Break state is still
-- tracked with the popup switched off, just nothing is shown.
local function beginBreak(remaining, total)
    wasBreakActive = true
    popupDismissed = false
    breakEndsAt, breakTotal = GetTime() + remaining, total
    if not ns.IsBreakPopupEnabled() then
        return
    end
    ns.ShowBreak(remaining, total)
end

local function endBreak()
    wasBreakActive = false
    lastPolledBreakStart, lastPolledBreakTotal = nil, nil
    barHiddenByUs = false
    ns.HideBreak()
end

local function checkBreak()
    local tbl = BigWigs3DB and BigWigs3DB.breakTime
    if tbl then
        local startTime, totalSeconds = tbl[1], tbl[2]
        local remaining = totalSeconds - (time() - startTime)
        if remaining > 0 then
            -- Refresh not just on the "no break -> break" transition, but
            -- also whenever BigWigs has overwritten breakTime with a
            -- different start/duration while one was already showing --
            -- otherwise extending an in-progress break (e.g. 5 min -> 10
            -- min) would never be reflected, just keep counting down to the
            -- original end time.
            local isNewOrChanged = not wasBreakActive
                or startTime ~= lastPolledBreakStart
                or totalSeconds ~= lastPolledBreakTotal
            if isNewOrChanged then
                lastPolledBreakStart, lastPolledBreakTotal = startTime, totalSeconds
                beginBreak(remaining, totalSeconds)
            end
            return
        end
    end

    if wasBreakActive then
        endBreak()
    end
end

local function isBreakPlugin(module)
    return type(module) == "table" and (module == breakPlugin or module.moduleName == "Break")
end

-- Registers with BigWigs' own message bus for exact-precision timing.
-- Current BigWigs no longer uses AceEvent-3.0 for its messages: they go
-- through BigWigsLoader.RegisterMessage/SendMessage instead, so that's
-- tried first (an AceEvent listener would never hear anything there).
-- AceEvent is only a fallback for older BigWigs builds. Returns false if
-- neither is available (the poll-based fallback above still works).
local function hookBigWigsMessages()
    local listener = {}
    local register

    local loader = BigWigsLoader
    if type(loader) == "table" and type(loader.RegisterMessage) == "function"
        and type(loader.SendMessage) == "function" then
        register = function(message, handler)
            loader.RegisterMessage(listener, message, handler)
        end
        sendBigWigsMessage = function(message, ...)
            loader.SendMessage(listener, message, ...)
        end
    else
        local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
        if not AceEvent then
            return false
        end
        AceEvent:Embed(listener)
        register = function(message, handler)
            listener:RegisterMessage(message, handler)
        end
        sendBigWigsMessage = function(message, ...)
            listener:SendMessage(message, ...)
        end
    end

    register("BigWigs_StartBreak", function(_, plugin, seconds)
        breakPlugin = plugin or breakPlugin

        -- BigWigs writes breakTime before firing this message, so it
        -- already describes this same break. When it's one we've already
        -- shown -- BigWigs restarting a break that was running before a
        -- /reload, which the load-time check picked up first -- leave the
        -- popup (and its picture) alone instead of opening it again.
        local tbl = BigWigs3DB and BigWigs3DB.breakTime
        local total = seconds
        if tbl then
            local isSameBreak = wasBreakActive
                and tbl[1] == lastPolledBreakStart and tbl[2] == lastPolledBreakTotal
            lastPolledBreakStart, lastPolledBreakTotal = tbl[1], tbl[2]
            if isSameBreak then
                return
            end
            -- After a restart `seconds` is only what's left of it.
            total = math.max(tbl[2] or seconds, seconds)
        end
        beginBreak(seconds, total)
    end)

    register("BigWigs_StopBreak", endBreak)

    -- BigWigs' Break plugin draws its own "Break time" bar by sending
    -- BigWigs_StartBar from itself. With the hide option on, we let that
    -- bar get created and then have BigWigs' Bars plugin stop it again --
    -- deferred a frame, since our handler can run before Bars' own one has
    -- made the bar. Matching on the sending plugin (not the bar text) keeps
    -- this independent of BigWigs' locale. This also hears our own replay
    -- from restoreBigWigsBreakBar, which is fine: the settings that made
    -- us replay it mean the deferred check below leaves it alone.
    register("BigWigs_StartBar", function(_, ...)
        local module, _, text = ...
        if not isBreakPlugin(module) then
            return
        end
        breakPlugin = module
        breakBarText = text
        breakBarArgs, breakBarArgCount = { ... }, select("#", ...)
        barHiddenByUs = false
        C_Timer.After(0, function()
            if shouldHideBigWigsBar() then
                stopBigWigsBreakBar()
            end
        end)
    end)

    return true
end

--------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------

local function createFrame()
    -- Width matches the image exactly (no side padding).
    local frame = CreateFrame("Frame", "ReforgedBreakTimerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(IMAGE_SIZE, TOP_ROW_HEIGHT + IMAGE_SIZE + PROGRESS_BAR_HEIGHT)
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
        tile = true,
        tileSize = 16,
    })
    frame:SetBackdropColor(0.04, 0.06, 0.08, 1)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -BUTTON_INSET, -BUTTON_INSET)
    frame.closeButton:SetScript("OnClick", function() ns.DismissBreak() end)

    -- Next-image (skip) button, beside the close button, for cycling to a different
    -- picture on demand instead of waiting for the next break.
    frame.nextImageButton = CreateFrame("Button", nil, frame)
    frame.nextImageButton:SetSize(20, 20)
    frame.nextImageButton:SetPoint("RIGHT", frame.closeButton, "LEFT", 2, 0)
    frame.nextImageButton:SetNormalTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\next_image")
    frame.nextImageButton:SetPushedTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\next_image")
    frame.nextImageButton:GetPushedTexture():SetVertexColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)
    frame.nextImageButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.nextImageButton:SetScript("OnClick", function() ns.ShowNextImage() end)
    frame.nextImageButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show a different image")
        GameTooltip:Show()
    end)
    frame.nextImageButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Image display -- flush with the frame's left/right edges (no side
    -- padding), leaving just enough room above for the button row.
    frame.imageBorder = CreateFrame("Frame", nil, frame)
    frame.imageBorder:SetSize(IMAGE_SIZE, IMAGE_SIZE)
    frame.imageBorder:SetPoint("TOP", 0, -TOP_ROW_HEIGHT)

    frame.image = frame.imageBorder:CreateTexture(nil, "ARTWORK")
    frame.image:SetAllPoints()
    frame.image:SetTexture(FALLBACK_IMAGE)

    -- Progress bar, flush against the bottom of the image (no gap) and the
    -- bottom of the frame, with the time remaining overlaid directly on it
    -- instead of as a separate line.
    frame.progressBar = CreateFrame("StatusBar", nil, frame)
    frame.progressBar:SetPoint("TOP", frame.imageBorder, "BOTTOM", 0, 0)
    frame.progressBar:SetSize(IMAGE_SIZE, PROGRESS_BAR_HEIGHT)
    frame.progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progressBar:SetStatusBarColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)
    frame.progressBar:SetMinMaxValues(0, 1)
    frame.progressBar:SetValue(0)

    frame.progressBarBg = frame.progressBar:CreateTexture(nil, "BACKGROUND")
    frame.progressBarBg:SetAllPoints()
    frame.progressBarBg:SetColorTexture(0, 0, 0, 0.5)

    frame.time = frame.progressBar:CreateFontString(nil, "OVERLAY")
    frame.time:SetPoint("CENTER")
    frame.time:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    frame.time:SetTextColor(1, 1, 1)

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
    if ReforgedBreakTimerDB.heartyFeastTTS == nil then
        ReforgedBreakTimerDB.heartyFeastTTS = false
    end
    if ReforgedBreakTimerDB.hideBigWigsBreakBar == nil then
        ReforgedBreakTimerDB.hideBigWigsBreakBar = true
    end
    if ReforgedBreakTimerDB.breakPopup == nil then
        ReforgedBreakTimerDB.breakPopup = true
    end
    ReforgedBreakTimerDB.raidImageSync = nil -- leftover from the removed raid picture sync
    if ReforgedBreakTimerDB.lootPassPrompt == nil then
        ReforgedBreakTimerDB.lootPassPrompt = false
    end
    if ReforgedBreakTimerDB.summonHelper == nil then
        ReforgedBreakTimerDB.summonHelper = false
    end

    local frame = createFrame()
    frame:SetScale(ns.GetFrameScale())

    if ReforgedBreakTimerDB.framePos then
        local pos = ReforgedBreakTimerDB.framePos
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 100)
    end

    -- Stay out of the way until BigWigs actually calls a break; the frame
    -- only appears on its own when the message hook (or, failing that,
    -- checkBreak()) detects one.
    frame:Hide()

    createSheetPreloads()
    updateSheetPreloads()

    -- ## OptionalDeps: BigWigs in the .toc means BigWigs (and with it
    -- BigWigsLoader) loads before we do, so this should succeed whenever
    -- BigWigs is installed. Only without it does breakTime get polled.
    if hookBigWigsMessages() then
        checkBreak()
    else
        C_Timer.NewTicker(0.2, checkBreak)
    end
end)
