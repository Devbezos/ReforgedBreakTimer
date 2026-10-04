local addonName, ns = ...

local settingsCategoryID

--------------------------------------------------------------------------
-- Style
--------------------------------------------------------------------------
-- Flat, card-based look built from plain WHITE8x8 rectangles tinted per
-- state, rather than Blizzard's stock gold-on-parchment widgets. The accent
-- matches the popup's progress bar (ACCENT_COLOR in ReforgedBreakTimer.lua).

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"

local ACCENT = { 0.20, 0.85, 0.35 }
local TEXT = { 0.92, 0.93, 0.95 }
local TEXT_MUTED = { 0.58, 0.61, 0.66 }
local CARD_BG = { 0.07, 0.08, 0.10, 0.92 }
local CARD_BORDER = { 1, 1, 1, 0.08 }
local CONTROL_BG = { 1, 1, 1, 0.06 }
local CONTROL_BG_HOVER = { 1, 1, 1, 0.11 }
local CONTROL_BORDER = { 1, 1, 1, 0.14 }

local PADDING = 16
local CARD_GAP = 12
local SETTINGS_CARD_HEIGHT = 112
local TILE_MIN_WIDTH = 104
local TILE_GAP = 8
local TILE_LABEL_HEIGHT = 22
local SCROLL_STEP = 60

--------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------

local function setColor(target, method, color)
    target[method](target, color[1], color[2], color[3], color[4] or 1)
end

local function applyBackdrop(frame, bg, border)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    setColor(frame, "SetBackdropColor", bg)
    setColor(frame, "SetBackdropBorderColor", border)
end

local function createText(parent, size, color, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(FONT, size, "")
    text:SetJustifyH("LEFT")
    setColor(text, "SetTextColor", color)
    return text
end

local function createCard(parent, titleText)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    applyBackdrop(card, CARD_BG, CARD_BORDER)

    card.title = createText(card, 13, TEXT)
    card.title:SetPoint("TOPLEFT", 14, -14)
    card.title:SetText(titleText)

    return card
end

-- Description text under a card's title, wrapping to the card's width.
local function createCardHint(card, text)
    local hint = createText(card, 11, TEXT_MUTED)
    hint:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    hint:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    hint:SetSpacing(2)
    hint:SetText(text)
    return hint
end

local function createButton(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 24)
    applyBackdrop(button, CONTROL_BG, CONTROL_BORDER)

    button.label = createText(button, 11, TEXT)
    button.label:SetPoint("CENTER")
    button.label:SetText(label)

    button:SetScript("OnEnter", function(self)
        setColor(self, "SetBackdropColor", CONTROL_BG_HOVER)
        setColor(self, "SetBackdropBorderColor", ACCENT)
    end)
    button:SetScript("OnLeave", function(self)
        setColor(self, "SetBackdropColor", CONTROL_BG)
        setColor(self, "SetBackdropBorderColor", CONTROL_BORDER)
    end)
    button:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER") end)
    button:SetScript("OnClick", onClick)

    return button
end

-- A sliding on/off switch with a clickable label. Uses SetOn/IsOn rather
-- than CheckButton's SetChecked since it's a plain Button underneath.
local function createToggle(parent, label, onChange)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetHeight(20)

    toggle.track = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    toggle.track:SetSize(36, 20)
    toggle.track:SetPoint("LEFT")
    toggle.track:EnableMouse(false)

    toggle.knob = toggle.track:CreateTexture(nil, "OVERLAY")
    toggle.knob:SetTexture(WHITE)
    toggle.knob:SetSize(14, 14)

    toggle.label = createText(toggle, 12, TEXT)
    toggle.label:SetPoint("LEFT", toggle.track, "RIGHT", 10, 0)
    toggle.label:SetText(label)
    toggle:SetWidth(36 + 10 + toggle.label:GetStringWidth())

    function toggle:SetOn(isOn)
        self.isOn = isOn and true or false
        self.knob:ClearAllPoints()
        if self.isOn then
            applyBackdrop(self.track, ACCENT, ACCENT)
            self.knob:SetPoint("RIGHT", -3, 0)
            self.knob:SetVertexColor(1, 1, 1, 1)
        else
            applyBackdrop(self.track, CONTROL_BG, CONTROL_BORDER)
            self.knob:SetPoint("LEFT", 3, 0)
            setColor(self.knob, "SetVertexColor", TEXT_MUTED)
        end
    end

    function toggle:IsOn()
        return self.isOn
    end

    toggle:SetScript("OnClick", function(self)
        self:SetOn(not self.isOn)
        onChange(self.isOn)
    end)
    toggle:SetOn(false)

    return toggle
end

--------------------------------------------------------------------------
-- Panel + header
--------------------------------------------------------------------------

local panel = CreateFrame("Frame", "ReforgedBreakTimerOptionsPanel", UIParent)
panel.name = "Reforged Break Timer"

local logo = panel:CreateTexture(nil, "ARTWORK")
logo:SetSize(40, 40)
logo:SetPoint("TOPLEFT", PADDING, -PADDING)
logo:SetTexture("Interface\\AddOns\\ReforgedBreakTimer\\textures\\logo")

local title = createText(panel, 18, TEXT)
title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
title:SetText("Reforged Break Timer")

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = getMetadata and getMetadata(addonName, "Version")
if version then
    local versionBadge = createText(panel, 10, ACCENT)
    versionBadge:SetPoint("LEFT", title, "RIGHT", 8, -1)
    versionBadge:SetText("v" .. version)
end

local subtitle = createText(panel, 11, TEXT_MUTED)
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -PADDING, 0)
subtitle:SetText("Pops up a picture whenever BigWigs calls a break.")

