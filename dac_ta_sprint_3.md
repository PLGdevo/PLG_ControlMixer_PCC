# Đặc tả Sprint 3 — rc_controller

> Giao diện mới · Hồ sơ xe · Kênh điều khiển (10 kênh) · Mix kênh · Ping thiết bị · Bố cục bảng điều khiển tuỳ chỉnh
>
> Phiên bản: 1.2 · Ngày: 25/09/2026 · Dự án: `rc_car` (app Flutter + firmware ESP32)
>
> **Thay đổi ở bản 1.1:** mix chạy đồng thời tối thiểu 10 luật (giới hạn 20, xem G1); xe chỉ nhận dữ liệu điều khiển kênh; toàn bộ cấu hình điều khiển (kênh, trim, hộp số, mix) được chỉnh và tính hoàn toàn trong app; khi kết nối chỉ đồng bộ **failsafe** xuống xe (xem 0.5). Phần tử điều khiển trên màn Lái được thêm và cấu hình riêng, kênh được gán vào phần tử (B2, H3).
>
> **Thay đổi ở bản 1.2:** sửa các chỗ mâu thuẫn (H3b ↔ H5, B2, H2, `ReturnConfig`, bảng kích thước, cây thư mục); ghi rõ phần làm tạm trong Sprint 3 (0.4). Mô hình Input → Condition → Mixer thay cho gán kênh 1:1 và `MixRule` hiện tại được đặc tả riêng ở `dac_ta_sprint_4_mixer.md`.

---

## 0. Tổng quan

### 0.1 Mục tiêu

1. App dùng phong cách tối theo mẫu Figma *Digital Agency Company Website UI (Dark Theme)*, có thêm giao diện sáng và nút chuyển.
2. Người dùng tạo và quản lý **hồ sơ xe**, gồm kết nối và toàn bộ cấu hình. Cấu hình **chỉ nằm trong app** và sửa được khi chưa kết nối xe; khi nối xe, app chỉ **đồng bộ failsafe** xuống xe.
3. Hỗ trợ **tối đa 10 kênh**. Cần gạt, nút, công tắc, núm xoay trên màn Lái được **thêm và cấu hình riêng**; người dùng **gán kênh vào phần tử**.
4. Có **mix kênh** do app tính, gồm cả luật ngưỡng có hysteresis. Ví dụ: CH3 = 100% khi CH1 ≥ 80%, CH3 = 0% khi CH1 < 70%.
5. Có **ping thiết bị** để đo độ trễ, mất gói và độ dao động, kèm cảnh báo kết nối yếu khi lái.
6. Người dùng **tự sắp xếp màn Lái**: đổi vị trí, kích thước và kiểu của cần gạt, nút và ô đồng hồ.

### 0.2 Hiện trạng (trước sprint)

| Màn | File | Ghi chú |
|---|---|---|
| Kết nối (WiFi/BLE) | `connect_screen.dart` | Màn mở app; nhập IP/port hoặc quét BLE |
| Lái xe | `control_screen.dart` | Khoá ngang; ga dọc trái, lái ngang phải, hộp số, trim |
| Cấu hình servo | `settings_screen.dart` | 3 tab Ga/Lái/Chung; **chỉ dùng được khi đã nối xe** |
| Xe giả lập | `tools/fake_car.py` | Chỉ nhánh UDP, port 4210 |

Theme hiện tại: Material 3 tối, màu nhấn cam, chỉ có giao diện tối.

### 0.3 Phạm vi

| Trong phạm vi | Ngoài phạm vi |
|---|---|
| App Flutter (Android, Windows để test) | iOS |
| Firmware ESP32 (UDP + BLE) | Tay điều khiển vật lý, gamepad |
| `fake_car.py` | Giả lập BLE |

### 0.4 Phương án chia sprint (đã chốt)

Chia hai. **Sprint 3:** A1–A3, E1–E4, E7, B1–B5, F1–F4, G1–G2, G5–G6, H1–H3, H5 (phần app, test được trên PC) · **Sprint 4:** C1–C4, E5–E6, E8, G3–G4, G7–G10, F5–F9, B6, H4, H6–H8, A4–A7, D

**Phần làm tạm trong Sprint 3** (vì E5, E6, C1 thuộc Sprint 4):

- E4 "Lưu khi đã kết nối": dùng `CarController.syncProfile` (giao thức v1, 2 kênh) thay cho `FS_WRITE`. Sprint 4 đổi sang `FS_WRITE` + `OutputPipeline` đủ 10 kênh.
- E7 mục "Mix": phần kiểm tra của G4 (trùng kênh, vòng lặp) **làm luôn trong Sprint 3**, dù phần chạy mix trong vòng gửi (G3) để Sprint 4.
- H5 "gửi Center khi sửa bố cục": Sprint 3 áp cho kênh Ga và Lái (gói v1 chỉ có 2 kênh); Sprint 4 áp cho mọi kênh cần gạt.
- Mô hình mix của Sprint 3 (`MixRule`, gán kênh 1:1) sẽ được thay ở Sprint 4 theo `dac_ta_sprint_4_mixer.md`; hồ sơ Sprint 3 được tự chuyển đổi.

### 0.5 Nguyên tắc: app giữ cấu hình, xe chỉ nhận lệnh điều khiển (đã chốt, bản 1.1)

| | App | Xe (ESP32) |
|---|---|---|
| Cấu hình kênh (Min/Center/Max, trim, offset, reverse) | Lưu trong hồ sơ, chỉnh trong app | Không có |
| Hộp số, mix kênh, tự về của cần gạt | Lưu và **tính trong app** | Không có |
| Bố cục màn Lái, gán kênh vào phần tử | Lưu trong hồ sơ | Không có |
| Failsafe (`failsafeUs` 10 kênh, `failsafeTimeoutMs`) | Chỉnh trong app | **Nhận khi kết nối**, lưu NVS, tự áp khi mất sóng |
| Dữ liệu gửi khi lái | Giá trị **cuối cùng** 10 kênh (µs) | Xuất thẳng ra PWM (chỉ kẹp an toàn 500–2500 µs) |

- Gói gửi xuống xe khi lái **chỉ là dữ liệu điều khiển các kênh**. Không có gói đọc/ghi cấu hình kênh hay mix.
- Mọi thay đổi cấu hình (trim, Min/Max, reverse, hộp số, mix, ...) có tác dụng **ngay** ở chu kỳ gửi tiếp theo vì app tự tính; không cần "ghi xuống xe".
- Failsafe là phần duy nhất phải nằm trên xe, vì khi mất sóng app không còn gửi được gì. App đồng bộ failsafe mỗi lần kết nối (E6) và mỗi khi failsafe bị sửa lúc đang kết nối.
- Đánh đổi: mix chạy ở app nên chịu độ trễ sóng; khi mất sóng thì xe về failsafe nên không có trạng thái mix "treo" trên xe.

---

## 1. Nhóm A — Hệ thống giao diện

### A1. Theme tối theo Figma

Code gom vào `app/lib/theme/app_theme.dart` (các `ThemeData`) và `app/lib/theme/tokens.dart` (các hằng màu, bo góc, khoảng cách).

#### Bảng màu gốc (Color Styles của mẫu Figma)

| Nhóm | Mã |
|---|---|
| Tuyệt đối | White `#FFFFFF` · Black `#000000` |
| Green (màu thương hiệu) | 50 `#9EFF00` · 60 `#B1FF33` · 70 `#C5FF66` · 80 `#D8FF99` · 90 `#ECFFCC` · 95 `#F5FFE5` · 97 `#F9FFF0` · 99 `#FDFFFA` |
| Grey | 10 `#191919` · 15 `#262626` · 20 `#333333` · 30 `#4C4C4D` · 35 `#59595A` · 40 `#656567` · 60 `#98989A` · 90 `#E6E6E6` |

Code khai báo nguyên hai dải Green/Grey trong `tokens.dart` (`Green.g50…g99`, `Grey.g10…g90`). Theme chỉ tham chiếu các token dưới đây, không dùng mã màu trực tiếp.

#### Token theo theme

