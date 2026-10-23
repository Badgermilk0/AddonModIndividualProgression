-- ============================================================================
--  ModIndividualProgression -- Skin  (loads FIRST, before the main file)
--
--  The addon's whole visual vocabulary lives here, in one chunk, exported as
--  the global `MIPSkin`. Nothing in this file knows anything about
--  progression tiers or quests -- it only knows how a Wrath-era window is
--  supposed to look.
--
--  BRANCHED FROM LegacyServicesSkin.lua (LegacyServices 3.4). Apart from this
--  header, the global's name and the TAB_ICONS table, the body below is that
--  file verbatim. Keep it that way, so a restyle made over there can be
--  carried across with a plain diff. That is also why a few comments still
--  name LegacyServices tabs (Vaults, Blessings, Teleports ...): they record
--  where a helper was first needed. Helpers this addon does not use yet --
--  item slots, cards, checkboxes, state borders -- are kept on purpose; they
--  are the kit a future tab is built from.
--
--  The global is MIPSkin rather than LSSkin so that this addon and
--  LegacyServices can be installed side by side without one replacing the
--  other's skin.
--
--  DESIGN NOTES
--
--  The look is built the way Altoholic builds its own: compose from Blizzard's
--  shipped FrameXML art instead of painting flat coloured rectangles. That is
--  what makes a custom window read as part of the game rather than as an
--  overlay drawn on top of it. Concretely:
--
--    * the window is the StaticPopup / quest-dialog frame -- a dark stone panel
--      inside the ornate gold DialogBox border, with a real UI-DialogBox-Header
--      plaque carrying the title;
--    * the left navigation is the Auction House's category list
--      (UI-AuctionFrame-FilterBg + FilterLines + the character-tab highlight),
--      exactly the widget Altoholic reuses for its own menus;
--    * list group headers are the Who-panel column tabs, sliced left/middle/
--      right so one 19px asset stretches to any width;
--    * item slots are the game's own ItemButtonTemplate, so a bank slot in this
--      window is pixel-identical to a bank slot in the real bank;
--    * rows highlight with UI-Listbox-Highlight, the same wash the game uses
--      for every hoverable list line.
--
--  Every texture path below is stock 3.3.5a art that ships in the client's
--  MPQs -- but "ships in the MPQs" is not the same as "looks the way vanilla
--  looks". This realm's client is HD-patched, and a patch MPQ can REPLACE a
--  stock texture: UI-DialogBox-Background is blanked on it, which is why the
--  window fill below is UI-Tooltip-Background and the stone grain is a separate,
--  optional layer. When you add a texture here, look at it in game before you
--  make anything structural depend on it.
--
--  The palette stays dark on purpose. The addon carries several hundred inline
--  |cffRRGGBB colour escapes written for a dark ground (gold titles, grey
--  sub-lines, red shortfalls); a parchment window would have meant rewriting
--  all of them, and getting one wrong is invisible until a player hits that
--  exact state.
-- ============================================================================

MIPSkin = {}
local S = MIPSkin

-- ---------------------------------------------------------------------------
-- PALETTE
--
-- Named so call sites read as intent ("border a card with GOLD_DIM") rather
-- than as four unexplained decimals. r/g/b arrays, unpacked at the call.
-- ---------------------------------------------------------------------------
S.GOLD        = { 1.00, 0.82, 0.00 }   -- Blizzard's title gold
S.GOLD_DIM    = { 0.72, 0.58, 0.30 }   -- bronze; card borders, hairlines
S.GOLD_DARK   = { 0.42, 0.33, 0.16 }   -- recessed bronze, unfocused chrome
S.PARCHMENT   = { 0.86, 0.78, 0.60 }   -- warm off-white for body text
S.GREEN       = { 0.45, 0.72, 0.28 }
S.RED         = { 0.70, 0.25, 0.22 }
S.BLUE        = { 0.36, 0.55, 0.78 }

-- Convenience: `S.Unpack(S.GOLD, 0.8)` -> r, g, b, a
function S.Unpack(c, alpha)
    return c[1], c[2], c[3], alpha or 1
end

