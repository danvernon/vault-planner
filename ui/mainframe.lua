local addonName, VaultPlanner = ...

local MainFrame = {}
VaultPlanner.MainFrame = MainFrame

local TRACK_COL_WIDTH = 130
local CHAR_COL_WIDTH = 270
local ROW_HEIGHT = 44
local ROW_STRIDE = 50
local HEADER_HEIGHT = 22
local CLASS_ICON_SIZE = 32

local COLORS = {
    accent  = "ff00d1c1",
    section = "ff7be3dc",
    value   = "ffffffff",
    muted   = "ff9bb0ae",
    good    = "ff5cff7a",
    warn    = "ffffc857",
    cardBg      = { 0.06, 0.08, 0.11, 0.90 },
    headerBg    = { 0.04, 0.06, 0.08, 0.95 },
    accentLine  = { 0.48, 0.89, 0.86, 0.9 },
    divider     = { 0.28, 0.36, 0.42, 1.0 },
}

local function C(hex, text) return string.format("|c%s%s|r", hex, text) end

local function ApplyCardBg(frame, color)
    if not frame._cardBg then
        frame._cardBg = frame:CreateTexture(nil, "BACKGROUND")
        frame._cardBg:SetAllPoints()
    end
    local c = color or COLORS.cardBg
    frame._cardBg:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function CountFilled(slots)
    local n = 0
    for _, s in ipairs(slots or {}) do if s.filled then n = n + 1 end end
    return n
end

local function FormatSlot(trackKey, slot)
    if not slot then return C(COLORS.muted, "—") end
    -- Unclaimed leftover reward from a prior week — flagged in cyan accent.
    if (slot.claimableLevel or 0) > 0 then
        return C(COLORS.accent, string.format("Claim · %d", slot.claimableLevel))
    end
    if slot.filled then
        local label = VaultPlanner.FormatLevelLabel(trackKey, slot.level)
        local ilvl = slot.rewardItemLevel or 0
        if ilvl > 0 and label ~= "" then
            return C(COLORS.good, string.format("%s · %d", label, ilvl))
        elseif ilvl > 0 then
            return C(COLORS.good, string.format("ilvl %d", ilvl))
        elseif label ~= "" then
            return C(COLORS.good, label)
        end
        return C(COLORS.good, "Filled")
    end
    return C(COLORS.warn, string.format("%d/%d", slot.progress or 0, slot.threshold or 0))
end

local function FormatTrackCell(trackKey, slots)
    if not slots or #slots == 0 then
        return C(COLORS.muted, "No progress")
    end
    local lines = {}
    for s = 1, 3 do lines[#lines + 1] = FormatSlot(trackKey, slots[s]) end
    return table.concat(lines, "\n")
end

local function CreateCharRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_STRIDE))
    row:SetPoint("RIGHT", 0, 0)

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetPoint("TOPLEFT", 0, 4)
    row.divider:SetPoint("RIGHT", 0, 0)
    row.divider:SetHeight(1)
    local d = COLORS.divider
    row.divider:SetColorTexture(d[1], d[2], d[3], d[4])
    if index == 1 then row.divider:Hide() end

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetPoint("TOPLEFT", 4, -4)
    row.classIcon:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
    row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.classIcon:SetTexCoord(0, 0.25, 0, 0.25)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 8, -2)
    row.name:SetJustifyH("LEFT")

    row.claimBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.claimBadge:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.claimBadge:SetJustifyH("LEFT")
    row.claimBadge:Hide()

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.meta:SetWidth(CHAR_COL_WIDTH - CLASS_ICON_SIZE - 16)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetTextColor(0.61, 0.69, 0.68)

    row.trackTexts = {}
    for i, t in ipairs(VaultPlanner.TRACKS) do
        local x = (CHAR_COL_WIDTH - 8) + (i - 1) * TRACK_COL_WIDTH
        local body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", x, -4)
        body:SetWidth(TRACK_COL_WIDTH - 8)
        body:SetJustifyH("LEFT")
        body:SetSpacing(1)
        row.trackTexts[t.key] = body
    end

    return row
end

local function ApplyClassIcon(texture, classFile)
    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
    else
        texture:SetTexCoord(0, 0.25, 0, 0.25)
    end
end

