# Word Wise English–Vietnamese for KOReader

**Inline English–Vietnamese explanations for difficult words and phrases while you read.**
**Hiển thị giải nghĩa Anh–Việt ngay trên trang sách trong KOReader.**

[![Latest release](https://img.shields.io/github/v/release/trigon1998/wordwise.koplugin-custom?include_prereleases&sort=semver&label=release)](https://github.com/trigon1998/wordwise.koplugin-custom/releases)
[![CI](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml/badge.svg)](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml)
[![Plugin downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Ftrigon1998%2Fwordwise.koplugin-custom%2Fmain%2Fstats%2Fdownloads-badge.json)](stats/downloads.svg)
[![Stars](https://img.shields.io/github/stars/trigon1998/wordwise.koplugin-custom?style=flat)](https://github.com/trigon1998/wordwise.koplugin-custom/stargazers)

<p align="center">
  <img src="docs/wordwise-preview.svg" width="860" alt="Word Wise hints displayed above difficult words in a KOReader page">
</p>

## What is this? · Đây là gì?

Word Wise is a KOReader plugin for English learners. It scans only the page
currently visible on screen, finds selected difficult words or phrases, and
places a short explanation directly above them. A Kindle-style rule and
downward caret show exactly which word each hint belongs to.

Word Wise là plugin dành cho người đọc sách tiếng Anh bằng KOReader. Plugin chỉ
quét trang đang hiển thị, tìm những từ hoặc cụm từ khó phù hợp rồi đặt giải
nghĩa ngắn ngay phía trên. Dấu mũi nhọn hướng xuống giúp xác định chính xác từ
được giải thích mà không cần rời trang để mở từ điển.

Current version: **`2026.07.1-rc1.3.5`**
Current channel: **prerelease / RC**

## Highlights

| Feature | What it does |
|---|---|
| Inline hints | Shows short English definitions and reviewed Vietnamese translations above the text |
| Phrase matching | Recognizes phrases up to five words, not only isolated words |
| Three domains | Separate General, Economics and Physics databases |
| Context filtering | Uses nearby words to reduce obviously wrong meanings |
| Known words | Lets you hide words you already know across books |
| Kindle-style marker | Uses a horizontal rule and downward caret to point to the exact word |
| Full OTA updates | Updates both plugin code and the three databases from the Word Wise menu |
| Safe rollback | Keeps backups and never packages reading progress, book sidecars or `known_words.db` |

## Compatibility

Designed for:

- KOReader reflowable documents handled by CREngine, such as EPUB and HTML;
- Android-based readers;
- tested primarily with KOReader 2026.03 “Snowflake” on iReader Ocean 5 Pro.

Fixed-layout PDF, DJVU and comic documents are not supported by the inline
word-coordinate renderer.

## Install or update

### Existing Word Wise users

Open:

```text
Word Wise → Updates → Check for updates
```

For RC builds, enable **Include prerelease/RC updates**, then choose
**Update all and restart**. The updater verifies the plugin ZIP, database ZIP,
checksums, manifest and SQLite integrity before installation.

### First installation

1. Open the [Releases](https://github.com/trigon1998/wordwise.koplugin-custom/releases) page.
2. Download the matching plugin and database ZIP files for the same version.
3. Exit KOReader completely.
4. Copy the extracted `wordwise.koplugin` folder into `koreader/plugins/`.
5. Extract the database package into the directory that already contains
   `koreader/`.
6. Restart KOReader.
7. Open **Word Wise → Diagnostics** and confirm that plugin and database versions match.

Do not delete or replace:

```text
<KOReader data>/wordwise/known_words.db
```

## How it protects your data

The Git repository contains plugin code only. Dictionary databases are attached
separately to GitHub Releases.

An update is allowed to replace only:

```text
koreader/plugins/wordwise.koplugin/
koreader/wordwise/databases/wordwise_general.db
koreader/wordwise/databases/wordwise_economics.db
koreader/wordwise/databases/wordwise_physics.db
```

The updater does **not** package or replace:

- `known_words.db`;
- reading progress;
- highlights and notes;
- per-book KOReader sidecars;
- unrelated KOReader settings.

The plugin contacts GitHub only when you manually check for an update. It does
not store a GitHub personal access token on the reading device.

## Download statistics

The chart below records cumulative downloads of actual plugin ZIP assets whose
names match `wordwise.koplugin-v*.zip`. Checksums, database packages and
GitHub-generated source archives are excluded.

[![Plugin ZIP download history](stats/downloads.svg)](stats/downloads.json)

The history begins when the tracker is enabled; GitHub exposes the current
cumulative count for each release asset but does not provide a complete
day-by-day history retroactively.

Repository owners can also view GitHub’s private rolling traffic report under:

```text
Insights → Traffic
```

That report includes repository views, unique visitors, clones, referrers and
popular content, but it is not published publicly in this README.

## Current release: RC1.3.5

RC1.3.5 replaces the unsuccessful target-glyph measurement experiment with the
simpler rendering strategy proven by
[`asxelot/wordwise.koplugin`](https://github.com/asxelot/wordwise.koplugin):

- stable 180% line spacing while automatic spacing is enabled;
- one font-level ascent/descent pair for consistent hint placement;
- horizontal rule with a fixed downward caret;
- clamping to the actual rendered text column;
- render diagnostics for matched, placed and hidden hints.

See the [Releases](https://github.com/trigon1998/wordwise.koplugin-custom/releases)
page for checksums and complete release notes.

## Troubleshooting

### Diagnostics finds hints but none appear

Open **Word Wise → Diagnostics** and inspect:

```text
Hint render: … matched · … placed · … hidden
```

A healthy page should report at least one `placed` hint when `Page hints` is
greater than zero.

### Restore the previous version

Open:

```text
Word Wise → Updates → Restore previous version
```

Backups are kept under KOReader’s Word Wise update directories. Known words and
book sidecars are outside those backup targets.

### The page becomes too widely spaced

RC1.3.5 intentionally uses 180% automatic line spacing to reserve a reliable
hint band. Disable automatic spacing or turn Word Wise off to restore the
captured original spacing.

## Development and technical reference

Detailed data-integrity rules, release history, OTA asset contracts, build
commands and recovery procedures have been moved to:

- [Technical reference and release history](docs/TECHNICAL_REFERENCE.md)
- [Data maintenance](DATA_MAINTENANCE.md)
- [Performance testing](PERFORMANCE_TEST.md)
- [Repository notice](NOTICE.md)

## Credits and distribution status

This is a code-only maintenance fork derived from
[`asxelot/wordwise.koplugin`](https://github.com/asxelot/wordwise.koplugin).

The upstream repository does not publish an explicit open-source license. The
repository owner confirms private permission from the upstream author to modify
and redistribute this code-only fork. See [NOTICE.md](NOTICE.md) for the exact
scope.
