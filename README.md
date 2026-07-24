# Word Wise English–Vietnamese for KOReader

Code-only maintenance fork of the KOReader Word Wise overlay, targeting
KOReader 2026.03 “Snowflake” on Android and the iReader Ocean 5 Pro.

Current plugin version: `2026.07.1-rc1.2.2`.

Release repository:
[`trigon1998/wordwise.koplugin-custom`](https://github.com/trigon1998/wordwise.koplugin-custom).

## Important repository status

This repository deliberately contains no dictionary database and no user data.
The custom databases remain under:

```text
<KOReader data>/wordwise/databases/
```

Known words remain under:

```text
<KOReader data>/wordwise/known_words.db
```

Per-book settings remain in KOReader sidecars.

The upstream repository does not publish an explicit open-source license. The
repository owner confirms private permission from the upstream author to
modify and redistribute this code-only fork. See [NOTICE.md](NOTICE.md) for the
scope of that notice.

## RC1.2.2 OTA Test

RC1.2.2 is a deliberately minimal successor to RC1.2.1 for validating the
complete on-device update path:

```text
RC1.2.1 → Check for updates → RC1.2.2 → Restart KOReader
```

It changes version and distribution metadata only. Runtime behavior, database
formats, known words and per-book settings remain unchanged.

## RC1.2.1 Updater Bootstrap

RC1.2.1 adds a manual, code-only GitHub Releases updater:

```text
Word Wise → Updates
```

The updater:

- accesses only a public GitHub `owner/repository`;
- checks only when the user taps **Check for updates**;
- requires an exact release ZIP and companion SHA-256 file;
- rejects unknown, duplicate, oversized and non-regular archive entries;
- compiles every staged Lua file before installation;
- checks that the release tag, `_meta.lua` and `update_config.lua` versions
  match;
- backs up the currently installed plugin code before replacing files;
- prompts for a KOReader restart after a successful update;
- never reads or writes `wordwise/databases`, `known_words.db` or book
  sidecars.

The first updater-enabled build must be installed manually. Later builds can
be installed directly from the Word Wise menu.

## Configure the release repository

This build defaults to:

```lua
default_repository = "trigon1998/wordwise.koplugin-custom"
```

It can be overridden on the device under:

```text
Word Wise → Updates → Repository
```

The repository must be public. This bootstrap intentionally does not store a
GitHub personal access token on the reading device.

Because the current build is an RC, **Include prerelease/RC updates** defaults
to enabled. Stable builds default to the stable channel.

## Manual installation

1. Exit KOReader completely.
2. Back up `koreader/plugins/wordwise.koplugin`.
3. Extract the release ZIP.
4. Copy its `wordwise.koplugin` folder into `koreader/plugins/`.
5. Do not delete or replace `koreader/wordwise/`.
6. Restart KOReader.
7. Open **Word Wise → Diagnostics** and verify the plugin version.

## Release asset contract

For tag `vVERSION`, the GitHub Release must contain:

```text
wordwise.koplugin-vVERSION.zip
wordwise.koplugin-vVERSION.zip.sha256
```

The ZIP has one top-level directory:

```text
wordwise.koplugin/
├── _meta.lua
├── main.lua
├── wordwise_db.lua
├── known_words.lua
├── context_scorer.lua
├── book_classifier.lua
├── wordwise_updater.lua
├── update_config.lua
├── README.md
└── NOTICE.md
```

GitHub-generated “Source code” archives are not updater assets. The updater
selects only the exact filenames above.

## Build and verify locally

Requirements: Bash, `zip`, `unzip`, `sha256sum`, Node.js/npm.

```bash
./tools/build_release.sh
./tools/verify_release.sh

for file in ./*.lua; do
  npx --yes luaparse "$file" >/dev/null
done

npx --yes --package=fengari-node-cli fengari tests/test_main.lua
npx --yes --package=fengari-node-cli fengari tests/test_updater.lua
```

## Creating a GitHub Release

1. Update `version` in `update_config.lua`.
2. Run all tests.
3. Commit the release state.
4. Create and push the matching tag, for example:

   ```bash
   git tag v2026.07.1-rc1.2.2
   git push origin main --tags
   ```

The included GitHub Actions workflow verifies the tag/version pair, rebuilds
the code-only asset and publishes both the ZIP and SHA-256 file.

## Recovery

Before each in-app update, the previous code is saved under:

```text
<KOReader settings>/wordwise_update/backup/
```

If the new plugin still loads, use:

```text
Word Wise → Updates → Restore previous version
```

If it does not load, exit KOReader and manually copy the backup files back to
`koreader/plugins/wordwise.koplugin/`.

## RC1.2.2 scope

- Provides a version-only successor for the first end-to-end OTA update test.
- Keeps the RC1.2.1 updater bootstrap, repository packaging, tests and release
  automation unchanged.
- Keeps the RC1.2 visible-hint tap fix, layout-aware cache and five-word phrase
  support.
- Does not include the planned RC1.3 battery optimizations.
- Does not change any database or user setting schema.
