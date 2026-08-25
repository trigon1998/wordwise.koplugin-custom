# Word Wise — Data Maintenance

Đây là tài liệu repository-only dành cho người bảo trì database. File này không
được đưa vào plugin ZIP vì updater dùng allow-list cố định.

## Nguyên tắc phát hành

Database runtime mới là một SQLite unified:

```text
koreader/wordwise/databases/wordwise.db
```

File này được merge từ ba source database General, Economics và Physics. Trường
`domain` được giữ nội bộ trong entries và trong `sense2_context` để audit/context
selection; người dùng không chọn domain.

**CEFR là difficulty authority duy nhất.** Published difficulty phải tuân theo:

```text
A1   -> 5
A2   -> 4
B1   -> 3
B2   -> 2
C1/C2 -> 1
```

Direct CEFR-J/Octanove evidence được ưu tiên. Words-CEFR-Dataset được dùng làm
lexical-POS fallback khi direct evidence không có. Mixed labels lấy evidence khó
nhất. Phrase yêu cầu CEFR evidence cho mọi token và lấy bucket khó nhất của token.
Numeric/ordinal noise và unresolved entries bị loại.

`wordfreq` không được dùng trong production builder để quyết định hoặc override
published bucket. Nếu dùng công cụ wordfreq audit trong workspace, kết quả chỉ là
review signal bên ngoài và không được ghi ngược vào database.

Bản dịch tiếng Việt chỉ được publish khi có review status, exact sense, POS,
source URL và gloss đã kiểm tra. Không tự sinh bản dịch. Coverage correction như
`dawdle` phải giữ source Wiktionary, CEFR evidence và inflections đã review.

## Workspace layout

Các đường dẫn mặc định:

```text
/home/ubuntu/wordwise-data-work/current/koreader/wordwise/databases/
/home/ubuntu/wordwise-data-work/candidate/koreader/wordwise/databases/
/home/ubuntu/wordwise-data-work/candidate-unified/
```

`current` là source domain databases; `candidate` là ba intermediate CEFR-only
outputs; `candidate-unified` là authoritative single-file output trước packaging.

## Rebuild và validate

Luôn build trong thư mục output có thể bị xóa/recreate. Không sửa trực tiếp
SQLite release bằng tay.

```bash
cd /home/ubuntu/wordwise-data-work
export WORDWISE_BUILD_VERSION=2026.07.1-rc1.4.7
export WORDWISE_TARGET_SCHEMA=2
export WORDWISE_MIN_UPDATER_SCHEMA=2
python3 test_cefr_only.py
python3 build_candidate_databases.py
python3 build_unified_database.py
python3 validate_unified_database.py
```

`build_candidate_databases.py` làm CEFR classification và rebuild ba intermediate
source-domain files. `build_unified_database.py` merge chúng thành một
`wordwise.db`, giữ domain nội bộ, merge aliases/irregulars và fail khi có conflict
thực sự. `validate_unified_database.py` kiểm tra schema-v2 physical 15 columns,
`domain`-aware `sense2_context`, metadata, counts, no numeric/ordinal noise,
SQLite integrity và coverage regression.

Test builder bắt buộc phải kiểm tra mapping A1–C2, direct-over-fallback, hardest
mixed evidence, phrase missing-token rejection, wordfreq invariance, dawdle
translation/source/inflections và numeric exclusion.

## Data package

README attribution nguồn được đặt ngoài output builder tại
`unified_database_README.txt`, vì builder recreate `candidate-unified`. Đóng gói:

```bash
python3 package_unified_database.py
python3 verify_unified_bundle.py
unzip -l candidate-unified/release/WordWise_Databases_2026.07.1-rc1.4.7.zip
```

Tên đúng theo packager là:

```text
WordWise_Databases_<version>.zip
WordWise_Databases_<version>.zip.sha256
```

ZIP unified phải có **đúng ba member** và không thêm attribution file thứ ba:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise.db
```

Manifest phải có `package_type=database-only`, `database_schema=2`,
`database_layout=unified-single-database`, `database_count=1`,
`known_words_included=false` và `book_settings_included=false`. Record duy nhất
phải khớp byte count, SHA-256, entry/phrase/alias/irregular/reviewed-Vietnamese
counts và translation policy.

`verify_unified_bundle.py` là gate bắt buộc. Không publish nếu fail exact allow-list,
manifest, database hash, tables/indexes/columns, CEFR-only metadata, coverage,
SQLite integrity hoặc user-data exclusion.

## Attribution

Wiktionary-derived rows là adapted/curated selection. Mỗi override cần source URL
và review note. Gói phát hành giữ CC BY-SA 4.0/GFDL notice trong README và
manifest. Các nguồn CEFR phải được ghi trong metadata và data README. Trước khi
phân phối rộng, review nghĩa vụ attribution, ShareAlike và transparent-copy cho
từng nguồn.

## Reviewed correction workflow

Mỗi correction phải ghi tối thiểu:

| Trường | Yêu cầu |
|---|---|
| term/lemma | normalized English surface và lemma |
| domain | `general`, `economics`, `physics` hoặc domain đã định nghĩa |
| short_en | exact sense ngắn, không mơ hồ |
| short_vi | gloss Việt đã review, không machine-generated |
| POS | khớp với sense |
| CEFR | evidence rõ ràng hoặc coverage CEFR level 1–6 |
| source | URL/source identifier có thể audit |
| review_status | `reviewed` hoặc `approved` |
| inflections | chỉ mapping tới lemma có thật trong entries |

Với source Wiktionary, giữ license note và link trang cụ thể. Không dùng similarity
score, WordNet hoặc OMW như căn cứ duy nhất để publish bản dịch.

## Runtime safety boundary

Database package không bao giờ chứa:

```text
known_words.db
reading progress
book settings
book sidecars
highlights/notes
plugin code
```

Updater RC1.4.6 nhận cả manifest legacy ba-file để rollback và manifest unified
một-file để migration. Khi unified install thành công, file legacy chỉ được xóa
sau khi `wordwise.db` đã atomic-replace thành công. Khi lỗi hoặc interrupted
install, backup layout cũ được restore. User data không thuộc backup/restore
database scope.

## Release sequencing

RC1.4.6 phải được phát hành trước như code-only bridge vì updater RC1.4.5 không
hiểu unified archive. Sau khi người dùng cài bridge và restart KOReader, mới phát
hành/cài database-only RC1.4.7. Không gửi unified archive trong Full OTA tới
client chưa có bridge.

Final release checklist:

```bash
cd /home/ubuntu/wordwise.koplugin-custom
for file in ./*.lua tests/*.lua; do npx --yes luaparse "$file" >/dev/null; done
bash tools/run_lua_tests.sh
git diff --check
bash tools/build_release.sh
bash tools/verify_release.sh
```

Sau đó chạy data pipeline và verifier ở trên, kiểm tra ZIP listing và SHA-256,
rồi mới tạo GitHub Release/tag. Không ghi đè hoặc sửa các tag/release công khai
trước đây.