| Token | Tối | Sáng (A2) | Dùng cho |
|---|---|---|---|
| `bg` | Grey 10 `#191919` | Green 99 `#FDFFFA` | Nền màn |
| `surface` | Grey 15 `#262626` | White `#FFFFFF` | Thẻ, app bar, thanh nút dưới |
| `surface2` | Grey 20 `#333333` | Green 97 `#F9FFF0` | Thẻ lồng, rãnh slider, ô nhập |
| `line` | Grey 20 `#333333` | Grey 90 `#E6E6E6` | Viền mảnh 1px |
| `text` | White `#FFFFFF` | Grey 10 `#191919` | Chữ chính, số đo |
| `textBody` | Grey 90 `#E6E6E6` | Grey 30 `#4C4C4D` | Đoạn văn, mô tả |
| `textMuted` | Grey 60 `#98989A` | Grey 35 `#59595A` | Nhãn phụ, đơn vị |
| `disabled` | Grey 35 `#59595A` | Grey 60 `#98989A` | Chữ/icon bị mờ |
| `accent` | Green 50 `#9EFF00` | `#3D6600` * | Chữ/icon nhấn, tab đang chọn, viền thẻ đang chọn |
| `accentFill` | Green 50 `#9EFF00` | Green 50 `#9EFF00` | Nền nút chính, thumb slider |
| `accentFillPressed` | Green 60 `#B1FF33` | Green 60 `#B1FF33` | Nút chính khi nhấn |
| `onAccentFill` | Grey 10 `#191919` | Grey 10 `#191919` | Chữ/icon trên nút chính |
| `accentContainer` | `#9EFF00` @ 12% | Green 90 `#ECFFCC` | Nền mục đang chọn, nút tonal |
| `onAccentContainer` | Green 70 `#C5FF66` | Grey 10 `#191919` | Chữ trên nền mục đang chọn |
| `ok` / `warn` / `bad` / `idle` | `#4CAF50` / `#FFC107` / `#F44336` / Grey 60 | `#2E7D32` / `#B26A00` / `#C62828` / Grey 35 | Huy hiệu trạng thái |

\* `#3D6600` không có trong bảng gốc. Green 50 trên nền trắng chỉ đạt khoảng 1.3:1 nên không đọc được; màu này là Green 50 kéo tối lại để đạt khoảng 6.8:1. Nền nút chính vẫn dùng Green 50 (chữ `#191919` trên đó đạt khoảng 14:1).

Độ tương phản đã tính cho giao diện tối: `textMuted` trên `bg` ≈ 6:1, `text` trên `surface` ≈ 15:1, `disabled` trên `bg` ≈ 2.6:1 (chấp nhận được vì chỉ dùng cho phần tử bị khoá).

> Lưu ý: xanh chanh thương hiệu và xanh "Đã kết nối" (`ok`) dễ lẫn nhau. Huy hiệu trạng thái vì vậy luôn có chữ đi kèm, không chỉ dựa vào màu.

#### Kiểu chữ: Barlow

- Dùng font **Barlow** với 5 độ đậm theo mẫu: Regular 400 · Medium 500 · SemiBold 600 · Bold 700 · ExtraBold 800.
- **Đóng gói file TTF vào `assets/fonts/`**, khai báo trong `pubspec.yaml`, không tải qua `google_fonts`. App thường dùng ngoài bãi, không có mạng, nên font phải có sẵn trong máy. Barlow hỗ trợ đủ dấu tiếng Việt.

| Kiểu | Cỡ / độ đậm | Dùng cho |
|---|---|---|
| `display` | 32 / ExtraBold | Số hiển thị lớn (số, tốc độ) |
| `headline` | 24 / Bold | Tiêu đề màn |
| `title` | 18 / SemiBold | Tiêu đề thẻ, tên xe |
| `body` | 15 / Regular | Nội dung |
| `label` | 14 / Medium | Nút, tab |
| `caption` | 12 / Medium, chữ hoa, giãn 0.08em | Nhãn phụ trên ô đồng hồ |
| `metric` | 18 / Bold, số đều nhau | Giá trị đo (V, A, km/h, ms) |

Số đo luôn bật `FontFeature.tabularFigures()` để con số không nhảy khi thay đổi.

#### Hình khối

- Nút chính dạng viên thuốc (bo 999), nền `accentFill`.
- Nút phụ dạng viên thuốc, viền 1px `line`.
- Thẻ bo 16, nền `surface`, viền 1px `line`, không đổ bóng. Thẻ đang chọn đổi viền sang `accent`.
- Khoảng cách theo lưới 4: 4 / 8 / 12 / 16 / 24 / 32.

#### Icon: Heroicons v2