local function BuildSortedList()
    local chars = VaultPlanner.Scanner:GetCharacters()
    local list = {}
    for key, c in pairs(chars) do
        c._key = key
        list[#list + 1] = c
    end
    table.sort(list, function(a, b)
        local af, bf = 0, 0
        for _, t in pairs(a.tracks or {}) do af = af + CountFilled(t) end
        for _, t in pairs(b.tracks or {}) do bf = bf + CountFilled(t) end
        if af ~= bf then return af > bf end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return list
end

function MainFrame:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "VaultPlannerFrame", UIParent)
    f:SetSize(CHAR_COL_WIDTH + TRACK_COL_WIDTH * 3 + 36, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(20)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.03, 0.04, 0.06, 0.95)

    -- Top bar
    f.topBar = f:CreateTexture(nil, "ARTWORK")
    f.topBar:SetPoint("TOPLEFT", 0, 0)
    f.topBar:SetPoint("TOPRIGHT", 0, 0)
    f.topBar:SetHeight(28)
    f.topBar:SetColorTexture(0.06, 0.08, 0.11, 0.98)

    f.topBarTopEdge = f:CreateTexture(nil, "BORDER")
    f.topBarTopEdge:SetPoint("TOPLEFT", 0, 0)
    f.topBarTopEdge:SetPoint("TOPRIGHT", 0, 0)
    f.topBarTopEdge:SetHeight(1)
    f.topBarTopEdge:SetColorTexture(0, 0.82, 0.76, 0.55)

    f.topBarBottomEdge = f:CreateTexture(nil, "BORDER")
    f.topBarBottomEdge:SetPoint("TOPLEFT", 0, -28)
    f.topBarBottomEdge:SetPoint("TOPRIGHT", 0, -28)
    f.topBarBottomEdge:SetHeight(1)
    f.topBarBottomEdge:SetColorTexture(0, 0.82, 0.76, 0.55)

    -- Footer bar
    f.footerBar = f:CreateTexture(nil, "ARTWORK")
    f.footerBar:SetPoint("BOTTOMLEFT", 0, 0)
    f.footerBar:SetPoint("BOTTOMRIGHT", 0, 0)
    f.footerBar:SetHeight(28)
    f.footerBar:SetColorTexture(0.05, 0.07, 0.1, 0.98)

    f.footerTopEdge = f:CreateTexture(nil, "BORDER")
    f.footerTopEdge:SetPoint("BOTTOMLEFT", 0, 28)
    f.footerTopEdge:SetPoint("BOTTOMRIGHT", 0, 28)
    f.footerTopEdge:SetHeight(1)
    f.footerTopEdge:SetColorTexture(0, 0.82, 0.76, 0.55)

    -- Title
    f.titleIcon = f:CreateTexture(nil, "OVERLAY")
    f.titleIcon:SetPoint("TOPLEFT", 8, -3)
    f.titleIcon:SetSize(22, 22)
    f.titleIcon:SetTexture("Interface\\Icons\\inv_misc_coin_01")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", f.titleIcon, "RIGHT", 6, 0)
    f.title:SetText("Vault Planner")

    -- Close button
    f.close = CreateFrame("Button", nil, f)
    f.close:SetPoint("TOPRIGHT", -6, -5)
    f.close:SetSize(18, 18)
    f.close.bg = f.close:CreateTexture(nil, "BACKGROUND")
    f.close.bg:SetAllPoints()
    f.close.bg:SetColorTexture(0, 0, 0, 0)
    f.close.label = f.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.close.label:SetPoint("CENTER", 0, 0)
    f.close.label:SetText("X")
    f.close.label:SetTextColor(1, 1, 1)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.close:SetScript("OnEnter", function()
        f.close.bg:SetColorTexture(0.16, 0.28, 0.32, 0.8)
        f.close.label:SetTextColor(0.85, 1, 0.97)
    end)
    f.close:SetScript("OnLeave", function()
        f.close.bg:SetColorTexture(0, 0, 0, 0)
        f.close.label:SetTextColor(1, 1, 1)
    end)

    -- Reset countdown (in footer, bottom-right)
    f.reset = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.reset:SetPoint("BOTTOMRIGHT", -10, 8)
    f.reset:SetJustifyH("RIGHT")

    -- Refresh button (top bar, left of close)
    f.refresh = CreateFrame("Button", nil, f)
    f.refresh:SetSize(72, 18)
    f.refresh:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.refresh.bg = f.refresh:CreateTexture(nil, "BACKGROUND")
    f.refresh.bg:SetAllPoints()
    f.refresh.bg:SetColorTexture(0.08, 0.11, 0.14, 0.9)
    f.refresh.border = f.refresh:CreateTexture(nil, "BORDER")
    f.refresh.border:SetAllPoints()
    f.refresh.border:SetColorTexture(0, 0.82, 0.76, 0.25)
    f.refresh.label = f.refresh:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.refresh.label:SetPoint("CENTER", 0, 0)
    f.refresh.label:SetText("Refresh")
    f.refresh:SetScript("OnEnter", function()
        f.refresh.bg:SetColorTexture(0.12, 0.18, 0.22, 0.95)
    end)
    f.refresh:SetScript("OnLeave", function()
        f.refresh.bg:SetColorTexture(0.08, 0.11, 0.14, 0.9)
    end)
    f.refresh:SetScript("OnClick", function()
        VaultPlanner.Scanner:ScanCurrentCharacter()
        MainFrame:Render()
    end)

    -- Card containing header + scrolling row list (transparent so it blends
    -- into the main backdrop instead of looking like an inset panel).
    f.card = CreateFrame("Frame", nil, f)
    f.card:SetPoint("TOPLEFT", 0, -28)
    f.card:SetPoint("BOTTOMRIGHT", 0, 28)

    local a = COLORS.accentLine

    -- Column header strip
    f.header = CreateFrame("Frame", nil, f.card)
    f.header:SetHeight(HEADER_HEIGHT)
    f.header:SetPoint("TOPLEFT", 8, -8)
    f.header:SetPoint("RIGHT", -8, 0)

    f.header.bg = f.header:CreateTexture(nil, "BACKGROUND")
    f.header.bg:SetAllPoints()
    local h = COLORS.headerBg
    f.header.bg:SetColorTexture(h[1], h[2], h[3], h[4])

    f.header.divider = f.header:CreateTexture(nil, "ARTWORK")
    f.header.divider:SetPoint("BOTTOMLEFT", 0, -1)
    f.header.divider:SetPoint("BOTTOMRIGHT", 0, -1)
    f.header.divider:SetHeight(1)
    f.header.divider:SetColorTexture(a[1], a[2], a[3], 0.6)

    local charLabel = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charLabel:SetPoint("LEFT", 4, 0)
    charLabel:SetText(C(COLORS.section, "CHARACTER"))

    for i, t in ipairs(VaultPlanner.TRACKS) do
        local x = (CHAR_COL_WIDTH - 8) + (i - 1) * TRACK_COL_WIDTH
        local label = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", x, 0)
        label:SetText(C(COLORS.section, t.label:upper()))
    end

    f.scroll = CreateFrame("ScrollFrame", nil, f.card, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 8, -8 - HEADER_HEIGHT - 4)
    f.scroll:SetPoint("BOTTOMRIGHT", -8, 8)

    -- Hide the default Blizzard scrollbar chrome
    local sb = f.scroll.ScrollBar
    if sb then
        sb:Hide()
        sb.Show = function() end
    end
    for _, name in ipairs({ "ScrollBarTop", "ScrollBarBottom", "ScrollBarMiddle" }) do
        local tex = _G[(f.scroll:GetName() or "") .. name]
        if tex then tex:Hide() end
    end

    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        local step = ROW_STRIDE
        local target = math.max(0, math.min(maxScroll, current - delta * step))
        self:SetVerticalScroll(target)
    end)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(1, 1)
    f.scroll:SetScrollChild(f.content)

    f.empty = f.card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER", f.scroll, "CENTER", 0, 0)
    f.empty:SetText("No characters scanned yet — log in on an alt to populate.")
    f.empty:Hide()

    f.rows = {}
    self.frame = f
    return f
