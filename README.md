# Word Wise Anh–Việt cho KOReader

**Hiển thị giải nghĩa Anh–Việt ngay phía trên những từ và cụm từ khó khi bạn đọc sách bằng KOReader.**

[![Bản phát hành mới nhất](https://img.shields.io/github/v/release/trigon1998/wordwise.koplugin-custom?include_prereleases&sort=semver&label=phi%C3%AAn%20b%E1%BA%A3n)](https://github.com/trigon1998/wordwise.koplugin-custom/releases)
[![Kiểm thử CI](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml/badge.svg)](https://github.com/trigon1998/wordwise.koplugin-custom/actions/workflows/ci.yml)
[![Lượt tải plugin](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Ftrigon1998%2Fwordwise.koplugin-custom%2Fmain%2Fstats%2Fdownloads-badge.json)](stats/downloads.svg)
[![GitHub Stars](https://img.shields.io/github/stars/trigon1998/wordwise.koplugin-custom?style=flat&label=stars)](https://github.com/trigon1998/wordwise.koplugin-custom/stargazers)

<p align="center">
  <img src="docs/wordwise-preview.svg" width="860" alt="Word Wise hiển thị giải nghĩa ngay phía trên từ khó trong KOReader">
</p>

## Word Wise là gì?

Word Wise là plugin dành cho người đọc sách tiếng Anh bằng KOReader. Plugin chỉ
quét trang đang hiển thị, tìm những từ hoặc cụm từ khó phù hợp rồi đặt giải
nghĩa ngắn ngay phía trên văn bản. Đường ngang và dấu mũi nhọn hướng xuống giúp
xác định chính xác từ đang được giải thích mà không cần rời khỏi trang sách để
mở từ điển.

**Phiên bản hiện tại:** `2026.07.1-rc1.3.5`
**Kênh cập nhật:** bản thử nghiệm RC

## Tính năng nổi bật

| Tính năng | Công dụng |
|---|---|
| Giải nghĩa ngay trên trang | Hiển thị định nghĩa tiếng Anh ngắn và bản dịch tiếng Việt đã được rà soát |
| Nhận diện cụm từ | Có thể nhận diện cụm từ dài tối đa 5 từ, không chỉ từng từ riêng lẻ |
| Ba lĩnh vực | Cơ sở dữ liệu Tổng quát, Kinh tế và Vật lý |
| Lọc theo ngữ cảnh | Dùng các từ xung quanh để hạn chế chọn nhầm nghĩa |
| Từ đã biết | Cho phép ẩn những từ bạn đã biết và dùng chung danh sách này giữa các sách |
| Dấu chỉ từ trực quan | Đường ngang và dấu mũi nhọn hướng xuống chỉ đúng từ đang được giải thích |
| Cập nhật OTA đầy đủ | Cập nhật cả plugin và ba cơ sở dữ liệu ngay trong menu Word Wise |
| Khôi phục an toàn | Luôn tạo bản sao lưu và không đụng đến tiến độ đọc, sidecar hay `known_words.db` |

## Khả năng tương thích

Plugin được thiết kế cho:

- tài liệu có thể dàn lại trang bằng CREngine của KOReader, chẳng hạn EPUB và HTML;
- thiết bị đọc sách chạy Android;
- được kiểm tra chủ yếu với KOReader 2026.03 “Snowflake” trên iReader Ocean 5 Pro.

Các tài liệu bố cục cố định như PDF, DJVU và truyện tranh không được hỗ trợ bởi
cơ chế xác định tọa độ từ trên trang.

## Cài đặt và cập nhật

### Đang sử dụng Word Wise

Mở:

```text
Word Wise → Updates → Check for updates
```

Đối với bản RC, bật **Include prerelease/RC updates**, sau đó chọn
**Update all and restart**.

Trước khi cài đặt, trình cập nhật sẽ kiểm tra:

- ZIP plugin;
- ZIP cơ sở dữ liệu;
- SHA-256;
- manifest;
- tính toàn vẹn SQLite;
- sự khớp phiên bản giữa plugin và database.

### Cài đặt lần đầu

1. Mở trang [Releases](https://github.com/trigon1998/wordwise.koplugin-custom/releases).
2. Tải ZIP plugin và ZIP cơ sở dữ liệu có cùng số phiên bản.
3. Thoát hoàn toàn khỏi KOReader.
4. Chép thư mục `wordwise.koplugin` đã giải nén vào `koreader/plugins/`.
5. Giải nén gói cơ sở dữ liệu vào thư mục đang chứa `koreader/`.
6. Khởi động lại KOReader.
7. Mở **Word Wise → Diagnostics** và kiểm tra phiên bản plugin cùng phiên bản cơ sở dữ liệu phải trùng nhau.

Không xóa hoặc thay thế:

```text
<KOReader data>/wordwise/known_words.db
```

## Dữ liệu của bạn được bảo vệ như thế nào?

Git repository này chỉ chứa mã nguồn plugin. Các cơ sở dữ liệu từ điển được
đính kèm riêng trong GitHub Releases.

Bản cập nhật chỉ được phép thay thế:

```text
koreader/plugins/wordwise.koplugin/
koreader/wordwise/databases/wordwise_general.db
koreader/wordwise/databases/wordwise_economics.db
koreader/wordwise/databases/wordwise_physics.db
```

Trình cập nhật **không đóng gói hoặc thay thế**:

- `known_words.db`;
- tiến độ đọc;
- phần tô sáng và ghi chú;
- sidecar riêng của từng sách;
- các thiết lập KOReader không liên quan.

Plugin chỉ kết nối tới GitHub khi bạn chủ động kiểm tra cập nhật và không lưu
GitHub Personal Access Token trên thiết bị đọc sách.

## Thống kê lượt tải

[![Lịch sử lượt tải plugin ZIP](stats/downloads.svg)](stats/downloads.json)

## Phiên bản hiện tại: RC1.3.5

RC1.3.5 chuyển sang chiến lược hiển thị đơn giản và ổn định hơn, dựa trên cách
làm của [`asxelot/wordwise.koplugin`](https://github.com/asxelot/wordwise.koplugin):

- khoảng cách dòng tự động 180% để dành vùng cho hint;
- dùng chung font metrics để đặt hint nhất quán;
- đường ngang cùng dấu mũi nhọn cố định hướng xuống;
- giới hạn hint trong cột văn bản thực tế;
- Diagnostics hiển thị số hint tìm thấy, đã đặt và bị ẩn.

Xem trang [Releases](https://github.com/trigon1998/wordwise.koplugin-custom/releases)
để tải file, kiểm tra checksum và đọc ghi chú phát hành.

## Xử lý sự cố

### Diagnostics tìm thấy hint nhưng không hiển thị

Mở **Word Wise → Diagnostics** và kiểm tra:

```text
Hint render: … matched · … placed · … hidden
```

Khi `Page hints` lớn hơn 0, trang hoạt động bình thường cần có ít nhất một hint
ở trạng thái `placed`.

### Khôi phục phiên bản trước

Mở:

```text
Word Wise → Updates → Restore previous version
```

Các bản sao lưu nằm trong thư mục cập nhật Word Wise của KOReader.
`known_words.db` và sidecar sách không thuộc phạm vi thay thế của updater.

### Khoảng cách dòng quá rộng

RC1.3.5 chủ động dùng khoảng cách dòng tự động 180% để dành đủ vùng hiển thị
cho hint. Tắt tự động điều chỉnh khoảng cách hoặc tắt Word Wise để khôi phục
khoảng cách dòng ban đầu đã được ghi nhớ.

## Tài liệu kỹ thuật

Các tài liệu dành cho phát triển và bảo trì:

- [Tài liệu kỹ thuật và lịch sử phát hành](docs/TECHNICAL_REFERENCE.md)
- [Quy trình bảo trì dữ liệu](DATA_MAINTENANCE.md)
- [Kiểm tra hiệu năng](PERFORMANCE_TEST.md)
- [Thông báo về repository](NOTICE.md)

`docs/TECHNICAL_REFERENCE.md` giữ nguyên nội dung kỹ thuật và lịch sử cũ để
không làm mất thông tin phát triển.

## Miễn trừ trách nhiệm

Dự án này được phát triển nhằm mục đích **nghiên cứu, học tập, thử nghiệm kỹ thuật và sử dụng cá nhân**.

Dự án **không phục vụ mục đích thương mại**, không cung cấp dịch vụ trả phí và không nhằm tạo ra lợi nhuận từ phần mềm, dữ liệu hoặc các thành phần liên quan.

Phần mềm được cung cấp theo hiện trạng để phục vụ thử nghiệm. Người sử dụng tự chịu trách nhiệm đối với việc cài đặt, sử dụng, chỉnh sửa và sao lưu dữ liệu trên thiết bị của mình.

Word Wise trong repository này là một dự án cộng đồng/cá nhân và không phải là sản phẩm thương mại chính thức.

## Ghi nhận và trạng thái phân phối

Đây là bản fork bảo trì chỉ chứa mã nguồn, được phát triển từ
[`asxelot/wordwise.koplugin`](https://github.com/asxelot/wordwise.koplugin).

