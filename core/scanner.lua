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

function Scanner:ScanCurrentCharacter()
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

    -- Auto-clear last week's "claimed" badge once the weekly reset has rolled.
    local now = time()
    if record.vaultClaimedExpiresAt and now >= record.vaultClaimedExpiresAt then
        record.vaultClaimedExpiresAt = nil
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
    local prevCanClaim = record.canClaim

    if anyTrackPopulated and vaultFrameOpen
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
        record.canClaim = canClaim

        -- Latch a "claimed for this week" flag that auto-expires at next reset.
        if prevCanClaim and not canClaim and record.weeklyResetAt then
            record.vaultClaimedExpiresAt = record.weeklyResetAt
        end
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
    -- Lazily clear stale weekly kill logs on read.
    for _, record in pairs(VaultPlannerDB.characters) do
        ClearStaleWeeklyKills(record)
    end
    return VaultPlannerDB.characters
end