end

function MainFrame:Render()
    local f = self:Build()

    local list = BuildSortedList()
    local now = time()

    local nextReset
    for _, c in ipairs(list) do
        if c.weeklyResetAt and c.weeklyResetAt > now then
            if not nextReset or c.weeklyResetAt < nextReset then
                nextReset = c.weeklyResetAt
            end
        end
    end
    if nextReset then
        f.reset:SetText("Weekly reset in " .. C(COLORS.section, VaultPlanner.FormatDuration(nextReset - now)))
    else
        f.reset:SetText("")
    end

    if #list == 0 then
        f.empty:Show()
    else
        f.empty:Hide()
    end

    for i, c in ipairs(list) do
        local row = f.rows[i] or CreateCharRow(f.content, i)
        f.rows[i] = row
        row:Show()

        ApplyClassIcon(row.classIcon, c.classFile)
        row.name:SetText(C(COLORS.value, c.name or c._key or "?"))

        local claimedThisWeek = c.vaultClaimedExpiresAt and c.vaultClaimedExpiresAt > now
        if c.canClaim then
            row.claimBadge:SetText("|TInterface\\GossipFrame\\AvailableQuestIcon:14|t " .. C(COLORS.warn, "Vault ready"))
            row.claimBadge:Show()
        elseif claimedThisWeek then
            row.claimBadge:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. C(COLORS.good, "Vault claimed"))
            row.claimBadge:Show()
        else
            row.claimBadge:Hide()
        end

        local seenAgo = c.lastSeen and VaultPlanner.FormatDuration(now - c.lastSeen) .. " ago" or "?"
        row.meta:SetText(C(COLORS.muted, string.format("%s  •  ilvl %d  •  %s",
            c.realm or "?", c.ilvl or 0, seenAgo)))

        for _, t in ipairs(VaultPlanner.TRACKS) do
            row.trackTexts[t.key]:SetText(FormatTrackCell(t.key, (c.tracks or {})[t.key]))
        end
    end

    for i = #list + 1, #f.rows do
        f.rows[i]:Hide()
    end

    f.content:SetSize(f.scroll:GetWidth(), math.max(1, #list * ROW_STRIDE + 8))
end

function MainFrame:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Render()
        self.frame:Show()
    end
end
