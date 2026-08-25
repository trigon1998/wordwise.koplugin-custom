# Word Wise — Technical Reference

Tài liệu này mô tả kiến trúc và contract phát hành của fork Word Wise cho KOReader
2026.03 “Snowflake”. README là tài liệu sử dụng; file này dành cho bảo trì,
kiểm thử và phát hành.

## Repository boundary

Git repository chứa **plugin code**. Dictionary data được phát hành như
release asset riêng. Dữ liệu người dùng không được commit và không được đưa vào
archive:

```text
<KOReader data>/wordwise/known_words.db
<KOReader data>/wordwise/databases/
KOReader book settings, progress, highlights, notes and sidecars
```

Runtime data path mới là:

```text
<KOReader data>/wordwise/databases/wordwise.db
```

## Unified database contract

Release data gộp các source General, Economics và Physics thành một SQLite
`wordwise.db`. `entries.domain` vẫn tồn tại để giữ provenance, domain-specific
sense và context keywords, nhưng đây là metadata nội bộ; không có domain selector
trong user-facing workflow.

| Thuộc tính | Contract |
|---|---|
| Database files | Một file `wordwise.db` |
| Layout marker | `database_layout=unified-single-database` |
| Database count | `database_count=1` |
| Physical schema | Schema-v2 |
| Context table | `sense2_context(term, domain, context_keywords)` |
| Entry key behavior | Không giả định `term` globally unique; cùng term khác domain có thể coexist |
| Runtime lookup | Trả nhiều candidates, chấm context rồi fail-closed khi ambiguous |

Schema-v2 entries có 15 cột theo thứ tự:

```text
term, lemma, short_en, short_vi, difficulty, pos, domain,
sense2_en, sense2_vi, context_keywords, phrase_len, priority,
requires_context, register_label, source
```

Bảng `sense2_context` có ba cột và key composite theo `term` + `domain`. Legacy
schema-v2 side-table chỉ có `term` + `context_keywords` vẫn được runtime đọc để
duy trì backward compatibility. Schema-v3 với cột context trong `entries` vẫn
được updater validate cho các database cũ/tương lai, nhưng unified bootstrap
release dùng schema-v2 để tương thích bridge.

## Difficulty policy

CEFR là **authority duy nhất** của published difficulty:

| Evidence | Word Wise bucket |
|---|---:|
| A1 | 5 |
| A2 | 4 |
| B1 | 3 |
| B2 | 2 |
| C1/C2 | 1 |

Mapping là `max(1, 6 - cefr_level)`. Nếu một term có nhiều label, builder lấy
CEFR numerically cao nhất, tức evidence khó nhất. Phrase chỉ được thêm khi mọi
token có CEFR evidence; bucket phrase là bucket khó nhất của các token.

Direct OLP CEFR-J/Octanove evidence được ưu tiên. Words-CEFR-Dataset là
lexical-POS fallback khi direct evidence vắng mặt. `wordfreq` không còn là
dependency của production builder và không thể thay đổi published `difficulty`.
Nếu workspace có công cụ wordfreq audit, công cụ đó chỉ để đo độ lệch/phân tích,
không được ghi kết quả vào release database.

Numeric tokens, ordinal terms và unresolved entries bị loại. Coverage override
chỉ được thêm khi có English gloss, Vietnamese gloss, POS, CEFR evidence, review
status và source URL. Không tự sinh bản dịch.

## Runtime selection

`wordwise_db.lua` giữ các API legacy `lookupExact` và `lookupWord`, nhưng các API
single-result này trả `nil` khi có hơn một candidate. API mới
`lookupCandidates` và `lookupWordCandidates` trả toàn bộ candidates theo thứ tự
ổn định để `main.lua` chấm:

1. context confidence;
2. priority;
3. nếu cùng điểm nhưng gloss Việt khác nhau thì fail-closed, không dùng thứ tự domain để đoán.

`ContextScorer` chấm primary và alternate sense trong context window đã chuẩn bị.
Alternate chỉ thắng khi score dương và lớn hơn primary. Entry yêu cầu context mà
không có evidence bị loại. Entry English-only vẫn tra dictionary thủ công nhưng
không tạo automatic bilingual inline hint.

Coverage `dawdle` có gloss `lãng phí thời gian`, CEFR C2 và mapping:

```text
dawdled -> dawdle
dawdling -> dawdle
dawdles -> dawdle
```

Quick Tap được xây bằng compact `ButtonDialog` với đúng hai action: `Known` và
`Open dictionary` (được KOReader gettext dịch thành **Đã biết** và **Mở từ điển**
trong locale tiếng Việt). Known action ghi scope `*`; dictionary action phát
sự kiện lookup cho surface word. Không có full-screen detail panel và không có
domain action.

## Updater contract

Updater nhận code ZIP và database ZIP độc lập. Code archive có allow-list cố định
và không được chứa database. Unified database archive có đúng ba member:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise.db
```

SHA-256 companion file nằm ngoài ZIP. Manifest unified yêu cầu:

```json
{
  "package_type": "database-only",
  "database_schema": 2,
  "database_layout": "unified-single-database",
  "database_count": 1,
  "known_words_included": false,
  "book_settings_included": false
}
```

Manifest legacy ba-record vẫn được nhận để hỗ trợ rollback/thiết bị cũ. Archive
không được mixed unified/legacy, không được path lạ, duplicate, file attribution
thừa hoặc member user-data.

### Staged rollout

RC1.4.6 là **code-only bridge**. Nó nâng updater để nhận unified layout nhưng
không gửi database unified trong cùng archive. Sau khi bridge được cài và
KOReader restart, release data-only RC1.4.7 mới có thể cài `wordwise.db`.

Flow data install:

1. download ZIP và SHA-256;
2. verify outer checksum và exact archive allow-list;
3. extract vào staging;
4. validate manifest, per-database hash, schema, object allow-list, metadata,
   counts, SQLite integrity và foreign-key check;
5. ghi pending version/schema/layout;
6. sau restart backup layout hiện tại;
7. atomic replace database mới;
8. chỉ sau khi replace thành công mới xóa database legacy obsolete;
9. lưu installed manifest và clear pending state.

Nếu một bước replacement hoặc cleanup thất bại, updater restore backup layout cũ.
Pending và backup state lưu layout để không nhầm unified với legacy. Known words,
progress và sidecars không bị backup/restore hoặc xóa bởi database flow.

## Release verification

Code release:

```bash
cd /home/ubuntu/wordwise.koplugin-custom
for file in ./*.lua tests/*.lua; do npx --yes luaparse "$file" >/dev/null; done
bash tools/run_lua_tests.sh
bash tools/build_release.sh
bash tools/verify_release.sh
```

Data release:

```bash
cd /home/ubuntu/wordwise-data-work
python3 test_cefr_only.py
python3 build_candidate_databases.py
python3 build_unified_database.py
python3 validate_unified_database.py
python3 package_unified_database.py
python3 verify_unified_bundle.py
```

Verifier unified phải kiểm tra exact ZIP names, manifest một record, archive/db
SHA-256, byte/count fields, expected tables/indexes/columns, CEFR-only metadata,
coverage `dawdle` và `PRAGMA integrity_check`.

## Release history

| Release | Nội dung |
|---|---|
| RC1.4.8 | Pending schema/layout state repair; mixed-directory legacy backup detection; code-only hotfix |
| RC1.4.6 | Code-only bridge; updater unified/legacy layout-aware; pending/backup layout metadata; compact Quick Tap; multi-candidate runtime |
| RC1.4.5 | Reviewed `dawdle` coverage, inflection mappings, English-only inline hint gate |
| RC1.4.4 | Capability bridge và code-only updater path |
| RC1.4.3 | Schema-v2 legacy-safe bootstrap |
| RC1.4.0–RC1.4.2 | Wiktionary expansion, attribution/archive compatibility và data cleanup |
| RC1.3.9 | Context-aware sense/gloss selection |
| RC1.3.6 | Top-edge hint fallback |

## Provenance

Wiktionary material là adapted/curated selection có source links. Database README
và manifest giữ CC BY-SA 4.0/GFDL attribution cùng cảnh báo ShareAlike và
transparent-copy. CEFR sources gồm OLP CEFR-J/Octanove và Words-CEFR-Dataset.
Trước khi phân phối rộng, cần review nghĩa vụ license cho từng source.

Xem thêm [README](../README.md), [DATA_MAINTENANCE](../DATA_MAINTENANCE.md) và
[NOTICE](../NOTICE.md).
