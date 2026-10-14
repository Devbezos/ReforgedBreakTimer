local addonName, ns = ...

--------------------------------------------------------------------------
-- Warlock summon list
--------------------------------------------------------------------------
-- For warlocks only: while inside a Heroic or Mythic raid, lists everyone
-- in the groups that are actually raiding (1-4 on Mythic, 1-6 on Heroic)
-- who isn't in the instance yet. Clicking a name targets them, ready for
-- Ritual of Summoning.
--
-- The rows are secure target buttons, which makes the whole list a
-- protected frame: it can't be shown, hidden or rebuilt in combat, so any
-- change that happens mid-fight is applied once combat ends.

local MAX_GROUP_BY_DIFFICULTY = {
    [15] = 6, -- Heroic
    [16] = 4, -- Mythic
}

-- WoW Forever's raids have no Heroic/Mythic split, so there every raid
-- counts and the whole raid (all 8 groups) is listed.
local IS_MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local ALL_GROUPS = 8

local ACCENT = { 0.20, 0.85, 0.35 }
local ROW_HEIGHT = 18
local WIDTH = 180
local REFRESH_INTERVAL = 2

local isWarlock = select(2, UnitClass("player")) == "WARLOCK"
local frame, rows
local dismissedKey -- the list the player closed; it reappears if it changes
local needsRefresh = false

function ns.IsSummonHelperEnabled()
    return ReforgedBreakTimerDB and ReforgedBreakTimerDB.summonHelper
end

-- Returns { {unit, name, classFile, pending}, ... } of who needs a summon,
-- or nil when the list doesn't apply here at all.
local function collectMissing()
    if not IsInRaid() then
        return nil
    end
    local instanceName, instanceType, difficultyID = GetInstanceInfo()
    local maxGroup = MAX_GROUP_BY_DIFFICULTY[difficultyID] or (not IS_MAINLINE and ALL_GROUPS)
    if instanceType ~= "raid" or not maxGroup then
        return nil
    end
    local zoneName = GetRealZoneText()

    local missing = {}
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name, _, subgroup, _, _, classFile, zone, online = GetRaidRosterInfo(i)
        -- zone is nil until the roster has it; skip rather than guess.
        if name and online and zone and subgroup <= maxGroup and not UnitIsUnit(unit, "player")
            and zone ~= instanceName and zone ~= zoneName then
            local pending = C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(unit)
            missing[#missing + 1] = {
                unit = unit,
                name = Ambiguate(name, "short"),
                classFile = classFile,
                pending = pending,
            }
        end
    end
    table.sort(missing, function(a, b) return a.name < b.name end)
    return missing
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    ReforgedBreakTimerDB.summonFramePos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function createRow(index)
    local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 8, -28 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -8, 0)
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetAttribute("type", "target")
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)

    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    row.text:SetPoint("LEFT", 4, 0)

    row.status = row:CreateFontString(nil, "OVERLAY")
    row.status:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    row.status:SetText("summoning")

    row:Hide()
    return row
end

local function createFrame()
    frame = CreateFrame("Frame", "ReforgedBreakTimerSummonFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", -300, 100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.07, 0.08, 0.10, 0.92)
    frame:SetBackdropBorderColor(1, 1, 1, 0.08)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    frame.title:SetPoint("TOPLEFT", 10, -9)
    frame.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetSize(22, 22)
    frame.closeButton:SetPoint("TOPRIGHT", -2, -2)
    frame.closeButton:SetScript("OnClick", function()
        if not InCombatLockdown() then
            dismissedKey = frame.key
            frame:Hide()
        end
    end)

    local pos = ReforgedBreakTimerDB.summonFramePos
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
    end

    rows = {}
    for i = 1, MAX_RAID_MEMBERS or 40 do
        rows[i] = createRow(i)
    end
    frame:Hide()
end

local function refresh()
    if not frame then
        return
    end
    if InCombatLockdown() then
        needsRefresh = true
        return
    end
    needsRefresh = false

    local missing = ns.IsSummonHelperEnabled() and collectMissing()
    if not missing or #missing == 0 then
        dismissedKey = nil
        frame:Hide()
        return
    end

    local names = {}
    for i, entry in ipairs(missing) do
        names[i] = entry.name .. (entry.pending and "*" or "")
    end
    frame.key = table.concat(names, ",")
    if frame.key == dismissedKey then
        frame:Hide()
        return
    end

    for i, row in ipairs(rows) do
        local entry = missing[i]
        if entry then
            local color = RAID_CLASS_COLORS[entry.classFile]
            row:SetAttribute("unit", entry.unit)
            row.text:SetText(entry.name)
            if color then
                row.text:SetTextColor(color.r, color.g, color.b)
            else
                row.text:SetTextColor(1, 1, 1)
            end
            row.status:SetShown(entry.pending and true or false)
            row:Show()
        else
            row:Hide()
        end
    end

    frame.title:SetText("Needs a summon (" .. #missing .. ")")
    frame:SetHeight(28 + #missing * ROW_HEIGHT + 8)
    frame:Show()
end

function ns.SetSummonHelperEnabled(isEnabled)
    ReforgedBreakTimerDB.summonHelper = isEnabled
    refresh()
end

if not isWarlock then
    return
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        createFrame()
        -- Raid members' zones don't reliably fire an event when they
        -- change, so the list is also re-checked on a slow tick.
        C_Timer.NewTicker(REFRESH_INTERVAL, refresh)
    elseif event == "PLAYER_REGEN_ENABLED" and not needsRefresh then
        return
    end
    refresh()
end)
