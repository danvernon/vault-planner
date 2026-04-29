# Changelog

## 0.1.0-rc1

- Initial release.
- Great Vault scanner triggered on login, `WEEKLY_REWARDS_UPDATE`, raid kills, and M+ completion.
- Per-character SavedVariables (`VaultPlannerDB`) keyed by Name-Realm.
- `/vault` and `/vp` slash commands.
- Window listing all characters with class icons, equipped item level, three vault tracks, and weekly reset countdown.
- Filled slots show difficulty/key level + reward item level (e.g. `Mythic · 285`, `+16 · 285`).
- Persistent `Vault ready` / `Vault claimed` badges, gated on the vault frame being open so transient API state can't flip them incorrectly.
- Custom dark frame chrome with cyan accents (no default Blizzard inset).
