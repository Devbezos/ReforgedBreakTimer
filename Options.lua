local _, ns = ...

local ROW_HEIGHT = 22
local checkboxRows = {}
local settingsCategoryID

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function createCheckbox(parent, entry)
    local row = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    row:SetSize(20, 20)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "RIGHT", 4, 0)
    row.icon:SetTexture(entry.path)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetText(entry.name)

    row:SetScript("OnClick", function(self)
        ns.SetImageEnabled(entry.path, self:GetChecked())
    end)

    return row
end

local function refreshCheckboxes()
    for _, row in ipairs(checkboxRows) do
        row:SetChecked(ns.IsImageEnabled(row.imagePath))
    end
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local panel = CreateFrame("Frame", "ReforgedBreakTimerOptionsPanel", UIParent)
panel.name = "Reforged Break Timer"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Reforged Break Timer")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("The popup appears automatically whenever BigWigs calls a break. Choose which pictures can show, and reposition the frame below.")

-- Reset position button
local resetPositionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetPositionButton:SetSize(140, 22)
resetPositionButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 8, -20)
resetPositionButton:SetText("Reset Frame Position")
resetPositionButton:SetScript("OnClick", function() ns.ResetFramePosition() end)

-- Section divider
local imagesHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
imagesHeader:SetPoint("TOPLEFT", resetPositionButton, "BOTTOMLEFT", 8, -20)
imagesHeader:SetText("Images shown on break")

local imagesHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
imagesHint:SetPoint("TOPLEFT", imagesHeader, "BOTTOMLEFT", 0, -4)
imagesHint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
imagesHint:SetJustifyH("LEFT")
imagesHint:SetText("Turn individual pictures on or off below. (Adding new ones is a job for whoever maintains this addon -- see its README.)")

-- Select all / none
local selectAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
selectAllButton:SetSize(90, 20)
selectAllButton:SetPoint("TOPLEFT", imagesHint, "BOTTOMLEFT", 0, -8)
selectAllButton:SetText("Select All")
selectAllButton:SetScript("OnClick", function()
    ns.SetAllImagesEnabled(true)
    refreshCheckboxes()
end)

local selectNoneButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
selectNoneButton:SetSize(90, 20)
selectNoneButton:SetPoint("LEFT", selectAllButton, "RIGHT", 8, 0)
selectNoneButton:SetText("Select None")
selectNoneButton:SetScript("OnClick", function()
    ns.SetAllImagesEnabled(false)
    refreshCheckboxes()
end)

-- Scroll list of images
local scrollFrame = CreateFrame("ScrollFrame", "ReforgedBreakTimerOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", selectAllButton, "BOTTOMLEFT", 0, -12)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(1, 1)
scrollFrame:SetScrollChild(scrollChild)

local emptyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
emptyText:SetPoint("TOPLEFT", 4, -4)
emptyText:SetText("No pictures found. Ask whoever maintains this addon to add some.")
emptyText:Hide()

local function buildImageList()
    for _, row in ipairs(checkboxRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(checkboxRows)

    if #ns.images == 0 then
        emptyText:Show()
        scrollChild:SetHeight(20)
        return
    end

    emptyText:Hide()

    local previousRow
    for _, entry in ipairs(ns.images) do
        local row = createCheckbox(scrollChild, entry)
        row.imagePath = entry.path
        if previousRow then
            row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -4)
        else
            row:SetPoint("TOPLEFT", 4, -4)
        end
        checkboxRows[#checkboxRows + 1] = row
        previousRow = row
    end

    scrollChild:SetHeight(#ns.images * (ROW_HEIGHT + 4) + 8)
    refreshCheckboxes()
end

panel:SetScript("OnShow", function()
    buildImageList()
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
