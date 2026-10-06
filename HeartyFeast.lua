local addonName, ns = ...

--------------------------------------------------------------------------
-- Hearty Feast alert
--------------------------------------------------------------------------
-- Registering COMBAT_LOG_EVENT_UNFILTERED to snoop other players' casts is
-- a protected call the game now rejects outright (ADDON_ACTION_FORBIDDEN).
-- The only cast-related event addons can still observe is
-- UNIT_SPELLCAST_SUCCEEDED for the "player" unit, i.e. your own casts --
-- so detection only fires for whoever actually drops the feast, and gets
-- relayed to the rest of the group over a raid/party addon message so
-- everyone (not just the dropper) gets the TTS. Spell IDs are the
-- current-season Hearty feast items, sourced from NorthernSkyRaidTools'
-- QoL.lua ConsumableSpells table.

local HEARTY_FEAST_SPELL_IDS = {
    [1278915] = true, -- Hearty Quel'dorei Medley
    [1278929] = true, -- Hearty Harandar Celebration
    [1278909] = true, -- Hearty Blooming Feast
    [1278895] = true, -- Hearty Silvermoon Parade
}

local ANNOUNCEMENT = "YO PIG, EAT THE FUCKING HEARTY FEAST"
local DEBOUNCE_SECONDS = 5 -- guards against near-simultaneous casts/messages re-announcing
local COMM_PREFIX = "RBTHeartyFeast"

local lastAnnounceTime = 0

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
end

-- Mythic dungeon (difficultyID 23), Mythic Keystone (8), or any raid
-- difficulty -- not normal/heroic dungeons, scenarios, or open world.
local function isEligibleInstance()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        return true
    end
    return instanceType == "party" and (difficultyID == 8 or difficultyID == 23)
end

local function speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then
        return
    end
    local rate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
    C_VoiceChat.SpeakText(0, text, rate, 100, true)
end

local function announce()
    local now = GetTime()
    if now - lastAnnounceTime < DEBOUNCE_SECONDS then
        return
    end
    lastAnnounceTime = now
    speak(ANNOUNCEMENT)
end

-- Tells the rest of the group to announce it too. The message also echoes
-- back to the sender, but the debounce swallows that so the caster's local
-- announce() doesn't play twice.
local function broadcastToGroup()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, "GO", channel)
    end
end

function ns.IsHeartyFeastTTSEnabled()
    return ReforgedBreakTimerDB and ReforgedBreakTimerDB.heartyFeastTTS
end

function ns.SetHeartyFeastTTSEnabled(isEnabled)
    ReforgedBreakTimerDB.heartyFeastTTS = isEnabled
end

-- Bypasses the enabled/instance checks and debounce, for the options panel's Test button.
function ns.TestHeartyFeastAnnouncement()
    speak(ANNOUNCEMENT)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not ns.IsHeartyFeastTTSEnabled() or not isEligibleInstance() then
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellId = ...
        if not HEARTY_FEAST_SPELL_IDS[spellId] then
            return
        end
        announce()
        broadcastToGroup()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix = ...
        if prefix == COMM_PREFIX then
            announce()
        end
    end
end)