- Dùng package [`heroicons`](https://pub.dev/packages/heroicons) (hoặc đóng gói SVG kèm `flutter_svg`).
- Mặc định dùng bộ **Outline 24px** (nét 1.5). Bộ **Solid** dùng cho trạng thái đang bật hoặc đang chọn; bộ **Mini 20px** dùng trong nút nhỏ và huy hiệu.
- Code gom vào `app/lib/theme/app_icons.dart` để đổi icon ở một chỗ.

| Chức năng | Heroicon |
|---|---|
| WiFi | `wifi` |
| Kết nối / Ngắt | `link` / `link-slash` |
| Quét | `magnifying-glass` |
| Cấu hình | `adjustments-horizontal` |
| Cài đặt chung | `cog-6-tooth` |
| Quay lại | `arrow-left` |
| Pin | `battery-50` / `battery-100` / `battery-0` |
| Dòng điện | `bolt` |
| Ping / RSSI | `signal` / `signal-slash` |
| Lưu | `arrow-down-tray` |
| Đồng bộ failsafe | `arrow-up-tray` |
| Mặc định | `arrow-uturn-left` |
| Tăng / Giảm | `plus` / `minus` |
| Thành công / Cảnh báo | `check-circle` / `exclamation-triangle` |
| Đèn | `light-bulb` |
| Còi | `megaphone` |
| Mix | `arrows-right-left` |
| Kéo đổi thứ tự | `bars-3` |
| Xoá / Nhân bản | `trash` / `document-duplicate` |
| Xuất / Nhập | `arrow-up-on-square` / `arrow-down-on-square` |
| Chẩn đoán | `chart-bar` |
| Tìm xe | `bell-alert` |
| Theme sáng / tối / hệ thống | `sun` / `moon` / `computer-desktop` |

Heroicons **không có** icon Bluetooth, xe, đồng hồ tốc độ và tay lái. Bốn icon này sẽ vẽ SVG riêng theo đúng quy cách Heroicons (khung 24×24, nét 1.5, đầu nét tròn) rồi đặt trong `assets/icons/`: `bluetooth.svg`, `car.svg`, `speedometer.svg`, `steering.svg`.

### A2. Theme sáng

- Dùng cột "Sáng" ở bảng token trên.
- Nền sáng hơi ngả xanh (Green 99), thẻ trắng, nên vẫn mang màu thương hiệu mà không bị chói.
- Green 50 **không** dùng làm màu chữ trên nền sáng. Nó chỉ làm nền nút chính và thumb slider; chữ và icon nhấn dùng `#3D6600`.

### A3. Chuyển giao diện

- Có 3 lựa chọn: **Tối / Sáng / Theo hệ thống**. Mặc định là Tối.
- Lựa chọn được lưu (`shared_preferences`) và áp dụng ngay, không cần khởi động lại app.

### A4–A6. Làm lại các màn

| Mục | Màn | Thay đổi chính |
|---|---|---|
| A4 | Xe của tôi / Tạo xe (thay màn Kết nối) | Xem nhóm E. Chọn WiFi/BLE dạng viên thuốc; thẻ xe có viền `accent` khi được chọn |
| A5 | Lái xe | Ô đồng hồ dạng thẻ; số lớn; dải failsafe/cảnh báo nổi bật ở cả hai theme; hàng nút kênh phụ (B6) |
| A6 | Cấu hình | Tab viên thuốc: **Ga · Lái · Kênh · Mix · Chung**; hàng −/+ gọn hơn; thanh nút dưới đồng bộ |

### A7. Độ tương phản

- Chữ thường đạt WCAG AA (≥ 4.5:1); chữ lớn và icon đạt ≥ 3:1. Áp dụng cho cả hai theme.
- Kiểm tra riêng: chữ phụ, nút bị mờ, huy hiệu trạng thái.

**Tiêu chí nghiệm thu nhóm A**

- [ ] Không còn mã màu viết cứng trong `screens/` và `widgets/`; mọi màu lấy từ theme/token.
- [ ] Chuyển theme thì cả 5 màn đổi đúng, không còn chỗ nào lệch màu.
- [ ] Ảnh chụp 5 màn × 2 theme đính kèm vào PR.

---

## 2. Nhóm E — Hồ sơ xe (tạo mới, chỉnh khi chưa kết nối)

### E1. Mô hình hồ sơ

```dart
class CarProfile {
  String id;                 // uuid
  String name;               // "Xe tải đỏ"
  String? icon;              // tên icon hoặc đường dẫn ảnh
  ConnType connType;         // wifi | ble
  WifiConn? wifi;            // ip, port, ssid (tuỳ chọn)
  BleConn? ble;              // mac, deviceName
  GearConfig gears;          // gearCount, maxThrottle[]
  int failsafeTimeoutMs;      // đồng bộ xuống xe cùng failsafeUs của 10 kênh (E6)
  List<ChannelConfig> channels;  // đúng 10 phần tử (B1)
  List<MixRule> mixes;           // chạy đồng thời tối thiểu 10 luật, giới hạn 20 (G1)
  PingConfig ping;               // ngưỡng cảnh báo (F6)
  List<ControlLayout> layouts;   // bố cục màn Lái (H1)
  String activeLayoutId;
  DateTime updatedAt;
  DateTime? lastSyncedAt;    // lần đồng bộ failsafe gần nhất với xe
  String? lastSyncedHash;    // hash failsafe lúc đồng bộ (E5)
  DateTime? lastConnectedAt;
}
```

- Lưu hồ sơ vào file JSON trong thư mục dữ liệu app. Mỗi hồ sơ một file `profiles/<id>.json` và có trường `schemaVersion`.
- Có `ProfileRepository` với các hàm: `list`, `get`, `save`, `delete`, `duplicate`, `export`, `import`.

### E2. Màn "Xe của tôi" (màn mở app)

- Hiện danh sách thẻ hồ sơ. Mỗi thẻ gồm: tên, icon, kiểu kết nối (IP:port hoặc tên BLE), dòng "Kết nối lần cuối", và huy hiệu *Chưa đồng bộ failsafe* (E5) nếu có.
- Mỗi thẻ có các nút: **Kết nối**, **Sửa**, **Kiểm tra** (ping nhanh, F4), và menu ⋮ gồm Đổi tên / Nhân bản / Xuất / Xoá.
- Có nút nổi **+ Tạo xe mới**.
- Chưa có hồ sơ nào thì hiện màn trống kèm nút tạo xe.

### E3. Luồng tạo xe mới (3 bước)

| Bước | Nội dung |
|---|---|
| 1 | Tên xe, chọn WiFi hoặc Bluetooth |
| 2 | **WiFi:** IP (mặc định `192.168.4.1`), port (mặc định `4210`), SSID tuỳ chọn · **BLE:** quét (timeout 6 s, lọc theo service UUID) hoặc nhập tay MAC/tên · Nút **Kiểm tra** (F4) |
| 3 | Mẫu khởi đầu: *Xe cơ bản 2 kênh* · *Xe có đèn/còi* · *Sao chép từ xe khác* |

- Bước 2 cho phép lưu dù kiểm tra thất bại (xe có thể đang tắt), nhưng app sẽ cảnh báo.

### E4. Chỉnh sửa khi chưa kết nối

- Màn Cấu hình **luôn mở được** và làm việc trên hồ sơ. Bỏ dòng "Kết nối xe để đọc cấu hình".
- Cấu hình chỉ nằm trong app (0.5) nên **bỏ** các nút *Đọc từ xe* và *Áp dụng thử*.

| Nút | Chưa kết nối | Đã kết nối |
|---|---|---|
| Lưu | Lưu vào máy | Lưu vào máy; cấu hình có tác dụng ngay khi lái. Nếu failsafe đổi thì tự gửi `FS_WRITE` (E6) |
| Đồng bộ failsafe | Mờ · "Cần kết nối xe" | Gửi lại failsafe xuống xe (dùng khi muốn chắc chắn) |
| Mặc định | Dùng được | Dùng được |

### E5. Trạng thái "Chưa đồng bộ failsafe"

- Chỉ tính trên phần failsafe: `hashFailsafe = hash(failsafeUs của 10 kênh, failsafeTimeoutMs)`.
- Hồ sơ được coi là chưa đồng bộ khi `hashFailsafe ≠ lastSyncedHash`, hoặc khi `lastSyncedAt == null`.
- Khi đó hiện huy hiệu vàng *Chưa đồng bộ failsafe* trên thẻ hồ sơ và trên app bar màn Cấu hình.
- Sửa trim, Min/Max, mix, hộp số, bố cục **không** làm hồ sơ thành chưa đồng bộ.

### E6. Đồng bộ failsafe khi kết nối

1. Nối xe xong, app gửi ngay `FS_WRITE` gồm `failsafeTimeoutMs` và `failsafeUs` của 10 kênh.
2. Xe lưu vào NVS, áp dụng ngay, rồi trả `FS_ACK` kèm `hash`.
3. `status = OK` và `hash` khớp thì app cập nhật `lastSynced*`, bắt đầu gửi `CONTROL`.
4. Không nhận ACK sau 1 s thì gửi lại, tối đa 3 lần. Vẫn lỗi thì **không cho lái**, hiện thông báo *"Không đồng bộ được failsafe với xe"* kèm nút Thử lại.
5. Đang kết nối mà sửa failsafe rồi Lưu thì app lặp lại bước 1–4 (không ngắt lái nếu đồng bộ thất bại, nhưng hiện cảnh báo và huy hiệu E5).
6. Không có bước so sánh hay "Lấy từ xe": app luôn là nguồn đúng.

### E7. Kiểm tra dữ liệu

| Trường | Luật |
|---|---|
| IP | IPv4 hợp lệ |
| Port | 1–65535 |
| Servo / kênh | 500 ≤ Min < Center < Max ≤ 2500 µs; Failsafe nằm trong [Min, Max] |
| Gán kênh | Mỗi kênh tối đa một phần tử trên một bố cục; bố cục phải có phần tử cho Ga và Lái (B4, H5) |
| Mix | Xem G4 |
| Tên hồ sơ | 1–32 ký tự, không trùng tên hồ sơ khác |

- Báo lỗi ngay dưới ô nhập. Nút Lưu bị khoá khi còn lỗi.

### E8. Quản lý hồ sơ

- Đổi tên, nhân bản (thêm hậu tố "(bản sao)"), xoá (có hộp thoại xác nhận).
- **Xuất/nhập** file `.json`. Khi nhập, app kiểm tra `schemaVersion` và dữ liệu (E7). Nếu trùng `id` thì hỏi: *Ghi đè* hay *Tạo bản mới*.

### E9. Test

- Unit test: lưu → đọc lại → so sánh bằng nhau; nâng `schemaVersion` cũ lên mới; kiểm tra dữ liệu E7.
- Tích hợp với `fake_car.py`: đồng bộ failsafe thành công; xe không trả ACK (gửi lại 3 lần rồi báo lỗi, không cho lái); sửa failsafe khi đang kết nối.

**Tiêu chí nghiệm thu nhóm E**

- [ ] Tắt WiFi/BT điện thoại vẫn tạo, sửa và lưu được hồ sơ.
- [ ] Sửa failsafe khi chưa nối xe thì hiện *Chưa đồng bộ failsafe*; nối xe thì app tự ghi failsafe và huy hiệu biến mất.
- [ ] Sửa trim / mix / Min–Max khi đang kết nối thì giá trị `fake_car.py` in ra đổi ngay, không cần ghi cấu hình xuống xe.
- [ ] Xuất rồi nhập lại trên máy khác cho ra hồ sơ giống hệt.

---

## 3. Nhóm B — Kênh điều khiển (10 kênh)

### B1. Mô hình kênh

```dart
class ChannelConfig {
  int index;               // 1..10
  String name;             // "Lái", "Ga", "Đèn", ...
  int minUs, centerUs, maxUs;   // mặc định 1000 / 1500 / 2000
  int trimUs, offsetUs;         // CH1/CH2 giữ ý nghĩa như hiện tại
  bool reverse;
  int failsafeUs;
  bool enabled;
}
```

Mặc định: **CH1 = Lái** (bố cục mẫu gán vào cần gạt ngang), **CH2 = Ga** (gán vào cần gạt dọc); CH3–CH10 tắt, chưa gán.

Kênh **không** có trường `source`: loại điều khiển do phần tử trên bố cục quyết định (`ControlItem.kind`), kênh chỉ được gán vào phần tử (`ControlItem.channel` / `channelY`). Hồ sơ cũ có `source` thì trường này bị bỏ qua khi đọc.

**Đường tính giá trị gửi đi (chạy trong app, mỗi chu kỳ gửi):**

```
giá trị phần tử trên màn Lái (%, sau tự về / vùng chết)
  → giới hạn hộp số (chỉ kênh Ga)
  → chạy mix theo thứ tự danh sách (G3)
  → reverse → đổi sang µs quanh Center, cộng trim + offset
  → kẹp trong [Min, Max]
  → gói CONTROL (10 kênh µs) gửi xuống xe
```

Kênh chưa gán và không bị mix ghi vào thì gửi Center.

**Quy ước phần trăm** (dùng trong UI và mix): giá trị kênh tính theo % từ −100% đến +100% so với Center.
`pct = (us − center) / (max − center) × 100` khi `us ≥ center`, và `/ (center − min)` khi nhỏ hơn.
Với nút hoặc công tắc: bật = +100%; **giá trị tắt chỉnh được theo %** qua `offValuePct` (mặc định −100%, khoảng cho phép −100…+100%). Áp dụng cho cả nút bật/tắt và công tắc 3 nấc (nấc giữa vẫn cố định 0%).

```dart
double offValuePct = -100; // -100..+100, chỉnh trong bảng thuộc tính (H3)
```

### B2. Loại phần tử điều khiển

| Loại | Giá trị ra | Ghi chú |
|---|---|---|
| Cần gạt ngang | −100…+100%, tự về 0 khi thả | Như cần lái hiện tại |
| Cần gạt dọc | −100…+100%, tự về 0 khi thả | Như cần ga hiện tại |
| Cần 2 trục | X và Y, mỗi trục −100…+100%, tự về theo từng trục | Giữ 2 kênh (trục X, trục Y); dùng cho bố cục "Tay cầm" |
| Nút nhấn giữ | bật khi giữ, thả ra là tắt | Còi |
| Nút bật/tắt | mỗi lần bấm đổi trạng thái | Đèn |
| Công tắc 3 nấc | −100 / 0 / +100% | Tời, ben |
| Núm xoay | −100…+100%, giữ nguyên vị trí | Servo phụ |

Kênh không được gán vào phần tử nào (và không bị mix ghi vào) thì gửi Center; khi mất sóng xe dùng Failsafe. "Chưa gán" là trạng thái của kênh, không phải một loại phần tử.

- Phần tử được **thêm tự do** ở chế độ Sửa bố cục (nút **Thêm** ▸ chọn loại), **không giới hạn số lượng**, kể cả cần gạt (có thể có nhiều cần gạt ngang/dọc).
- Mỗi phần tử có **cấu hình riêng** (tự về, vùng chết, kích thước núm, nhãn, icon, ...) theo H3/H3b, không phụ thuộc kênh.
- Phần tử mới thêm ở trạng thái *Chưa gán kênh*; người dùng gán kênh trong bảng thuộc tính (H3) hoặc ở trang chi tiết kênh (B3).

### B3. Tab "Kênh"

- Danh sách 10 hàng: `CHn · tên · phần tử đang gán · công tắc bật/tắt`.
- Bấm vào một hàng để mở trang chi tiết. Trang này có: tên, **Phần tử điều khiển**, Min/Center/Max, Trim/Offset, Reverse, Failsafe, và **thanh xem trước** (kéo thử để thấy giá trị µs và %).
- **Phần tử điều khiển** mở danh sách chọn: *Chưa gán* · các phần tử đang có trên bố cục (cần 2 trục có hai chỗ: trục X, trục Y) kèm kênh đang gán · *Tạo phần tử mới* (thêm phần tử loại đó vào chỗ trống trên màn Lái và gán luôn kênh này).
- Tắt kênh thì kênh được gỡ khỏi phần tử; phần tử vẫn ở trên màn Lái (hiện *Chưa gán kênh*).

### B4. Chống gán trùng

- Mỗi kênh có tối đa **một** phần tử trên một bố cục; mỗi chỗ gán của phần tử giữ tối đa một kênh.
- Ở trang chi tiết kênh, chọn phần tử đang giữ kênh khác thì hiện hộp thoại: *"Cần gạt ngang đang gán CH5. Thay bằng CH3? CH5 sẽ thành chưa gán."* với **Thay** hoặc **Huỷ**.
- Ở bảng thuộc tính, chọn kênh đang ở phần tử khác thì kênh được **chuyển** sang phần tử đang chọn (phần tử cũ thành chưa gán) và app báo lại.
- Kênh Ga/Lái không bỏ gán được ở trang kênh; bố cục thiếu phần tử cho Ga hoặc Lái thì không cho lưu (H5).

### B5. Chuyển Ga/Lái sang hệ kênh

- Tab Ga và tab Lái giữ nguyên giao diện nhưng đọc/ghi vào `channels[1]` và `channels[0]`.
- Hộp số (`gearCount`, `maxThrottle[]`) vẫn áp lên kênh Ga (CH2), dù kênh này gán vào phần tử nào.
- Trim chỉnh trên màn Lái có tác dụng ngay vì app tự tính; không gửi cấu hình xuống xe (0.5).
- Hồ sơ cũ (định dạng trước sprint) được tự chuyển sang hệ kênh khi mở.

### B6. Kênh phụ trên màn Lái

- Các kênh phụ được đặt tự do trên màn Lái theo **nhóm H** (vị trí, kích thước, kiểu đều tuỳ chỉnh được). Hàng nút cố định trong bản trước bị bỏ.
- Mỗi nút hiện tên kênh và trạng thái (sáng lên khi bật; công tắc 3 nấc hiện ◀ ● ▶).
- Thoát màn thì mọi kênh cần gạt về Center, riêng nút bật/tắt giữ nguyên trạng thái. Đây là mở rộng của `dispose()` hiện tại.
- Loại **Cần 2 trục** (B2) phục vụ bố cục "Tay cầm" (H4).

**Tiêu chí nghiệm thu nhóm B**

- [ ] Thêm nút bật/tắt lên màn Lái, gán CH3 "Đèn" vào nút; bấm nút thì `fake_car.py` in CH3 đổi từ 1000 sang 2000 µs.
- [ ] Thêm được nhiều cần gạt cùng loại, mỗi cái có cài đặt tự về riêng.
- [ ] Một phần tử không giữ hai kênh (trừ cần 2 trục: X và Y) và một kênh không nằm trên hai phần tử.
- [ ] Hồ sơ cũ mở ra có CH1/CH2 đúng giá trị cũ.

---

## 4. Nhóm G — Mix kênh

### G1. Mô hình luật

```dart
class MixRule {
  String id;
  bool enabled;
  MixType type;            // threshold | linear | curve | select
  int sourceCh;            // 1..10
  int targetCh;            // 1..10, khác sourceCh — không dùng khi type = select
  int? gateCh;             // điều kiện bằng nút (tuỳ chọn) — không dùng khi type = select
  MixMode mode;            // override | add | max
  // threshold
  double onAtPct, offBelowPct, onValuePct, offValuePct;
  // linear
  double gainPct, offsetPct;
  // curve
  List<double> curvePts;   // 5 điểm tại -100, -50, 0, 50, 100
  // select (chuyển kênh bằng nút, xem G2d)
  int selectCh;             // nút/công tắc chọn; > 0% = ON
  int targetOnCh;           // đích khi selectCh ON
  int targetOffCh;          // đích khi selectCh OFF
  bool requireNeutralToSwitch; // khoá an toàn, mặc định true
  double neutralDeadzonePct;   // vùng coi là "giữa", mặc định 5
}
```

**Số luật chạy cùng lúc:**

- App phải chạy **đồng thời ít nhất 10 luật** đang bật. Giới hạn danh sách là **20 luật** (`MixRule.maxRules = 20`); đủ 20 thì nút *Thêm luật* bị khoá và báo *"Tối đa 20 luật mix"*.
- Mọi luật đang bật đều được tính **trong cùng một chu kỳ gửi** (25 ms), theo thứ tự danh sách (G4). Không có luật nào phải chờ chu kỳ sau.
- Nhiều luật được dùng chung kênh nguồn, và nhiều luật được ghi vào cùng một kênh đích (theo `mode` ở G4), miễn là không tạo vòng lặp.
- Thời gian tính toàn bộ mix mỗi chu kỳ không quá **2 ms** trên điện thoại Android tầm trung với 20 luật, để không làm trễ gói `CONTROL`.

### G2. Các loại mix

**a) Ngưỡng có hysteresis**

