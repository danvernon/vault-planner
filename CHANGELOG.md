# Changelog

## 0.1.1

- Hover any character row to see a tooltip listing every raid boss killed and every Mythic+ key completed this week, with their difficulty / key level. Auto-clears at weekly reset.
- Tooltip now follows the cursor instead of anchoring to the right of the window.

## 0.1.0

- Custom keyhole-vault logo in the title bar (`Textures/VaultPlannerLogo.tga`).
- Locked slots now show difficulty / key level / projected ilvl alongside their progress (e.g. `4/6 Heroic · 278`, `3/8 +12 · 272`), so you can see the trajectory before the slot fills.
- Character list sorted by most-recently-seen first.
- `ESC` closes the window.

## 0.1.0-rc1

- Initial release.
- Great Vault scanner triggered on login, `WEEKLY_REWARDS_UPDATE`, raid kills, and M+ completion.
- Per-character SavedVariables (`VaultPlannerDB`) keyed by Name-Realm.
- `/vault` and `/vp` slash commands.
- Window listing all characters with class icons, equipped item level, three vault tracks, and weekly reset countdown.
- Filled slots show difficulty/key level + reward item level (e.g. `Mythic · 285`, `+16 · 285`).
- Persistent `Vault ready` / `Vault claimed` badges, gated on the vault frame being open so transient API state can't flip them incorrectly.
- Custom dark frame chrome with cyan accents (no default Blizzard inset).
