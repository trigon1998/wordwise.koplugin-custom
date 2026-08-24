# Technical reference and release history

> This document preserves the detailed README that existed before the public landing page was simplified. The main [README](../README.md) is the recommended starting point for users.

# Word Wise English–Vietnamese for KOReader

Maintenance fork of the KOReader Word Wise overlay, targeting KOReader 2026.03
“Snowflake” on Android and the iReader Ocean 5 Pro. The Git source tree remains
code-only; verified dictionary databases are distributed as a separate Full OTA
Release asset.

Current plugin candidate version: `2026.07.1-rc1.4.2`.

Release repository:
[`trigon1998/wordwise.koplugin-custom`](https://github.com/trigon1998/wordwise.koplugin-custom).

## Important repository status

This Git source tree deliberately contains no dictionary database and no user
data. GitHub Releases may attach a separately verified database-only asset. On
the device, the custom databases remain under:

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

## RC1.4.2 OTA Compatibility Hotfix

RC1.4.2 fixes the RC1.4.1 compatibility mistake. The required auxiliary allow-list remains limited to the two files accepted by older clients: `manifest.json` and `WordWise_Databases_README.txt`. `WIKTIONARY_ATTRIBUTION.md` is now optional for new clients, not required in the data archive, and its attribution content is duplicated in the legacy-safe README and manifest. This allows an existing RC1.3.9/RC1.4.0-era updater to install the new database bundle without rejecting an unknown file, while the new updater can still accept the earlier bundle that contains the optional file.

## RC1.4.1 OTA Allow-List Mistake

RC1.4.1 attempted to permit a top-level `WIKTIONARY_ATTRIBUTION.md` auxiliary file, but that change could not help an older updater: the older client validates the database archive before installing the new updater code. RC1.4.2 therefore removes that extra file from the published bundle while retaining its attribution text in the legacy-safe README and manifest. All unlisted files remain rejected, and this correction does not alter database contents or user-data handling.

## RC1.4.0 Wiktionary Expansion and Hybrid Difficulty

RC1.4.0 keeps the RC1.3.9 runtime sense-selection contract and expands the General data in a separate database-only candidate. The builder imports 538 exact Vietnamese gloss overrides from English Wiktionary and 92 phrase rows from a manually curated first batch. General rises from 48 to 678 entries with non-empty Vietnamese glosses and from 0 to 92 phrases. General overrides are domain-scoped; they are not applied to Economics or Physics merely because a term is shared.

The Wiktionary extraction stores a source URL per override and ships `WIKTIONARY_ATTRIBUTION.md` with the database bundle. Unreviewed Wiktionary, ACL, EAWL and SWL queues remain outside the runtime data. The extraction pipeline does not generate Vietnamese text. The release candidate is an adapted selection of Wiktionary material and therefore retains CC BY-SA 4.0/GFDL attribution, applicable ShareAlike/transparent-copy obligations, and the source links required for audit.

Three existing alternate senses that had a reviewed English/Vietnamese match in Wiktionary now receive a Vietnamese alternate gloss: Economics `beta`, and Physics `inflation` and `infrared`. The remaining nine sense2 rows without a sufficiently direct Wiktionary translation remain unchanged rather than receiving guessed text.

The candidate database builder applies the approved hybrid difficulty policy: `min(CEFR difficulty, frequency difficulty)`, wordfreq 3.1.1 Zipf scores with term/lemma normalization, CEFR-only fallback for Zipf 0, conservative phrase handling, and preserved numeric/POS/proper-name/domain exceptions. The candidate archive is named `WordWise_Databases_<version>.zip`, matching `Updater.dataAssetNamesForVersion()` exactly.

## RC1.3.9 Context-Aware Sense/Gloss Selection

RC1.3.9 completes the context-aware behavior that earlier releases only applied at candidate filtering/ranking level. `main.lua` now passes the prepared ±10-token context to `ContextScorer.acceptPrepared()`, captures the selected gloss and sense kind, and renders that selected English/Vietnamese pair. The popup preserves the primary and alternate glosses and labels the non-selected one as the other possible sense.

`context_scorer.lua` scores primary `context_keywords` and reviewed alternate `sense2_context_keywords` independently. An alternate sense wins only when it has a strict positive score greater than the primary score; ties, zero evidence, missing alternate metadata and legacy entries all remain on the primary gloss. Required-context entries still fail closed when neither sense has evidence.

The database runtime probes for `sense2_context_keywords` and explicitly selects either the schema-v3 column or the legacy schema-v2 query. The updater accepts both physical entries layouts, while new candidate databases use schema version 3 with the append-only column. The data package contains 83 reviewed context mappings: 28 Economics and 55 Physics. RC1.4.0 adds only three Wiktionary-sourced alternate Vietnamese glosses to existing sense2 rows; no Vietnamese translation is generated automatically.

The behavior is covered by context scorer tests for primary/alternate/tie/zero fallback, main tests for rendering a selected alternate gloss, database tests for schema-aware prepared statements, and the existing updater/full-archive checks.

## RC1.3.8 Performance OTA and RC1.3.7 CEFR-A Database Update

RC1.3.8 keeps the RC1.3.6 top-edge fallback: difficult words at the physical
top edge remain eligible for a visible hint instead of being clipped or
silently dropped. The renderer tries normal above-word placement first, clamps
small overflows when the downward caret can remain above the target, then falls
back below the word with an upward caret when there is no safe room above.

The fallback participates in two-dimensional collision checks so it cannot
overlap a neighboring hint in the same interline band. A hint is hidden only
when neither above nor below placement fits inside the screen-safe bounds.

The RC1.3.8 database bundle applies the approved CEFR-A policy. CEFR-J v1.5 and
Octanove C1/C2 v1.0 are the primary labels; Words-CEFR-Dataset is a filtered
lexical-POS fallback. Existing domain-curated/manual overrides remain eligible,
while number/ordinal tokens and entries without sufficient CEFR evidence are
excluded. Runtime difficulty maps A1 to 5, A2 to 4, B1 to 3, B2 to 2, and C1/C2
to 1 because the plugin schema has five buckets.

The candidate contains 25,403 General entries, 25,649 Economics entries and 25,620 Physics entries. It retains the existing reviewed Vietnamese glosses (48, 348 and 352 respectively) and does not generate new translations. RC1.3.8 also adds bounded visible-page/token caches, prepared context scoring, and bounded gloss-width measurement caches. The RC1.3.9 full four-asset OTA contract is synchronized at `2026.07.1-rc1.3.9`; the SQLite metadata, manifest counts and checksums are verified before release.

## RC1.3.5 Upstream-Style Hint Renderer OTA Test

RC1.3.5 abandons the RC1.3.4 target-glyph measurement experiment and returns
to the simpler renderer strategy used by `asxelot/wordwise.koplugin`.

The plugin now reserves a stable 180% interline band, uses font-level gloss
metrics, draws a horizontal rule with a fixed downward caret, centers the
complete hint unit in the raised leading, and clamps long glosses to the real
text column. Placement no longer has a target-measurement failure path.

Dictionary rows remain unchanged from RC1.3.4; only matching database build
metadata advances for the four-asset Full OTA test.

## RC1.3.4 Hint Vertical Alignment Round 2 OTA Test

RC1.3.4 removes the RC1.3.3 line-spacing estimate that remained too high on
the iReader. It measures the target word with the active book face, centers
the measured glyph height inside the CRE box, and anchors the gloss directly
above that estimate.

Compact or top-screen hints fail closed when safe placement is impossible.
Dictionary rows remain unchanged from RC1.3.3; only matching database build
metadata advances for the four-asset Full OTA test. PR #5 remains draft until
the same page is validated on-device.

## RC1.3.3 Hint Vertical Alignment OTA Test

RC1.3.3 moves inline glosses down toward the word they explain when raised
line spacing provides sufficient room. It never moves a compact-line gloss
upward relative to RC1.3.2, shortens the caret to the available gap, and hides
a hint when it cannot fit safely at the top of the screen.

The dictionary rows are unchanged from RC1.3.2. The matching database package
advances build metadata only so the complete four-asset OTA path can be tested.
The release remains a prerelease and PR #5 remains unmerged until on-device
validation is complete.

## RC1.3.2 Bootstrap Compatibility Hotfix

RC1.3.1 accidentally placed the repository-only `DATA_MAINTENANCE.md`
document inside the runtime plugin ZIP. RC1.3.0 and older updaters correctly
rejected that unknown path because their archive allow-list is fixed. RC1.3.2
restores the exact legacy plugin ZIP file set. The document remains available
in this source repository but is never installed on the reader.

After the RC1.3.2 code update and restart, the Full OTA updater downloads the
matching RC1.3.2 database package. Its reviewed dictionary content is unchanged
from RC1.3.1; only release/build metadata is advanced so the tag, plugin,
manifest and SQLite databases match exactly.

## RC1.3.1 Data Integrity Emergency Fix

RC1.3.1 fixes a systemic defect in the custom English–Vietnamese data build:
the old pipeline overwhelmingly selected the first StarDict sense even when
the English gloss requested a different sense or part of speech. This caused
unrelated results such as `appealing → van lơn`. A separate morphology bug
could also reduce `gaming` to the unrelated noun `gam`.

The maintenance release deliberately fails closed:

- only exact-sense translations reviewed by a human or the separately curated
  Economics/Physics rows are displayed in Vietnamese;
- unreviewed General translations and unverified POS values are quarantined,
  while their English definitions remain available;
- the reviewed database pack contains 48 Vietnamese General entries, 348
  Economics entries and 352 Physics entries;
- `gaming` has an exact, context-gated Economics entry and regular morphology
  accepts only one POS-valid lemma;
- case-sensitive acronyms such as `BOP`, `ROE`, `EFT` and `GUT` now beat their
  unrelated lowercase words;
- aliases with multiple targets fail closed, scientifically incorrect aliases
  are removed, and domain aliases hidden by exact General rows are promoted;
- 135 orphan irregular mappings and two wrong-POS mappings are removed from
  each database;
- 18 hyphenated entries have corrected phrase lengths, so terms such as
  `half-life` and `bid-ask spread` can be matched again;
- malformed English glosses and several reviewed domain terminology errors are
  corrected by explicit, version-controlled overrides.

The database pack remains separate from the plugin code ZIP, but both are now
part of the same Full OTA GitHub Release. The updater downloads and verifies
all four required assets before changing code or staging database replacement.
The pack contains no `known_words.db` and no book sidecars.

### RC1.3.1 Full OTA bootstrap

- Devices already running the RC1.3.1 updater or a later version download code
  and all three databases in one update operation, then finish database
  replacement on restart before any SQLite connection opens.
- RC1.3.0 and older code-only updaters first install the RC1.3.1 code ZIP. After
  restart, RC1.3.1 detects the unsynchronized database bundle and offers the
  matching database asset. This one-time two-stage bootstrap is unavoidable
  because the old updater does not know that a data asset exists.
- Every database is checked against the outer ZIP checksum, the inner manifest
  SHA-256, SQLite integrity/foreign-key checks, schema/domain/build metadata and
  manifest counts.
- An interrupted database replacement is restored from backup before retrying.
- `known_words.db` and per-book sidecars are never accepted archive paths.

See [DATA_MAINTENANCE.md](DATA_MAINTENANCE.md) for the reproducible audit,
quarantine and packaging workflow.

## RC1.3.0 Battery Optimization

RC1.3.0 reduces avoidable CPU and SQLite work while preserving the RC1.2
rendering and data behavior:

- coalesces back-to-back KOReader position/page events into one hint scan on
  the next UI tick;
- builds a compact, lazy first-word index for the 2–5-word phrases in the
  active database;
- attempts only phrase lengths that can actually begin with the visible word;
- includes multi-word aliases in the phrase index;
- ignores irregular mappings whose target entry does not exist;
- closes one-shot phrase-index statements after the index is built;
- exposes opt-in counters under **Word Wise → Performance counters** and
  **Diagnostics**.

Word Wise still scans only the currently visible page. RC1.3.0 does not limit
coverage to one paragraph because that would remove hints from other visible
paragraphs. No battery percentage claim is made until the build is measured on
the target reader.

The active dictionary remains lazy-loaded. Database files, `known_words.db`
and per-book settings are not migrated or replaced.

Use [PERFORMANCE_TEST.md](PERFORMANCE_TEST.md) for the controlled on-device
comparison against RC1.2.2.

## RC1.2.2 OTA Test

RC1.2.2 is a deliberately minimal successor to RC1.2.1 for validating the
complete on-device update path:

```text
RC1.2.1 → Check for updates → RC1.2.2 → Restart KOReader
```

It changes version and distribution metadata only. Runtime behavior, database
formats, known words and per-book settings remain unchanged.

## RC1.2.1 Updater Bootstrap (historical)

RC1.2.1 introduced the original manual, code-only GitHub Releases updater:

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
  sidecars. RC1.3.1 extends this design with the separately verified Full OTA
  database channel described above.

The first updater-enabled build had to be installed manually. Current builds
can update code and databases from the Word Wise menu.

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
2. Back up `koreader/plugins/wordwise.koplugin` and the three files under
   `koreader/wordwise/databases/`.
3. Extract `wordwise.koplugin-vVERSION.zip` and copy its
   `wordwise.koplugin` folder into `koreader/plugins/`.
4. Extract `WordWise_Databases_VERSION.zip` into the directory that already
   contains `koreader/`.
5. Do not delete or replace `koreader/wordwise/known_words.db`.
6. Restart KOReader.
7. Open **Word Wise → Diagnostics** and verify that plugin and database build
   versions match.

## Release asset contract

For tag `vVERSION`, the GitHub Release must contain:

```text
wordwise.koplugin-vVERSION.zip
wordwise.koplugin-vVERSION.zip.sha256
WordWise_Databases_VERSION.zip
WordWise_Databases_VERSION.zip.sha256
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
selects only the exact filenames above. A release missing any one of the four
assets is rejected.

The database ZIP has this exact allow-list:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise_general.db
koreader/wordwise/databases/wordwise_economics.db
koreader/wordwise/databases/wordwise_physics.db
```

Any additional path, duplicate, symlink, oversized file, user database or book
setting makes the update fail closed.

## Build and verify locally

Requirements: Bash, Python 3.12+, `zip`, `unzip`, `sha256sum`, Node.js/npm.

```bash
./tools/build_release.sh
./tools/verify_release.sh

# Build and verify all four Full OTA assets from already-audited databases.
./tools/build_full_release.sh /path/to/verified/databases

python3 -m py_compile tools/*.py tests/test_data_tools.py
python3 -m unittest -v tests/test_data_tools.py

for file in ./*.lua; do
  npx --yes luaparse "$file" >/dev/null
done

npx --yes --package=fengari-node-cli fengari tests/test_main.lua
npx --yes --package=fengari-node-cli fengari tests/test_db.lua
npx --yes --package=fengari-node-cli fengari tests/test_updater.lua
```

## Creating a GitHub Release

1. Update `version` in `update_config.lua`.
2. Run all tests.
3. Build all four assets with `tools/build_full_release.sh` and inspect their
   checksums.
4. Commit the release state.
5. Create and push the matching tag, for example:

   ```bash
   git tag v2026.07.1-rc1.3.1
   git push origin main --tags
   ```

The GitHub Actions workflow verifies the tag/version pair, rebuilds the code
assets and creates or updates a **draft** Release. It deliberately never makes
that Release public. Attach the locally verified database ZIP and checksum:

```bash
gh release upload vVERSION \
  dist/WordWise_Databases_VERSION.zip \
  dist/WordWise_Databases_VERSION.zip.sha256
```

Confirm that the draft contains exactly the four required assets, then publish
it. The public Releases API never exposes a half-complete draft to devices.

## Recovery

Before each in-app update, previous code and databases are saved under:

```text
<KOReader settings>/wordwise_update/backup/
<KOReader settings>/wordwise_update/database-backup/
```

If the new plugin still loads, use:

```text
Word Wise → Updates → Restore previous version
```

This restores the previous code and, when available, the previous database
bundle. `known_words.db` and book sidecars are not part of either backup. If
the plugin does not load, exit KOReader and manually copy both backup sets back
to their corresponding code/database directories.

## RC1.3.1 scope

- Keeps the verified RC1.2.2 updater, visible-hint tap fix, layout-aware cache
  and the RC1.3.0 battery optimizations.
- Adds correctness-first lookup, alias and English-only rendering behavior.
- Adds reproducible data audit/rebuild tools and regression tests, without
  committing any database to this Git source tree.
- Adds a four-asset Full OTA contract with staged database validation,
  restart-time replacement, interrupted-install recovery and rollback.
- Keeps the database schema at version 2 and never migrates known words or
  book sidecars.