local HEADER_HEIGHT = 40 + PADDING + CARD_GAP + 4

--------------------------------------------------------------------------
-- Popup card
--------------------------------------------------------------------------

local popupCard = createCard(panel, "Popup")
popupCard:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -HEADER_HEIGHT)
popupCard:SetPoint("TOPRIGHT", panel, "TOP", -CARD_GAP / 2, -HEADER_HEIGHT)
popupCard:SetHeight(SETTINGS_CARD_HEIGHT)
createCardHint(popupCard, "Drag the popup to move it. Preview shows it for 15 seconds.")

-- The Settings window sits above the popup's normal strata, so a preview is
-- lifted over it (and dropped back down when the panel closes).
local previewButton = createButton(popupCard, "Preview", 90, function()
    ReforgedBreakTimerFrame:SetFrameStrata("DIALOG")
    ns.ShowBreak(15, 15)
end)
previewButton:SetPoint("BOTTOMLEFT", 14, 14)

local resetPositionButton = createButton(popupCard, "Reset position", 110, function()
    ns.ResetFramePosition()
end)
resetPositionButton:SetPoint("LEFT", previewButton, "RIGHT", 8, 0)

--------------------------------------------------------------------------
-- Hearty Feast card
--------------------------------------------------------------------------

local feastCard = createCard(panel, "Hearty Feast alert")
feastCard:SetPoint("TOPLEFT", panel, "TOP", CARD_GAP / 2, -HEADER_HEIGHT)
feastCard:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -HEADER_HEIGHT)
feastCard:SetHeight(SETTINGS_CARD_HEIGHT)
createCardHint(feastCard, "Yells over text-to-speech the moment anyone drops a Hearty Feast.")

local feastToggle = createToggle(feastCard, "Announce", function(isOn)
    ns.SetHeartyFeastTTSEnabled(isOn)
end)
feastToggle:SetPoint("BOTTOMLEFT", 14, 16)

local feastTestButton = createButton(feastCard, "Test", 70, function()
    ns.TestHeartyFeastAnnouncement()
end)
feastTestButton:SetPoint("BOTTOMRIGHT", -14, 14)

--------------------------------------------------------------------------
-- Images card: a scrollable grid of clickable thumbnails
--------------------------------------------------------------------------

local imagesCard = createCard(panel, "Break images")
imagesCard:SetPoint("TOPLEFT", popupCard, "BOTTOMLEFT", 0, -CARD_GAP)
imagesCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)

local imageCount = createText(imagesCard, 11, TEXT_MUTED)
imageCount:SetPoint("LEFT", imagesCard.title, "RIGHT", 10, -1)

local tiles = {}

