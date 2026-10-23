# ModIndividualProgression (client addon) — Design

A **read-only** WoW 3.3.5a addon that shows where the current character stands in
**mod-individual-progression**: its tier, the level cap that tier implies, what every tier
unlocks, and how to reach the next one. It is a branch of the
[LegacyServices](../LegacyServices/DESIGN.md) addon's **Temporal Alignment** tab, for realms
that run mod-individual-progression **without** the LegacyServices server scripts.

- **No server script.** Everything it shows is read on the client or written into the addon.
  Nothing is sent to the server except the stock completed-quests query.
- **No purchasing.** LegacyServices' tab exists to sell tiers for gold. That path is gone: no
  Advance button, no confirmation popup, no prices, no Legacy Points and no Temporal Exchange.
- **Same window and layout** as LegacyServices: the 864×620 stone window, the navigation rail,
  and the tab's header, progress bar, grouped tier list, tooltips and Next Objective card.
  The rail is kept although only one tab exists, so a future tab slots in without window
  rework. That is also why the `CreateContentFrame` / `SetActiveTab` / `COMPANION_FILES` /
  `ModIndividualProgressionUI` machinery is still here.

## Files

| File | What it is |
|---|---|
| [`ModIndividualProgression.toc`](ModIndividualProgression.toc) | Interface 30300; SavedVariables `ModIndividualProgressionDB`. **Skin first, then main**: the main chunk calls `MIPSkin` at file scope, so the order is a load requirement, not a style choice. |
| [`ModIndividualProgressionSkin.lua`](ModIndividualProgressionSkin.lua) | The global `MIPSkin`: every backdrop, texture path and widget factory. It is a **verbatim branch** of `LegacyServicesSkin.lua` (3.4) apart from its header, the global's name and `TAB_ICONS`; see *Keeping in step with LegacyServices*. |
| [`ModIndividualProgression.lua`](ModIndividualProgression.lua) | Everything else: progress reading, the window, the rail, the Temporal Alignment tab, slash commands, minimap button, events. About 1450 lines; its chunk is nowhere near the Lua 5.1 200-local cap, so it needs none of the IIFEs LegacyServices wraps its tabs in. |

## Where the tier comes from

mod-individual-progression stores a character's tier as **rewarded hidden quests**:
- quest `66000 + N` is rewarded for every tier N the character has passed;
- the quest rows are 66001–66018 in the module's `data/sql/world/base/player_progression.sql`,
  with Flags 1024 (tracking) and non-repeatable;
- `IndividualProgression::GetPlayerProgressionFromQuests` returns the highest N whose quest is
  rewarded.

The GM command `.ip get` is `SEC_GAMEMASTER`, so a player can't ask for it. The stock 3.3.5a
client doesn't need to:

```
QueryQuestsCompleted()  ->  QUEST_QUERY_COMPLETE  ->  GetQuestsCompleted(t)   -- t[questId] = true
```

The core answers the query with the character's whole rewarded set
(`WorldSession::HandleQueryQuestsCompleted`, `CORE/.../Handlers/QuestHandler.cpp`). The
handler has no throttle of its own, and the shipped `antidos_opcode_policies` table has no row
for the opcode (`CMSG_QUERY_QUESTS_COMPLETED`, 0x500); a realm could still add one.
DataStore_Quests,
EveryQuest and Zygor in this workspace use the same calls. `ReadTier()` walks 1..18 and keeps
the highest N with `t[66000 + N]` — the module's own rule, so the addon can't disagree with the
server about which tier a character is on.

- **`wipe` before and after.** `GetQuestsCompleted(t)` fills the table it is given without
  clearing it. The addon reuses one table, so it wipes it first; otherwise a tier the server
  has since removed would survive as a stale key (a GM's `.ip set` to a lower value runs
  `ForceUpdateProgressionState`, which un-rewards the higher quests). It wipes again afterwards
  so thousands of quest ids are not held between reads.
