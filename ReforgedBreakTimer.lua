local addonName, ns = ...

local FALLBACK_IMAGE = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACCENT_COLOR = { 0.20, 0.85, 0.35 }
local IMAGE_SIZE = 267 -- also the frame's width, so there's no side padding
local TOP_ROW_HEIGHT = 40 -- room above the image for the logo/close/rotate buttons
local BUTTON_INSET = 6 -- keeps those buttons inside the box instead of flush on its edge
local PROGRESS_BAR_HEIGHT = 28

ns.images = ns.images or {} -- populated by Images.lua

-- True for a local test deploy (scripts/deploy_to_wow.ps1 stamps "-dev" onto
-- the ## Version in the .toc it copies into your WoW AddOns folder; a real
-- release zip never has that suffix), used to gate dev-only UI like the
-- "next image" button below.
local function IsDevBuild()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(addonName, "Version")
    return version ~= nil and version:match("%-dev$") ~= nil
end

local currentImagePath
local endTime = 0
local wasBreakActive = false

-- Shuffled "bag" of not-yet-shown images for the current cycle -- refilled
-- and reshuffled once it runs dry, so every enabled picture gets shown
-- once before any of them repeat, instead of a pure random pick that could
-- skip some entirely while repeating others.
local imageQueue = {}

-- Playback state for the current image, when it's an animated (GIF-sourced)
-- one: { frames = {path, ...}, delay = secondsPerFrame, frameIndex, elapsed }.
-- nil whenever the current image is a plain static picture.
local currentAnimation

--------------------------------------------------------------------------
-- Image selection
--------------------------------------------------------------------------

-- Every animated (GIF-sourced) image plays back by rapidly SetTexture-ing
-- between many small frame files; the first time any given frame file is
-- used, WoW has to load and decode it from disk, which is slow enough
-- relative to the per-frame delay to show up as a few seconds of flicker
-- before the animation settles down (once every frame's actually been
-- drawn once and is sitting in the texture cache). Loading every frame of
-- every animated image once, up front at addon load -- long before any
-- break can actually happen -- avoids ever paying that cost during real
-- playback.
--
-- This has to actually get each frame drawn on screen at least once, not
-- just call SetTexture on it: an invisible (alpha 0) or instantly-replaced
-- texture may never trigger the real decode/GPU-upload work, since that's
-- tied to the draw pass, not the SetTexture call itself. So this uses a
-- small pool of real (if practically invisible) on-screen textures, and
-- staggers assigning new paths to them a handful at a time so each one
-- gets several actual rendered frames before it's reused for the next path.
local PRELOAD_POOL_SIZE = 6
local PRELOAD_BATCH_INTERVAL = 0.05

local preloadPool = {}

local function getPreloadTexture(slot)
    local tex = preloadPool[slot]
    if not tex then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(4, 4)
        holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(slot * 5), 2)
        -- Low but non-zero: alpha 0 can skip the actual draw (and so the
        -- decode/upload it would trigger) entirely; this stays imperceptible
        -- while still being a real draw target.
        holder:SetAlpha(0.02)
        holder:Show()
        tex = holder:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        preloadPool[slot] = tex
    end
    return tex
end

