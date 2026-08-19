# Word Wise 2026.07.1-rc1.3.8

## Performance OTA and CEFR-A Database Update

RC1.3.8 keeps the top-edge hint fallback introduced in RC1.3.6, retains the CEFR-A database selection policy from RC1.3.7, and adds bounded runtime caches to reduce repeated page, context and text-measurement work.

### Performance changes

- Caches visible page records by page and layout signature, including normalized token data and screen boxes.
- Reuses prepared, normalized context sets across candidate scoring within one page scan.
- Caches gloss width measurements by font and screen width with a bounded capacity.
- Invalidates caches when the page, screen geometry, font or document state changes.
- Exposes opt-in cache hit/miss counters in diagnostics for on-device measurement.
- Adds regression coverage for prepared context scoring and repeated gloss measurement.

The implementation keeps the existing first-word phrase index and database lookup cache rather than adding a second candidate index without device-profile evidence.

### Database changes

- Uses CEFR-J Vocabulary Profile v1.5 and Octanove C1/C2 v1.0 as the primary CEFR sources.
- Uses Words-CEFR-Dataset as a filtered lexical/POS fallback only; derived labels are not treated as human-reviewed translations.
- Maps A1 → runtime difficulty 5, A2 → 4, B1 → 3, B2 → 2 and C1/C2 → 1.
- Preserves existing manual/domain-curated overrides and reviewed Vietnamese glosses.
- Excludes number/ordinal tokens and entries without sufficient lexical, POS or CEFR evidence.
- Does not generate new Vietnamese translations automatically; unresolved translations remain English-only or quarantined according to the existing policy.

The database bundle contains 25,403 General entries, 25,649 Economics entries and 25,620 Physics entries. Reviewed Vietnamese gloss counts remain 48, 348 and 352 respectively.

### Renderer and updater

- Keeps normal above-word placement, top-edge clamping and below-word fallback with an upward caret.
- Keeps automatic 180% line spacing and collision-safe placement.
- Uses matching plugin/database build metadata `2026.07.1-rc1.3.8` so the Full OTA path can detect and install the matching code and data revision safely.
- Preserves `known_words.db`, book sidecars, reading progress and other user data.

### Verification

The release candidate passed Lua parsing, main/context/database/updater behavior tests, sample data evaluation, plugin ZIP build and plugin checksum/allow-list verification. The database archive passed manifest, SHA-256, schema, metadata, row-count, SQLite integrity and archive allow-list verification. GitHub Actions CI passed for the performance commit before this release was created.

### Provenance

CEFR-J: https://github.com/openlanguageprofiles/olp-en-cefrj

Octanove / Words-CEFR-Dataset: https://github.com/Maximax67/Words-CEFR-Dataset

The database README retains the source and license notes required for review before public distribution.

This is a prerelease for direct OTA validation. Please inspect hint selection and performance counters on representative books. Adjust the Hint Level if the new CEFR distribution is too dense or too sparse for a particular reading workflow.

Known words, reading progress and per-book settings are preserved by the updater.

## Previous releases

RC1.3.7 introduced the CEFR-A database selection policy.

RC1.3.6 introduced the top-edge hint fallback for words near the top of the screen.

RC1.3.5 introduced the upstream-style renderer and automatic 180% interline spacing.

## License and distribution

The database bundle is distributed separately from the code-only repository source tree. Review the repository notice and the database README before publishing the assets.

The release remains a prerelease until on-device validation confirms that the CEFR-A selection and performance changes match the intended reading experience.

## References

1. [Open Language Profiles CEFR-J Vocabulary Profile](https://github.com/openlanguageprofiles/olp-en-cefrj)
2. [Words-CEFR-Dataset and Octanove profile](https://github.com/Maximax67/Words-CEFR-Dataset)
3. [Word Wise repository](https://github.com/trigon1998/wordwise.koplugin-custom)
