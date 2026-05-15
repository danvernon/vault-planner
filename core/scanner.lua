local addonName, VaultPlanner = ...

local Scanner = {}
VaultPlanner.Scanner = Scanner

local DB_VERSION = 1

local function EnsureDB()
    VaultPlannerDB = VaultPlannerDB or {}
    if VaultPlannerDB.version ~= DB_VERSION then
        VaultPlannerDB.characters = {}
        VaultPlannerDB.version = DB_VERSION
    end
    VaultPlannerDB.characters = VaultPlannerDB.characters or {}
end

local function GetRewardItemLevel(activity)
    if not activity or not activity.id then return 0 end
    if not (C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks) then return 0 end
    local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
    if not link or link == "" then return 0 end
    return GetDetailedItemLevelInfo(link) or 0
end

local function ScanTrack(track)
    local typeId = VaultPlanner.TrackId(track)
    if not typeId then return {} end
    local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities(typeId)
    if not activities then return {} end

    local slots = {}
    for _, a in ipairs(activities) do
        local filled = (a.progress or 0) >= (a.threshold or 0)
        slots[#slots + 1] = {
            id = a.id,
            index = a.index,
            threshold = a.threshold,
            progress = a.progress,
            level = a.level or 0,
            claimableLevel = a.claimableLevel or 0,
            filled = filled,
            -- Reward ilvl works for locked slots too; it reflects what the
            -- reward would be at the slot's current trajectory.
            rewardItemLevel = GetRewardItemLevel(a),
        }
    end
    table.sort(slots, function(a, b) return a.index < b.index end)
    return slots
end

local function CurrentItemLevel()
    local _, equipped = GetAverageItemLevel()
    return math.floor((equipped or 0) + 0.5)
end

function Scanner:ScanCurrentCharacter(opts)
    opts = opts or {}
    EnsureDB()

    if C_WeeklyRewards and C_WeeklyRewards.HasGeneratedRewards
        and not C_WeeklyRewards.HasGeneratedRewards()
        and C_WeeklyRewards.RequestRewards then
        C_WeeklyRewards.RequestRewards()
    end

    local key = VaultPlanner.GetCurrentCharacterKey()
    local record = VaultPlannerDB.characters[key] or {}

    record.name = UnitName("player")
    record.realm = GetRealmName()
    record.classFile = select(2, UnitClass("player"))
    record.level = UnitLevel("player")
    record.ilvl = CurrentItemLevel()
    record.lastSeen = time()

    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        record.weeklyResetAt = time() + C_DateAndTime.GetSecondsUntilWeeklyReset()
    end

    -- Roll the vault status forward at the weekly reset boundary.
    local now = time()
    if record.vaultStatusExpiresAt and now >= record.vaultStatusExpiresAt then
        record.vaultStatus = nil
        record.vaultStatusExpiresAt = nil
    end

    record.tracks = record.tracks or {}
    local anyTrackPopulated = false
    for _, t in ipairs(VaultPlanner.TRACKS) do
        local scanned = ScanTrack(t)
        if #scanned > 0 then
            record.tracks[t.key] = scanned
            anyTrackPopulated = true
        else
            record.tracks[t.key] = record.tracks[t.key] or {}
        end
    end

    -- CanClaimRewards / claimableLevel are only authoritative while the vault
    -- frame is actually visible. Closing the vault clears Blizzard's cached
    -- state and fires another WEEKLY_REWARDS_UPDATE with empty data, which
    -- would otherwise look like a claim transition. Gate the update behind
    -- WeeklyRewardsFrame:IsShown() so canClaim only changes when we have
    -- trustworthy data — i.e. the player actually has the vault open.
    local vaultFrameOpen = WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown
        and WeeklyRewardsFrame:IsShown()
    -- liveClaimState is passed from the vault frame's OnHide hook, where the
    -- API still reflects the user's just-finished interaction even though the
    -- frame is no longer visible.
    local trustClaimState = opts.liveClaimState or vaultFrameOpen
    local prevStatus = record.vaultStatus

    if anyTrackPopulated and trustClaimState
        and C_WeeklyRewards and C_WeeklyRewards.CanClaimRewards then
        local canClaim = C_WeeklyRewards.CanClaimRewards()
        if not canClaim then
            for _, slots in pairs(record.tracks) do
                for _, s in ipairs(slots) do
                    if (s.claimableLevel or 0) > 0 then
                        canClaim = true
                        break
                    end
                end
                if canClaim then break end
            end
        end

        if canClaim then
            -- A reward is waiting. Always reflect this in the DB.
            record.vaultStatus = "ready"
            record.vaultStatusExpiresAt = record.weeklyResetAt
        elseif prevStatus == "ready" then
            -- We previously knew there was a vault to claim and now there
            -- isn't — the user has just claimed it. Persist that.
            record.vaultStatus = "claimed"
            record.vaultStatusExpiresAt = record.weeklyResetAt
        end
        -- If canClaim is false and prevStatus wasn't "ready", we have no signal
        -- to assert anything — leave the existing status alone.
    end

    -- One-shot migration from the old multi-field scheme.
    if record.canClaim ~= nil or record.canClaimExpiresAt or record.vaultClaimedExpiresAt then
        if record.canClaim and not record.vaultStatus then
            record.vaultStatus = "ready"
            record.vaultStatusExpiresAt = record.canClaimExpiresAt or record.weeklyResetAt
        elseif record.vaultClaimedExpiresAt and not record.vaultStatus then
            record.vaultStatus = "claimed"
            record.vaultStatusExpiresAt = record.vaultClaimedExpiresAt
        end
        record.canClaim = nil
        record.canClaimExpiresAt = nil
        record.vaultClaimedExpiresAt = nil
    end

    VaultPlannerDB.characters[key] = record
