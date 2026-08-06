# RC1.3.4 Hint Vertical Alignment Round 2 — development patch

## Scope

This patch is designed to apply on top of the current
`fix/rc1.3.3-hint-vertical-alignment` branch after the RC1.3.3 OTA test.

It does not bump the plugin version or publish a release.

## Geometry change

RC1.3.3 inferred the word top from `line_spacing` and `box.h`. The iReader
test proved that estimate remained too high.

Round 2:

- measures the target surface with the active book face;
- centers the measured target glyph height inside the CRE box;
- anchors the gloss bottom exactly three pixels above that glyph estimate;
- preserves the old centered baseline as a lower bound;
- hides compact/top-screen hints when safe placement is impossible;
- fails closed when target measurement is unavailable;
- removes line-spacing percentage from the vertical-placement API.

## Files changed

- `main.lua`
- `tests/test_main.lua`

## Validation before release

1. `git apply --check`
2. Lua parse
3. `tests/test_main.lua`
4. `tests/test_db.lua`
5. `tests/test_updater.lua`
6. release build/verify
7. direct OTA prerelease validation on the same iReader page

PR #5 should remain draft until the visual result is confirmed.
