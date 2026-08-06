# Word Wise 2026.07.1-rc1.3.3

## Hint Vertical Alignment OTA Test

- Moves inline glosses closer to the words they explain when raised line
  spacing provides room.
- Never moves compact-line glosses upward relative to RC1.3.2.
- Shrinks the caret to the available vertical gap instead of drawing through
  the gloss.
- Hides a hint when the gloss cannot fit safely near the top of the screen.
- Adds regression coverage for tall line boxes, compact line boxes and the
  top-screen safety margin.
- Keeps dictionary rows unchanged from RC1.3.2; database build metadata is
  advanced only for the matching Full OTA package.
- Preserves known words, reading progress and per-book settings.

This is a prerelease for direct OTA validation on the iReader. PR #5 remains
draft and unmerged until the on-device result is confirmed.