- Nguồn ≥ `onAtPct` thì trạng thái chuyển sang **BẬT**, đích = `onValuePct`.
- Nguồn < `offBelowPct` thì trạng thái chuyển sang **TẮT**, đích = `offValuePct`.
- Nguồn nằm giữa hai ngưỡng thì **giữ trạng thái trước**.
- Ràng buộc: `offBelowPct ≤ onAtPct`. Trạng thái ban đầu là TẮT.

Ví dụ yêu cầu: `source=CH1, target=CH3, onAt=80, offBelow=70, onValue=100, offValue=0`.

| CH1 đi qua | CH3 |
|---|---|
| 0 → 75 | 0% (chưa chạm 80) |
| 75 → 82 | **100%** |
| 82 → 72 | 100% (vẫn ≥ 70, giữ) |
| 72 → 69 | **0%** |
| 69 → 78 | 0% (chưa chạm 80, giữ) |

**b) Tỉ lệ:** `đích = nguồn × gain% + offset%`, rồi kẹp trong khoảng −100…+100.

**c) Đường cong:** nội suy tuyến tính giữa 5 điểm.

**Điều kiện bằng nút (`gateCh`):** luật chỉ chạy khi kênh gate > 0%. Khi gate tắt, luật coi như không tồn tại và trạng thái hysteresis được reset về TẮT.

**d) Chuyển kênh (select):** một nguồn (thường là cần gạt) được **định tuyến** sang một trong hai kênh đích tuỳ theo nút chọn, ví dụ: nút A bật (`selectCh` > 0%) thì cần gạt ga/lái ghi vào `targetOnCh` (CH1); nút A tắt thì ghi vào `targetOffCh` (CH2). Kênh đích không active nhận Center/0% (coi như không có luật nào ghi vào nó).

