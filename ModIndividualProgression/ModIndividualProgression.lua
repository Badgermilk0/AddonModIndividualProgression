-- ============================================================================
--  ModIndividualProgression  —  WoW 3.3.5a Client Addon
--  Slash command:  /ipp   or   /progression
--
--  A read-only view of this character's mod-individual-progression tier:
--  where it stands, what each tier unlocks, and how to reach the next one.
--  Branched from the LegacyServices addon's Temporal Alignment tab, with the
--  gold purchase path taken out.
--
--  It needs NO server script. mod-individual-progression records a
--  character's tier as rewarded hidden quests 66000 + tier (66001..66018), and
--  the stock 3.3.5a client can list its own rewarded quests:
--      QueryQuestsCompleted()  ->  QUEST_QUERY_COMPLETE  ->  GetQuestsCompleted(t)
--  The tier is the highest i with quest 66000 + i rewarded -- the same rule as
--  the module's own IndividualProgression::GetPlayerProgressionFromQuests.
-- ============================================================================

local ADDON_NAME = "ModIndividualProgression"
-- Mirrors "## Version:" in ModIndividualProgression.toc. Quoted back at the
-- player when a companion tab fails to load, so a stale .toc is obvious.
local ADDON_VERSION = "1.0"

-- ============================================================================
-- SAVED VARIABLES
--
-- ModIndividualProgressionDB (account-wide, "## SavedVariables" in the .toc):
--   minimapAngle - where the minimap button sits, in degrees
--   lastTab      - the tab index to reopen on
--   pos          - { point, x, y } of the main window
--
-- The client loads saved variables AFTER it has run this file, and only then
-- fires ADDON_LOADED. So nothing here reads them at file scope -- a table made
-- up here would simply be replaced by the saved one. InitSavedVariables()
-- fills in the defaults from the ADDON_LOADED handler, and every later read
-- goes through the global.
-- ============================================================================

-- LegacyServices' minimap button defaults to 220 degrees; starting 30 degrees
-- away keeps the two from stacking when both addons are installed.
local DEFAULT_MINIMAP_ANGLE = 190

local function InitSavedVariables()
    if type(ModIndividualProgressionDB) ~= "table" then
        ModIndividualProgressionDB = {}
    end
    local db = ModIndividualProgressionDB
    if db.minimapAngle == nil then db.minimapAngle = DEFAULT_MINIMAP_ANGLE end
end

-- ============================================================================
-- DATA MODEL
-- ============================================================================

-- mod-individual-progression keeps a character's tier as rewarded hidden
-- quests: quest 66000 + N is rewarded for every tier N the character has
-- passed (IndividualProgression.cpp, GetPlayerProgressionFromQuests).
local IP_QUEST_BASE = 66000
local MAX_TIERS     = 18        -- PROGRESSION_WOTLK_TIER_5

-- The tier catalog. LegacyServices received these names from its server
-- script (the TI rows); a standalone client has to own them. They mirror
-- ProgressionTiers in LUA_SCRIPTS/LegacyServices/LegacyServices.lua, so both
-- addons name every tier the same way.
--
-- KEY 11 IS DELIBERATELY ABSENT. mod-individual-progression removed
-- PROGRESSION_TBC_TIER_3 in upstream commit 7944f77: Zul'Aman became an entry
-- requirement (RequiredZulAmanProgression, default 12) and Illidan now grants
-- tier 12. The list is therefore SPARSE -- never assume the next tier is
-- charTier + 1; walk forward to the next index that exists.
local TIERS = {
    [1]  = { name = "Molten Core" },
    [2]  = { name = "Onyxia's Lair" },
    [3]  = { name = "Blackwing Lair" },
    [4]  = { name = "Pre-AQ (War Effort)" },
    [5]  = { name = "AQ War (Gates Open)" },
    [6]  = { name = "Ahn'Qiraj" },
    [7]  = { name = "Naxxramas (Lvl 60)" },
    [8]  = { name = "Pre-TBC Invasion" },
    [9]  = { name = "Karazhan & Gruul's Lair" },
    [10] = { name = "Serpentshrine & Tempest Keep" },
    -- [11] intentionally omitted -- see above.
    [12] = { name = "Hyjal & Black Temple" },
    [13] = { name = "Sunwell Plateau" },
    [14] = { name = "Wrath of the Lich King" },
    [15] = { name = "Ulduar" },
    [16] = { name = "Trial of the Crusader" },
    [17] = { name = "Icecrown Citadel" },
    [18] = { name = "Ruby Sanctum" },
}

-- Names for tier values a character can HOLD that have no row of their own:
--   0   nothing passed yet;
--   11  a character that killed Zul'jin before upstream 7944f77 still has quest
--       66011 as its highest, and the module really does report 11 for it
--       (its quest_template row still exists). There is no row to show, but the
--       header must not call that character "The Beginning".
local TIER_NAME_START   = "The Beginning"
local TIER_NAME_RETIRED = { [11] = "Zul'Aman (retired tier)" }

local data = {
    charTier      = 0,        -- highest progression quest this character has been rewarded
    loaded        = false,    -- true once a completed-quest reply has been read this session
    queryTimedOut = false,    -- our query went unanswered before the first reply arrived
    unsupported   = false,    -- this client has no QueryQuestsCompleted() at all
    levelOverride = nil,      -- PLAYER_LEVEL_UP's new level, until UnitLevel catches up
    tiers         = TIERS,    -- [idx] = { name }  (sparse: no 11)
}

-- ============================================================================
-- UTILITY
-- ============================================================================

local function TierName(idx)
    if TIERS[idx] then return TIERS[idx].name end
    return TIER_NAME_RETIRED[idx] or TIER_NAME_START
end

-- The level ceiling a character has while sitting AT tierIdx. Mirrors
-- IndividualProgressionPlayer.cpp (OnPlayerGiveXP): XP stops at 60 until the
-- character has passed tier 8 (PROGRESSION_PRE_TBC) and at 70 until it has
-- passed tier 13 (PROGRESSION_TBC_TIER_5) -- so the cap lifts ON tiers 8 and
-- 13. 80 means "no progression cap". Must stay in step with the `cap` field in
-- alignFrame.tierInfo.
local function CapForTier(tierIdx)
    if tierIdx < 8  then return 60 end
    if tierIdx < 13 then return 70 end
    return 80
end

-- UnitLevel("player") can still report the OLD level inside PLAYER_LEVEL_UP,
-- so that handler parks the new level here until the unit catches up.
local function PlayerLevel()
    local lvl = UnitLevel("player") or 0
    if data.levelOverride and data.levelOverride > lvl then
        return data.levelOverride
    end
    return lvl
end

-- ============================================================================
-- FORWARD DECLARATIONS  (filled in after GUI creation)
-- ============================================================================

local UpdateDisplay              -- refreshes all visible GUI elements
local RefreshActiveTab           -- re-pulls the data the currently open tab renders

