# Individual Progression (WoW 3.3.5a addon)

A read-only in-game window for AzerothCore realms running
[mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression).
It shows the current character's progression tier and the level cap that comes with it. It also lists what
every tier unlocks, and which boss kill or quest grants the next tier.

- **No server script needed.** The addon reads the tier from the character's completed quests.
  The module records tier N as the rewarded hidden quest `66000 + N`, and the stock client can list
  those quests itself through `QueryQuestsCompleted`.
- **Read-only.** You can't buy or change anything from the window.
- Can be installed next to the LegacyServices addon without conflicts.

## Install

1. Copy the `ModIndividualProgression` folder into `Interface/AddOns/`. If you downloaded a
   source zip, rename the folder to exactly `ModIndividualProgression`.
2. Fully restart the client (a new addon is only picked up at startup).
3. Enable it at character select (turn on "Load out of date AddOns" if needed).
4. In game: `/ipp` or `/progression`, or click the minimap button.

## Docs

- [START.md](START.md): testing, where to make common changes, troubleshooting.
- [DESIGN.md](DESIGN.md): data source, refresh rules, layout decisions, limits.

Links in those docs to `../LegacyServices/` point to the sibling addon this one was branched
from. That addon is not part of this repository.

## Release history

- **1.0**: first release.
