# Word Wise 2026.07.1-rc1.3.9

## Context-Aware Sense/Gloss Selection

RC1.3.9 chuyển context awareness từ mức lọc/xếp hạng candidate sang **chọn sense và gloss thực sự**. Khi một database entry có sense2 đã được review, plugin chấm riêng keyword của sense primary và alternate trong cửa sổ context quanh candidate. Alternate chỉ được chọn khi có ít nhất một hit và điểm của alternate cao hơn nghiêm ngặt điểm primary; hòa, zero evidence, thiếu metadata hoặc database legacy đều giữ primary để bảo toàn hành vi ổn định.

`main.lua` nhận selected gloss từ `ContextScorer.acceptPrepared()` và dùng cặp `short_en/short_vi` được chọn khi render hint. Popup vẫn giữ sense không được chọn dưới nhãn “Other possible sense”, giúp người đọc kiểm tra lựa chọn hiện tại thay vì bị giới hạn bởi nghĩa đầu tiên.

### Data curation

Database bundle có **83 mapping alternate-context được review**, gồm 28 Economics và 55 Physics; General hiện không có row sense2. File `data/sense_context_overrides.tsv` ghi term, domain, POS, gloss alternate English/Vietnamese đã tồn tại, keyword context và review note. Không có bản dịch tiếng Việt nào được tự động sinh trong thay đổi này.

Các database vẫn giữ chính sách CEFR-A của RC1.3.8: 25,403 General entries, 25,649 Economics entries và 25,620 Physics entries. Các token số/thứ tự và entry không có evidence CEFR đủ tốt tiếp tục bị loại theo pipeline hiện hành.

### Schema and compatibility

Database mới dùng schema version 3 với cột append-only `sense2_context_keywords`. Runtime probe schema khi mở database và chọn query phù hợp, nên vẫn đọc database schema version 2 của các bản cũ. Updater cũng chấp nhận cả hai layout của bảng `entries` trước khi staging database mới.

Full OTA không bao gồm `known_words.db`, reading progress, book sidecars hoặc các dữ liệu người dùng khác. Cơ chế backup, checksum, manifest, SQLite integrity check và replacement khi restart được giữ nguyên.

### Performance and renderer

Các bounded page/token caches, prepared context set, gloss-width cache, automatic 180% line spacing, top-edge fallback và collision-safe placement từ RC1.3.8 được giữ nguyên. Sense selection dùng context set đã chuẩn bị sẵn, tránh normalize lặp lại trong cùng một page scan.

### Verification

RC1.3.9 đã được kiểm tra bằng Lua parse, main behavior tests, context scorer tests, database schema/cache tests, updater tests, candidate data validation, manifest/archive verification, SHA-256 verification và SQLite integrity checks. Regression coverage xác nhận primary/alternate selection, strict-win rule, tie/zero fallback, selected-gloss rendering và schema-aware lookup.

### Provenance

CEFR-J Vocabulary Profile: <https://github.com/openlanguageprofiles/olp-en-cefrj>

Octanove / Words-CEFR-Dataset: <https://github.com/Maximax67/Words-CEFR-Dataset>

## Previous releases

RC1.3.8 introduced bounded runtime caches and the CEFR-A database selection policy.

RC1.3.7 introduced the CEFR-A database selection policy.

RC1.3.6 introduced the top-edge hint fallback for words near the top of the screen.

RC1.3.5 introduced the upstream-style renderer and automatic 180% interline spacing.

## License and distribution

The database bundle is distributed separately from the code-only repository source tree. Review the repository notice and the database README before publishing the assets.

This is a prerelease for direct OTA and on-device context-selection validation. Please inspect representative Economics, Physics and General books. Known words, reading progress and per-book settings are preserved by the updater.

## References

1. [Open Language Profiles CEFR-J Vocabulary Profile](https://github.com/openlanguageprofiles/olp-en-cefrj)
2. [Words-CEFR-Dataset and Octanove profile](https://github.com/Maximax67/Words-CEFR-Dataset)
3. [Word Wise repository](https://github.com/trigon1998/wordwise.koplugin-custom)
