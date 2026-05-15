local addonName, VaultPlanner = ...

VaultPlanner.events = CreateFrame("Frame")
local rescanQueued = false

local function QueueRescan(delay)
    if rescanQueued then return end
    rescanQueued = true
    C_Timer.After(delay or 0, function()
        rescanQueued = false
        VaultPlanner.Scanner:ScanCurrentCharacter()
        if VaultPlanner.MainFrame.frame and VaultPlanner.MainFrame.frame:IsShown() then
            VaultPlanner.MainFrame:Render()
        end
    end)
end

-- Force-load Blizzard's weekly-rewards UI addon so we can hook the frame's
-- OnHide; that's the only reliable moment to read the claim state after the
-- user has claimed (Blizzard clears the cached data soon after).
local vaultHookInstalled = false
local function InstallVaultFrameHook()
    if vaultHookInstalled then return end
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    if not WeeklyRewardsFrame then return end
    vaultHookInstalled = true
    WeeklyRewardsFrame:HookScript("OnHide", function()
        -- Run immediately while the API still has the live post-claim state,
        -- then again shortly after to catch any final WEEKLY_REWARDS_UPDATE.
        VaultPlanner.Scanner:ScanCurrentCharacter({ liveClaimState = true })
        C_Timer.After(0.25, function()
            VaultPlanner.Scanner:ScanCurrentCharacter({ liveClaimState = true })
            if VaultPlanner.MainFrame.frame and VaultPlanner.MainFrame.frame:IsShown() then
                VaultPlanner.MainFrame:Render()
            end
        end)
    end)
end

SLASH_VAULTPLANNER1 = "/vault"
SLASH_VAULTPLANNER2 = "/vp"
SlashCmdList.VAULTPLANNER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""

    if cmd == "scan" then
        VaultPlanner.Scanner:ScanCurrentCharacter()
        print("|cff00d1c1VaultPlanner:|r Scanned " .. VaultPlanner.GetCurrentCharacterKey())
        return
    end

    if cmd == "remove" then
        local arg = (msg or ""):match("^%s*%S+%s+(.-)%s*$")
        if arg and arg ~= "" and VaultPlannerDB and VaultPlannerDB.characters
            and VaultPlannerDB.characters[arg] then
            VaultPlannerDB.characters[arg] = nil
            print("|cff00d1c1VaultPlanner:|r Removed " .. arg)
        else
            print("|cff00d1c1VaultPlanner:|r Unknown character key.")
        end
        return
    end

    if cmd == "claimed" then
        local key = VaultPlanner.GetCurrentCharacterKey()
        local r = VaultPlannerDB and VaultPlannerDB.characters and VaultPlannerDB.characters[key]
        if r then
            r.vaultStatus = "claimed"
            r.vaultStatusExpiresAt = r.weeklyResetAt
            r.canClaim = nil
            r.canClaimExpiresAt = nil
            r.vaultClaimedExpiresAt = nil
            print("|cff00d1c1VaultPlanner:|r Marked " .. key .. " as claimed.")
            if VaultPlanner.MainFrame.frame and VaultPlanner.MainFrame.frame:IsShown() then
                VaultPlanner.MainFrame:Render()
            end
        end
        return
    end

    if cmd == "list" then
        for key, c in pairs((VaultPlannerDB and VaultPlannerDB.characters) or {}) do
            local seen = c.lastSeen and date("%Y-%m-%d %H:%M", c.lastSeen) or "never"
            print(string.format("  %s — ilvl %d — seen %s", key, c.ilvl or 0, seen))
        end
        return
    end

    VaultPlanner.MainFrame:Toggle()
end

VaultPlanner.events:RegisterEvent("PLAYER_LOGIN")
VaultPlanner.events:RegisterEvent("ADDON_LOADED")
VaultPlanner.events:RegisterEvent("PLAYER_ENTERING_WORLD")
VaultPlanner.events:RegisterEvent("WEEKLY_REWARDS_UPDATE")
VaultPlanner.events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
VaultPlanner.events:RegisterEvent("BOSS_KILL")
VaultPlanner.events:RegisterEvent("ENCOUNTER_END")

VaultPlanner.events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InstallVaultFrameHook()
        QueueRescan(0)
        C_Timer.After(3, function() QueueRescan(0) end)
    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_WeeklyRewards" then
            InstallVaultFrameHook()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        QueueRescan(2)
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        QueueRescan(0.25)
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, _, success = ...
        VaultPlanner.Scanner:RecordEncounter(encounterID, encounterName, difficultyID, success)
        QueueRescan(5)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        VaultPlanner.Scanner:RecordChallengeMode()
        QueueRescan(5)
    elseif event == "BOSS_KILL" then
        QueueRescan(5)
    end
end)
