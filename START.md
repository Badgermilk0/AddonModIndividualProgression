# ModIndividualProgression (client addon) — Start Here

## What this is

An in-game window that shows this character's **mod-individual-progression** tier: where it
stands, its level cap, what every tier unlocks, and the boss kill or quest that grants the next
one. It is the **Temporal Alignment** tab of [LegacyServices](../LegacyServices/START.md),
branched into a standalone, **read-only** addon for realms that run mod-individual-progression
**without** the LegacyServices server scripts. Nothing can be bought here, and nothing needs to
be installed on the server.

It reads the tier from the character's own completed quests: the module records tier N as
rewarded hidden quest `66000 + N`, and the client can list those itself
(`QueryQuestsCompleted`). The details are in [DESIGN.md](DESIGN.md).

- Skin: [`ModIndividualProgressionSkin.lua`](ModIndividualProgressionSkin.lua), the global
  `MIPSkin`. It is a branch of `LegacyServicesSkin.lua` and loads first.
- Main: [`ModIndividualProgression.lua`](ModIndividualProgression.lua).
- Manifest: [`ModIndividualProgression.toc`](ModIndividualProgression.toc) (Interface 30300),
  skin first, then main.

## Install / load

1. Copy the whole `ModIndividualProgression` folder into the client's `Interface/AddOns/`.
2. **Fully restart the client.** A new addon (and any `.toc` change) is only picked up at
   startup; `/reload` is enough for later `.lua` edits.
3. At character select, make sure it is enabled (and "Load out of date AddOns" is on if the
   client complains about 30300).
4. In game: `/ipp` or `/progression`, or the minimap button (the time-stop emblem).

It can be installed next to LegacyServices; no global, frame, saved variable or slash command
overlaps.

## How to test

- `/ipp` → the **Temporal Alignment** tab:
  - header: *Current Tier* `[Tier N]  Name` and *Level Cap*;
  - progress bar: `N / 17 Tiers Completed`;
  - tier list: grouped by expansion.

  There are **17 tiers and no Tier 11**. A character at tier 10 must show **tier 12** as next.
  If it is stuck on "Loading…", see Troubleshooting.
- **Rows**:
  - completed tiers are green with a check on the icon;
  - the next tier is highlighted gold;
  - later tiers are dimmed.

  The right-hand column names the boss kill or quest that grants each tier (*Defeat Ragnaros*,
  *Quest: Into the Breach*…). Hover any row for the era, level cap, lore, *How it's earned* and
  *Unlocks*.
- **Next Objective** card (bottom): names the next tier and how to reach it. At a level cap it
  adds "You are level 60 and will gain no more XP until Tier 8."
- **Readouts:**
  - title band: your class emblem, name and level;
  - rail foot: *Progression Tier* and the XP plate (*Gaining XP* / *XP capped at 60/70* /
    *Max level*). Hover the XP plate for the rule.
- **Live change (GM):** with the window open, `.ip set <yourname> 12`. Within a couple of
  seconds (or press **Refresh**) the tab should read Tier 12 with Tier 13 next. Set it back
  lower and it must follow down, too.
- **Side by side:** with LegacyServices installed as well, both Temporal Alignment tabs should
  agree on the tier for the same character.
- The window reopens where you last dragged it; the minimap button remembers its angle.

## Where to make common changes

| Goal | Place |
|---|---|
| Edit a tier's **requirement text, lore or unlock list** | `alignFrame.tierInfo` in `ModIndividualProgression.lua`. `goal` is the short row column, `earn` the full sentence, `unlocks` the tooltip list, and `cap` must agree with `CapForTier`. Except `goal`, it is copied from LegacyServices' `alignFrame.tierInfo`; change both. |
| Rename a tier | `TIERS` (the catalog) near the top of the main file. It mirrors the LegacyServices server's `ProgressionTiers`. **Key 11 stays absent.** |
| Change a tier's **icon** or the **era groups** | `alignFrame.tierIcons` / `alignFrame.tierGroups`. |
| Change **how often it asks the server** | `QUERY_GAP` (minimum seconds between queries) and `QUERY_TIMEOUT`. Every query returns *every* rewarded quest, so don't lower the gap much. |
| React to another **progression trigger** | the event handler at the end of the main file. Call `RequestProgress(delay)`; never `QueryQuestsCompleted()` directly, or the throttle is bypassed. |
| Change **how anything looks** | `ModIndividualProgressionSkin.lua`. Better: make the change in `LegacyServicesSkin.lua` too, and keep the two files diffable. |
| Add a **new tab** | add its name to `TAB_NAMES`, its tooltip to `TAB_TOOLTIPS`, its emblem to `MIPSkin.TAB_ICONS`, and a slot in `NAV_SECTIONS` (in the rail's do-block). Build the tab in a **companion file** listed in the `.toc` after the main file; it reads `data` / `CreateContentFrame` / `RequestProgress` from `ModIndividualProgressionUI`. In the main file, add `[idx] = "YourFile.lua"` to `COMPANION_FILES` (so a failed load names the file) and wire the tab's data pull into `RefreshActiveTab()`. Indices must stay contiguous. |

## Client-Lua rules you must follow

1. **No `\xHH` escapes** — stock Lua 5.1. Use decimal `\ddd` or literal UTF-8.
2. **Don't read `ModIndividualProgressionDB` at file scope.** Saved variables are assigned after
   the files run; initialise them in the `ADDON_LOADED` handler, as `InitSavedVariables` does.
3. **Keep the event handler last in the file.** It closes over functions from every section; a
   local declared after it is a nil global to it, silently.
4. **Unique names for templated frames** (`MIPAlignScroll`, …). A second addon's frame with the
   same name would take over the global.
5. This client runs with **`scriptErrors` off**: a compile error means `/ipp` and the minimap
   button simply don't exist. Parse with python `luaparser` (Lua 5.1) and run `luacheck` before
   handing a change over.

## Troubleshooting

- **Always Tier 0.**
  - The character may really not have passed Molten Core yet.
  - Or the realm doesn't run mod-individual-progression, or has it disabled
    (`IndividualProgression.Enable = 0`), so the 660xx quests are never rewarded.
  - A GM can compare with `.ip get <name>`.
- **"Loading…" forever, or "The server has not answered yet."** The completed-quests query got
  no reply. Press Refresh. If it persists, the realm may throttle that packet: check its
  `antidos_opcode_policies` table for opcode 1280 (0x500). The stock table has no row for it.
- **The tier is right but the requirement text is wrong.** The realm has changed how tiers are
  granted (`CustomProgression`, `DisableDefaultProgression`, `ProgressionLimit`). The addon
  reads the result correctly but its prose describes the module's defaults.
- **"XP capped" on a character that still gains XP.** The account is on the realm's excluded
  list (`ExcludedAccountsRegex`), which has no caps; the client can't see that.
- **Tier 11 "Zul'Aman (retired tier)".** Correct for a character that finished Zul'Aman before
  the module retired that tier. Its next tier is 12.
- **No window, no minimap button, `/ipp` does nothing.** The addon failed to load. Check it is
  enabled, the `.toc` lists the skin before the main file, and you restarted the client after
  copying it in.

## See also

- [DESIGN.md](DESIGN.md) — data source, refresh rules, layout decisions, limits.
- [../LegacyServices/START.md](../LegacyServices/START.md) — the full addon this came from.
