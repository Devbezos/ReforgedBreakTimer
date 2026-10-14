local addonName, ns = ...

--------------------------------------------------------------------------
-- Gruul's Gone Wild loot prompt
--------------------------------------------------------------------------
-- On zoning into a raid instance, if the raid leader's guild is Gruul's
-- Gone Wild, asks whether to pass on loot. "Yes" flips the game's own
-- "Pass on Loot" option (SetOptOutOfLoot) on, and we flip it back off when
-- leaving the raid -- but only if it was us who turned it on.

local GUILD_KEY = "gruulsgonewild"
-- The leader's guild isn't always known the moment we zone in (or the
-- roster can still be filling in), so the check retries for a while.
local RETRY_INTERVAL = 2
local MAX_RETRIES = 10

local promptedThisVisit = false
local optedOutByUs = false
local retriesLeft = 0
local retryPending = false

-- "Gruul's Gone Wild", "Gruuls Gone Wild", "gruuls gone wild" all match.
local function normalize(guildName)
    return guildName:lower():gsub("[^%w]", "")
end

local function findLeaderUnit()
    if UnitIsGroupLeader("player") then
        return "player"
    end
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitIsGroupLeader(unit) then
            return unit
        end
    end
end

StaticPopupDialogs["REFORGEDBREAKTIMER_GGW_LOOT"] = {
    text = "Your raid leader is in Gruul's Gone Wild.\nDo you want to pass on loot?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        SetOptOutOfLoot(true)
        optedOutByUs = true
        print("|cff33d959Dev's Raid Tools:|r Passing on loot for this raid.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.IsLootPassPromptEnabled()
    return ReforgedBreakTimerDB and ReforgedBreakTimerDB.lootPassPrompt
end

function ns.SetLootPassPromptEnabled(isEnabled)
    ReforgedBreakTimerDB.lootPassPrompt = isEnabled
end

local function isInRaidInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "raid"
end

local check

local function scheduleRetry()
    if retryPending or retriesLeft <= 0 then
        return
    end
    retriesLeft = retriesLeft - 1
    retryPending = true
    C_Timer.After(RETRY_INTERVAL, function()
        retryPending = false
        check()
    end)
end

check = function()
    if promptedThisVisit or not ns.IsLootPassPromptEnabled() then
        return
    end
    if not (IsInRaid() and isInRaidInstance()) or GetOptOutOfLoot() then
        return
    end

    local leader = findLeaderUnit()
    local guildName = leader and GetGuildInfo(leader)
    if not guildName then
        scheduleRetry()
        return
    end

    -- Whatever the answer, only ask once per trip into the raid.
    promptedThisVisit = true
    if normalize(guildName) == GUILD_KEY then
        StaticPopup_Show("REFORGEDBREAKTIMER_GGW_LOOT")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInRaidInstance() then
            retriesLeft = MAX_RETRIES
        else
            -- Left the raid: the next time in is a fresh visit.
            promptedThisVisit = false
            StaticPopup_Hide("REFORGEDBREAKTIMER_GGW_LOOT")
            if optedOutByUs then
                SetOptOutOfLoot(false)
                optedOutByUs = false
                print("|cff33d959Dev's Raid Tools:|r No longer passing on loot.")
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" and retriesLeft <= 0 then
        -- Joined the group (or the leader changed) while already inside.
        retriesLeft = MAX_RETRIES
    end
    check()
end)