Ví dụ yêu cầu: `source=CH_ga, select=CH_A, targetOn=CH1, targetOff=CH2`.

| Nút A | CH1 | CH2 |
|---|---|---|
| tắt | 0% (không active) | = giá trị cần ga |
| bật | = giá trị cần ga | 0% (không active) |

**Khoá an toàn (`requireNeutralToSwitch`, mặc định bật):** đổi trạng thái nút chọn **không** đổi đích ngay nếu nguồn đang lệch tâm. App giữ đích cũ cho tới khi nguồn về trong vùng chết `neutralDeadzonePct` (mặc định 5%) quanh 0%, lúc đó mới chuyển sang đích mới; trong lúc chờ, đích còn lại vẫn ở 0%. Mục đích: tránh nhảy giá trị đột ngột khi đang chạy (ví dụ đang ga 80% mà đổi đích thì kênh mới không bất ngờ nhận 80%).

- `sourceCh`, `selectCh`, `targetOnCh`, `targetOffCh` phải khác nhau đôi một; không cho lưu nếu trùng.
- Failsafe bỏ qua khoá an toàn: xe đưa cả hai đích về `failsafeUs` ngay; app huỷ trạng thái chờ chuyển.

### G3. Nơi chạy mix: app

- Mix chạy **trong app**, trong vòng gửi `CONTROL` (mỗi 25 ms). Xe chỉ nhận giá trị kênh đã mix xong (0.5).
- Thứ tự xử lý xem đường tính ở B1: phần tử → hộp số → **mix** → reverse / trim / offset → µs → kẹp [Min, Max] → gửi.
- Chạy đồng thời tối thiểu 10 luật, giới hạn 20 (G1); mỗi luật giữ trạng thái hysteresis riêng trong RAM của app.
- Cùng một `MixEngine` dùng cho lúc lái, xem trước (G6) và hiển thị (G7).
- Mất kết nối, thoát màn Lái, hoặc telemetry báo xe đang failsafe: app reset trạng thái hysteresis và trạng thái chờ của luật `select`.

### G4. Ưu tiên và xung đột

| Tình huống | Xử lý |
|---|---|
| Failsafe | Xe tự đưa mọi kênh về `failsafeUs` (không phụ thuộc app); app reset trạng thái hysteresis |
| Kênh đích đang có nguồn điều khiển | Theo `mode`: **override** (mix thay thế) · **add** (cộng dồn) · **max** (lấy giá trị lớn hơn) |
| Nhiều luật cùng ghi một kênh | Tính theo thứ tự danh sách; luật sau nhận kết quả của luật trước |
| Vòng lặp (CH3→CH1 và CH1→CH3, hoặc dài hơn) | App báo lỗi và không cho lưu (tìm chu trình trên đồ thị nguồn→đích; luật `select` góp hai cạnh nguồn→`targetOnCh` và nguồn→`targetOffCh`) |
| `source == target` | Không cho lưu (luật `select`: `sourceCh`/`selectCh`/`targetOnCh`/`targetOffCh` không được trùng nhau) |

### G5. Tab "Mix"

- Danh sách thẻ luật, mỗi thẻ có mô tả tự sinh, ví dụ: `CH1 ≥ 80% → CH3 = 100% · < 70% → 0%`, hoặc với luật `select`: `Nút A bật → Ga vào CH1 · tắt → Ga vào CH2 (khoá an toàn)`.
- Thao tác: thêm, sửa, xoá, **kéo để đổi thứ tự**, bật/tắt từng luật. Đầu danh sách hiện số luật đang bật, ví dụ *"12/20 luật · 10 đang bật"*.
- Sửa được khi chưa nối xe (E4).

### G6. Xem trước mix

- Trong trang sửa luật có thanh kéo giả lập kênh nguồn và cột hiển thị giá trị kênh đích.
- Luật ngưỡng hiện thêm vùng giữ trạng thái (ví dụ 70–80%) được tô nhạt, cùng đèn trạng thái BẬT/TẮT.
- Luật `select` có thêm nút giả lập nút chọn và hai cột (`targetOnCh`/`targetOffCh`); bấm nút khi đang kéo thanh nguồn lệch tâm để thấy rõ trạng thái "chờ về giữa mới chuyển" của khoá an toàn.

### G7. Hiển thị khi lái

- Nút hoặc ô của kênh đang bị mix chi phối có chấm `accent` nhỏ.
- Nhấn giữ vào nút hoặc ô đó để xem luật nào đang tác động.

### G8. Lưu luật mix

- Luật mix chỉ lưu trong hồ sơ trên điện thoại, **không** ghi xuống xe (0.5). Sửa luật khi đang kết nối có tác dụng ngay.

### G9. Giả lập trong `fake_car.py`

- Xe giả **không** chạy mix; chỉ in 10 kênh nhận được (đã mix sẵn từ app) mỗi 200 ms, và in failsafe khi nhận `FS_WRITE`.

### G10. Test

- **Bộ vector test** trong `tests/mix_vectors.json` (đầu vào theo thời gian → đầu ra mong đợi), chạy bằng unit test Dart của `MixEngine`.
- Các ca bắt buộc: **10 luật cùng bật trong một chu kỳ** (đủ 4 loại, có luật chung nguồn và luật chung đích) cho kết quả đúng; 20 luật chạy trong ≤ 2 ms; bảng hysteresis ở G2a; dao động trong vùng giữ; failsafe giữa chừng; gate bật/tắt; 3 chế độ override/add/max; phát hiện vòng lặp; luật `select` — đổi nút chọn khi nguồn lệch tâm (phải giữ đích cũ), đổi khi nguồn ở vùng chết (chuyển ngay), failsafe huỷ trạng thái chờ chuyển.

**Tiêu chí nghiệm thu nhóm G**

- [ ] Ví dụ CH1 ≥ 80% → CH3 = 100%, CH1 < 70% → CH3 = 0% chạy đúng bảng G2a; `fake_car.py` và xe thật nhận đúng CH3 do app gửi.
- [ ] Mất sóng thì xe đưa CH3 về failsafe đã đồng bộ, không giữ 100%.
- [ ] Bật cùng lúc ít nhất 10 luật mix thì tất cả cùng tác động trong một chu kỳ, `fake_car.py` in đúng các kênh đích.
- [ ] Tạo vòng lặp thì bị chặn khi lưu.
- [ ] Luật `select`: bấm nút A khi ga đang 60% thì CH1 vẫn giữ 60% cho tới khi trả ga về ≤ 5%, lúc đó CH2 mới nhận giá trị ga và CH1 về 0%.

---

## 5. Nhóm F — Ping thiết bị

### F1. Giao thức

Có ba gói: `PING(seq, t_gửi)`, `PONG(seq, t_gửi, uptime_xe)` và `IDENTIFY(duration)` (dùng cho F8). Định dạng gói xem mục 6.

### F2. Firmware

- Nhận `PING` thì trả `PONG` **ngay trong vòng nhận**, không xếp hàng chờ.
- Hỗ trợ cả UDP và BLE.

### F3. `ping_service.dart`

- Tham số: `timeoutMs` (mặc định 1000), `intervalMs`, `count` (hoặc chạy liên tục).
- Thống kê trên cửa sổ trượt 20 gói gần nhất: RTT min/avg/max, **jitter** (trung bình |RTTᵢ − RTTᵢ₋₁|), % mất gói.
- Gói về sau khi đã timeout thì tính là mất, không làm sai thống kê.
- Gói về sai thứ tự thì ghép theo `seq`.

### F4. Ping nhanh (không cần kết nối hẳn)

| Kiểu | Cách làm | Kết quả trên thẻ |
|---|---|---|
| WiFi | Gửi 3 gói UDP thẳng tới IP:port của hồ sơ | `✓ 12 ms` / `✗ Không phản hồi` |
| BLE | Kết nối tạm → 3 ping → ngắt | `✓ 35 ms` / `✗ …` |
| BLE (chỉ quét) | Không kết nối | Chỉ hiện RSSI |

- Nút này có trên thẻ hồ sơ (E2) và ở bước 2 tạo xe (E3).

### F5. Màn "Chẩn đoán kết nối"

- Vào từ thẻ xe hoặc từ màn Cấu hình.
- Điều khiển: Bắt đầu/Dừng; số gói 10 / 50 / liên tục; khoảng cách 100 / 250 / 500 ms.
- Hiển thị: biểu đồ đường RTT theo thời gian, bảng thống kê, danh sách gói mất hoặc trễ bất thường.

### F6. Ping ngầm khi lái

- Ping mỗi 1 s và không ảnh hưởng nhịp gửi lệnh lái.
- Ô RSSI trên màn Lái đổi thành **Ping `18 ms`**; RSSI chuyển xuống dòng phụ.
- Màu ô theo ngưỡng cài trong hồ sơ (`PingConfig`):