local function updateImageCount()
    local enabled = 0
    for _, entry in ipairs(ns.images) do
        if ns.IsImageEnabled(entry.path) then
            enabled = enabled + 1
        end
    end
    imageCount:SetText(enabled .. " of " .. #ns.images .. " shown")
end

local function applyTileState(tile)
    local isEnabled = ns.IsImageEnabled(tile.entry.path)
    local isHovered = tile:IsMouseOver()

    tile.thumb:SetDesaturated(not isEnabled)
    tile.thumb:SetAlpha(isEnabled and 1 or 0.35)
    setColor(tile.label, "SetTextColor", isEnabled and TEXT or TEXT_MUTED)
    tile.badge:SetShown(isEnabled)
    tile.check:SetShown(isEnabled)

    setColor(tile, "SetBackdropColor", isHovered and CONTROL_BG_HOVER or CONTROL_BG)
    if isEnabled then
        setColor(tile, "SetBackdropBorderColor", ACCENT)
    else
        setColor(tile, "SetBackdropBorderColor", isHovered and CONTROL_BORDER or CARD_BORDER)
    end
end

local function refreshTiles()
    for _, tile in ipairs(tiles) do
        applyTileState(tile)
    end
    updateImageCount()
end

local selectNoneButton = createButton(imagesCard, "Hide all", 76, function()
    ns.SetAllImagesEnabled(false)
    refreshTiles()
end)
selectNoneButton:SetPoint("TOPRIGHT", -14, -10)

local selectAllButton = createButton(imagesCard, "Show all", 76, function()
    ns.SetAllImagesEnabled(true)
    refreshTiles()
end)
selectAllButton:SetPoint("RIGHT", selectNoneButton, "LEFT", -8, 0)

local scrollFrame = CreateFrame("ScrollFrame", nil, imagesCard)
scrollFrame:SetPoint("TOPLEFT", 14, -46)
scrollFrame:SetPoint("BOTTOMRIGHT", -24, 14)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(1, 1)
scrollFrame:SetScrollChild(scrollChild)

-- Thin flat scrollbar in place of UIPanelScrollFrameTemplate's arrows.
local scrollBar = CreateFrame("Slider", nil, imagesCard)
scrollBar:SetPoint("TOPRIGHT", -10, -46)
scrollBar:SetPoint("BOTTOMRIGHT", -10, 14)
scrollBar:SetWidth(4)
scrollBar:SetOrientation("VERTICAL")
scrollBar:EnableMouse(true)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)

local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
scrollTrack:SetAllPoints()
scrollTrack:SetColorTexture(1, 1, 1, 0.05)

scrollBar:SetThumbTexture(WHITE)
local scrollThumb = scrollBar:GetThumbTexture()
scrollThumb:SetVertexColor(1, 1, 1, 0.3)
scrollThumb:SetSize(4, 40)

scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
end)

scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(_, delta)
    local _, maxScroll = scrollBar:GetMinMaxValues()
    local value = scrollBar:GetValue() - delta * SCROLL_STEP
    scrollBar:SetValue(math.max(0, math.min(maxScroll, value)))
end)

local emptyText = createText(scrollChild, 11, TEXT_MUTED)
emptyText:SetPoint("TOPLEFT", 0, -4)
emptyText:SetText("No pictures found. Ask whoever maintains this addon to add some.")
emptyText:Hide()

