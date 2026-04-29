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
VaultPlanner.events:RegisterEvent("PLAYER_ENTERING_WORLD")
VaultPlanner.events:RegisterEvent("WEEKLY_REWARDS_UPDATE")
VaultPlanner.events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
VaultPlanner.events:RegisterEvent("BOSS_KILL")
VaultPlanner.events:RegisterEvent("ENCOUNTER_END")

VaultPlanner.events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        QueueRescan(0)
        C_Timer.After(3, function() QueueRescan(0) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        QueueRescan(2)
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        QueueRescan(0.25)
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "BOSS_KILL" or event == "ENCOUNTER_END" then
        QueueRescan(5)
    end
end)