-- ============================================================================
-- PROGRESS READING  (the client's own completed-quest list)
--
-- QueryQuestsCompleted() asks the server for every quest this character has
-- been rewarded; the reply fires QUEST_QUERY_COMPLETE, after which
-- GetQuestsCompleted(t) fills t[questId] = true. AzerothCore's handler has no
-- throttle of its own (WorldSession::HandleQueryQuestsCompleted), but every
-- reply carries the WHOLE rewarded set -- thousands of ids on a well-played
-- character -- so the addon asks sparingly:
--
--   * every request goes through RequestProgress(delay);
--   * one shared OnUpdate driver sends at most one query per QUERY_GAP and
--     merges requests that arrive while one is pending;
--   * ANY QUEST_QUERY_COMPLETE is read, whoever asked -- DataStore_Quests,
--     Zygor and EveryQuest all issue the same query, so their answers are free.
--
-- One driver frame, deliberately: a frame per timer leaks permanently on
-- 3.3.5a (frames are never garbage collected) and there is no C_Timer.
-- ============================================================================

local QUERY_GAP     = 5      -- seconds between two of our own queries, at least
local QUERY_TIMEOUT = 10     -- seconds before an unanswered first query is reported

-- GetQuestsCompleted fills the table it is given without clearing it, so the
-- reused table is wiped first -- otherwise a tier the server has since taken
-- away (a GM's .ip set to a lower value) would linger as a stale key. It is
-- wiped again afterwards so thousands of ids are not held between reads.
local completedQuests = {}

local function ReadTier()
    if not GetQuestsCompleted then return data.charTier end
    wipe(completedQuests)
    GetQuestsCompleted(completedQuests)
    local tier = 0
    for i = 1, MAX_TIERS do
        if completedQuests[IP_QUEST_BASE + i] then tier = i end
    end
    wipe(completedQuests)
    return tier
end

local queryDriver = CreateFrame("Frame")
queryDriver:Hide()
queryDriver.dueAt   = nil    -- GetTime() at which the pending query goes out
queryDriver.sentAt  = nil    -- GetTime() of our last QueryQuestsCompleted()
queryDriver.waiting = false  -- a query of ours is out and not yet answered
queryDriver:SetScript("OnUpdate", function(self)
    local now = GetTime()
    if self.dueAt and now >= self.dueAt then
        self.dueAt   = nil
        self.sentAt  = now
        self.waiting = true
        QueryQuestsCompleted()
    end
    if self.waiting and now - self.sentAt >= QUERY_TIMEOUT then
        self.waiting = false
        -- Only the FIRST read matters here: once a tier is on screen, a late or
        -- lost reply just leaves it as it was. Before that, a silent
        -- "Loading..." would be the only symptom, on a client that shows no
        -- Lua errors either -- so say what happened.
        if not data.loaded then
            data.queryTimedOut = true
            UpdateDisplay()
        end
    end
    if not self.dueAt and not self.waiting then self:Hide() end
end)

-- Ask the server for this character's completed quests, no sooner than
-- `delay` seconds from now and never within QUERY_GAP of our previous query.
-- A request made while another is pending merges into it; the earlier due time
-- wins, so an explicit Refresh is not held back by a background trigger.
local function RequestProgress(delay)
    if not QueryQuestsCompleted then
        data.unsupported = true
        return
    end
    local d   = queryDriver
    local due = GetTime() + (delay or 0)
    if d.sentAt and due < d.sentAt + QUERY_GAP then due = d.sentAt + QUERY_GAP end
    if not d.dueAt or due < d.dueAt then d.dueAt = due end
    d:Show()
end

local function OnQuestQueryComplete()
    queryDriver.waiting = false
    data.charTier      = ReadTier()
    data.loaded        = true
    data.queryTimedOut = false
    UpdateDisplay()
end

-- ============================================================================
-- SHARED SURFACES
--
-- The addon's look lives in ModIndividualProgressionSkin.lua (the global
-- `MIPSkin`), which the .toc loads first. What remain here are local aliases
-- for the factory helpers the tab below calls by name -- thin forwards into
-- MIPSkin, so restyling the addon means editing the skin file and nothing else.
-- ============================================================================

-- Tab-header band: gold title, grey sub-line, carved rule.
local TabHeader = MIPSkin.TabHeader

-- ============================================================================
-- MAIN FRAME
--
-- Sized around a FIXED 648px-wide content column -- the width the Temporal
-- Alignment tab was laid out against in LegacyServices -- plus the navigation
-- rail on its left. Changing MIP_NAV_W or the outer padding moves the window's
-- width and nothing else; changing the content column means revisiting the tab.
-- ============================================================================

local mainFrame = CreateFrame("Frame", "ModIndividualProgressionFrame", UIParent)
mainFrame:SetSize(864, 620)
mainFrame:SetPoint("CENTER")
MIPSkin.Skin(mainFrame, "window")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetFrameStrata("DIALOG")
mainFrame:SetClampedToScreen(true)
mainFrame:Hide()
tinsert(UISpecialFrames, "ModIndividualProgressionFrame")

-- Remember where the player put the window. Only the anchor point and offset
-- are stored; the relative-to frame is always UIParent.
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    if ModIndividualProgressionDB then
        ModIndividualProgressionDB.pos = { point = point, x = x, y = y }
    end
end)

-- Called from ADDON_LOADED, once the saved variables exist.
local function RestoreWindowPosition()
    local p = ModIndividualProgressionDB and ModIndividualProgressionDB.pos
    if p and p.point then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    end
end

-- Title, carried on the gold DialogBox header plaque that sits astride the top
-- border -- the single most recognisable piece of Wrath-era window furniture.
MIPSkin.HeaderPlaque(mainFrame, "|cffFFD100Individual Progression|r", 320)

-- Close button
local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -6, -6)

-- Portrait medallion in the top-left corner, the way every Blizzard panel with
-- a subject wears one. The time-stop emblem is the Temporal Alignment tab's own.
MIPSkin.Portrait(mainFrame, "Interface\\Icons\\Spell_Nature_TimeStop", 40, 22, -16)

-- Stone grain over the (already opaque) fill, and the rule that closes the
-- title band off from the body. Both decorative.
do
    MIPSkin.Grain(mainFrame, 0.45, 12)
    MIPSkin.Divider(mainFrame, -62, 16, 0.45)
end

-- The tier readout on its carved plate at the foot of the navigation rail.
-- Declared here, assigned inside the rail's do-block, and driven by
-- mainFrame.UpdateHeaderStatus().
local tierText

-- Refresh button, seated with the plates at the foot of the rail.
local refreshBtn

