# Word Wise 2026.07.1-rc1.3.1

RC1.3.1 is an emergency data-integrity and Full OTA release.

## Critical correctness fixes

- Fixes unrelated Vietnamese senses such as `appealing → van lơn`.
- Prevents unsafe morphology such as `gaming → gam`.
- Removes orphan/wrong-POS irregular mappings, ambiguous aliases and invalid
  phrase lengths.
- Publishes Vietnamese only for explicitly reviewed General rows or curated
  domain rows; unreviewed entries remain available with English definitions.

## Full OTA

The Release contains four exact assets: plugin ZIP/checksum and database
ZIP/checksum. RC1.3.1 verifies the outer checksum, fixed archive allow-list,
database manifest, per-file SHA-256, SQLite integrity, schema, domain, build
version and counts before staging an update. Database replacement happens on
restart before any Word Wise database connection opens.

The previous plugin and dictionary databases are backed up. An interrupted
database replacement is restored before retrying. `known_words.db`, reading
progress and per-book settings are never package targets or backup inputs.

## Upgrade path

- From RC1.3.1 or later: one check downloads code and databases together.
- From RC1.3.0 or an older code-only updater: update the RC1.3.1 plugin first,
  restart, then accept the one-time matching database synchronization prompt.

After the final restart, open **Word Wise → Diagnostics** and confirm that both
the plugin version and database build show `2026.07.1-rc1.3.1`.
