# VaultPlanner

Track Great Vault progress across all your alts in one window.

## Features

- Scans your Great Vault on login, weekly reset, raid kills, and M+ completion.
- Persists per-character snapshots (Name-Realm) in `VaultPlannerDB`.
- `/vault` (alias `/vp`) opens a window with all known characters showing:
  - Class-colored character names with realm and equipped item level.
  - Three vault tracks (Raid, Mythic+, World/Delves), three slots each.
  - Filled slots show the reward item level; locked slots show progress (e.g. `4/8`).
  - Time until the next weekly reset.
- Sorted by filled-slot count, then most-recently-seen first.

## Slash commands

- `/vault` or `/vp` — open the window.
- `/vp scan` — force a re-scan of the current character.
- `/vp list` — print all known characters.
- `/vp remove Name-Realm` — delete a character record.

## Requirements

- World of Warcraft retail (Interface 120001 / 120005, Midnight 12.0+).

## License

MIT — see `LICENSE`.