-- The class sheet CLASS_ICON_TCOORDS indexes into (the same pairing Altoholic uses).
local CLASS_ICONS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- ---------------------------------------------------------------------------
-- The live readouts that belong to the WINDOW rather than to any one tab,
-- all repainted by mainFrame.UpdateHeaderStatus():
--   title band  who this character is, and their level. (LegacyServices put
--               the character's gold here, because that is what it spent.)
--   rail foot   the progression tier, and whether the module's level cap is
--               holding this character's XP -- in the places LegacyServices'
--               Legacy Points and Resting plates occupied.
-- ---------------------------------------------------------------------------
do
    local plate = MIPSkin.Plate(mainFrame)
    plate:SetPoint("TOPRIGHT", -46, -20)
    plate:SetSize(196, 30)

    local icon = plate:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mainFrame.charIcon = icon
    mainFrame.charText = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainFrame.charText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    mainFrame.charText:SetPoint("RIGHT", -8, 0)
    mainFrame.charText:SetJustifyH("RIGHT")
    mainFrame.charText:SetText("|cff909090--|r")
end

-- ============================================================================
-- NAVIGATION RAIL
--
-- The Auction House's own category widget -- the same rail LegacyServices
-- uses -- grouped into labelled sections so the list reads as a table of
-- contents. Only one tab exists so far. The rail is kept anyway, rather than
-- shrinking the window to a single panel, so the layout matches LegacyServices
-- and a future tab is a TAB_NAMES / TAB_TOOLTIPS / MIPSkin.TAB_ICONS /
-- NAV_SECTIONS entry plus a companion file -- no window rework.
--
-- Tab INDICES match CreateContentFrame(n), the RefreshActiveTab ladder and
-- ModIndividualProgressionDB.lastTab. Both `tabs` and `contentFrames` are
-- walked with ipairs, so the indices must stay contiguous.
-- ============================================================================

local TAB_NAMES = { "Temporal Alignment" }

-- One-line hover description per tab. The rail labels are terse by necessity,
-- so the tooltip is where a tab says what it is for.
local TAB_TOOLTIPS = {
    "This character's progression tier, what each tier unlocks, and how to reach the next one.",
}

-- Tabs whose content frame is built by a companion file rather than this chunk
-- (none yet). Used only to make a failed load say which file to go looking
-- for -- this client runs with scriptErrors off, so an unloaded companion is
-- otherwise just a silent transparent hole where the tab should be.
local COMPANION_FILES = {}

local tabs          = {}
local contentFrames = {}
local activeTab     = 1

-- Geometry. The content column is pinned to 648px, exactly as in LegacyServices.
local MIP_NAV_W     = 172
local CONTENT_TOP_Y = -70

local function CreateContentFrame(index)
    local f = CreateFrame("Frame", nil, mainFrame)
    f:SetPoint("TOPLEFT", 18 + MIP_NAV_W + 8, CONTENT_TOP_Y)
    f:SetPoint("BOTTOMRIGHT", -18, 18)
    MIPSkin.Skin(f, "inset")
    f:SetBackdropColor(0.10, 0.09, 0.08, 0.90)
    f:Hide()
    contentFrames[index] = f
    return f
end

local function SetActiveTab(index)
    activeTab = index
    if ModIndividualProgressionDB then ModIndividualProgressionDB.lastTab = index end
    for i, tab in ipairs(tabs) do
        MIPSkin.NavSelect(tab, i == index)
    end
    for i, cf in ipairs(contentFrames) do
        if i == index then cf:Show() else cf:Hide() end
    end

    -- A tab whose content frame was never built shows as a transparent hole in
    -- the window and nothing else -- and this client runs with scriptErrors OFF,
    -- so the load error that caused it is invisible. Say so out loud instead.
    if not contentFrames[index] then
        local file = COMPANION_FILES[index]
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffff6060[Individual Progression] The \"%s\" tab did not load.|r %s",
            TAB_NAMES[index] or ("tab " .. index),
            file and ("Check that " .. file .. " is in the AddOns folder AND listed in "
                .. "ModIndividualProgression.toc (which should read '## Version: " .. ADDON_VERSION
                .. "'). The file never ran -- had it run and errored, it would have said so.")
                or "Its content frame was never built."))
    end
end