local function preloadAnimatedImages()
    local paths = {}
    for _, entry in ipairs(ns.images) do
        if entry.frames then
            for _, framePath in ipairs(entry.frames) do
                paths[#paths + 1] = framePath
            end
        end
    end

    if #paths == 0 then
        return
    end

    local nextIndex = 1
    local ticker
    ticker = C_Timer.NewTicker(PRELOAD_BATCH_INTERVAL, function()
        for slot = 1, PRELOAD_POOL_SIZE do
            if nextIndex > #paths then
                ticker:Cancel()
                return
            end
            getPreloadTexture(slot):SetTexture(paths[nextIndex])
            nextIndex = nextIndex + 1
        end
    end)
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

function ns.ChooseRandomImage()
    local enabled = ns.GetEnabledImages()

    if #enabled == 0 then
        currentImagePath = nil
        currentAnimation = nil
        imageQueue = {}
        ReforgedBreakTimerFrame.image:SetTexture(FALLBACK_IMAGE)
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

    local choice = table.remove(imageQueue)
    currentImagePath = choice.path

    if choice.frames then
        -- Animated (GIF-sourced) image: play its frames in a loop, starting
        -- from the first one. See advanceAnimation, driven from onBreakUpdate.
        currentAnimation = {
            frames = choice.frames,
            delay = math.max(choice.delay or 0.1, 0.02),
            frameIndex = 1,
            elapsed = 0,
        }
    else
        currentAnimation = nil
    end

    ReforgedBreakTimerFrame.image:SetTexture(choice.path)
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
        anim.frameIndex = (anim.frameIndex % #anim.frames) + 1
        changed = true
    end

    if changed then
        ReforgedBreakTimerFrame.image:SetTexture(anim.frames[anim.frameIndex])
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

-- Shows the break frame with a random image and starts its countdown.
-- The image stays static for the whole break; a new one is only picked
-- the next time a break starts.
-- `remaining`/`total` are seconds, as reported by BigWigs.
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

--------------------------------------------------------------------------
-- BigWigs break detection
--------------------------------------------------------------------------
-- Primary path: BigWigs' Break plugin fires "BigWigs_StartBreak" /
-- "BigWigs_StopBreak" via AceEvent-3.0 the instant a break starts/ends,
-- with full GetTime()-precision duration -- no rounding, no polling lag,
-- so our countdown starts in the same tick as BigWigs' own bar.
--
-- Fallback path: BigWigs_Plugins/Break.lua also stores the active break in
-- BigWigs3DB.breakTime: { time(), totalSeconds, nick, isDBM }. We poll that
-- (5x/sec) in case the message path isn't available -- e.g. our addon
-- registers after BigWigs already fired BigWigs_StartBreak for this break,
-- or AceEvent-3.0 isn't loaded for some reason. This path only has
-- whole-second precision (time(), not GetTime()), so it's the one place
-- a ~1s offset from BigWigs' own bar can still show up.

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

-- Registers with BigWigs' own message bus for exact-precision timing.
-- Returns true if it managed to hook in, false if AceEvent-3.0 isn't
-- available yet (the poll-based fallback above still works either way).
local function hookBigWigsMessages()
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if not AceEvent then
        return false
    end

    local listener = {}
    AceEvent:Embed(listener)

    listener:RegisterMessage("BigWigs_StartBreak", function(_, _, seconds)
        wasBreakActive = true
        ns.ShowBreak(seconds, seconds)
    end)

    listener:RegisterMessage("BigWigs_StopBreak", function()
        wasBreakActive = false
        ns.HideBreak()
    end)

    return true
end

--------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------

local function createFrame()
    -- Width matches the image exactly (no side padding), so the logo and
    -- close button (anchored flush to the top corners) end up flush with
    -- its edges too.
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
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

    -- Dev-only: a "next image" button beside the close button, for cycling
    -- through pictures on demand while testing instead of waiting for real
    -- breaks. Only exists on a local -dev deploy; never ships in a release.
    if IsDevBuild() then
        frame.devNextImageButton = CreateFrame("Button", nil, frame)
        frame.devNextImageButton:SetSize(20, 20)
        frame.devNextImageButton:SetPoint("RIGHT", frame.closeButton, "LEFT", 2, 0)
        frame.devNextImageButton:SetNormalTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\next_image")
        frame.devNextImageButton:SetPushedTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\next_image")
        frame.devNextImageButton:GetPushedTexture():SetVertexColor(ACCENT_COLOR[1], ACCENT_COLOR[2], ACCENT_COLOR[3], 1)
        frame.devNextImageButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        frame.devNextImageButton:SetScript("OnClick", function() ns.ChooseRandomImage() end)
        frame.devNextImageButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("[Dev] Rotate to next image")
            GameTooltip:Show()
        end)
        frame.devNextImageButton:SetScript("OnLeave", GameTooltip_Hide)
    end

    -- Logo, inset from the top-left corner so it sits inside the box.
    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(32, 32)
    frame.logo:SetPoint("TOPLEFT", BUTTON_INSET, -BUTTON_INSET)
    frame.logo:SetTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\logo")

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

    local frame = createFrame()

    if ReforgedBreakTimerDB.framePos then
        local pos = ReforgedBreakTimerDB.framePos
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 100)
    end

    -- Stay out of the way until BigWigs actually calls a break; the frame
    -- only appears on its own when the message hook (or, failing that,
    -- checkBreak()) detects one.
    frame:Hide()

    preloadAnimatedImages()

    -- ## OptionalDeps: BigWigs in the .toc means BigWigs (and its bundled
    -- AceEvent-3.0) loads before we do, so this should succeed whenever
    -- BigWigs is installed. The poll below still runs regardless, as a
    -- safety net for whatever this doesn't catch.
    hookBigWigsMessages()

    C_Timer.NewTicker(0.2, checkBreak)
end)
