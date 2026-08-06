# RC1.3.3 Hint Vertical Alignment Hotfix — development patch

Scope:
- Move glosses down toward the word they explain when raised line spacing leaves enough room.
- Never move a gloss upward relative to the previous placement formula.
- Shrink the caret to the available vertical gap instead of drawing through the gloss.
- Hide a hint when its gloss would cross the safe top-screen margin.
- Preserve collision handling, hitboxes, database behavior and OTA behavior.

The patch deliberately does not bump the release version yet. Versioning and release notes should be updated only after CI passes and the placement is confirmed on the iReader.