end

local function CurrentCharacterRecord()
    EnsureDB()
    local key = VaultPlanner.GetCurrentCharacterKey()
    local record = VaultPlannerDB.characters[key] or {}
    VaultPlannerDB.characters[key] = record
    return record
end

local function ClearStaleWeeklyKills(record)
    local kills = record.weeklyKills
    if not kills then return end
    if kills.expiresAt and time() >= kills.expiresAt then
        record.weeklyKills = nil
    end
end

local function EnsureWeeklyKills(record)
    ClearStaleWeeklyKills(record)
    if not record.weeklyKills then
        local expiresAt
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
            expiresAt = time() + C_DateAndTime.GetSecondsUntilWeeklyReset()
        end
        record.weeklyKills = { raid = {}, mplus = {}, expiresAt = expiresAt }
    end
    record.weeklyKills.raid = record.weeklyKills.raid or {}
    record.weeklyKills.mplus = record.weeklyKills.mplus or {}
    return record.weeklyKills
end

function Scanner:RecordEncounter(encounterID, encounterName, difficultyID, success)
    if success ~= 1 then return end
    local _, instanceType = IsInInstance()
    if instanceType ~= "raid" then return end

    local record = CurrentCharacterRecord()
    local kills = EnsureWeeklyKills(record)
    table.insert(kills.raid, {
        encounterID = encounterID,
        name = encounterName,
        difficultyID = difficultyID,
        killedAt = time(),
    })
end

function Scanner:RecordChallengeMode()
    if not (C_ChallengeMode and C_ChallengeMode.GetCompletionInfo) then return end
    local mapID, level, _, onTime = C_ChallengeMode.GetCompletionInfo()
    if not mapID or not level or level <= 0 then return end

    local mapName
    if C_ChallengeMode.GetMapUIInfo then
        mapName = C_ChallengeMode.GetMapUIInfo(mapID)
    end

    local record = CurrentCharacterRecord()
    local kills = EnsureWeeklyKills(record)
    table.insert(kills.mplus, {
        mapID = mapID,
        name = mapName or "Dungeon",
        level = level,
        onTime = onTime and true or false,
        completedAt = time(),
    })
end

function Scanner:GetCharacters()
    EnsureDB()
    local now = time()
    for _, record in pairs(VaultPlannerDB.characters) do
        ClearStaleWeeklyKills(record)
        -- Expire vault status at its boundary.
        if record.vaultStatusExpiresAt and now >= record.vaultStatusExpiresAt then
            record.vaultStatus = nil
            record.vaultStatusExpiresAt = nil
        end
        -- Belt-and-suspenders for records that have a status without an
        -- explicit expiry but whose last known weekly-reset boundary has
        -- already passed (e.g. legacy data, alts never logged in).
        if record.vaultStatus and not record.vaultStatusExpiresAt
            and record.weeklyResetAt and now >= record.weeklyResetAt then
            record.vaultStatus = nil
        end
    end
    return VaultPlannerDB.characters
end
