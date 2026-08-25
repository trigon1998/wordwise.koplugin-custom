# Word Wise 2026.07.1 — Unified CEFR rollout

## RC1.4.10 — staged schema validation hotfix

RC1.4.10 sửa lỗi gốc trong đường data-only OTA. Hàm validate staged database
trước đây trả thành công theo dạng `(ok, schema, layout)`, trong khi caller đọc
theo dạng `(ok, error, schema, layout)`. Vì vậy trên thiết bị, schema `2` bị đọc
như error và layout bị đọc như schema, dẫn tới thông báo `invalid staged database
schema` dù manifest và SQLite database đều hợp lệ.

Hàm nay trả tuple nhất quán `(ok, error, schema, layout)` cho mọi caller. Combined
với việc RC1.4.9 chọn đúng data-only RC1.4.7 và hiển thị đúng legacy fallback,
thiết bị có thể retry unified database mà không cần xóa database cũ hoặc state
người dùng.

Thiết bị đang chạy RC1.4.9 nên cài RC1.4.10 code-only và restart trước khi retry
database RC1.4.7. Thiết bị RC1.4.3 vẫn cần bootstrap bằng plugin ZIP mới hơn.

## RC1.4.9 — data-only retry and diagnostics hotfix

RC1.4.9 sửa lỗi xảy ra sau khi cài RC1.4.8: khi plugin code đã ở version mới
nhưng database vẫn là RC1.4.3, updater trước đó chọn release code-only hiện tại
làm fallback cho database và báo thiếu verified data assets. Updater nay lọc
riêng các release có đủ data ZIP/SHA-256, chọn data-only RC1.4.7 nếu version đó
mới hơn database đang cài và không vượt version plugin hiện tại.

Diagnostics cũng chỉ báo `Domain: Unified` khi file `wordwise.db` thực sự tồn tại.
Trong giai đoạn chuyển tiếp, database legacy General được hiển thị đúng là
`General (legacy fallback)` thay vì bị gắn nhãn Unified. Không có thay đổi nào
đối với known words, tiến độ đọc hoặc sidecar.

Thiết bị có RC1.4.8 nên cài RC1.4.9 code-only và restart trước khi retry database
RC1.4.7. Thiết bị RC1.4.3 vẫn cần cài bridge thủ công trước.

## RC1.4.8 — pending-state migration hotfix

RC1.4.8 là code-only hotfix cho thiết bị đã cài bridge nhưng còn state pending
được tạo bởi lần thử migration trước. Một số state cũ có thể ghi layout legacy,
thiếu layout hoặc không đồng bộ với manifest unified, khiến updater giữ nguyên
database cũ và báo `pending database layout state does not match its manifest`.

Updater nay coi staged manifest và database đã validate là nguồn sự thật, repair
atomically các file state schema/layout nhỏ trước khi install, và chỉ fail-closed
khi staged schema/layout thực sự không hợp lệ. Khi thư mục runtime đang ở trạng
thái mixed do một lần install bị gián đoạn, backup ưu tiên thu đủ các database
legacy hiện có để rollback không bỏ sót file. Không có thay đổi nào tới
`known_words.db`, tiến độ đọc hoặc sidecar.

Thiết bị đang chạy RC1.4.6 nên cài RC1.4.8 code-only và restart trước khi retry
cài unified database RC1.4.7. Thiết bị RC1.4.3 vẫn cần cài bridge thủ công trước.

## RC1.4.6 — code-only bridge

RC1.4.6 là bản phát hành **chỉ có plugin code**, không chứa database archive.
Mục tiêu của release này là đưa updater trên thiết bị lên phiên bản hiểu được
layout unified trước khi nhận database mới. Người dùng đang ở RC1.4.5 hoặc cũ
hơn phải cài RC1.4.6 và khởi động lại KOReader trước khi cài database unified.

Updater RC1.4.6 giữ tương thích với database legacy gồm ba file và đồng thời
nhận contract mới `unified-single-database`. Validator chọn layout từ manifest,
kiểm tra đúng số record, schema/object/table, checksum, SQLite integrity và
translation/count metadata. Archive có file lạ, path lạ, archive mixed layout,
record trùng hoặc cờ user-data đều bị từ chối.

Updater cũng hỗ trợ release data-only. Khi database mới có version cao hơn version
plugin hiện tại nhưng đã được bridge xác thực, plugin coi bundle đó là database
mới nhất hợp lệ thay vì buộc người dùng tải lại code.

## RC1.4.7 — unified CEFR-only database

Database release tiếp theo gộp General, Economics và Physics vào **một file duy
nhất**:

```text
koreader/wordwise/databases/wordwise.db
```

