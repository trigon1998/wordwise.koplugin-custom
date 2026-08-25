# Word Wise Anh–Việt cho KOReader

**Hiển thị giải nghĩa Anh–Việt ngắn ngay phía trên những từ và cụm từ khó khi bạn đọc sách bằng KOReader.**

[![Bản phát hành mới nhất](https://img.shields.io/github/v/release/trigon1998/wordwise.koplugin-custom?include_prereleases&sort=semver&label=phi%C3%AAn%20b%E1%BA%A3n)](https://github.com/trigon1998/wordwise.koplugin-custom/releases)
[![Kiểm thử CI](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml/badge.svg)](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml)
[![GitHub Stars](https://img.shields.io/github/stars/trigon1998/wordwise.koplugin-custom?style=flat&label=stars)](https://github.com/trigon1998/wordwise.koplugin-custom/stargazers)

<p align="center">
  <img src="docs/wordwise-preview.svg" width="860" alt="Word Wise hiển thị giải nghĩa ngay phía trên từ khó trong KOReader">
</p>

## Word Wise là gì?

Word Wise là plugin dành cho người đọc sách tiếng Anh bằng KOReader. Plugin chỉ
quét trang đang hiển thị, tìm những từ hoặc cụm từ khó phù hợp rồi đặt giải
nghĩa ngắn ngay phía trên văn bản. Đường ngang và dấu mũi nhọn giúp xác định
chính xác từ đang được giải thích mà không cần rời khỏi trang để mở từ điển.

**Phiên bản code candidate:** `2026.07.1-rc1.4.9`

**Kênh cập nhật:** bản thử nghiệm RC
**Database candidate tiếp theo:** `2026.07.1-rc1.4.7`, phát hành riêng sau khi
đã cài bridge RC1.4.6; RC1.4.9 là hotfix cho data-only selection và pending-state migration.

## Tính năng nổi bật

| Tính năng | Công dụng |
|---|---|
| Giải nghĩa ngay trên trang | Hiển thị định nghĩa tiếng Anh ngắn và bản dịch tiếng Việt đã được rà soát |
| Nhận diện cụm từ | Nhận diện cụm từ dài tối đa 5 từ, không chỉ từng từ riêng lẻ |
| Một database thống nhất | General, Economics và Physics được gộp trong một file `wordwise.db`; domain chỉ còn là metadata nội bộ để chọn sense theo ngữ cảnh |
| Phân loại CEFR duy nhất | A1→5, A2→4, B1→3, B2→2, C1/C2→1; wordfreq không thay đổi difficulty đã phát hành |
| Chọn nghĩa theo ngữ cảnh | Dùng các từ xung quanh để chọn primary/alternate gloss; khi các gloss khác nhau vẫn hòa điểm thì đóng fail-closed thay vì đoán bừa |
| Từ đã biết | Lưu lựa chọn đã biết ở scope thống nhất `*`, đồng thời vẫn đọc các record domain cũ để không làm mất lựa chọn trước đây |
| Quick Tap compact | Chỉ còn đúng hai hành động: **Đã biết** và **Mở từ điển**; không còn bảng chi tiết chiếm toàn màn hình |
| Dấu chỉ từ trực quan | Đường ngang và dấu mũi nhọn chỉ đúng từ đang được giải thích |
| Cập nhật OTA có kiểm chứng | Kiểm tra checksum, manifest, schema, SQLite integrity và rollback trước khi thay dữ liệu |

## Khả năng tương thích

Plugin được thiết kế cho tài liệu có thể dàn lại trang bằng CREngine của KOReader,
chẳng hạn EPUB và HTML, trên các thiết bị đọc sách chạy Android. Plugin được
kiểm tra chủ yếu với KOReader 2026.03 “Snowflake” trên iReader Ocean 5 Pro.

Các tài liệu bố cục cố định như PDF, DJVU và truyện tranh không được hỗ trợ bởi
cơ chế xác định tọa độ từ trên trang.

## Database và difficulty

Database phát hành mới có một file duy nhất:

```text
<KOReader data>/wordwise/databases/wordwise.db
```

Các nguồn General, Economics và Physics được merge vào file này. Trường `domain`
vẫn được giữ trong từng row để audit và context-aware sense selection, nhưng
người dùng không chọn database hoặc category. Runtime ưu tiên file unified; một
fallback General tạm thời vẫn được giữ trong code để bridge có thể đọc thiết bị
chưa nhận data mới trong quá trình chuyển đổi.

CEFR là **tiêu chuẩn phân loại difficulty duy nhất** trong data pipeline:

| CEFR evidence | Word Wise difficulty | Ý nghĩa hiển thị |
|---|---:|---|
| A1 | 5 | Dễ nhất, có thể xuất hiện ở level cao |
| A2 | 4 | Khá thông dụng |
| B1 | 3 | Trung bình |
| B2 | 2 | Khó |
| C1 hoặc C2 | 1 | Khó nhất, hiếm nhất |

Khi nhiều nguồn CEFR đưa ra các level khác nhau, builder giữ **evidence khó nhất**
để không làm một từ khó trở thành bucket dễ hơn. Direct CEFR evidence được ưu
tiên; Words-CEFR-Dataset chỉ là fallback lexical-POS rõ ràng khi direct evidence
không có. `wordfreq` không được import hoặc dùng để nâng, hạ hay quyết định
published `difficulty`.

Các từ số, số thứ tự và entry không có CEFR evidence đủ tin cậy bị loại khỏi
inline Word Wise. Bản dịch tiếng Việt chỉ được đưa vào khi có row đã review và
source link; pipeline không tự sinh bản dịch. Entry English-only vẫn có thể mở
bằng dictionary thủ công, nhưng không tạo automatic bilingual hint.

## Cài đặt và cập nhật theo hai bước

RC1.4.6 là **code-only bridge**. Do updater ở RC1.4.5 và các bản cũ kiểm tra
archive database trước khi cài code mới, không được cài unified database trực tiếp
trên các bản đó.

| Bước | Release | Nội dung | Hành động |
|---|---|---|---|
| 1 | `2026.07.1-rc1.4.6` | Plugin code bridge | Cài code ZIP, khởi động lại KOReader |
| 2 | `2026.07.1-rc1.4.7` | Unified CEFR-only database | Sau khi chạy RC1.4.6, tải database ZIP và khởi động lại |

Trong bản RC, bật **Include prerelease/RC updates**, sau đó mở:

```text
Word Wise → Updates → Check code and database updates
```

Updater chỉ nhận archive có tên và SHA-256 đúng release, allow-list exact, manifest
khớp phiên bản, schema/domain/layout hợp lệ và SQLite integrity pass. Unified
archive chỉ chứa đúng ba member:

```text
WordWise_Databases_README.txt
manifest.json
koreader/wordwise/databases/wordwise.db
```

File `.sha256` là asset đi kèm bên ngoài ZIP. Database archive không chứa
`known_words.db`, tiến độ đọc, book settings, highlight, note hoặc sidecar.

### Cài đặt lần đầu thủ công

1. Mở trang [Releases](https://github.com/trigon1998/wordwise.koplugin-custom/releases).
2. Cài plugin ZIP của bridge trước và khởi động lại KOReader.
3. Tải database ZIP unified có cùng release data version với hướng dẫn phát hành.
4. Thoát hoàn toàn khỏi KOReader.
5. Chép thư mục `wordwise.koplugin` vào `koreader/plugins/`.
6. Giải nén database archive vào thư mục đang chứa `koreader/`.
7. Khởi động lại KOReader và kiểm tra **Word Wise → Diagnostics**.

Không xóa hoặc thay thế thủ công file sau:

```text
<KOReader data>/wordwise/known_words.db
```

## Hướng dẫn sử dụng

### Bật Word Wise

Mở một sách tiếng Anh reflowable rồi vào:

```text
Word Wise → Enable inline hints
```

Word Wise phân tích trang đang hiển thị và tự chèn giải nghĩa phía trên một số
từ hoặc cụm từ khó. Plugin không sửa nội dung file sách.

### Điều chỉnh số lượng hint

Vào:

```text
Word Wise → Hint level
```

Word Wise có năm mức. Mức `1` chỉ ưu tiên từ khó nhất; mức `5` cho phép nhiều
entry dễ hơn xuất hiện. Difficulty của entry không đổi khi người dùng thay đổi
Hint level; level chỉ thay đổi ngưỡng hiển thị.

### Quick Tap

Mặc định Quick Tap được bật. Chạm vào hint sẽ mở một hộp thoại compact với đúng
hai lựa chọn:

| Hành động | Kết quả |
|---|---|
| **Đã biết** | Ghi lemma vào known-word scope thống nhất và không hiển thị lại hint |
| **Mở từ điển** | Gọi dictionary lookup của KOReader cho surface word |

Popup này không mở bảng thông tin toàn màn hình và không có lựa chọn General,
Economics hay Physics.

### Context-aware sense selection

Với term có nhiều sense, runtime chuẩn bị cửa sổ context xung quanh term và chấm
keyword của primary/alternate sense. Alternate chỉ thắng khi có evidence dương
và mạnh hơn primary. Nếu nhiều domain có gloss Việt khác nhau nhưng context score
và priority bằng nhau, runtime không tự chọn một domain; hint được bỏ qua để
tránh dịch sai.

## Diagnostics và bảo toàn dữ liệu

Mở:

```text
Word Wise → Diagnostics
```

Thông tin hữu ích gồm database path, `Domain: Unified`, database build, số entries,
reviewed Vietnamese, Hint level, Page hints và Hint render.

Full OTA và data-only OTA chỉ được phép thay thế code plugin, database staging,
manifest và các file backup nội bộ của updater. Updater không bao giờ coi các
file sau là archive target:

```text
<KOReader data>/wordwise/known_words.db
<KOReader data>/settings/sidecar/
reading progress
highlights and notes
book-specific sidecars
```

Trước khi cài database, updater backup layout hiện tại và lưu layout/schema vào
metadata. Khi unified install thành công, các file database General/Economics/
Physics cũ được dọn khỏi thư mục runtime; khi install thất bại hoặc bị gián đoạn,
backup layout cũ được restore. `known_words.db` và sidecar không nằm trong các
bước này.

## Dữ liệu, attribution và nguồn

Database là curated/adapted selection từ các nguồn CEFR và Wiktionary. Mỗi
coverage correction có source URL, review status, POS, Vietnamese gloss và CEFR
evidence. Gói database giữ attribution/share-alike notice trong
`WordWise_Databases_README.txt` và `manifest.json`; không thêm file attribution
thứ ba để duy trì allow-list exact.

Các nguồn chính:

- [English Wiktionary](https://en.wiktionary.org/)
- [Wiktionary copyrights](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)
- [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.en)
- [GNU Free Documentation License](https://www.gnu.org/licenses/fdl-1.3.html)
- [Open Language Profiles CEFR-J](https://github.com/openlanguageprofiles/olp-en-cefrj)
- [Words-CEFR-Dataset](https://github.com/Maximax67/Words-CEFR-Dataset)

Trước khi phân phối rộng, cần tiếp tục kiểm tra nghĩa vụ attribution, ShareAlike
và transparent-copy đối với từng nguồn dữ liệu.

## Kiểm thử và bảo trì

Code bridge được kiểm tra bằng Lua parse, regression tests cho renderer, context
scoring, legacy schema, unified schema, Quick Tap và updater. Data pipeline được
kiểm tra riêng bằng Python với các bước:

```bash
cd /home/ubuntu/wordwise-data-work
python3 test_cefr_only.py
python3 build_candidate_databases.py
python3 build_unified_database.py
python3 validate_unified_database.py
python3 package_unified_database.py
python3 verify_unified_bundle.py
```

Các tài liệu kỹ thuật nằm tại:

- [Lịch sử và contract kỹ thuật](docs/TECHNICAL_REFERENCE.md)
- [Quy trình bảo trì data](DATA_MAINTENANCE.md)
- [Kiểm tra hiệu năng](PERFORMANCE_TEST.md)
- [Thông báo repository](NOTICE.md)

## Thống kê và trạng thái dự án

[![Lịch sử lượt tải plugin ZIP](stats/downloads.svg)](stats/downloads.json)

Đây là bản fork bảo trì code-only, được phát triển từ
[`asxelot/wordwise.koplugin`](https://github.com/asxelot/wordwise.koplugin). Dự án
phục vụ nghiên cứu, học tập, thử nghiệm kỹ thuật và sử dụng cá nhân; không phải
là sản phẩm thương mại chính thức.