-- ---------------------------------------------------------------------------
-- ART PATHS
--
-- Centralised so a texture that turns out to be missing on a given client is a
-- one-line fix rather than a hunt through four files.
-- ---------------------------------------------------------------------------
S.ART = {
    dialogBG      = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dialogBorder  = "Interface\\DialogFrame\\UI-DialogBox-Border",
    dialogHeader  = "Interface\\DialogFrame\\UI-DialogBox-Header",
    tooltipBG     = "Interface\\Tooltips\\UI-Tooltip-Background",
    tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    white         = "Interface\\Buttons\\WHITE8X8",
    filterBG      = "Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg",
    filterLines   = "Interface\\AuctionFrame\\UI-AuctionFrame-FilterLines",
    tabHighlight  = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    columnTabs    = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs",
    listHighlight = "Interface\\Buttons\\UI-Listbox-Highlight",
    checkHilight  = "Interface\\Buttons\\CheckButtonHilight",
    plus          = "Interface\\Buttons\\UI-PlusButton-Up",
    minus         = "Interface\\Buttons\\UI-MinusButton-Up",
    statusBar     = "Interface\\TargetingFrame\\UI-StatusBar",
    ringIcon      = "Interface\\AchievementFrame\\UI-Achievement-IconFrame",
    slotGlow      = "Interface\\Buttons\\UI-ActionButton-Border",
    questionMark  = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- ---------------------------------------------------------------------------
-- One emblem per tab, in TAB INDEX order (the same indices CreateContentFrame
-- and the RefreshActiveTab ladder use). Only Temporal Alignment exists so far;
-- a new tab adds its emblem here.
--
-- It lives here rather than beside the nav rail because two places need it --
-- the rail button and the tab's own heading -- and a tab whose two emblems
-- disagreed would be worse than one with none.
-- ---------------------------------------------------------------------------
S.TAB_ICONS = {
    [1] = "Interface\\Icons\\Spell_Nature_TimeStop",           -- Temporal Alignment
}

-- ---------------------------------------------------------------------------
-- BACKDROPS
--
-- WINDOW  the main window: carved stone panel inside the ornate gold border
--         the game uses for StaticPopup and the quest frame.
-- INSET   a recessed panel inside the window (cards, list wells, panes). Same
--         stone, darkened by its backdrop colour, inside a thin tooltip edge.
-- SLOT    a small square well: icon holders, plates, source buttons.
-- THIN    a hairline-bordered strip, for cast bars and other slim chrome.
-- ---------------------------------------------------------------------------
-- ⚠ The FILL is UI-Tooltip-Background, not UI-DialogBox-Background, even though
-- the latter is what StaticPopup uses and what this frame is imitating.
-- UI-DialogBox-Background is transparent on HD-patched 3.3.5a clients (several
-- interface overhauls blank it for a "clean" look), and a backdrop whose bgFile
-- is transparent shows the game world straight through the window -- which is
-- exactly what happened. UI-Tooltip-Background is a plain tileable fill that
-- every client has and that takes SetBackdropColor predictably, so the panel's
-- opacity is ours rather than the client's to decide.
--
-- The stone GRAIN is layered on top separately by S.Grain, where a missing or
-- blanked texture costs a little texture and nothing else.
--
-- edgeSize 32 and the asymmetric 11/12/12/11 insets are Blizzard's own numbers
-- from StaticPopupTemplate: they are what make the DialogBox border's corner
-- ornaments land correctly instead of stretching.
S.BACKDROP_WINDOW = {
    bgFile   = S.ART.tooltipBG,
    edgeFile = S.ART.dialogBorder,
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

S.BACKDROP_INSET = {
    bgFile   = S.ART.tooltipBG,
    edgeFile = S.ART.tooltipBorder,
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

S.BACKDROP_SLOT = {
    bgFile   = S.ART.tooltipBG,
    edgeFile = S.ART.tooltipBorder,
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

S.BACKDROP_THIN = {
    bgFile   = S.ART.tooltipBG,
    edgeFile = S.ART.tooltipBorder,
    tile = true, tileSize = 8, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- ---------------------------------------------------------------------------
-- Apply one of the four backdrops with its house colours in a single call, so
-- a card is one line rather than five and can never drift out of step with the
-- rest of the addon.
-- ---------------------------------------------------------------------------
-- Three levels of depth, and they must stay in this order to read as carved
-- rather than as a pile of panels: the WINDOW is the lightest surface, an INSET
-- is cut into it (darker), and a CARD sits back up out of the inset (lighter
-- than the inset, darker than the window). Getting the ordering wrong is what
-- makes a nested UI look flat no matter how good the border art is.
S.FILL_WINDOW = { 0.14, 0.13, 0.12, 0.97 }
S.FILL_INSET  = { 0.07, 0.065, 0.06, 0.95 }
S.FILL_CARD   = { 0.18, 0.165, 0.15, 0.95 }
S.FILL_SLOT   = { 0.05, 0.05, 0.05, 0.90 }

function S.Skin(frame, kind)
    if kind == "window" then
        frame:SetBackdrop(S.BACKDROP_WINDOW)
        frame:SetBackdropColor(S.Unpack(S.FILL_WINDOW, S.FILL_WINDOW[4]))
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    elseif kind == "slot" then
        frame:SetBackdrop(S.BACKDROP_SLOT)
        frame:SetBackdropColor(S.Unpack(S.FILL_SLOT, S.FILL_SLOT[4]))
        frame:SetBackdropBorderColor(S.Unpack(S.GOLD_DARK, 0.9))
    elseif kind == "thin" then
        frame:SetBackdrop(S.BACKDROP_THIN)
        frame:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
        frame:SetBackdropBorderColor(S.Unpack(S.GOLD_DARK, 0.9))
    else   -- "inset"
        frame:SetBackdrop(S.BACKDROP_INSET)
        frame:SetBackdropColor(S.Unpack(S.FILL_INSET, S.FILL_INSET[4]))
        frame:SetBackdropBorderColor(S.Unpack(S.GOLD_DIM, 0.85))
    end
    return frame
end

-- ---------------------------------------------------------------------------
-- Decorative stone grain, layered over a fill that is already opaque. Kept
-- separate from the backdrop precisely so that a client which has blanked
-- UI-DialogBox-Background loses the texture and not the window.
-- ---------------------------------------------------------------------------
function S.Grain(frame, alpha, inset)
    inset = inset or 10
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(S.ART.dialogBG)
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    t:SetAlpha(alpha or 0.5)
    return t
end

-- ============================================================================
-- WINDOW CHROME
-- ============================================================================

-- ---------------------------------------------------------------------------
-- The gold header plaque, the piece of art that says "Wrath" more than any
-- other. UI-DialogBox-Header carries transparent margin at its top, so
-- anchoring it slightly ABOVE the frame's top edge is what makes it sit ON the
-- border the way Blizzard's own dialogs do.
--
-- `width` stretches the plaque; it is a single non-sliced texture, so very wide
-- values smear the end caps. 240-340 looks right.
--
-- The 64px height and the -14 title offset are Blizzard's own numbers for this
-- asset (it is a 256x64 sheet with transparent margin above the metal, and the
-- game's dialogs anchor their title 14px down from the texture's top). Sizing it
-- 68 tall with the title at -22, as this did first, left the text sitting low in
-- the plaque's recess rather than centred in it.
-- ---------------------------------------------------------------------------
function S.HeaderPlaque(frame, text, width)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(S.ART.dialogHeader)
    tex:SetSize(width or 300, 64)
    tex:SetPoint("TOP", frame, "TOP", 0, 12)

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", tex, "TOP", 0, -14)
    fs:SetText(text or "")

    frame.headerPlaque = tex
    frame.headerText   = fs
    return fs, tex
end

-- ---------------------------------------------------------------------------
-- Portrait medallion. Blizzard frames bake the ring into their frame art; a
-- custom-sized window cannot, so the ring is a separate overlay texture.
-- UI-Achievement-IconFrame is a 128x128 sheet whose ring occupies the top-left
-- 0..0.5625 in both axes -- hence the TexCoord.
-- ---------------------------------------------------------------------------
function S.Portrait(frame, iconPath, size, x, y)
    size = size or 52

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("TOPLEFT", x or 14, y or -12)
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(S.ART.ringIcon)
    ring:SetTexCoord(0, 0.5625, 0, 0.5625)
    ring:SetSize(size * 1.45, size * 1.45)
    ring:SetPoint("CENTER", icon, "CENTER", 0, 0)

    frame.portrait     = icon
    frame.portraitRing = ring
    return icon, ring
end

-- ---------------------------------------------------------------------------
-- Gold hairline. Two textures rather than one: a bronze line with a black line
-- directly beneath it reads as a carved bevel, which is what the game's own
-- separators are. A single flat line reads as a border drawn in a paint app.
-- ---------------------------------------------------------------------------
function S.Divider(parent, y, inset, alpha)
    inset = inset or 12
    alpha = alpha or 0.55

    local core = parent:CreateTexture(nil, "ARTWORK")
    core:SetTexture(S.ART.white)
    core:SetHeight(1)
    core:SetPoint("TOPLEFT", inset, y)
    core:SetPoint("TOPRIGHT", -inset, y)
    core:SetVertexColor(S.GOLD_DIM[1], S.GOLD_DIM[2], S.GOLD_DIM[3], alpha)

    local shade = parent:CreateTexture(nil, "ARTWORK")
    shade:SetTexture(S.ART.white)
    shade:SetHeight(1)
    shade:SetPoint("TOPLEFT", core, "BOTTOMLEFT", 0, 0)
    shade:SetPoint("TOPRIGHT", core, "BOTTOMRIGHT", 0, 0)
    shade:SetVertexColor(0, 0, 0, alpha * 0.7)

    return core
end

-- Vertical twin of S.Divider, for splitting a tab into two panes.
function S.VDivider(parent, x, topY, bottomY)
    local core = parent:CreateTexture(nil, "ARTWORK")
    core:SetTexture(S.ART.white)
    core:SetWidth(1)
    core:SetPoint("TOPLEFT", x, topY or -8)
    core:SetPoint("BOTTOMLEFT", x, bottomY or 8)
    core:SetVertexColor(S.GOLD_DIM[1], S.GOLD_DIM[2], S.GOLD_DIM[3], 0.45)

    local shade = parent:CreateTexture(nil, "ARTWORK")
    shade:SetTexture(S.ART.white)
    shade:SetWidth(1)
    shade:SetPoint("TOPLEFT", core, "TOPRIGHT", 0, 0)
    shade:SetPoint("BOTTOMLEFT", core, "BOTTOMRIGHT", 0, 0)
    shade:SetVertexColor(0, 0, 0, 0.4)

    return core
end

-- ============================================================================
-- PANELS
-- ============================================================================

-- A recessed pane filling an area of its parent. The workhorse for list wells.
function S.Inset(parent, l, t, r, b)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", l or 0, t or 0)
    f:SetPoint("BOTTOMRIGHT", r or 0, b or 0)
    S.Skin(f, "inset")
    return f
end

-- A fixed-size card anchored to the TOP of its parent, `yTop` px down. This is
-- the shape every "one subject, one panel" section in the addon uses.
function S.Card(parent, width, yTop, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, height)
    card:SetPoint("TOP", 0, yTop)
    S.Skin(card, "inset")
    card:SetBackdropColor(S.Unpack(S.FILL_CARD, S.FILL_CARD[4]))
    return card
end

-- The decorative emblem in a card's top-left corner.
function S.CardIcon(card, texture, size)
    size = size or 20
    local t = card:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("TOPLEFT", 12, -8)
    t:SetTexture(texture)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-- ---------------------------------------------------------------------------
-- Framed icon well -- an icon sunk into a bevelled square. Used wherever an
-- icon is the subject of a row rather than a decoration on it.
-- ---------------------------------------------------------------------------
function S.IconWell(parent, size, x, y)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    if x then holder:SetPoint("TOPLEFT", x, y) end
    S.Skin(holder, "slot")
    holder:SetBackdropColor(0.10, 0.08, 0.05, 1)
    holder:SetBackdropBorderColor(S.Unpack(S.GOLD_DIM))

    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("TOPLEFT", 3, -3)
    holder.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return holder
end

-- ---------------------------------------------------------------------------
-- The band that opens a list-style tab: gold title, grey explanatory sub-line,
-- and a carved rule under both. Returns the two font strings, because several
-- tabs retitle their sub-line live (Teleports swaps it for a resting warning).
-- ---------------------------------------------------------------------------
-- `iconPath` is optional; with one the title wears the same ringed emblem its
-- entry in the nav rail does, so a tab is recognisable from its heading alone
-- and not only from the list you left behind. Without one the layout is
-- unchanged, which is what keeps this safe to add tab by tab.
function S.TabHeader(frame, title, subtitle, ruleY, iconPath)
    local textX = 14

    if iconPath then
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 13, -12)
        icon:SetTexture(iconPath)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local ring = frame:CreateTexture(nil, "OVERLAY")
        ring:SetTexture(S.ART.ringIcon)
        ring:SetTexCoord(0, 0.5625, 0, 0.5625)
        ring:SetSize(28 * 1.45, 28 * 1.45)
        ring:SetPoint("CENTER", icon, "CENTER", 0, 0)

        frame.headerIcon = icon
        textX = 52
    end

    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", textX, -10)
    t:SetText("|cffFFD100" .. title .. "|r")

    local s = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s:SetPoint("TOPLEFT", textX, -32)
    s:SetPoint("TOPRIGHT", -14, -32)
    s:SetJustifyH("LEFT")
    s:SetText("|cff909090" .. subtitle .. "|r")

    S.Divider(frame, ruleY, 10)
    return t, s
end

-- ---------------------------------------------------------------------------
-- Small emblem for a heading that already exists.
--
-- The icon hangs off the STRING's left edge rather than replacing its anchor,
-- so a caller that has anchored its label to two points (the usual
-- TOPLEFT + TOPRIGHT for a wrapping line) keeps both. The caller pays for the
-- room by indenting the label itself -- `S.LABEL_INDENT` is that indent for the
-- default size, so the two never drift apart.
-- ---------------------------------------------------------------------------
S.LABEL_INDENT = 19

function S.LabelIcon(fs, iconPath, size, gap)
    size = size or 14
    local tex = fs:GetParent():CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetTexture(iconPath)
    tex:SetPoint("RIGHT", fs, "LEFT", -(gap or 5), 0)
    return tex
end

-- Icon + text pair: the repeated unit of a card body row.
function S.StatusChip(card, x, y, textWidth, fontObject)
    local ic = card:CreateTexture(nil, "ARTWORK")
    ic:SetSize(18, 18)
    ic:SetPoint("TOPLEFT", x, y)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local st = card:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    st:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    st:SetJustifyH("LEFT")
    st:SetWidth(textWidth)
    return ic, st
end

-- ============================================================================
-- NAVIGATION  (Auction House category list)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- One entry of the left-hand menu, built from the same three pieces the game's
-- own auction filters use:
--   NormalTexture    UI-AuctionFrame-FilterBg    the parchment strip
--   FilterLines      the little tree-branch tick at the left
--   HighlightTexture UI-Character-Tab-Highlight  the hover glow
--
-- The TexCoords are Blizzard's, lifted from AuctionFrameFilter: the sheet
-- carries several bands and only the top-left 0.53125 x 0.625 is the row art.
--
-- `S.NavSelect(button, selected)` paints state; the button keeps its own icon
-- and label so a caller only ever touches those two.
-- ---------------------------------------------------------------------------
function S.NavButton(parent, width, height, label, iconPath)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)

    b:SetNormalTexture(S.ART.filterBG)
    b:GetNormalTexture():SetTexCoord(0, 0.53125, 0, 0.625)
    -- Pinned to BACKGROUND on purpose. A Button's normal texture defaults into
    -- ARTWORK, where it is drawn as part of the button rather than as a plain
    -- region -- so the emblem below, created afterwards on the same layer, was
    -- covered by it and the whole rail rendered as text with a blank gap where
    -- its icons should be. Every layer here is now stated rather than inferred:
    -- plate (BACKGROUND) -> lines (BORDER) -> emblem (ARTWORK) -> marker and
    -- label (OVERLAY).
    b:GetNormalTexture():SetDrawLayer("BACKGROUND")

    b.lines = b:CreateTexture(nil, "BORDER")
    b.lines:SetTexture(S.ART.filterLines)
    b.lines:SetSize(7, height)
    b.lines:SetPoint("LEFT", 5, 0)
    b.lines:SetTexCoord(0, 0.4375, 0, 0.625)

    b:SetHighlightTexture(S.ART.tabHighlight, "ADD")

    -- Selected marker: a gold bar down the left edge. Cheaper to read at a
    -- glance than a colour change alone, and it survives the hover wash.
    b.marker = b:CreateTexture(nil, "OVERLAY")
    b.marker:SetTexture(S.ART.white)
    b.marker:SetWidth(2)
    b.marker:SetPoint("TOPLEFT", 2, -2)
    b.marker:SetPoint("BOTTOMLEFT", 2, 2)
    b.marker:SetVertexColor(S.Unpack(S.GOLD))
    b.marker:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(height - 9, height - 9)
    b.icon:SetPoint("LEFT", 15, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if iconPath then b.icon:SetTexture(iconPath) end

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetText(label or "")

    return b
end

function S.NavSelect(b, selected)
    if selected then
        b.marker:Show()
        b.text:SetTextColor(S.Unpack(S.GOLD))
        b:GetNormalTexture():SetVertexColor(1, 0.95, 0.80, 1)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(1)
    else
        b.marker:Hide()
        b.text:SetTextColor(0.74, 0.70, 0.62)
        b:GetNormalTexture():SetVertexColor(0.72, 0.70, 0.67, 1)
        -- Dimmed, never desaturated: a greyed emblem at this size is an
        -- unreadable blob, and the icon is how you find the row you want.
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(0.85)
    end
end

-- Section label above a run of nav buttons.
function S.NavHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText("|cffb9a06a" .. text .. "|r")
    return fs
end

-- ============================================================================
-- LIST FURNITURE
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Turn a bare Button into a Blizzard column-tab group header.
--
-- WhoFrame-ColumnTabs is a three-slice sheet: a 5px left cap, a stretchable
-- middle and a 4px right cap, all inside a 0..0.59375 vertical band. Slicing it
-- (as Altoholic does for its sort buttons) is what lets one 19px asset become a
-- header of any width -- and it is why these keep their bevel instead of
-- smearing when the list they head is resized.
--
-- Sets up h.slices and h.bg; paint hover with S.HeaderHover(h, true/false).
-- ---------------------------------------------------------------------------
function S.GroupHeader(h)
    local left = h:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(S.ART.columnTabs)
    left:SetTexCoord(0, 0.078125, 0, 0.59375)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(5)

    local right = h:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(S.ART.columnTabs)
    right:SetTexCoord(0.90625, 0.96875, 0, 0.59375)
    right:SetPoint("TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    right:SetWidth(4)

    local mid = h:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture(S.ART.columnTabs)
    mid:SetTexCoord(0.078125, 0.90625, 0, 0.59375)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)

    h.slices = { left, mid, right }

    -- The hover wash, kept under the name `bg` the old flat headers used.
    h.bg = h:CreateTexture(nil, "BORDER")
    h.bg:SetTexture(S.ART.listHighlight)
    h.bg:SetBlendMode("ADD")
    h.bg:SetAllPoints()
    h.bg:SetAlpha(0)

    S.HeaderHover(h, false)
    return h
end

-- Hover state for a header built by S.GroupHeader.
function S.HeaderHover(h, on)
    if h.bg then h.bg:SetAlpha(on and 0.30 or 0) end
    if h.slices then
        local v = on and 1.0 or 0.80
        for i = 1, 3 do h.slices[i]:SetVertexColor(v, v, v, 1) end
    end
end

-- ---------------------------------------------------------------------------
-- Hover / selection wash for a list row. UI-Listbox-Highlight is the exact
-- texture the game paints under a hovered line in every scrolling list it has,
-- so a row lit with it feels native rather than merely tinted.
-- ---------------------------------------------------------------------------
function S.RowHighlight(row, layer)
    local t = row:CreateTexture(nil, layer or "BORDER")
    t:SetTexture(S.ART.listHighlight)
    t:SetBlendMode("ADD")
    t:SetAllPoints()
    t:SetAlpha(0.40)
    t:Hide()
    return t
end

-- The zebra stripe under alternating rows: subtle, and cheaper to read than a
-- border on every line. Starts fully transparent; the renderer tints it.
function S.RowStripe(row)
    local t = row:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(S.ART.white)
    t:SetAllPoints()
    t:SetVertexColor(1, 1, 1, 0)
    return t
end

-- ---------------------------------------------------------------------------
-- A status bar with the game's bar fill, a black well behind it and a hairline
-- frame around it. Returns the bar; its label is bar.text.
--
-- The frame is four 1px textures rather than a backdrop, so the bar can be any
-- height without a backdrop's insets eating into the fill.
-- ---------------------------------------------------------------------------
function S.StatusBar(parent, width, height, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    -- `width` is optional: several bars take their width from left/right anchors
    -- the caller sets afterwards. Height never comes from anchors, so it is set
    -- either way -- forgetting it leaves a 0px-tall bar that renders as nothing.
    if width then
        bar:SetSize(width, height)
    elseif height then
        bar:SetHeight(height)
    end
    bar:SetStatusBarTexture(S.ART.statusBar)
    bar:SetStatusBarColor(r or 0.85, g or 0.65, b or 0.20, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetTexture(S.ART.white)
    bar.bg:SetAllPoints()
    bar.bg:SetVertexColor(0, 0, 0, 0.6)

    local function edge(p1, o1x, o1y, p2, o2x, o2y, w, h)
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetTexture(S.ART.white)
        t:SetVertexColor(S.Unpack(S.GOLD_DARK, 0.95))
        t:SetPoint(p1, o1x, o1y)
        t:SetPoint(p2, o2x, o2y)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    edge("TOPLEFT", -1, 1, "TOPRIGHT", 1, 1, nil, 1)
    edge("BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1, nil, 1)
    edge("TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1, 1, nil)
    edge("TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1, 1, nil)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    return bar
end

-- ---------------------------------------------------------------------------
-- Item slot, built on the game's own ItemButtonTemplate -- the same widget the
-- bank and your bags use. A slot in this window is therefore pixel-identical
-- to the slot it mirrors, which is the whole point.
--
-- The template needs a unique global NAME: it builds $parentIconTexture,
-- $parentCount and $parentNormalTexture from it, and a nil name makes those
-- collide on the globals and leaves the button unpainted.
--
-- Quality is shown with UI-ActionButton-Border, the additive glow bag addons
-- have used since vanilla; 3.3.5a's ItemButtonTemplate has no $parentIconBorder
-- of its own -- that arrived in Cataclysm.
-- ---------------------------------------------------------------------------
function S.ItemSlot(parent, name, size)
    size = size or 37
    local b = CreateFrame("Button", name, parent, "ItemButtonTemplate")
    b:SetSize(size, size)

    -- The template's own regions. Guarded rather than assumed: a client whose
    -- FrameXML has been replaced by a UI overhaul may not ship them, and a nil
    -- icon here would only surface as an error the first time a slot is filled.
    b.icon  = _G[name .. "IconTexture"]
    b.count = _G[name .. "Count"]

    if not b.icon then
        b.icon = b:CreateTexture(nil, "BORDER")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if not b.count then
        b.count = b:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -5, 2)
    end

    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(S.ART.slotGlow)
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(size * 1.7, size * 1.7)
    b.glow:SetPoint("CENTER")
    b.glow:Hide()

    -- Selection ring. CheckButtonHilight is what the game uses to say "this one
    -- is picked", which is exactly the state a selected vault slot is in.
    b.highlight = b:CreateTexture(nil, "OVERLAY")
    b.highlight:SetTexture(S.ART.checkHilight)
    b.highlight:SetBlendMode("ADD")
    b.highlight:SetAllPoints()
    b.highlight:Hide()

    return b
end

-- Write (or clear) a slot's stack size.
--
-- ItemButtonTemplate ships $parentCount HIDDEN -- it is Blizzard's
-- SetItemButtonCount that shows it, and nothing else does. SetText on its own
-- therefore paints an invisible string, which is exactly how every stack size
-- in the vaults, the guild bank and the reagent bank disappeared when the slots
-- moved onto the real template. Anything writing a count must come through
-- here.
function S.SetSlotCount(b, text)
    if text and text ~= "" then
        b.count:SetText(text)
        b.count:Show()
    else
        b.count:SetText("")
        b.count:Hide()
    end
end

-- Paint one slot's contents. `quality` nil or below Uncommon clears the glow.
function S.SetSlotItem(b, texture, count, quality)
    if texture then
        b.icon:SetTexture(texture)
        b.icon:Show()
    else
        b.icon:SetTexture(nil)
        b.icon:Hide()
    end
    S.SetSlotCount(b, (count and count > 1) and count or nil)

    if quality and quality >= 2 then
        local r, g, bb = GetItemQualityColor(quality)
        b.glow:SetVertexColor(r, g, bb, 0.9)
        b.glow:Show()
    else
        b.glow:Hide()
    end
end

-- Wash a slot out (filtered away, or blocked from withdrawal) or restore it.
function S.DimSlot(b, dim, alpha)
    if dim then
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(alpha or 0.25)
        b.count:SetAlpha(0.3)
        b.glow:SetAlpha(0.25)
    else
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(1)
        b.count:SetAlpha(1)
        b.glow:SetAlpha(1)
    end
end

-- ---------------------------------------------------------------------------
-- Labelled checkbox. The label is our own font string rather than the
-- template's $parentText, whose anchoring differs between check templates --
-- this way the layout is ours and cannot shift underneath us. `name` must be
-- unique: the template builds its textures from it.
-- ---------------------------------------------------------------------------
function S.Check(parent, name, x, y, label, tip, onToggle)
    local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c:SetPoint("TOPLEFT", x, y)

    local t = _G[name .. "Text"]
    if t then t:SetText("") end

    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(label)

    c:SetScript("OnClick", function(self)
        onToggle(self:GetChecked() and true or false)
    end)

    if tip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return c
end

-- ---------------------------------------------------------------------------
-- Mouse-wheel scrolling for a bare ScrollFrame. UIPanelScrollFrameTemplate
-- always draws its up/down buttons and thumb even with nothing to scroll, so
-- lists that may not overflow use a plain ScrollFrame plus this.
-- ---------------------------------------------------------------------------
function S.WheelScroll(scroll, step)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * (step or 40)
        local m = self:GetVerticalScrollRange()
        if v < 0 then v = 0 elseif v > m then v = m end
        self:SetVerticalScroll(v)
    end)
end

-- ---------------------------------------------------------------------------
-- Seat a UIPanelScrollFrameTemplate scroll bar against a dark window.
--
-- ⚠ Do NOT hide the bar's Top / Bottom / Middle regions. Those three ARE the
-- trough; blanking them leaves the up and down arrows floating unattached in
-- empty space, which is exactly how it looked. The template's art is Blizzard's
-- own and belongs here -- all this does is sink a dark track behind it so the
-- bar reads as a channel cut into the panel rather than a strip laid on top.
--
-- Pass the SCROLL FRAME's global name.
-- ---------------------------------------------------------------------------
function S.SkinScrollBar(scrollName)
    local sb = _G[scrollName .. "ScrollBar"]
    if not sb then return end

    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(S.ART.white)
    track:SetPoint("TOPLEFT", 4, -16)
    track:SetPoint("BOTTOMRIGHT", -4, 16)
    track:SetVertexColor(0, 0, 0, 0.55)

    return sb
end

-- ---------------------------------------------------------------------------
-- State border for a card that represents something buyable.
--
-- Three tabs -- Blessings, the Armory and Teleports -- each say the same four
-- things with a border colour: you can have this, you cannot afford it yet, it
-- is not open to you, and it is running right now. They used to say it with
-- three separately drifting sets of decimals. One vocabulary, in one place:
--
--   ready   green   affordable and available
--   short   amber   available, but you do not have the points
--   locked  red     gated -- wrong tier, wrong era, not earned
--   off     grey    inert for a reason that is not about this card (mid-cast,
--                   not resting) -- deliberately colourless, so it does not
--                   read as a rejection of the item itself
--   active  blue    currently running
-- ---------------------------------------------------------------------------
S.STATE_BORDER = {
    ready  = { 0.45, 0.72, 0.28, 0.95 },
    short  = { 0.78, 0.55, 0.20, 0.90 },
    locked = { 0.62, 0.24, 0.22, 0.85 },
    off    = { 0.38, 0.36, 0.34, 0.75 },
    active = { 0.36, 0.60, 0.86, 0.95 },
}

function S.StateBorder(frame, state)
    local c = S.STATE_BORDER[state] or S.STATE_BORDER.off
    frame:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- ---------------------------------------------------------------------------
-- Carved plate for a small readout (points, totals, a selection summary): a
-- dark well with a bronze hairline, sized by whatever anchors the caller sets.
-- ---------------------------------------------------------------------------
function S.Plate(parent)
    local f = CreateFrame("Frame", nil, parent)
    S.Skin(f, "slot")
    f:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
    f:SetBackdropBorderColor(S.Unpack(S.GOLD_DARK, 0.9))
    return f
end