| Mức | Mặc định |
|---|---|
| Xanh | RTT ≤ 60 ms và mất gói ≤ 2% |
| Vàng | RTT ≤ 150 ms và mất gói ≤ 10% |
| Đỏ | vượt mức vàng |

- Mức đỏ kéo dài ≥ 3 s thì hiện dải vàng **"Kết nối yếu"**, xuất hiện trước khi xe vào failsafe.

### F7. Giả lập

- `fake_car.py --delay <ms> --jitter <ms> --loss <%>`: xe giả trả `PONG` với độ trễ và tỉ lệ rớt gói theo tham số.

### F8. "Tìm xe"

- Gửi gói `IDENTIFY(duration=3000)`; xe nháy **nhanh** LED trạng thái (xem C2) trong 3 s, đè lên kiểu nháy hiện tại rồi trả về bình thường.
- Có trong menu thẻ hồ sơ và trong danh sách BLE khi quét.

### F9. Test

- Unit test thống kê: gói mất, gói về sau timeout, gói sai thứ tự.
- Đo nhịp gửi lệnh lái khi bật và tắt ping ngầm; chênh lệch phải < 5%.

**Tiêu chí nghiệm thu nhóm F**

- [ ] Chạy `fake_car.py --delay 80 --loss 5` thì màn Chẩn đoán hiện RTT ≈ 80 ms và mất gói ≈ 5%.
- [ ] Chạy `--delay 200` khi đang lái thì ô Ping đỏ; sau 3 s hiện dải "Kết nối yếu".

---

## 5b. Nhóm H — Tuỳ chỉnh bố cục bảng điều khiển

Người dùng tự đặt **vị trí**, **kích thước** và **kiểu** của cần gạt, nút, công tắc, núm xoay và ô đồng hồ trên màn Lái. Bố cục được lưu theo hồ sơ xe.

### H1. Mô hình bố cục

```dart
class ControlLayout {
  String id;
  String name;               // "Mặc định", "Thuận tay trái", ...
  int cols = 24, rows = 12;  // lưới tương đối, không tính theo pixel
  List<ControlItem> items;
}

class ControlItem {
  String id;
  ItemKind kind;     // stickH | stickV | stick2D | button | toggle | switch3 | knob
                     // | gauge (pin/dòng/tốc độ/ping/RSSI) | gearBox | trim | statusBadge
  int? channel;      // kênh điều khiển (1..10); stick2D có channelX + channelY
  int? channelY;
  String? gaugeKey;  // với kind = gauge
  int x, y, w, h;    // tính theo ô lưới
  ItemStyle style;   // xem H3
  ReturnConfig? returnCfg;   // chỉ cần gạt; xem H3b
}
```

- Vị trí và kích thước tính theo **ô lưới**, không theo pixel. Nhờ vậy cùng một bố cục hiển thị đúng tỉ lệ trên điện thoại nhỏ, điện thoại lớn và máy tính bảng.
- Mỗi hồ sơ xe (E1) có danh sách `layouts` và `activeLayoutId`. Bố cục đi cùng hồ sơ khi xuất/nhập (E8).
- Bố cục chỉ lưu trong điện thoại, **không ghi xuống xe**.

### H2. Chế độ "Sửa bố cục"

- Vào từ nút `adjustments-horizontal` ▸ **Sửa bố cục** trên màn Lái, hoặc từ thẻ hồ sơ (sửa được khi chưa nối xe, giống E4).
- Thao tác:
  - **Di chuyển:** kéo phần tử; phần tử tự bám vào lưới và hiện đường gióng khi thẳng hàng với phần tử khác.
  - **Đổi kích thước:** kéo tay nắm ở 4 góc. Mỗi loại có kích thước nhỏ nhất và lớn nhất riêng (bảng dưới).
  - **Chống chồng lấn:** phần tử không được đè lên nhau. Khi kéo vào vị trí đã có phần tử khác, khung chuyển đỏ và thả tay thì phần tử quay về chỗ cũ.
  - **Thêm:** mở ngăn "Thêm điều khiển". Ngăn này liệt kê các **loại phần tử** (B2, không giới hạn số lượng) và các ô đồng hồ đang ẩn. Phần tử mới ở trạng thái *Chưa gán kênh*; gán kênh trong bảng thuộc tính (H3).
  - **Xoá:** kéo phần tử vào thùng rác, hoặc bấm nút xoá trong bảng thuộc tính.
  - **Hoàn tác / Làm lại:** tối đa 30 bước.
  - **Lưu / Huỷ:** Huỷ thì bỏ mọi thay đổi từ lúc vào chế độ sửa.
- Trong chế độ sửa, các phần tử **không điều khiển xe**. Nền lưới hiện mờ để dễ căn.

| Loại | Nhỏ nhất (ô) | Lớn nhất (ô) |
|---|---|---|
| Cần gạt ngang | 6 × 2 | 24 × 4 |
| Cần gạt dọc | 2 × 6 | 4 × 12 |
| Cần 2 trục | 5 × 5 | 12 × 12 |
| Nút / nút bật tắt | 2 × 2 | 6 × 4 |
| Công tắc 3 nấc | 3 × 2 | 8 × 4 |
| Núm xoay | 3 × 3 | 6 × 6 |
| Ô đồng hồ / Trạng thái | 3 × 2 | 8 × 4 |
| Hộp số / Trim | 4 × 2 | 12 × 4 |

Ngoài giới hạn theo ô, mọi phần tử bấm được phải có vùng chạm **≥ 48 dp** trên màn thật. Nếu màn quá nhỏ khiến một ô nhỏ hơn 48 dp, app tự nâng kích thước nhỏ nhất của loại đó.

### H3. Bảng thuộc tính

Chọn một phần tử thì bảng thuộc tính mở ra ở cạnh màn:

| Thuộc tính | Áp dụng cho | Giá trị |
|---|---|---|
| Gán kênh | mọi phần tử điều khiển | *Chưa gán* hoặc CH1–CH10 (cần 2 trục: trục X, trục Y). Kênh đang ở phần tử khác thì chuyển sang. Gán thì kênh được bật |
| Giá trị khi tắt | nút, công tắc (đã gán kênh) | −100…+100% (`offValuePct` của kênh) |
| Nhãn | mọi phần tử | Tên kênh hoặc chữ tự đặt; hiện / ẩn |
| Icon | nút, công tắc | Chọn từ bộ Heroicons |
| Hiện giá trị | cần gạt, núm | % hoặc µs, hoặc ẩn |
| Kích thước núm cầm | cần gạt | Nhỏ / Vừa / Lớn |
| Tự về (spring) | cần gạt | Chỉnh chi tiết ở mục H3b |
| Vùng chết | cần gạt, núm | 0–20% |
| Rung khi chạm | nút, công tắc, cần gạt ở tâm | Bật / Tắt |
| Độ trong suốt | mọi phần tử | 30–100% |

### H3b. Cài đặt tự về của cần gạt

Mỗi cần gạt (ngang, dọc, và từng trục của cần 2 trục) có bộ cài đặt tự về riêng. Mặc định giữ hành vi hiện tại: thả tay là về 0%.

```dart
class ReturnConfig {
  ReturnMode mode;        // spring | hold | halfSpring
  double targetPct;       // vị trí sẽ về, mặc định 0 (−100…+100)
  int delayMs;            // chờ bao lâu sau khi thả tay mới bắt đầu về, mặc định 0
  int durationMs;         // thời gian chạy về, mặc định 0 = về ngay; tối đa 2000
  ReturnCurve curve;      // linear | easeOut
  bool positiveOnly;      // chỉ dùng khi mode = halfSpring: tự về khi cần ở nửa dương
  bool negativeOnly;      // chỉ dùng khi mode = halfSpring: tự về khi cần ở nửa âm
  bool rememberOnExit;    // chỉ dùng khi mode = hold: nhớ vị trí khi thoát, mặc định false
}
```

| Cài đặt | Giá trị | Tác dụng |
|---|---|---|
| **Chế độ** | **Tự về**: thả tay là về `targetPct` · **Giữ vị trí**: thả tay vẫn đứng nguyên (hợp ga tàu/thuyền, cần dâng ben) · **Về một nửa**: chỉ nửa dương hoặc nửa âm tự về (xem hai ô dưới) | Quyết định có tự về hay không |
| **Vị trí về** | −100…+100%, bước 1% (mặc định **0%**) | Ví dụ đặt 0% cho lái, hoặc −100% cho ga cần về hẳn mức thấp nhất |
| **Trễ trước khi về** | 0–1000 ms (mặc định 0) | Chống giật khi tay vừa nhấc lên rồi chạm lại |
| **Thời gian về** | 0–2000 ms (mặc định 0 = ngay lập tức) | Về từ từ, êm hơn, tránh servo giật mạnh hoặc xe xóc khi thả cần ga |
| **Đường về** | Tuyến tính · Chậm dần cuối | Cách tốc độ giảm khi gần đến vị trí về |
| **Chỉ tự về nửa dương / nửa âm** | Bật / Tắt | Ví dụ ga: nửa dương (tiến) tự về 0%, nửa âm (lùi) giữ nguyên; hoặc ngược lại |

