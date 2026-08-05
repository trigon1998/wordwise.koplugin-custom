# Word Wise data maintenance

RC1.3.1 treats translation correctness as a release invariant. Automated
similarity is useful for finding review candidates, but it is never sufficient
to publish a Vietnamese gloss.

## Why the old data was unsafe

The original custom build paired an English gloss with a StarDict headword and
usually kept the first Vietnamese sense. Part of speech and exact sense were
not reliably aligned. The source General database contains 16,041 headwords
with multiple StarDict senses, while 26,549 of 27,173 matched headwords use the
first sense. This is a systemic provenance problem, not a small typo list.

WordNet and Open Multilingual Wordnet alignment were evaluated as independent
signals. Even the strictest tested automatic threshold produced false matches
such as sperm/semen and literal rather than contextual senses. RC1.3.1
therefore uses those sources for audit suggestions only.

## Release policy

- A General Vietnamese gloss and POS are published only through an explicit
  row in `data/translation_overrides.tsv`.
- English-gloss repairs are explicit rows in `data/english_overrides.tsv`.
- Existing Economics and Physics rows are preserved because they were created
  as separate curated domain data; explicit domain overrides fix confirmed
  terminology errors.
- Unreviewed General rows retain `short_en`, but `short_vi` is empty and `pos`
  is unknown. This prevents both a wrong translation and unsafe regular
  deinflection.
- The 15 surviving irregular mappings have an existing target and a reviewed
  or WordNet-compatible target POS. Orphans and incompatible targets are
  deleted.
- Rejected StarDict glosses are not copied into a hidden audit table in the
  runtime database. Optional review logs stay outside the data package.

## Audit

The audit is read-only. It checks SQLite integrity, schema invariants, metadata
counts, aliases, irregular targets, phrase lengths, punctuation balance,
StarDict POS availability and WordNet/OMW alignment.

```bash
python3 tools/audit_wordwise_data.py \
  --database-dir /path/to/source/databases \
  --stardict-dir /path/to/extracted/stardict \
  --wordnet-zip /path/to/wordnet.zip \
  --omw-vie /path/to/wn-wikt-vie.tab \
  --cache /path/to/stardict-senses.sqlite3 \
  --output /path/to/audit.json
```

The JSON suggestions are a review queue, not publishable translations.

## Rebuild

The output directory must be new or empty. The command refuses to overwrite an
existing SQLite database or journal/WAL sidecar.

```bash
python3 tools/rebuild_wordwise_data.py \
  --source-dir /path/to/source/databases \
  --output-dir /path/to/new-output \
  --wordnet-zip /path/to/wordnet.zip \
  --overrides data/translation_overrides.tsv \
  --english-overrides data/english_overrides.tsv \
  --build-version 2026.07.1-rc1.3.1 \
  --manifest /path/to/rebuild-manifest.json \
  --review-log-dir /path/to/private-review-logs
```

The rebuild:

1. copies each source database to a new destination;
2. removes any rejected-translation audit table;
3. repairs reviewed English and Vietnamese rows;
4. quarantines every unreviewed General VI/POS value;
5. removes unsafe, ambiguous, one-character and unreachable aliases;
6. promotes safe domain aliases hidden by General exact entries;
7. removes orphan/wrong-POS irregular mappings;
8. corrects phrase lengths using whitespace-visible KOReader tokens;
9. updates all metadata counts;
10. runs integrity/foreign-key/schema checks, `ANALYZE`, `VACUUM`, closes and
    reopens every output to detect a stale SQLite journal or rollback.

## Package

```bash
python3 tools/build_data_release.py \
  --database-dir /path/to/new-output \
  --output-dir /path/to/package-output \
  --version 2026.07.1-rc1.3.1
```

The ZIP allow-list is fixed to:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise_general.db
koreader/wordwise/databases/wordwise_economics.db
koreader/wordwise/databases/wordwise_physics.db
```

`known_words.db`, plugin code and book settings cannot enter this package. The
builder validates all three database hashes, metadata versions and integrity
before writing the archive and companion SHA-256 file.

For a Full OTA release, run:

```bash
./tools/build_full_release.sh /path/to/new-output
```

This builds and verifies the code ZIP/checksum and database ZIP/checksum as one
release set. The on-device updater independently repeats the outer checksum,
manifest, per-database SHA-256, SQLite integrity, schema/domain/build and count
checks before creating a pending restart-time install.

## Adding a reviewed correction

For each correction, record the database domain (`*` only for a General row),
the exact term, exact requested sense, POS and a short review note. Do not add a
translation based only on the headword or on a similarity score.

Run:

```bash
python3 -m py_compile tools/*.py tests/test_data_tools.py
python3 -m unittest -v tests/test_data_tools.py
```

Then rebuild into a fresh directory, rerun the full audit and inspect every
manifest change before packaging.

## Distribution boundary

This Git source tree remains code-only. A GitHub Release may attach the
database-only Full OTA asset only after its distributor has independently
verified the rights for every included data source. The asset must remain in a
draft Release until both its ZIP and checksum pass `verify_data_release.py`.
