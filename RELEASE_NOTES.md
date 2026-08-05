# Word Wise 2026.07.1-rc1.3.2

RC1.3.2 is a bootstrap-compatibility hotfix for the RC1.3.1 Full OTA release.

## Fixed

- Removes the repository-only `DATA_MAINTENANCE.md` document from the runtime plugin ZIP.
- Restores exact compatibility with the fixed archive allow-list in RC1.3.0 and older code-only updaters.
- Adds a release regression guard so future plugin ZIPs cannot accidentally add files outside the legacy OTA contract.

## Full OTA path

Devices on RC1.3.0 or older first install the RC1.3.2 plugin through the normal Word Wise updater. After restart, RC1.3.2 offers the matching database synchronization and installs all three databases on the next restart.

The reviewed dictionary content is unchanged from RC1.3.1. The database package is re-versioned to `2026.07.1-rc1.3.2` so the release tag, plugin version, manifest and SQLite build metadata match exactly.

`known_words.db`, reading progress and per-book settings are never package targets.