Quy tắc:

- Bảng thuộc tính có **thanh xem trước**: kéo thử cần, thả ra và xem cần chạy về theo đúng cài đặt, chưa cần nối xe.
- Có nút **Cài đặt nhanh**: *Về 0% ngay* (mặc định) · *Về 0% êm* (300 ms, chậm dần) · *Giữ vị trí*.
- Khi vào màn Lái, cần đặt ở `targetPct` (chế độ Giữ vị trí thì đặt ở giá trị đã lưu lần trước nếu bật "Nhớ vị trí", ngược lại đặt ở `targetPct`).
- Mỗi cần gạt có công tắc **Nhớ vị trí khi thoát** (chỉ cho chế độ Giữ vị trí, mặc định tắt). Cần gạt ga thì cảnh báo nếu bật.
- **Ngoại lệ an toàn, không cài đặt nào thay đổi được:**
  - Mất kết nối hoặc failsafe kích hoạt: mọi kênh về `failsafeUs` của kênh, bỏ qua mọi cài đặt tự về.
  - Thoát màn Lái, vào chế độ sửa bố cục (H5), hoặc app xuống nền: cần gạt (vị trí trên màn) về `targetPct`. Riêng kênh ga cấu hình "Giữ vị trí" thì **bắt buộc về Center**.
  - Trong suốt chế độ sửa bố cục, **giá trị gửi xuống xe** của các kênh cần gạt là Center (H5), không phải `targetPct`. Thoát chế độ sửa thì gửi lại theo vị trí cần.
  - Cần gạt ga khi cài "Giữ vị trí" hoặc "Thời gian về" > 500 ms hiện cảnh báo: *"Xe có thể tiếp tục chạy sau khi thả tay"* trước khi lưu.
- Giá trị `targetPct` nằm ngoài [−100, +100] hoặc `positiveOnly` và `negativeOnly` cùng bật thì không cho lưu (E7).
- Kênh đã gắn luật mix (G) vẫn theo `targetPct` của kênh nguồn; mix tính trên giá trị sau tự về.

**Cấu hình mẫu**

| Mục đích | Chế độ | Vị trí về | Trễ | Thời gian về |
|---|---|---|---|---|
| Lái xe | Tự về | 0% | 0 | 0 (ngay) |
| Ga xe (tiến/lùi) | Tự về | 0% | 0 | 200 ms |
| Ga tàu/thuyền | Giữ vị trí | — | — | — |
| Ga chỉ tiến, lùi giữ | Về một nửa (nửa dương) | 0% | 0 | 0 |
| Cần dâng ben | Giữ vị trí | — | — | — |

### H4. Bố cục mẫu

| Mẫu | Mô tả |
|---|---|
| Mặc định | Giống màn Lái hiện tại: ga dọc trái, lái ngang phải, đồng hồ ở giữa |
| Thuận tay trái | Lật ngang bố cục mặc định |
| Tay cầm | Hai cần 2 trục ở hai góc dưới, nút kênh phụ ở giữa |
| Tối giản | Chỉ ga, lái và ô Ping; ẩn mọi ô đồng hồ khác |

- Nút **Lật ngang** áp được cho bất kỳ bố cục nào.
- **Khôi phục mặc định** có hỏi xác nhận.
- Một hồ sơ có nhiều bố cục (tạo mới, nhân bản, đổi tên, xoá). Đổi bố cục nhanh bằng cách nhấn giữ nút cấu hình trên màn Lái.

### H5. An toàn

- Chỉ vào được chế độ sửa khi **ga đang ở vị trí nghỉ**: cần ga đã thả và nằm đúng *Vị trí về* đã cài ở H3b (ví dụ −28%); ga "Giữ vị trí" hoặc gán vào phần tử không phải cần gạt thì vị trí nghỉ là 0%. Trong suốt thời gian sửa, app gửi giá trị Center cho mọi kênh cần gạt; nút bật/tắt giữ trạng thái đang có.
- Mọi bố cục bắt buộc có một phần tử gán cho kênh Ga và một cho kênh Lái. Thiếu thì không cho lưu.
- Phần tử không được đặt vào vùng cử chỉ hệ thống (mép màn, tai thỏ). App tính theo `MediaQuery.viewPadding` và `systemGestureInsets`.
- Có công tắc **Khoá bố cục** (mặc định bật) để không vô tình vào chế độ sửa khi đang lái.

**Lỗi đã sửa trong sprint**

| Mã | Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|---|
| H5-1 | Đặt *Vị trí về* của cần ga khác 0% (vd −28%) thì không bao giờ vào được **Sửa bố cục**, luôn báo *"Trả ga về 0 trước khi sửa bố cục"* | Điều kiện H5 so ga với 0% cứng, trong khi ga lúc thả tay nằm ở `targetPct` | So với vị trí nghỉ `ReturnMotion.restPct(layout, CH2)` (= `onExit` của trục gán kênh Ga). Báo lỗi đổi thành *"Thả cần ga trước khi sửa bố cục"*. Sửa ở `control_screen.dart`, `return_motion.dart`, `preview/ui_preview.html`; test ở `layout_test.dart` |

### H6. Hiển thị trên nhiều cỡ màn

- Lưới 24 × 12 được co giãn theo vùng an toàn của màn Lái (luôn nằm ngang).
- Tỉ lệ màn khác 2:1 thì ô lưới không vuông. Cần 2 trục và núm xoay vẫn giữ hình tròn, căn giữa trong khung của nó.
- Trên máy tính bảng, lưới giữ nguyên và các phần tử to theo.

### H7. Liên quan tới các nhóm khác

- **Thay B6.** Hàng nút kênh phụ cố định ở B6 không còn; kênh phụ được gán vào phần tử như mọi kênh khác. Bố cục mẫu chỉ xếp sẵn Ga/Lái (và Đèn/Còi với mẫu hồ sơ "Xe có đèn/còi").
- **B2 / B4.** Mỗi kênh có tối đa **một** phần tử điều khiển trên một bố cục. Gán kênh đã có trên màn cho phần tử khác thì kênh được chuyển sang phần tử đó.
- **A5.** Phần làm lại màn Lái được làm trên nền bố cục mới.
- **F6 / G7.** Ô Ping và chấm báo mix hiện đúng trên phần tử tương ứng, dù phần tử đó nằm ở đâu.

### H8. Test

- Unit test: bám lưới, chống chồng lấn, giới hạn kích thước, lật ngang, chuyển bố cục cũ sang mới.
- Unit test tự về (H3b): về đúng `targetPct`; trễ và thời gian về đúng mili-giây; nửa dương/nửa âm; Giữ vị trí không tự về; failsafe và thoát màn luôn ghi đè cài đặt.
- Widget test: cùng một bố cục hiển thị trên 3 cỡ màn (16:9, 20:9, 4:3), không phần tử nào ra ngoài vùng an toàn và mọi vùng chạm đều ≥ 48 dp.
- Test thật: vào/thoát chế độ sửa khi đang nối xe, `fake_car.py` phải nhận ga = Center suốt thời gian sửa.

**Tiêu chí nghiệm thu nhóm H**

- [ ] Kéo cần ga sang phải, phóng to cần lái, lưu, thoát app rồi mở lại: bố cục giữ nguyên.
- [ ] Hai phần tử không chồng lên nhau được; phần tử không nhỏ hơn giới hạn.
- [ ] Bố cục làm trên điện thoại 6" mở trên máy tính bảng vẫn đúng vị trí tương đối.
- [ ] Không vào được chế độ sửa khi đang giữ cần ga (ga khác vị trí nghỉ).
- [ ] Cần ga đặt "Vị trí về = −28%": thả tay rồi bấm **Sửa bố cục** thì vào được (lỗi H5-1).
- [ ] Đặt cần lái "Vị trí về = 0%, thời gian về 300 ms": thả tay thì cần trượt êm về 0% trong 0,3 s và `fake_car.py` nhận giá trị giảm dần tương ứng.
- [ ] Đặt cần ga "Giữ vị trí": thả tay cần đứng nguyên; mất sóng thì xe vẫn về failsafe, thoát màn thì ga về Center.

---

## 6. Nhóm C — Giao thức và phần cứng

### C1. Định dạng gói (đề xuất)

Mọi gói đều có header 4 byte:

| Byte | Trường | Giá trị |
|---|---|---|
| 0–1 | `magic` | `0x52 0x43` ("RC") |
| 2 | `version` | `0x02` (sprint này) |
| 3 | `type` | xem bảng dưới |

