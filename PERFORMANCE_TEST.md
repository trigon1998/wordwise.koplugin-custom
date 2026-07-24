# RC1.3.0 on-device performance test

RC1.3.0 intentionally makes no battery-percentage claim before measurement on
the target reader. Use the same English EPUB and the same KOReader settings for
each comparison.

## Fixed conditions

- same device and KOReader build;
- same book, domain and hint level;
- same font, font size, margins and line spacing;
- same frontlight and wireless state;
- begin each run at the same page;
- do not open dictionaries or other plugins during the run.

## Functional check

1. Enable **Word Wise → Performance counters**.
2. Turn forward through 20 English pages at a normal reading pace.
3. Open **Word Wise → Diagnostics**.
4. Record:
   - compute requests and coalesced requests;
   - scans and page-cache hits;
   - last visible-word count;
   - last phrase-probe count;
   - last scan time.
5. Return to previously visited pages and confirm hints remain correct.
6. Change font size, margins and orientation once each. Confirm hint
   coordinates refresh and no stale hint receives a tap.

## Battery comparison

Battery percentage is too coarse for a short test. Compare RC1.2.2 and RC1.3.0
in separate sessions of at least 60 minutes, preferably twice per version.
Keep the fixed conditions above and record:

- starting and ending battery percentage;
- pages turned;
- elapsed reading time;
- any visible page-turn delay or crash.

Treat a single run as directional evidence only. Do not report a percentage
improvement unless repeated runs agree.

## Pass criteria

- dictionaries, known words and per-book settings are unchanged;
- hints remain correct after reflow and rotation;
- back-to-back events produce coalesced requests;
- normal words that cannot begin a stored phrase produce no phrase probe;
- no crash or noticeable page-turn regression;
- OTA rollback to RC1.2.2 remains available.