-- Build the rail. Everything here is throwaway once the buttons exist, so it
-- lives in a do-block; the only handles anything later needs are in `tabs`,
-- `tierText`, `refreshBtn` and the fields hung off mainFrame.
do
    -- Section -> the tab indices under it, in the order they are drawn.
    -- "Timeline" is the section Temporal Alignment sits in on LegacyServices.
    local NAV_SECTIONS = {
        { "Timeline", { 1 } },
    }

    local rail = CreateFrame("Frame", nil, mainFrame)
    rail:SetPoint("TOPLEFT", 18, CONTENT_TOP_Y)
    rail:SetPoint("BOTTOMLEFT", 18, 18)
    rail:SetWidth(MIP_NAV_W)
    MIPSkin.Skin(rail, "inset")
    rail:SetBackdropColor(0.10, 0.09, 0.08, 0.90)

    local NAV_H, NAV_GAP, SECTION_GAP = 26, 1, 10
    local y = -10

    for si, section in ipairs(NAV_SECTIONS) do
        local label = MIPSkin.NavHeader(rail, section[1])
        label:SetPoint("TOPLEFT", 12, y)
        y = y - 16

        for _, idx in ipairs(section[2]) do
            local name = TAB_NAMES[idx]
            local b = MIPSkin.NavButton(rail, MIP_NAV_W - 16, NAV_H, name, MIPSkin.TAB_ICONS[idx])
            b:SetPoint("TOPLEFT", 8, y)

            b:SetScript("OnClick", function()
                SetActiveTab(idx)
                RefreshActiveTab()
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(name, 1, 0.82, 0)
                if TAB_TOOLTIPS[idx] then
                    GameTooltip:AddLine(TAB_TOOLTIPS[idx], 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)

            tabs[idx] = b
            y = y - (NAV_H + NAV_GAP)
        end

        -- A rule BETWEEN sections, not after the last one: a trailing rule with
        -- nothing under it reads as a missing section rather than a separator.
        if si < #NAV_SECTIONS then
            MIPSkin.Divider(rail, y - 4, 10, 0.35)
            y = y - SECTION_GAP
        end
    end

    -- ---- Foot of the rail: the tier plate and Refresh ----------------------
    refreshBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
    refreshBtn:SetSize(MIP_NAV_W - 24, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", 12, 12)
    refreshBtn:SetText("Refresh")

    local plate = MIPSkin.Plate(rail)
    plate:SetPoint("BOTTOMLEFT", 8, 42)
    plate:SetPoint("BOTTOMRIGHT", -8, 42)
    plate:SetHeight(48)

    local rune = plate:CreateTexture(nil, "ARTWORK")
    rune:SetSize(22, 22)
    rune:SetPoint("TOPLEFT", 8, -6)
    rune:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
    rune:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local caption = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("LEFT", rune, "RIGHT", 6, 0)
    caption:SetText("|cffb9a06aProgression Tier|r")

    -- The plate is the label; the string is the value.
    tierText = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tierText:SetPoint("BOTTOMLEFT", 10, 6)
    tierText:SetPoint("BOTTOMRIGHT", -10, 6)
    tierText:SetJustifyH("RIGHT")
    tierText:SetText("|cff909090--|r")

    -- ---- XP indicator -----------------------------------------------------
    -- The module withholds all XP at 60 until tier 8 and at 70 until tier 13.
    -- That is the one progression rule a player feels without knowing about
    -- it -- the bar simply stops -- so it is stated once, for the whole window,
    -- the way LegacyServices states whether you are resting.
    local xpPlate = MIPSkin.Plate(rail)
    xpPlate:SetPoint("BOTTOMLEFT", 8, 96)
    xpPlate:SetPoint("BOTTOMRIGHT", -8, 96)
    xpPlate:SetHeight(30)

    local xpIcon = xpPlate:CreateTexture(nil, "ARTWORK")
    xpIcon:SetSize(20, 20)
    xpIcon:SetPoint("LEFT", 9, 0)
    xpIcon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
    xpIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    mainFrame.xpText = xpPlate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.xpText:SetPoint("LEFT", xpIcon, "RIGHT", 6, 0)
    mainFrame.xpText:SetPoint("RIGHT", -8, 0)
    mainFrame.xpText:SetJustifyH("RIGHT")

    xpPlate:EnableMouse(true)
    xpPlate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Experience", 1, 0.82, 0)
        GameTooltip:AddLine("Individual Progression holds a character's experience at level 60 "
            .. "until it reaches Tier 8 (Pre-TBC Invasion), and at level 70 until it reaches "
            .. "Tier 13 (Sunwell Plateau). Levels already earned are kept; only further "
            .. "experience is withheld.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    xpPlate:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.xpIcon = xpIcon
end

-- ---------------------------------------------------------------------------
-- Repaint the window-level readouts. Called from UpdateDisplay; the character
-- plate is live at any time, the tier and XP plates only once a tier has been
-- read (before that there is nothing true to say about either).
-- ---------------------------------------------------------------------------
mainFrame.UpdateHeaderStatus = function()
    local level = PlayerLevel()

    -- Title band: who this is, in their class colour, and their level.
    local name = UnitName("player") or "?"
    local _, classFile = UnitClass("player")
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local hex = "ffffff"
    if color then
        hex = string.format("%02x%02x%02x", math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
    end
    mainFrame.charText:SetText(string.format("|cff%s%s|r  |cffbbbbbbLevel %d|r", hex, name, level))

    local tc = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if tc then
        mainFrame.charIcon:SetTexture(CLASS_ICONS_TEXTURE)
        mainFrame.charIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    end

    if not data.loaded then
        tierText:SetText("|cff909090--|r")
        mainFrame.xpText:SetText("|cff909090--|r")
        mainFrame.xpIcon:SetDesaturated(true)
        mainFrame.xpIcon:SetAlpha(0.55)
        return
    end

    tierText:SetText(string.format("|cffFFD100Tier %d|r", data.charTier))

    local cap = CapForTier(data.charTier)
    if level >= 80 then
        mainFrame.xpText:SetText("|cffbbbbbbMax level|r")
        mainFrame.xpIcon:SetDesaturated(false)
        mainFrame.xpIcon:SetAlpha(0.85)
    elseif level >= cap then
        mainFrame.xpText:SetText(string.format("|cffff8080XP capped at %d|r", cap))
        mainFrame.xpIcon:SetDesaturated(true)
        mainFrame.xpIcon:SetAlpha(0.55)
    else
        mainFrame.xpText:SetText("|cff40dd40Gaining XP|r")
        mainFrame.xpIcon:SetDesaturated(false)
        mainFrame.xpIcon:SetAlpha(1)
    end
end

-- ----------------------------------------------------------------------------
-- The per-tab lazy-load ladder, in ONE place. Three callers need it: clicking
-- a tab, the Refresh button, and the window's OnShow.
-- ----------------------------------------------------------------------------
RefreshActiveTab = function()
    if activeTab == 1 then
        -- Temporal Alignment: re-read the hidden progression quests.
        RequestProgress(0)
    end
end

refreshBtn:SetScript("OnClick", function()
    RefreshActiveTab()
end)

-- ============================================================================
-- TAB 1:  TEMPORAL ALIGNMENT
-- ============================================================================

local alignFrame = CreateContentFrame(1)

TabHeader(alignFrame, "Temporal Alignment",
    "Where this character stands on the progression timeline, and what opens the next era.",
    -56, MIPSkin.TAB_ICONS[1])

-- Info header: the pair of facts the whole tab turns on -- which tier this
-- character is on, and the level it can reach while it stays there.
--
-- Labels and values are SEPARATE font strings anchored to a shared column,
-- because the client's fonts are proportional: padding a label with spaces
-- inside one string leaves the two values starting at visibly different x.
-- The labels are static, so they live in a do-block.
local MIP_STAT_X = 150

do
    local a = alignFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    a:SetPoint("TOPLEFT", 16, -64)
    a:SetJustifyH("LEFT")
    a:SetText("|cffadd8e6Current Tier|r")

    local b = alignFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b:SetPoint("TOPLEFT", 16, -84)
    b:SetJustifyH("LEFT")
    b:SetText("|cffFF8000Level Cap|r")
end

local alignCurrent = alignFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alignCurrent:SetPoint("TOPLEFT", MIP_STAT_X, -64)
alignCurrent:SetPoint("TOPRIGHT", -16, -64)
alignCurrent:SetJustifyH("LEFT")

local alignCap = alignFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alignCap:SetPoint("TOPLEFT", MIP_STAT_X, -84)
alignCap:SetPoint("TOPRIGHT", -16, -84)
alignCap:SetJustifyH("LEFT")

-- Progression bar: how far THIS character has climbed. (LegacyServices
-- measured the account here, because the account's reach was what gold could
-- buy; standalone, the character is the whole story.)
do
    local bar = MIPSkin.StatusBar(alignFrame, nil, 13, 0.85, 0.65, 0.20)
    bar:SetPoint("TOPLEFT", 16, -108)
    bar:SetPoint("TOPRIGHT", -16, -108)
    alignFrame.progressBar     = bar
    alignFrame.progressBarText = bar.text
end

MIPSkin.Divider(alignFrame, -128, 10)

-- Scroll frame for the tier list. The bottom stops short of the frame edge to
-- leave room for the Next Objective card built below.
local alignScroll = CreateFrame("ScrollFrame", "MIPAlignScroll", alignFrame, "UIPanelScrollFrameTemplate")
alignScroll:SetPoint("TOPLEFT", 10, -136)
alignScroll:SetPoint("BOTTOMRIGHT", -30, 116)
MIPSkin.SkinScrollBar("MIPAlignScroll")

local alignScrollChild = CreateFrame("Frame")
alignScrollChild:SetSize(1, 1)      -- resized on every render
alignScroll:SetScrollChild(alignScrollChild)

-- Tier rows
local TIER_ROW_HEIGHT = 26
local tierRows        = {}

-- Wheel scrolling: the list overflows its viewport once an era or two is
-- expanded, and hovering rows for tooltips means the cursor is already there.
alignScroll:EnableMouseWheel(true)
alignScroll:SetScript("OnMouseWheel", function(self, delta)
    local newPos = self:GetVerticalScroll() - (delta * TIER_ROW_HEIGHT)
    local maxPos = self:GetVerticalScrollRange()
    if newPos < 0 then newPos = 0 elseif newPos > maxPos then newPos = maxPos end
    self:SetVerticalScroll(newPos)
end)

for i = 1, MAX_TIERS do
    local row = CreateFrame("Frame", nil, alignScrollChild)
    row:SetSize(600, TIER_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * TIER_ROW_HEIGHT)
    row.tierIndex = i

    -- State highlight, recoloured per tier state in UpdateAlignmentTab.
    -- Also serves as the subtle alternating stripe for rows not reached yet.
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetTexture(1, 1, 1, 0)
    row.hl = hl

    -- Hover wash. Deliberately a SEPARATE texture from row.hl: the renderer
    -- rewrites row.hl on every pass, which would wipe a hover tint stored there
    -- the moment anything re-rendered under the cursor. It is the game's own
    -- list-box highlight, so a hovered tier lights up exactly like a hovered
    -- line in the quest log or the who panel.
    row.hover = MIPSkin.RowHighlight(row)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        alignFrame.ShowTierTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)

    -- Era accent: a thin coloured bar down the row's left edge, tinted per
    -- expansion in UpdateAlignmentTab so each group reads as one continuous
    -- coloured band (header accent + all its rows).
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", 0, 0)

    -- Per-tier boss/content portrait on the left, sunk into a bevelled well so
    -- it reads as a medallion rather than a floating icon (full colour when
    -- reached or next, desaturated when not reached yet).
    local well = MIPSkin.IconWell(row, 20)
    well:SetPoint("LEFT", 7, 0)
    well:Hide()
    row.iconWell = well
    row.icon = well.icon

    -- Small "completed" check stamped into the portrait's lower-right corner.
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(12, 12)
    check:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", 4, -4)
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    check:Hide()
    row.check = check

    -- Tier label. 290px holds the longest one, "[Tier 10]  Serpentshrine &
    -- Tempest Keep", and leaves the requirement column the room it needs.
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 34, 0)
    text:SetJustifyH("LEFT")
    text:SetWidth(290)
    row.text = text

    -- Requirement: the kill or quest that grants the tier, right-aligned into
    -- its own column (this was the price column in LegacyServices). 230px fits
    -- the longest, "Quest: Chaos and Destruction".
    local goal = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goal:SetPoint("RIGHT", -10, 0)
    goal:SetJustifyH("RIGHT")
    goal:SetWidth(230)
    row.goal = goal

    tierRows[i] = row
end

-- Next Objective card: pinned to the bottom of the tab so the player always
-- sees what to do next without hunting through the list.
do
    local card = CreateFrame("Frame", nil, alignFrame)
    card:SetPoint("BOTTOMLEFT", 8, 8)
    card:SetPoint("BOTTOMRIGHT", -8, 8)
    card:SetHeight(96)
    MIPSkin.Skin(card, "inset")
    card:SetBackdropColor(0.16, 0.14, 0.11, 0.95)

    -- The objective's portrait, sunk into a well: this card is the tab's call
    -- to action, so its icon is the subject rather than a bullet point.
    local well = MIPSkin.IconWell(card, 40, 12, -12)
    card.iconWell = well
    card.icon = well.icon
    well:Hide()

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 60, -13)
    card.title:SetPoint("TOPRIGHT", -12, -13)
    card.title:SetJustifyH("LEFT")

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.body:SetPoint("TOPLEFT", 60, -31)
    card.body:SetPoint("TOPRIGHT", -12, -31)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetHeight(56)
    card.body:SetWordWrap(true)
    card.body:SetNonSpaceWrap(true)

    alignFrame.nextCard = card
end

-- Repaints the Next Objective card from current state; called at the end of
-- UpdateAlignmentTab.
alignFrame.UpdateNextCard = function()
    local card = alignFrame.nextCard

    -- No tier read yet: say why, rather than letting the card claim anything.
    if not data.loaded then
        card.iconWell:Hide()
        if data.unsupported then
            card.title:SetText("|cffff8080Progress cannot be read on this client.|r")
            card.body:SetText("|cffbbbbbbThe tier is read from the character's completed quests, "
                .. "and this client has no QueryQuestsCompleted().|r")
        elseif data.queryTimedOut then
            card.title:SetText("|cffff8080The server has not answered yet.|r")
            card.body:SetText("|cffbbbbbbThe completed-quest query that carries your progression "
                .. "tier got no reply. Press Refresh to ask again.|r")
        else
            card.title:SetText("|cff909090Loading...|r")
            card.body:SetText("")
        end
        return
    end

    local nextTier = alignFrame.nextTier
    local tier     = nextTier and data.tiers[nextTier]

    if not tier then
        card.iconWell:Hide()
        card.title:SetText("|cff33dd33Your timeline is complete.|r")
        card.body:SetText("|cff909090Every era has been reached. All content is open to you.|r")
        return
    end

    local info     = alignFrame.tierInfo[nextTier]
    local earnText = (info and info.earn) or "Defeat this tier's final encounter."

    card.icon:SetTexture(alignFrame.tierIcons[nextTier] or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.icon:SetDesaturated(false)
    card.iconWell:Show()

    card.title:SetText(string.format("|cffFFD100NEXT:|r  |cffffffff[Tier %d]  %s|r", nextTier, tier.name))
    card.body:SetText("|cffbbbbbbTo reach it: " .. earnText .. "|r")

    -- The most common confusion this system creates: XP silently stops at the
    -- progression level cap. Say so, but only when the player is actually
    -- stuck. The cap follows the tier the character is ON, not the one they
    -- are heading to.
    local cap   = CapForTier(data.charTier)
    local level = PlayerLevel()
    if cap < 80 and level >= cap then
        card.body:SetText(card.body:GetText() .. string.format(
            "  |cffFF8000You are level %d and will gain no more XP until Tier %d.|r",
            level, (cap == 60) and 8 or 13))
    end
end

-- The Level Cap line: this character's ceiling, and the tier that lifts it.
local function CapLineText(charTier)
    local cap = CapForTier(charTier)
    local capStr
    if cap < 80 and PlayerLevel() >= cap then
        capStr = string.format("|cffFF8000%d (reached)|r", cap)
    else
        capStr = string.format("|cffffffff%d|r", cap)
    end
    if cap >= 80 then
        return capStr .. "  |cff909090—  no progression cap|r"
    end
    local lift = (cap == 60) and 8 or 13
    return string.format("%s  |cff909090—  rises to %d at|r  |cffFFD100[Tier %d]|r  |cffddbb88%s|r",
        capStr, cap + 10, lift, TierName(lift))
end

local function UpdateAlignmentTab()
    local groups  = alignFrame.tierGroups
    local headers = alignFrame.groupHeaders

    -- Reset: hide every pooled group header + tier row; re-show what we render.
    for gi = 1, #headers do headers[gi]:Hide() end
    for i = 1, MAX_TIERS do tierRows[i]:Hide() end

    -- Nothing read yet: an empty list under a "Loading..." card. Drawing the
    -- tiers now would show every one of them as not reached -- a claim, not a
    -- placeholder.
    if not data.loaded then
        alignCurrent:SetText("|cff909090--|r")
        alignCap:SetText("|cff909090--|r")
        alignFrame.progressBar:SetMinMaxValues(0, 1)
        alignFrame.progressBar:SetValue(0)
        alignFrame.progressBarText:SetText("|cff909090Reading progression...|r")
        alignFrame.nextTier = nil
        alignScrollChild:SetSize(600, 4)
        alignFrame.UpdateNextCard()
        return
    end

    local charTier = data.charTier

    -- The tier list is SPARSE (no 11), so the next tier is not charTier + 1;
    -- it is the next index the catalog actually has. Getting this wrong
    -- strands anyone sitting at tier 10 (or a legacy 11) with no next tier.
    local nextTier
    for idx = charTier + 1, MAX_TIERS do
        if data.tiers[idx] then
            nextTier = idx
            break
        end
    end
    alignFrame.nextTier = nextTier

    -- Header
    alignCurrent:SetText(string.format("|cffFFD100[Tier %d]|r  |cffffffff%s|r", charTier, TierName(charTier)))
    alignCap:SetText(CapLineText(charTier))

    -- Progression bar: count the tiers that actually exist, not the highest
    -- index, so the gap at 11 doesn't inflate the total (17 real tiers).
    local totalTiers, doneTiers = 0, 0
    for idx in pairs(data.tiers) do
        totalTiers = totalTiers + 1
        if idx <= charTier then doneTiers = doneTiers + 1 end
    end
    if totalTiers < 1 then totalTiers = MAX_TIERS end
    alignFrame.progressBar:SetMinMaxValues(0, totalTiers)
    alignFrame.progressBar:SetValue(doneTiers)
    alignFrame.progressBarText:SetText(string.format(
        "|cffffd100%d / %d Tiers Completed|r", doneTiers, totalTiers))

    local collapsed = alignFrame.groupCollapsed
    local yOffset = 0

    for gi, grp in ipairs(groups) do
        -- Count this expansion's existing tiers and how many are completed.
        local total, done = 0, 0
        for i = grp.first, grp.last do
            if data.tiers[i] then
                total = total + 1
                if i <= charTier then done = done + 1 end
            end
        end

        if total > 0 then
            local isCollapsed = collapsed[gi] and true or false
            local h = headers[gi]
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -yOffset)
            h.accent:SetTexture(grp.r, grp.g, grp.b, 1)
            h.toggle:SetTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                                            or  "Interface\\Buttons\\UI-MinusButton-Up")
            h.label:SetText(string.format("|cff%s%s|r  |cff909090(%d/%d)|r",
                grp.hex, grp.name, done, total))
            h:Show()
            yOffset = yOffset + 22   -- group header height

            if not isCollapsed then
                for i = grp.first, grp.last do
                    local tier = data.tiers[i]
                    if tier then
                        local row = tierRows[i]
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", 0, -yOffset)
                        row:Show()

                        -- Tint the left accent with this expansion's colour so
                        -- the whole group shows one continuous coloured band.
                        row.accent:SetTexture(grp.r, grp.g, grp.b, 1)

                        -- Per-tier portrait (same texture in every state; state
                        -- is shown via desaturation + the row tint, with a check
                        -- badge on completed tiers).
                        row.icon:SetTexture(alignFrame.tierIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
                        row.iconWell:Show()
                        row.check:Hide()

                        local info = alignFrame.tierInfo[i]
                        local goal = (info and info.goal) or ""

                        if i <= charTier then
                            -- Completed
                            row.text:SetText(string.format("|cff33dd33[Tier %d]  %s|r", i, tier.name))
                            row.goal:SetText("|cff00cc00" .. goal .. "|r")
                            row.icon:SetDesaturated(false)
                            row.icon:SetAlpha(1)
                            row.check:Show()
                            row.hl:SetTexture(0.20, 0.60, 0.20, 0.05)

                        elseif i == nextTier then
                            -- The next tier this character can reach
                            row.text:SetText(string.format("|cffffffff[Tier %d]  %s|r", i, tier.name))
                            row.goal:SetText("|cffffffff" .. goal .. "|r")
                            row.icon:SetDesaturated(false)
                            row.icon:SetAlpha(1)
                            row.hl:SetTexture(1, 0.82, 0, 0.11)

                        else
                            -- Not reached yet
                            row.text:SetText(string.format("|cff606060[Tier %d]  %s|r", i, tier.name))
                            row.goal:SetText("|cff707070" .. goal .. "|r")
                            row.icon:SetDesaturated(true)
                            row.icon:SetAlpha(0.4)
                            row.hl:SetTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
                        end

                        yOffset = yOffset + TIER_ROW_HEIGHT
                    end
                end
            end
        end
    end

    alignScrollChild:SetSize(600, yOffset + 4)

    alignFrame.UpdateNextCard()
end

-- Expansion grouping for the tier list. Ranges are by tier index, matching the
-- fixed tier order.
alignFrame.tierGroups = {
    { name = "The Old World",          hex = "d4a017", r = 0.83, g = 0.63, b = 0.09, first = 1,  last = 8  },
    { name = "The Burning Crusade",    hex = "66bb33", r = 0.40, g = 0.73, b = 0.20, first = 9,  last = 13 },
    { name = "Wrath of the Lich King", hex = "79bfff", r = 0.47, g = 0.75, b = 1.00, first = 14, last = 18 },
}

-- Per-tier portrait: each tier's signature boss/content, indexed to match the
-- tier catalog. Any unmapped tier falls back to a question mark rather than
-- rendering a broken-texture square.
alignFrame.tierIcons = {
    [1]  = "Interface\\Icons\\Achievement_Boss_Ragnaros",             -- Molten Core
    [2]  = "Interface\\Icons\\Achievement_Boss_Onyxia",               -- Onyxia's Lair
    [3]  = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",            -- Blackwing Lair (Nefarian)
    [4]  = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",           -- Pre-AQ (War Effort)
    [5]  = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",               -- AQ War (Gates Open)
    [6]  = "Interface\\Icons\\Achievement_Boss_Cthun",               -- Ahn'Qiraj
    [7]  = "Interface\\Icons\\Spell_Shadow_RaiseDead",                -- Naxxramas (Lvl 60) — Kel'Thuzad
    [8]  = "Interface\\Icons\\Spell_Shadow_SummonInfernal",           -- Pre-TBC Invasion
    [9]  = "Interface\\Icons\\Achievement_Boss_Gruulthedragonkiller", -- Karazhan & Gruul's Lair
    [10] = "Interface\\Icons\\Achievement_Boss_LadyVashj",            -- Serpentshrine & Tempest Keep
    -- [11] has no tier of its own (see the catalog) — never rendered.
    [12] = "Interface\\Icons\\Achievement_Boss_Illidan",              -- Hyjal & Black Temple
    [13] = "Interface\\Icons\\Achievement_Boss_Kiljaedan",            -- Sunwell Plateau
    [14] = "Interface\\Icons\\Achievement_Boss_LichKing",             -- Wrath of the Lich King
    [15] = "Interface\\Icons\\Achievement_Boss_YoggSaron_01",         -- Ulduar
    [16] = "Interface\\Icons\\Achievement_Boss_Anubarak",             -- Trial of the Crusader
    [17] = "Interface\\Icons\\INV_Sword_133",                         -- Icecrown Citadel (Frostmourne)
    [18] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",              -- Ruby Sanctum
}

-- Per-tier guidance shown in the row, its tooltip and the Next Objective card.
-- This is the single source of truth for the tab's player-facing prose.
--
--   era     — expansion label for the tooltip sub-line
--   cap     — the level ceiling a character has once AT this tier: 60 below
--             tier 8, 70 below tier 13, 80 from 13 up -- so the cap lifts ON
--             tiers 8 and 13, which is why those two carry 70 and 80 rather
--             than their era's value. CapForTier() computes the same thing and
--             must stay in step.
--   flavor  — lore line, mirrors LUA_SCRIPTS/LegacyServices ProgressionTiers[i].flavor
--   goal    — the short requirement in the row's right-hand column: exactly
--             what makes mod-individual-progression grant the tier -- the boss
--             kill in checkKillProgression (IndividualProgression.cpp) or the
--             quest turn-in in OnPlayerCompleteQuest (IndividualProgressionPlayer.cpp)
--   earn    — the same, told in full: how the tier is earned
--   unlocks — what reaching this tier opens up
--
-- Everything except `goal` is copied from the LegacyServices addon's
-- alignFrame.tierInfo; keep the two in step when either changes. Key 11 is
-- absent on purpose (see the tier catalog).
alignFrame.tierInfo = {
    [1] = {
        era = "Vanilla", cap = 60,
        flavor  = "Your soul is bound to the first age of fire. Let the journey begin.",
        goal    = "Defeat Ragnaros",
        earn    = "Defeat Ragnaros in the Molten Core.",
        unlocks = { "Your first anchor in the timeline" },
    },
    [2] = {
        era = "Vanilla", cap = 60,
        flavor  = "The Broodmother watches from within the weave of your history.",
        goal    = "Defeat Onyxia",
        earn    = "Defeat Onyxia in Onyxia's Lair. Entry needs level 50 and the Drakefire Amulet.",
        unlocks = { "Blackwing Lair" },
    },
    [3] = {
        era = "Vanilla", cap = 60,
        flavor  = "Nefarian's twisted bloodline is woven forever into the fabric of your age.",
        goal    = "Defeat Nefarian",
        earn    = "Defeat Nefarian in Blackwing Lair. Bring an Onyxia Scale Cloak to survive Shadowflame.",
        unlocks = { "Zul'Gurub", "The AQ War Effort and the Ahn'Qiraj quest line", "Dungeon Set 2 armour NPCs" },
    },
    [4] = {
        era = "Vanilla", cap = 60,
        flavor  = "The war drums of Silithus now resonate from within your anchored era.",
        goal    = "Quest: Bang a Gong!",
        earn    = "Complete the AQ War Effort — turn in each resource quest, gather 1000 Commendation Signets, "
               .. "then ring the Scarab Gong for 'Bang a Gong!' or 'Simply Bang a Gong!'.",
        unlocks = { "The gates of Ahn'Qiraj open", "Ruins of Ahn'Qiraj (20) and Temple of Ahn'Qiraj (40)", "The outdoor war in Silithus" },
    },
    [5] = {
        era = "Vanilla", cap = 60,
        flavor  = "The opening of the gates is forever marked upon your thread.",
        goal    = "Quest: Chaos and Destruction",
        earn    = "Fight the outdoor war in Silithus and complete 'Chaos and Destruction' by slaying "
               .. "Lieutenant General Nokhor.",
        unlocks = { "The Silithus war ends", "All Cenarion Hold NPCs", "Field Duty quests" },
    },
    [6] = {
        era = "Vanilla", cap = 60,
        flavor  = "The Old God's dreams bleed into the edges of your anchored timeline.",
        goal    = "Defeat C'Thun",
        earn    = "Defeat C'Thun in the Temple of Ahn'Qiraj.",
        unlocks = { "Naxxramas (40) — attune at Light's Hope Chapel", "The Scourge Invasion" },
    },
    [7] = {
        era = "Vanilla", cap = 60,
        flavor  = "The cold fingers of the Scourge reach into the seams of your thread.",
        goal    = "Defeat Kel'Thuzad (40)",
        earn    = "Attune to Naxxramas at Light's Hope Chapel, then defeat Kel'Thuzad in the Dread Citadel.",
        unlocks = { "The Dark Portal invasion and the quest 'Into the Breach'" },
    },
    [8] = {
        era = "Vanilla", cap = 70,
        flavor  = "The crackle of the Dark Portal echoes through the corridors of your era.",
        goal    = "Quest: Into the Breach",
        earn    = "Help the Argent Dawn hold back the Dark Portal invasion and complete 'Into the Breach'.",
        unlocks = { "Outland and every Outland dungeon", "Your level cap rises to 70", "Karazhan, Gruul's Lair, Magtheridon's Lair", "Burning Crusade spell ranks" },
    },
    [9] = {
        era = "Burning Crusade", cap = 70,
        flavor  = "The broken skies of Outland are now forever part of your anchored age.",
        goal    = "Defeat Prince Malchezaar",
        earn    = "Step through the Dark Portal, reach level 70, and defeat Prince Malchezaar in Karazhan.",
        unlocks = { "Serpentshrine Cavern — needs 'The Cudgel of Kar'desh'", "Tempest Keep — needs the Tempest Key and 'Trial of the Naaru: Magtheridon'" },
    },
    [10] = {
        era = "Burning Crusade", cap = 70,
        flavor  = "The summits of Outland's great strongholds are written into your thread.",
        goal    = "Defeat Kael'thas",
        earn    = "Defeat Kael'thas Sunstrider in Tempest Keep: The Eye.",
        unlocks = { "Mount Hyjal — needs 'The Vials of Eternity'", "Black Temple — needs the Medallion of Karabor" },
    },
    -- [11] omitted: mod-individual-progression removed PROGRESSION_TBC_TIER_3.
    [12] = {
        era = "Burning Crusade", cap = 70,
        flavor  = "The Betrayer's silhouette is cast upon the tapestry of your history.",
        goal    = "Defeat Illidan",
        earn    = "Hold the line at Mount Hyjal, then defeat Illidan Stormrage in the Black Temple.",
        unlocks = { "The Isle of Quel'Danas", "Magisters' Terrace and Sunwell Plateau", "Zul'Aman" },
    },
    [13] = {
        era = "Burning Crusade", cap = 80,
        flavor  = "The Sunwell's radiance and shadow both pulse within the weave of your timeline.",
        goal    = "Defeat Kil'jaeden",
        earn    = "Work through the Isle of Quel'Danas dailies and defeat Kil'jaeden in Sunwell Plateau.",
        unlocks = { "Northrend and every Northrend dungeon", "Your level cap rises to 80", "Naxxramas (10/25), Eye of Eternity, Obsidian Sanctum", "Wrath spell ranks. Naxxramas (40) and level-60 Onyxia close" },
    },
    [14] = {
        era = "Wrath of the Lich King", cap = 80,
        flavor  = "The chill of Northrend seeps into every corner of your anchored age.",
        goal    = "Defeat Kel'Thuzad",
        earn    = "Sail for Northrend, reach level 80, and defeat Kel'Thuzad in Naxxramas (10 or 25).",
        unlocks = { "Ulduar" },
    },
    [15] = {
        era = "Wrath of the Lich King", cap = 80,
        flavor  = "The ancient mechanisms of the titans grind and shift within your thread.",
        goal    = "Defeat Yogg-Saron",
        earn    = "Defeat Yogg-Saron in Ulduar.",
        unlocks = { "Trial of the Champion", "Trial of the Crusader" },
    },
    [16] = {
        era = "Wrath of the Lich King", cap = 80,
        flavor  = "The banners of the Argent Crusade are sewn into the tapestry of your era.",
        goal    = "Defeat Anub'arak",
        earn    = "Prove yourself at the Argent Tournament and defeat Anub'arak in Trial of the Crusader.",
        unlocks = { "Icecrown Citadel", "The Frozen Halls (Forge of Souls and beyond)" },
    },
    [17] = {
        era = "Wrath of the Lich King", cap = 80,
        flavor  = "The shadow of Icecrown falls upon every thread of your timeline.",
        goal    = "Defeat the Lich King",
        earn    = "Climb Icecrown Citadel and defeat the Lich King.",
        unlocks = { "The Ruby Sanctum" },
    },
    [18] = {
        era = "Wrath of the Lich King", cap = 80,
        flavor  = "The dragonflights bear witness as your thread is woven to its completion.",
        goal    = "Defeat Halion",
        earn    = "Defeat Halion in the Ruby Sanctum.",
        unlocks = { "Nothing further — your timeline is complete" },
    },
}

-- Tier row tooltip. Hung off alignFrame so the row OnEnter handlers (set above,
-- in the row-construction loop) can reach it; resolved at hover time, so
-- defining it after the rows is fine.
alignFrame.ShowTierTooltip = function(row)
    local idx  = row.tierIndex
    local tier = data.tiers[idx]
    if not tier then return end
    local info = alignFrame.tierInfo[idx]

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    -- Title, tinted to match the row's state.
    local titleColor = "|cff606060"
    if idx <= data.charTier then
        titleColor = "|cff33dd33"
    elseif idx == alignFrame.nextTier then
        titleColor = "|cffffffff"
    end
    GameTooltip:SetText(string.format("%s[Tier %d]  %s|r", titleColor, idx, tier.name))

    if info then
        GameTooltip:AddLine(string.format("%s  ·  Level cap %d", info.era, info.cap), 0.56, 0.56, 0.56)
        if info.flavor then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(info.flavor, 0.83, 0.63, 0.09, true)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("How it's earned", 0.68, 0.85, 0.90)
        GameTooltip:AddLine(info.earn, 1, 1, 1, true)

        if info.unlocks then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Unlocks", 0.68, 0.85, 0.90)
            for ui = 1, #info.unlocks do
                GameTooltip:AddLine("• " .. info.unlocks[ui], 1, 1, 1, true)
            end
        end
    end

    -- Where this tier stands for THIS character right now.
    GameTooltip:AddLine(" ")
    if idx <= data.charTier then
        GameTooltip:AddLine("This character has reached this tier.", 0.20, 0.80, 0.20, true)
    elseif idx == alignFrame.nextTier then
        GameTooltip:AddLine("This is your next tier.", 1, 0.82, 0, true)
    else
        GameTooltip:AddLine("Reach the earlier tiers first.", 0.60, 0.60, 0.60, true)
    end

    GameTooltip:Show()
end

alignFrame.groupCollapsed = {}   -- [groupIndex] = true when collapsed (session only)
alignFrame.groupHeaders   = {}

do
    for gi = 1, #alignFrame.tierGroups do
        local h = CreateFrame("Button", nil, alignScrollChild)
        h:SetSize(600, 22)
        MIPSkin.GroupHeader(h)

        h.accent = h:CreateTexture(nil, "ARTWORK")
        h.accent:SetWidth(3)
        h.accent:SetPoint("TOPLEFT", 0, 0)
        h.accent:SetPoint("BOTTOMLEFT", 0, 0)

        h.toggle = h:CreateTexture(nil, "ARTWORK")
        h.toggle:SetSize(16, 16)
        h.toggle:SetPoint("LEFT", 8, 0)

        h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.label:SetPoint("LEFT", h.toggle, "RIGHT", 6, 0)
        h.label:SetJustifyH("LEFT")

        h.gi = gi
        h:SetScript("OnClick", function(self)
            alignFrame.groupCollapsed[self.gi] = not alignFrame.groupCollapsed[self.gi]
            UpdateAlignmentTab()
        end)
        h:SetScript("OnEnter", function(self) MIPSkin.HeaderHover(self, true) end)
        h:SetScript("OnLeave", function(self) MIPSkin.HeaderHover(self, false) end)

        alignFrame.groupHeaders[gi] = h
    end
end

-- ============================================================================
-- SHARED HANDLES for companion files. A future tab belongs in its own file (a
-- fresh Lua 5.1 local budget) and reads these through the global below.
-- Merge into it, never reassign it with a table constructor: a second writer
-- doing `= { ... }` would silently drop the other half's handles.
-- ============================================================================
ModIndividualProgressionUI = ModIndividualProgressionUI or {}
ModIndividualProgressionUI.data               = data
ModIndividualProgressionUI.CreateContentFrame = CreateContentFrame
ModIndividualProgressionUI.RequestProgress    = RequestProgress

-- ============================================================================
-- MASTER UPDATE
-- ============================================================================

UpdateDisplay = function()
    mainFrame.UpdateHeaderStatus()
    UpdateAlignmentTab()
end

-- ============================================================================
-- MAIN FRAME SHOW
-- ============================================================================

mainFrame:SetScript("OnShow", function()
    -- Come back to whichever tab was last in use.
    local last = ModIndividualProgressionDB and ModIndividualProgressionDB.lastTab
    SetActiveTab((last and TAB_NAMES[last]) and last or 1)
    -- Ask the server for the current tier, then paint what is already known
    -- ("Loading..." before the first read). Asking first only matters on a
    -- client without QueryQuestsCompleted: the request is what discovers that,
    -- and the paint that follows can then say so instead of "Loading...".
    RefreshActiveTab()
    UpdateDisplay()
end)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_MODINDIVIDUALPROGRESSION1 = "/ipp"
SLASH_MODINDIVIDUALPROGRESSION2 = "/progression"

SlashCmdList["MODINDIVIDUALPROGRESSION"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFD100Individual Progression|r commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /ipp           -  Toggle the Individual Progression window")
        DEFAULT_CHAT_FRAME:AddMessage("  /progression   -  Same as /ipp")
        DEFAULT_CHAT_FRAME:AddMessage("  /ipp help      -  Show this help")
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local minimapBtn = CreateFrame("Button", "ModIndividualProgressionMinimapButton", Minimap)
minimapBtn:SetSize(33, 33)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local minimapOverlay = minimapBtn:CreateTexture(nil, "OVERLAY")
minimapOverlay:SetSize(53, 53)
minimapOverlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapOverlay:SetPoint("TOPLEFT")

local minimapIcon = minimapBtn:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetSize(21, 21)
minimapIcon:SetTexture("Interface\\Icons\\Spell_Nature_TimeStop")
minimapIcon:SetPoint("CENTER", minimapBtn, "CENTER", 0, 1)

local function UpdateMinimapPosition()
    local db    = ModIndividualProgressionDB
    local angle = math.rad((db and db.minimapAngle) or DEFAULT_MINIMAP_ANGLE)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale  = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        if ModIndividualProgressionDB then
            ModIndividualProgressionDB.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
        end
        UpdateMinimapPosition()
    end)
end)

minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

minimapBtn:SetScript("OnClick", function()
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffFFD100Individual Progression|r")
    GameTooltip:AddLine("Click to toggle the window.", 1, 1, 1)
    GameTooltip:AddLine("Drag to reposition this button.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

UpdateMinimapPosition()

-- ============================================================================
-- EVENT HANDLING
--
-- Last in the file on purpose: the handler closes over functions from every
-- section above, and a Lua local is only visible to code written after it.
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitSavedVariables()
            RestoreWindowPosition()
            UpdateMinimapPosition()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Once per session (every zone change fires this too, and zoning cannot
        -- change a tier): read the tier now, so the window opens on real data.
        if not self.primed then
            self.primed = true
            RequestProgress(3)
        end

    elseif event == "QUEST_QUERY_COMPLETE" then
        -- Ours or any other addon's -- the answer is the same list.
        OnQuestQueryComplete()

    elseif event == "ACHIEVEMENT_EARNED" or event == "QUEST_FINISHED" then
        -- A tier changes on a boss kill (which almost always awards an
        -- achievement too) or on turning in Bang a Gong!, Chaos and
        -- Destruction or Into the Breach. Only worth a query while the window
        -- is open; opening it always re-reads anyway.
        if mainFrame:IsShown() then RequestProgress(2) end

    elseif event == "CHAT_MSG_SYSTEM" then
        -- A GM's ".ip set" on this character.
        if arg1 and mainFrame:IsShown() and arg1:find("Updated Progression Level", 1, true) then
            RequestProgress(2)
        end

    elseif event == "PLAYER_LEVEL_UP" then
        -- The level-cap readouts move with the level; UnitLevel may still say
        -- the old one inside this handler, so carry the new one ourselves.
        data.levelOverride = tonumber(arg1)
        UpdateDisplay()
    end
end)

DEFAULT_CHAT_FRAME:AddMessage("|cffFFD100Individual Progression|r addon loaded. Type |cff00ff00/ipp|r to open.")