| `type` | Tên | Hướng | Payload |
|---|---|---|---|
| `0x01` | CONTROL | App → Xe | `seq:u16` · `ch[10]:u16` (µs, little-endian) → 22 byte |
| `0x02` | TELEMETRY | Xe → App | pin, dòng, tốc độ, RSSI, cờ failsafe (như hiện tại) |
| `0x10` | PING | App → Xe | `seq:u16` · `t_send:u32` (ms) |
| `0x11` | PONG | Xe → App | `seq:u16` · `t_send:u32` · `uptime:u32` |
| `0x12` | IDENTIFY | App → Xe | `duration_ms:u16` |
| `0x20` | FS_WRITE | App → Xe | `timeout_ms:u16` · `fs[10]:u16` (µs) · `crc16` → 24 byte |
| `0x21` | FS_ACK | Xe → App | `status:u8` · `hash:u32` |

- `CONTROL` mang giá trị **cuối cùng** của 10 kênh (đã qua mix, trim, reverse, kẹp Min/Max ở app). Đây là dữ liệu duy nhất gửi liên tục khi lái.
- Không có gói đọc/ghi cấu hình kênh, hộp số hay mix (0.5). `FS_WRITE` là gói cấu hình duy nhất.
- `hash` trong `FS_ACK` tính trên đúng dữ liệu failsafe nhận được, để app so với `hashFailsafe` (E5).
- **Tương thích ngược:** gói không có `magic` được coi là giao thức v1 (2 kênh, xe tự áp trim/servo như cũ). App phát hiện firmware cũ, chỉ cho lái 2 kênh và báo *"Firmware xe cần cập nhật để dùng 10 kênh/mix"*.
- Nhịp gửi CONTROL giữ như hiện tại.

### C2. Firmware ESP32

- Xuất 10 kênh PWM 50 Hz (dùng LEDC). **Sơ đồ chân cần chốt**; nếu thiếu chân thì dùng mạch mở rộng **PCA9685** (I²C, 16 kênh).
- Nhận `CONTROL` và xuất thẳng giá trị µs ra PWM; chỉ kẹp an toàn 500–2500 µs. **Không** chạy mix, không có trim/Min/Max/reverse (0.5).
- Failsafe riêng cho từng kênh; timeout theo `failsafeTimeoutMs`. Nhận qua `FS_WRITE`, lưu **NVS** để khởi động lại vẫn dùng được.
- Chưa từng đồng bộ (NVS trống): failsafe mặc định 1500 µs cho mọi kênh, timeout 400 ms.
- Từ lúc bật nguồn tới khi nhận `CONTROL` đầu tiên: xuất failsafe.
- Trả lời PING (F2).
- **LED trạng thái:** 1 chân GPIO rời (nằm trong phần "sơ đồ chân cần chốt" ở trên), tách khỏi 10 kênh PWM.

| Trạng thái | Kiểu nháy |
|---|---|
| Chưa kết nối | Tắt |
| Đã kết nối, ổn định | Sáng liên tục |
| Kết nối yếu (ứng với dải vàng F6) | Nháy chậm (1 Hz) |
| Failsafe / mất kết nối | Nháy nhanh (4 Hz) liên tục tới khi hết failsafe |
| Đang "Tìm xe" (IDENTIFY) | Nháy nhanh (8 Hz) trong 3 s, đè lên trạng thái trên rồi trả lại |

### C3. Đồng bộ failsafe

Xem E6. Không còn đọc/ghi cấu hình khác.

### C4. `fake_car.py`

- Hỗ trợ giao thức v2: 10 kênh `CONTROL`, `FS_WRITE`/`FS_ACK`, PING/PONG, IDENTIFY. Không chạy mix.
- Thêm cờ `--no-ack` để thử nhánh lỗi đồng bộ failsafe (E6).
- Thêm cờ `--delay`, `--jitter`, `--loss` (F7) và `--legacy` (giả lập firmware v1).

---

## 7. Nhóm D — Kiểm thử và bàn giao

| Mục | Nội dung |
|---|---|
| D1 | Unit test: kênh (gán, reverse, kẹp Min/Max, chống trùng), đường tính giá trị gửi đi (B1), hồ sơ (E9), mix (G10), ping (F9) |
| D2 | Test trên PC (Windows) với `fake_car.py`: 2 theme, mọi loại phần tử điều khiển, đồng bộ failsafe, ping |
| D3 | Test thật: Android + ESP32; WiFi và BLE; rút nguồn phát giữa chừng để thử failsafe; thử luật mix CH1 → CH3 |
| D4 | Cập nhật trang mockup: 2 theme, thêm các màn Xe của tôi, Tạo xe, Kênh, Mix, Chẩn đoán |

---

## 8. Thứ tự thực hiện

```
A1 → A2 → A3
→ E1 → B1 → B2 → G1
→ E2 → E3 → E4
→ B3 → B4 → B5 → G2 → G5 → G6 → E7
→ C1 + F1
→ C2 + F2
→ G3 + G4 (mix trong vòng gửi của app)
→ F3 → F4
→ E5 → E6 (đồng bộ failsafe)
→ H1 → H2 → H3 → H5 → B6 → H4 → H6
→ G7 → F6
→ C4 + F7 + G9
→ F5
→ A4 → A5 → A6 → A7
→ E8 → F8
→ D1…D4 + E9 + F9 + G10 + H8
```

Mọi bước trước `C1` đều làm và test được trên PC, không cần xe.

---

## 9. Cấu trúc file dự kiến

```
app/lib/
  theme/        app_theme.dart, tokens.dart, app_icons.dart, theme_controller.dart
  models/       car_profile.dart, channel_config.dart, mix_rule.dart, ping_config.dart,
                control_layout.dart
  data/         profile_repository.dart, profile_migration.dart
  protocol/     protocol.dart (Sprint 4 tách: packet.dart, packet_codec.dart, failsafe_codec.dart)
  transport/    transport.dart, udp_transport.dart, ble_transport.dart
  controller/   car_controller.dart
  services/     ping_service.dart, quick_ping.dart, failsafe_sync.dart (Sprint 4),
                mix_engine.dart, output_pipeline.dart (B1)
  screens/      garage_screen.dart (Xe của tôi), profile_wizard_screen.dart,
                control_screen.dart, settings_screen.dart, channel_detail_screen.dart,
                mix_rule_screen.dart, diagnostics_screen.dart (Sprint 4)
  widgets/      channel_tile.dart, mix_rule_card.dart, mix_preview.dart, number_field.dart,
                status_badge.dart, ping_tile.dart
  layout/       layout_canvas.dart (hiển thị + chế độ sửa), layout_grid.dart, item_widgets.dart,
                properties_panel.dart, layout_templates.dart, layout_history.dart, return_motion.dart
app/assets/
  fonts/        Barlow-Regular/Medium/SemiBold/Bold/ExtraBold.ttf
  icons/        bluetooth.svg, car.svg, speedometer.svg, steering.svg
app/test/       profile_test.dart, mix_engine_test.dart, output_pipeline_test.dart, layout_test.dart,
                ping_window_test.dart, widget_test.dart
firmware/src/   protocol.*, channels.* (xuất PWM), failsafe_store.* (NVS)
tools/          fake_car.py
tests/          mix_vectors.json (Sprint 4, G10)
```

---

## 10. Việc cần chốt

| # | Câu hỏi | Ảnh hưởng |
|---|---|---|
| 1 | ~~Mã màu gốc của mẫu Figma~~ Đã có: bảng Green/Grey, font Barlow, icon Heroicons | A1, A2 |
| 2 | ~~Một sprint hay chia hai~~ Đã chốt: chia hai theo mục 0.4 | Kế hoạch |
| 3 | Sơ đồ chân ESP32 cho 10 kênh; có dùng PCA9685 không | C2 |
| 4 | ~~Nút/công tắc tắt = −100% hay 0%~~ Đã chốt: chỉnh được theo %, mặc định −100% (`offValuePct`, xem B1) | B1, G2 |
| 5 | ~~Có làm F8 "Tìm xe" không~~ Đã chốt: có làm, dùng 1 LED trạng thái trên xe (bỏ còi) — xem F8, C2 | F8 |
| 6 | ~~Lưới 24 × 12 bám ô, hay cho đặt tự do từng pixel~~ Đã chốt: bám ô 24 × 12 (xem H1, H6) | H1, H2 |
| 7 | ~~Mix và cấu hình kênh chạy trên xe hay trên app~~ Đã chốt: xe chỉ nhận dữ liệu điều khiển 10 kênh; cấu hình và mix do app giữ và tính; khi kết nối chỉ đồng bộ failsafe (xem 0.5, E6) | E4–E6, G3, G8, C1–C4 |
| 8 | Chuyển sang mô hình Input → Condition → Mixer: đã chốt làm ở Sprint 4, xem `dac_ta_sprint_4_mixer.md` | B, G, H3 |