- **Tier 11 is a real state, with no row.** Upstream `7944f77` deleted
  `PROGRESSION_TBC_TIER_3`, but quest 66011 still exists in `quest_template`. A character that
  killed Zul'jin before that change can still have 66011 as its highest quest, and the module
  then really reports 11. The addon names it `Zul'Aman (retired tier)` rather than falling back
  to "The Beginning" (the reference tab's fallback). The next tier after it is 12, and the bar
  counts tiers 1–10 as done.
  - Characters that reach 12 the normal way also have 66011 rewarded:
    `UpdateProgressionState` rewards every quest from the current state up to the new one, and
    the 66011 template still exists. The highest-quest rule is what makes that harmless.

### When it asks

Each reply lists **every** rewarded quest, often thousands of ids, so the addon asks sparingly:

| Trigger | Request |
|---|---|
| First `PLAYER_ENTERING_WORLD` of the session | `RequestProgress(3)`, so the window usually opens on real data. Zoning fires the event again, but can't change a tier. |
| Window `OnShow`, **Refresh**, clicking the tab | `RequestProgress(0)` via `RefreshActiveTab()` |
| `ACHIEVEMENT_EARNED` (the boss kills that grant tiers almost always award one), `QUEST_FINISHED` (tiers 4, 5 and 8 are quest turn-ins), a `CHAT_MSG_SYSTEM` containing `Updated Progression Level` (a GM's `.ip set` on this character) | `RequestProgress(2)`, **only while the window is open**. Opening it re-reads anyway, so querying for a closed window would only cost bandwidth. |
| `QUEST_QUERY_COMPLETE` from **any** addon | Read it. Zygor polls every 10 s and DataStore queries at login; their answers are the same list and cost nothing extra. |

`RequestProgress(delay)` feeds a single hidden `OnUpdate` driver frame:
- **Throttle.** At most one query per `QUERY_GAP` (5 s).
- **Coalescing.** A request made while one is pending merges into it, and the earlier due time
  wins, so an explicit Refresh is never held back by a background trigger.
- **One frame only.** A frame-per-timer helper would leak (frames are never garbage-collected
  on 3.3.5a) and there is no `C_Timer`.
- **Timeout hint.** If the *first* read of the session gets no reply within `QUERY_TIMEOUT`
  (10 s, counted from the latest query), `data.queryTimedOut` turns the Next Objective card into
  "The server has not answered yet". The user's client runs with `scriptErrors` off, so a
  silent "Loading…" would be the only clue. Once a tier is on screen, a lost reply just leaves
  it as it was.
- **Missing API.** If `QueryQuestsCompleted` doesn't exist, `data.unsupported` makes the card
  say so. It can't happen on a real 3.3.5a client; it only guards a port.

## Data model

```
data = { charTier, loaded, queryTimedOut, unsupported, levelOverride, tiers = TIERS }
```

- **`TIERS` is a static client-side catalog.** LegacyServices received tier names from its
  server script as `TI` rows; standalone, the client owns them. The names mirror
  `ProgressionTiers` in `LUA_SCRIPTS/LegacyServices/LegacyServices.lua`, so both addons name
  every tier identically. **Key 11 is absent**, so the list is sparse: the next tier is found by
  walking forward to the next key that exists (`alignFrame.nextTier`), never `charTier + 1`.
  The progress bar counts catalog entries, so it reads `n / 17`.
- **`CapForTier(t)`** is the level ceiling while *at* tier t:
  - 60 below tier 8, 70 below tier 13, 80 from 13 up;
  - mirrors `OnPlayerGiveXP` in `IndividualProgressionPlayer.cpp`;
  - it is a chunk-level local, not an `alignFrame` field, because the window's header readouts
    are built before the tab and need it.
- **`levelOverride`** exists because `UnitLevel("player")` can still report the old level
  inside `PLAYER_LEVEL_UP`. The handler carries the event's level until the unit catches up
  (`PlayerLevel()` takes the higher of the two).

## UI

What changed against the LegacyServices tab, and why:

| Element | LegacyServices | Here |
|---|---|---|
| Window title | Legacy Services | Individual Progression |
| Title-band plate | the character's gold (what the tab spent) | class emblem, class-coloured name and `Level N` |
| Rail-foot large plate | Legacy Points | *Progression Tier*, `Tier N` |
| Rail-foot small plate | Resting (gates four other tabs) | XP state: *Gaining XP* / *XP capped at 60/70* / *Max level*, with a tooltip explaining the caps. It is the same kind of window-wide gate the Resting plate reported. |
| Header line 1 | *Soul Anchored* `[Tier N]` | *Current Tier* `[Tier N]  Name` |
| Header line 2 | *Account Peak*, a server DB query over every character on the account | *Level Cap*, e.g. `60  —  rises to 70 at  [Tier 8]  Pre-TBC Invasion`, orange with "(reached)" when the character sits at it. The client cannot ask the server about other characters, so the line became the fact this tier *does* decide. |
| Progress bar | account tiers unlocked | this character's tiers completed |
| Row right column | gold price | **requirement**: the kill or quest that grants the tier |
| Row states | completed / next (buyable or short of gold) / unlocked on the account / locked | completed / next / not reached yet |
| Tooltip closing line | price and affordability | state only |
| Next Objective card | "anchor with gold" vs "earn it yourself" | *To reach it:* the earn text, plus the level-cap warning |

- **The requirement column** comes from a new `goal` field in `alignFrame.tierInfo`:
  - it is the module's exact trigger: the boss map in
    `IndividualProgression::checkKillProgression`, and the three quests (Bang a Gong! / Simply
    Bang a Gong!, Chaos and Destruction, Into the Breach) in
    `IndividualProgressionPlayer::OnPlayerCompleteQuest`;
  - the columns moved from 315/205 to 290/230 so `Quest: Chaos and Destruction` fits, while the
    longest label, `[Tier 10]  Serpentshrine & Tempest Keep`, still fits;
  - the full story stays in the tooltip (*How it's earned*) and the Next Objective card.
- **The level-cap warning** now names the character's real level ("You are level 62…"). The
  reference printed the cap there, which is wrong for a character above the cap: one levelled
  before the module was installed, or boosted.
- **Before the first read** the list is hidden, the header reads `--` and the bar reads
  *Reading progression…*. Drawing the tiers early would show every one of them as not reached,
  which is a claim rather than a placeholder. The rail-foot plates read `--` too; the character
  plate is live at any time.

## Keeping in step with LegacyServices

- **Skin.** `ModIndividualProgressionSkin.lua` is `LegacyServicesSkin.lua` with three edits:
  the header, `LSSkin` → `MIPSkin`, and a one-entry `TAB_ICONS`. `PROFESSION_ICONS` is dropped.
  A restyle there is carried across by diffing the two files. Comments that name LegacyServices
  tabs (Vaults, Blessings, Teleports…) were kept so the diff stays small. Unused helpers (item
  slots, cards, checkboxes, state borders) were kept as the kit for future tabs.
- **Tier prose.** `tierInfo` (era, cap, flavor, earn, unlocks), `tierIcons` and `tierGroups`
  are copied from LegacyServices' `alignFrame`. Only `goal` is new. Edit one, edit the other.
- **Tier names** mirror the LegacyServices server's `ProgressionTiers`.
- **Global names never overlap**, so both addons can be installed at once:

  | Kind | LegacyServices | ModIndividualProgression |
  |---|---|---|
  | Skin | `LSSkin` | `MIPSkin` |
  | SavedVariables | `LegacyServicesDB` | `ModIndividualProgressionDB` |
  | Shared handles | `LegacyServicesUI` | `ModIndividualProgressionUI` |
  | Frames | `LegacyServicesFrame`, `LSAlignScroll`, `LegacyServicesMinimapButton` | `ModIndividualProgressionFrame`, `MIPAlignScroll`, `ModIndividualProgressionMinimapButton` |
  | Slash | `/legacy`, `/ls` | `/ipp`, `/progression` |
  | Minimap default | 220° | 190°, so the two buttons don't stack |

  `luacheck --only 111 112` confirms these are the only globals the addon writes.

## Client-Lua decisions (the "why")

- **SavedVariables are read in `ADDON_LOADED`, never at file scope.** The client runs an addon's
  files *first*, then assigns its saved variables, then fires `ADDON_LOADED`, so a table built
  at file scope is simply replaced. `InitSavedVariables()` fills defaults (`minimapAngle`) and
  `RestoreWindowPosition()` re-anchors the window from there, and every later read goes through
  the global. (LegacyServices restores its window position at file scope. That appears to work
  only because the client's own layout cache puts a user-moved named frame back.)
- **Event handling is the last section of the file.** Its handler closes over functions from
  every section above, and a Lua local is only visible to code written after it. Reordering it
  upward would turn those calls into nil global reads with no error, because this client runs
  with `scriptErrors` off.
- **Stock Lua 5.1:** no `\xHH` escapes. The `—`, `·` and `•` in strings are literal UTF-8, as
  in LegacyServices.

## Limits

The client sees the *result* (which quests are rewarded) but none of the realm's configuration:
- **`ProgressionLimit`, `DisableDefaultProgression`, `CustomProgression`** change how tiers are
  granted. The tier readout stays correct, because it reads the same quests the module writes,
  but the requirement column and the earn/unlock prose describe the module's **defaults**. So
  do the content gates: ZG at 3 and ZA at 12 from `individualProgression.conf.dist`, and the
  Death Knight start at 13.
- **Excluded accounts** (`ExcludedAccountsRegex`) never have XP withheld, but the XP plate and
  cap line can't tell and will still report a cap.
- **Max level** is taken as 80 (*Max level* on the XP plate, "no progression cap" on the cap
  line).

## Verification that was done

Static checks, plus execution in an offline harness (python `lupa.lua51` with a stubbed WoW
API); not in game.
- **Static:** luaparser (Lua 5.1) parse, luacheck 0/0, and a scan confirming no `\xHH` escapes.
- **Harness scenarios:**
  - tiers 0, 7@60, 10@70, 11 (legacy), 13@58 (DK start) and 18@80;
  - no reply (Loading… → timeout hint → late reply renders);
  - missing API;
  - `PLAYER_LEVEL_UP` while `UnitLevel` still reports the old level;
  - query throttle, coalescing, and no background queries while closed;
  - tier lowered by a GM (the wipe);
  - group collapse, slash help and toggle;
  - saved position and minimap angle restored after `ADDON_LOADED`.

  Mutating the next-tier walk to `charTier + 1`, or dropping the `wipe`, makes the harness fail
  as expected.

## See also

- [START.md](START.md) — install, test, where to edit, troubleshooting.
- [../LegacyServices/DESIGN.md](../LegacyServices/DESIGN.md) — the addon this was branched from.
- `MODULES/mod-individual-progression/` — `IndividualProgression.h` (the `ProgressionState`
  enum), `IndividualProgression.cpp` (`GetPlayerProgressionFromQuests`,
  `checkKillProgression`), `IndividualProgressionPlayer.cpp` (XP caps, quest triggers,
  teleport gates).
