local _, ns = ...

--------------------------------------------------------------------------
-- Gruul's Gone Wild auto-pass
--------------------------------------------------------------------------
-- While in a raid instance whose raid leader is in Gruul's Gone Wild, and
-- RCLootCouncil is switched on and actually running loot for the group,
-- turns on the game's own "Pass on Loot" option (SetOptOutOfLoot). It goes
-- back off as soon as any of that stops being true -- but only if it was us
-- who turned it on, so a Pass on Loot the player set themselves is left
-- alone.
--
-- RCLootCouncil exposes its addon object as the global RCLootCouncil:
--   .enabled     the player's own RC on/off switch
--   .handleLoot  the master looter is running RC for this group (set when
--                their StartHandleLoot reaches us, cleared on StopHandleLoot
--                or leaving the group -- not always through a function we
--                could hook, hence the polling below)
--   .isMasterLooter  we're the one running it (never auto-pass then)

local GUILD_KEY = "gruulsgonewild"
local CHECK_INTERVAL = 2

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

function ns.IsLootPassPromptEnabled()
    return ReforgedBreakTimerDB and ReforgedBreakTimerDB.lootPassPrompt
end

local update

function ns.SetLootPassPromptEnabled(isEnabled)
    ReforgedBreakTimerDB.lootPassPrompt = isEnabled
    update()
end

local function isInRaidInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "raid"
end

local function isRCLootCouncilRunning()
    local rc = _G.RCLootCouncil
    return type(rc) == "table" and rc.enabled and rc.handleLoot and not rc.isMasterLooter
end

-- true/false, or nil when the leader's guild isn't known yet (it can take
-- a moment after zoning in or joining) -- treated as "no change".
local function shouldPassOnLoot()
    if not (ns.IsLootPassPromptEnabled() and IsInRaid() and isInRaidInstance() and isRCLootCouncilRunning()) then
        return false
    end
    local leader = findLeaderUnit()
    local guildName = leader and GetGuildInfo(leader)
    if not guildName then
        return nil
    end
    return normalize(guildName) == GUILD_KEY
end

-- Whether it was us who turned Pass on Loot on is kept in the saved
-- variables (lootPassOptedOut), so a /reload mid-raid doesn't forget it.
update = function()
    local shouldPass = shouldPassOnLoot()
    if shouldPass == nil then
        return
    end

    if shouldPass and not ReforgedBreakTimerDB.lootPassOptedOut and not GetOptOutOfLoot() then
        SetOptOutOfLoot(true)
        ReforgedBreakTimerDB.lootPassOptedOut = true
        print("|cff33d959Dev's Raid Tools:|r Gruul's Gone Wild is running RCLootCouncil -- passing on loot.")
    elseif not shouldPass and ReforgedBreakTimerDB.lootPassOptedOut then
        SetOptOutOfLoot(false)
        ReforgedBreakTimerDB.lootPassOptedOut = nil
        print("|cff33d959Dev's Raid Tools:|r No longer passing on loot.")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    update()
    if event == "PLAYER_ENTERING_WORLD" and not eventFrame.ticker then
        -- RC's handleLoot flips on and off without any event we can see.
        eventFrame.ticker = C_Timer.NewTicker(CHECK_INTERVAL, update)
    end
end)