`domain` vẫn được giữ trong entries để audit và context-aware selection, nhưng
không còn database selector trong giao diện. Archive database có allow-list exact
ba member:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise.db
```

File SHA-256 nằm ngoài ZIP như companion release asset. Archive không chứa
`known_words.db`, reading progress, book settings, sidecar, highlight hoặc note.

### CEFR là difficulty authority duy nhất

Published `difficulty` không còn bị ảnh hưởng bởi wordfreq. Mapping duy nhất là:

| CEFR | Difficulty |
|---|---:|
| A1 | 5 |
| A2 | 4 |
| B1 | 3 |
| B2 | 2 |
| C1/C2 | 1 |

Direct CEFR evidence được ưu tiên. Words-CEFR-Dataset chỉ làm fallback
lexical-POS khi không có direct evidence. Khi nhiều level cùng xuất hiện, builder
lấy evidence khó nhất để không làm understated một từ khó. Phrase sử dụng bucket
khó nhất của các token có CEFR evidence đầy đủ; phrase thiếu evidence cho bất kỳ
token nào không được thêm theo đường tự động. Numeric và ordinal noise tiếp tục bị
loại.

Wordfreq đã được tách khỏi production builder. Các công cụ audit wordfreq nếu còn
trong workspace chỉ phục vụ phân tích chất lượng, không được ghi vào published
bucket hoặc dùng để override CEFR.

### Coverage và bản dịch

Coverage `dawdle` được review với bản dịch tiếng Việt `lãng phí thời gian`, nguồn
Wiktionary, CEFR C2 và các mapping `dawdled`, `dawdling`, `dawdles` về lemma này.
Bản dịch tiếng Việt không được tự sinh. Entry English-only vẫn có thể tra thủ
công nhưng không tạo automatic bilingual inline hint.

### Context-aware selection

Runtime trả về nhiều candidates cho một term trong unified DB và nạp
`sense2_context` theo cả `term` và `domain`. Context scorer chấm primary/alternate
sense trong cửa sổ từ xung quanh. Alternate chỉ thắng khi có evidence dương và
mạnh hơn primary. Nếu các gloss Việt khác nhau có cùng context score và priority,
runtime fail-closed thay vì dùng thứ tự alphabetic của domain để đoán.

### Quick Tap

Quick Tap được thu gọn thành một `ButtonDialog` compact với đúng hai hành động:

| Hành động | Kết quả |
|---|---|
| **Đã biết** | Ghi lemma vào known-word scope `*` |
| **Mở từ điển** | Gọi dictionary lookup của KOReader |

Không còn bảng detail full-screen và không còn action chọn domain.

## Migration and rollback safety

Database install là staged và chỉ hoàn tất sau khi KOReader restart. Updater backup
layout/schema hiện tại, validate database mới trước khi thay thế, dùng atomic file
replacement và dọn các file database legacy chỉ sau khi file unified đã được đặt
thành công. Nếu install bị gián đoạn hoặc một replacement thất bại, layout cũ
được restore từ backup. Pending/backup state lưu layout để không nhầm unified với
legacy.

Known words và dữ liệu đọc không bị xóa. Runtime unified coi các record global
`*`, `unified` và các scope General/Economics/Physics cũ là đã biết, nhờ vậy lựa
chọn của người dùng từ các bản trước được bảo toàn.

## Verification

Đã kiểm tra:

- Lua parse toàn bộ file runtime;
- main behavior, context scorer, legacy schema và unified schema regression;
- single-result DB API fail-closed khi có nhiều domain candidates;
- Quick Tap có đúng một row và hai action;
- unified manifest một record và legacy manifest ba record;
- rejection của mixed/unknown archive layout;
- CEFR mapping A1–C2, direct-over-fallback, hardest-evidence aggregation và wordfreq invariant;
- unified database 76,310 entries, 21 aliases, 18 irregular mappings và 79 side-table context mappings;
- ZIP exact 3 files, manifest/hash/counts/schema, SQLite integrity và coverage `dawdle`.

## Provenance

Wiktionary-derived material là adapted/curated selection có source URL và review
status. `WordWise_Databases_README.txt` và `manifest.json` giữ attribution cho
CC BY-SA 4.0/GFDL; final distribution vẫn phải xem xét nghĩa vụ ShareAlike và
transparent-copy theo từng nguồn.

Sources:

1. [English Wiktionary](https://en.wiktionary.org/)
2. [Wiktionary copyrights](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)
3. [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.en)
4. [GNU Free Documentation License](https://www.gnu.org/licenses/fdl-1.3.html)
5. [Open Language Profiles CEFR-J](https://github.com/openlanguageprofiles/olp-en-cefrj)
6. [Words-CEFR-Dataset](https://github.com/Maximax67/Words-CEFR-Dataset)

## Previous releases

RC1.4.5 corrected reviewed `dawdle` coverage and suppressed English-only automatic
hints. RC1.4.4 introduced the code-only bridge capability contract. RC1.4.3
restored the schema-v2 legacy-safe data contract. RC1.3.9 introduced actual
context-aware sense/gloss selection, and RC1.3.6 introduced top-edge hint
fallback.
