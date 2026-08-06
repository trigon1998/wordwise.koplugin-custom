# Word Wise 2026.07.1-rc1.3.5

## Upstream-Style Hint Renderer OTA Test

- Reverts the RC1.3.4 target-word glyph measurement experiment.
- Ports the proven rendering geometry from `asxelot/wordwise.koplugin`.
- Reserves a stable 180% interline band while automatic spacing is enabled.
- Uses one font-level ascent/descent pair for every gloss.
- Draws the Kindle-style horizontal rule with a fixed downward caret.
- Centers the whole gloss/rule/caret unit in the raised leading.
- Clamps glosses to the real rendered text column.
- Never drops a matched hint because target-font measurement failed.
- Adds Diagnostics for matched, placed and hidden render counts.
- Keeps dictionary rows unchanged from RC1.3.4; database build metadata is
  advanced only for the matching Full OTA package.
- Preserves known words, reading progress and per-book settings.

This is a prerelease for direct OTA validation on the iReader.
PR #5 remains draft and unmerged until spacing and caret placement are verified.
