# Word Wise 2026.07.1-rc1.3.4

## Hint Vertical Alignment Round 2 OTA Test

- Replaces the RC1.3.3 line-spacing estimate with target-word measurement
  using the active book face.
- Centers the measured target glyph height inside the CRE word box.
- Anchors the gloss directly above that glyph estimate.
- Keeps the old centered baseline as a lower bound.
- Hides compact or top-screen hints when safe placement is impossible.
- Fails closed when target measurement is unavailable.
- Adds regression coverage for glyph anchoring, compact lines and measurement
  failure.
- Keeps dictionary rows unchanged from RC1.3.3; database build metadata is
  advanced only for the matching Full OTA package.
- Preserves known words, reading progress and per-book settings.

This is a prerelease for direct OTA validation on the same iReader page.
PR #5 remains draft and unmerged until the visual result is confirmed.