local function createTile(entry)
    local tile = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
    tile.entry = entry
    tile:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })

    tile.thumb = tile:CreateTexture(nil, "ARTWORK")
    tile.thumb:SetPoint("TOPLEFT", 5, -5)
    tile.thumb:SetPoint("TOPRIGHT", -5, -5)
    tile.thumb:SetTexture(entry.path)
    if entry.frames then
        -- Animated image: show just the first cell of its sprite sheet.
        tile.thumb:SetTexCoord(ns.GetFrameTexCoords(entry, 1))
    end

    tile.label = createText(tile, 10, TEXT)
    tile.label:SetPoint("BOTTOMLEFT", 6, 6)
    tile.label:SetPoint("BOTTOMRIGHT", -6, 6)
    tile.label:SetJustifyH("CENTER")
    tile.label:SetWordWrap(false)
    tile.label:SetText(entry.name)

    -- Accent corner badge with a check mark, shown while the image is enabled.
    tile.badge = tile:CreateTexture(nil, "OVERLAY")
    tile.badge:SetSize(18, 18)
    tile.badge:SetPoint("TOPRIGHT", -1, -1)
    setColor(tile.badge, "SetColorTexture", ACCENT)

    tile.check = tile:CreateTexture(nil, "OVERLAY", nil, 1)
    tile.check:SetSize(18, 18)
    tile.check:SetPoint("CENTER", tile.badge)
    tile.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tile.check:SetDesaturated(true)
    tile.check:SetVertexColor(0.05, 0.05, 0.05, 1)

    tile:SetScript("OnClick", function(self)
        ns.SetImageEnabled(self.entry.path, not ns.IsImageEnabled(self.entry.path))
        applyTileState(self)
        updateImageCount()
    end)
    tile:SetScript("OnEnter", function(self)
        applyTileState(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.name, 1, 1, 1)
        if self.entry.frames then
            GameTooltip:AddLine("Animated", ACCENT[1], ACCENT[2], ACCENT[3])
        end
        local action = ns.IsImageEnabled(self.entry.path) and "stop showing" or "show"
        GameTooltip:AddLine("Click to " .. action .. " it on breaks.", TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(self)
        applyTileState(self)
        GameTooltip_Hide()
    end)

    return tile
end

-- Tiles stretch to fill each row, so the grid always spans the card's full
-- width whatever size the Settings window gives the panel.
local function layoutTiles(width)
    if width <= 0 then
        return
    end

    local columns = math.max(1, math.floor((width + TILE_GAP) / (TILE_MIN_WIDTH + TILE_GAP)))
    local tileWidth = math.floor((width - (columns - 1) * TILE_GAP) / columns)
    local thumbSize = tileWidth - 10
    local tileHeight = 5 + thumbSize + TILE_LABEL_HEIGHT

    for index, tile in ipairs(tiles) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        tile:SetSize(tileWidth, tileHeight)
        tile.thumb:SetHeight(thumbSize)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", column * (tileWidth + TILE_GAP), -row * (tileHeight + TILE_GAP))
    end

    local rows = math.ceil(#tiles / columns)
    local contentHeight = math.max(20, rows * tileHeight + math.max(0, rows - 1) * TILE_GAP)
    scrollChild:SetSize(width, contentHeight)
    scrollFrame:UpdateScrollChildRect()

    local maxScroll = math.max(0, contentHeight - scrollFrame:GetHeight())
    scrollBar:SetMinMaxValues(0, maxScroll)
    scrollBar:SetValue(math.min(scrollBar:GetValue(), maxScroll))
    scrollBar:SetShown(maxScroll > 0)
    if maxScroll > 0 then
        scrollThumb:SetHeight(math.max(24, scrollBar:GetHeight() * scrollFrame:GetHeight() / contentHeight))
    end
end

-- ns.images is fully populated by Images.lua before this file loads, so the
-- tiles are built once here rather than recreated (and leaked -- WoW never
-- frees frames) on every open.
for _, entry in ipairs(ns.images) do
    tiles[#tiles + 1] = createTile(entry)
end
emptyText:SetShown(#tiles == 0)

-- The panel has no real size until the Settings window first lays it out,
-- so the grid is (re)flowed whenever its size actually changes.
scrollFrame:SetScript("OnSizeChanged", function(self, width)
    layoutTiles(width)
    self:UpdateScrollChildRect()
end)

local function refreshPanel()
    refreshTiles()
    feastToggle:SetOn(ns.IsHeartyFeastTTSEnabled())
    layoutTiles(scrollFrame:GetWidth())
end

-- Frames are created already shown, so without this the Settings window's
-- first Show() of the panel isn't a hidden -> shown transition and OnShow
-- never fires -- leaving every setting unsynced until the second open.
panel:Hide()
panel:SetScript("OnShow", refreshPanel)
panel:SetScript("OnHide", function()
    ReforgedBreakTimerFrame:SetFrameStrata("MEDIUM")
end)

--------------------------------------------------------------------------
-- Registration (modern Settings API with legacy fallback)
--------------------------------------------------------------------------

function ns.OpenOptions()
    if Settings and Settings.OpenToCategory and settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice to work around a long-standing Blizzard bug where the
        -- first call can open to the wrong sub-category.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
