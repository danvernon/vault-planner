local addonName, VaultPlanner = ...

-- Track ids resolved lazily from Enum.WeeklyRewardChestThresholdType; a fallback
-- map covers the case where the enum is missing. Numbers came from
-- recent Blizzard API docs but the enum is authoritative when present.
local FALLBACK_IDS = { Raid = 1, Activities = 2, World = 3 }

local function EnumId(name)
    local E = Enum and Enum.WeeklyRewardChestThresholdType
    if E and E[name] ~= nil then return E[name] end
    return FALLBACK_IDS[name]
end

VaultPlanner.TRACKS = {
    { key = "raid",  label = "Raid",    enumName = "Raid" },
    { key = "mplus", label = "Mythic+", enumName = "Activities" },
    { key = "world", label = "World",   enumName = "World" },
}

function VaultPlanner.TrackId(track)
    return EnumId(track.enumName)
end

local function FormatRaidDifficulty(level)
    local id = DifficultyUtil and DifficultyUtil.ID
    if id then
        if level == id.PrimaryRaidLFR or level == 17 then return "LFR" end
        if level == id.PrimaryRaidNormal or level == 14 then return "Normal" end
        if level == id.PrimaryRaidHeroic or level == 15 then return "Heroic" end
        if level == id.PrimaryRaidMythic or level == 16 then return "Mythic" end
    end
    -- Last-ditch hardcoded mapping (DF/TWW/Midnight values)
    if level == 17 then return "LFR" end
    if level == 14 then return "Normal" end
    if level == 15 then return "Heroic" end
    if level == 16 then return "Mythic" end
    return "diff " .. tostring(level)
end

function VaultPlanner.FormatLevelLabel(trackKey, level)
    if not level or level <= 0 then return "" end
    if trackKey == "mplus" then return "+" .. level end
    if trackKey == "raid" then return FormatRaidDifficulty(level) end
    return "T" .. level
end

function VaultPlanner.GetCharacterKey(name, realm)
    return string.format("%s-%s", name or "Unknown", realm or "UnknownRealm")
end

function VaultPlanner.GetCurrentCharacterKey()
    return VaultPlanner.GetCharacterKey(UnitName("player"), GetRealmName())
end

function VaultPlanner.ClassColorHex(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c and c.colorStr then
        return c.colorStr
    end
    if c then
        return string.format("ff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
    end
    return "ffffffff"
end

function VaultPlanner.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end
