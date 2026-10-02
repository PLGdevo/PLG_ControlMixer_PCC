# Đặc tả tổng hợp — PCC TX Control (`rc_car`)

> App Flutter điều khiển xe RC + firmware ESP32-S3. Gộp toàn bộ các đặc tả sprint thành một file, khớp với code hiện tại.
>
> Phiên bản: **2.0** · Ngày: 02/10/2026 · Dự án: `rc_car` (app Flutter + firmware ESP32-S3 + `tools/fake_car.py`)
>
> **Gộp từ:** `dac_ta_sprint_3.md` (v1.2) · `dac_ta_sprint_4_mixer.md` (v1.1) · `dac_ta_wifi_3_che_do.md` (v1.0), cùng các thay đổi đã làm sau đó (26/09 – 30/09/2026). Hai file Sprint 3 và Sprint 4 đã xoá (xem lại bằng `git show 6fba01f:<tên file>`). Mã mục giữ như cũ ở chỗ còn cùng nội dung; mã cũ mà comment trong code còn nhắc tới thì tra ở mục 20.
>
> **Ký hiệu trạng thái:** ✅ đã làm · 🟡 đã làm, chưa thử trên xe/máy thật · ⬜ chưa làm · ❌ đã bỏ

---

## Mục lục

0. [Tổng quan](#0-tổng-quan)
1. [Nhóm A — Giao diện](#1-nhóm-a--giao-diện)
2. [Nhóm E — Hồ sơ xe và chọn xe](#2-nhóm-e--hồ-sơ-xe-và-chọn-xe)
3. [Nhóm I — Input](#3-nhóm-i--input)
4. [Nhóm K — Condition](#4-nhóm-k--condition)
5. [Nhóm M — Mixer](#5-nhóm-m--mixer)
6. [Nhóm O — Kênh và đầu ra](#6-nhóm-o--kênh-và-đầu-ra)
7. [Nhóm R — Kết nối và ARM](#7-nhóm-r--kết-nối-và-arm)
8. [Nhóm H — Màn Lái và bố cục](#8-nhóm-h--màn-lái-và-bố-cục)
9. [Nhóm F — Ping và chất lượng tín hiệu](#9-nhóm-f--ping-và-chất-lượng-tín-hiệu)
10. [Nhóm C — Giao thức](#10-nhóm-c--giao-thức)
11. [Nhóm W — WiFi 3 chế độ](#11-nhóm-w--wifi-3-chế-độ)
12. [Nhóm FW — Firmware ESP32-S3](#12-nhóm-fw--firmware-esp32-s3)
13. [Nhóm V — Kiểm tra dữ liệu](#13-nhóm-v--kiểm-tra-dữ-liệu)
14. [Nhóm J — Dữ liệu hồ sơ và chuyển đổi](#14-nhóm-j--dữ-liệu-hồ-sơ-và-chuyển-đổi)
15. [Mã nguồn](#15-mã-nguồn)
16. [Kiểm thử](#16-kiểm-thử)
17. [Tiêu chí nghiệm thu](#17-tiêu-chí-nghiệm-thu)
18. [Việc còn mở](#18-việc-còn-mở)
19. [Các quyết định đã chốt](#19-các-quyết-định-đã-chốt)
20. [Tra mã mục cũ](#20-tra-mã-mục-cũ)

---

## 0. Tổng quan

### 0.1 Mục tiêu

1. App phong cách tối theo mẫu Figma *Digital Agency (Dark Theme)*, có giao diện sáng, **song ngữ Việt/Anh**, chọn màu chủ đạo.
2. Người dùng tạo và quản lý **hồ sơ xe**, chọn xe như chọn model trên tay RC. Cấu hình điều khiển **chỉ nằm trong app**; khi nối xe, app chỉ đồng bộ **failsafe**.
3. Mô hình điều khiển **Input → Condition → Mixer → Kênh → ARM**: UI chỉ tạo Input; luật mix quyết định Input đi vào kênh nào.
4. Xe có **8 kênh PWM**; app tính sẵn giá trị µs và gửi qua giao thức n kênh.
5. Màn Lái **tự sắp xếp**: phần tử điều khiển và phần tử hiển thị đặt tự do trên lưới, kiểu tay RC.
6. **Ping và chất lượng tín hiệu (LQ)** chạy ngầm, cảnh báo "Tín hiệu yếu".
7. Xe có **3 chế độ mạng** (AP / Router / Cấu hình), chỉnh trong app.

### 0.2 Kiến trúc

```
 Bố cục màn Lái (H)          Hồ sơ (JSON, schemaVersion 2)
 ControlItem ──bind──┐          │
                     ▼          ▼
               INPUT MANAGER  ◄─ inputs[]                     (I)
                     │  trạng thái + % của từng Input
                     ▼
              CONDITION ENGINE ◄─ conditions[] (có hysteresis)  (K)
                     │  đúng / sai cho từng luật
                     ▼
               MIXER ENGINE   ◄─ mixer[] (priority, combine, khoá an toàn)  (M)
                     │  CH1…CH10 (%, −100…+100)
                     ▼
               CHANNEL STAGE  ◄─ channels[] (reverse, trim, offset, Min/Center/Max)  (O)
                     │  CH1…CH10 (µs)
                     ▼
                ARM GATE      ◄─ trạng thái kết nối / ARM  (R)
                     │  chưa ARM → gửi failsafeUs
                     ▼
              CONTROL_US (cắt còn số kênh của xe, 8) ─► UDP / BLE ─► ESP32-S3 ─► PWM CH1…CH8
```

- Cả chuỗi chạy trong app. Nhịp gửi theo đường truyền: **WiFi 10 ms (100 Hz)**, **BLE 20 ms (50 Hz)** (`CarTransport.controlPeriod`).
- Xe chỉ xuất µs ra PWM, giữ failsafe, đo pin/tốc độ và trả telemetry 10 Hz.

### 0.3 Nguyên tắc: app giữ cấu hình, xe chỉ nhận lệnh kênh

| | App | Xe (ESP32-S3) |
|---|---|---|
| Input, Condition, luật mix | Lưu trong hồ sơ, **tính trong app** | Không có |
| Cấu hình kênh (Min/Center/Max, trim, offset, reverse) | Lưu trong hồ sơ, tính trong app | Không có |
| Bố cục màn Lái | Lưu trong hồ sơ | Không có |
| Failsafe (`failsafeUs` từng kênh, `failsafeTimeoutMs`) | Chỉnh trong app | **Nhận khi kết nối** (`FS_WRITE`), lưu NVS, tự áp khi mất sóng |
| Dữ liệu gửi khi lái | µs **cuối cùng** của từng kênh | Xuất thẳng ra PWM (kẹp an toàn 500–2500 µs) |
| **Ngoại lệ 1:** cấu hình mạng (WiFi, IP, port, tên) | Chỉnh qua màn Mạng của xe | **Lưu trên xe** (NVS `rcnet`) vì xe cần lúc khởi động; hồ sơ xuất ra file không mang mật khẩu |
| **Ngoại lệ 2:** tinh chỉnh xuất xung (làm mượt, tần số PWM, vùng chết) | — | Lưu trên xe, chỉnh qua lệnh Serial (FW4) |

- Mọi thay đổi cấu hình có tác dụng ở chu kỳ gửi tiếp theo; không có bước "ghi cấu hình xuống xe".
- Failsafe phải nằm trên xe vì khi mất sóng app không gửi được gì.
- Đánh đổi: mix chạy ở app nên chịu độ trễ sóng; mất sóng thì xe về failsafe, không có trạng thái mix "treo" trên xe.

### 0.4 Lịch sử

| Giai đoạn | Nội dung chính | Commit |
|---|---|---|
| Trước Sprint 3 | App 2 kênh (ga dọc trái, lái ngang phải), màn Kết nối, Cấu hình servo chỉ dùng khi nối xe; xe tự áp trim/servo/hộp số | — |
| Sprint 3 | Theme Figma, hồ sơ xe, 10 kênh, gán phần tử 1:1, mix 4 loại, bố cục tuỳ chỉnh, ping | — |
| Sprint 4 | Input → Condition → Mixer → ARM, schemaVersion 2, migration v1→v2 | `158b0c7`, `03d54d8` |
| WiFi 3 chế độ | AP / Router / Cấu hình, màn Mạng của xe, DISCOVER/HERE | `74b720a` |
| 26/09 | Kênh Ga/Lái do người dùng chọn, mẫu "Trống"; song ngữ, màu chủ đạo; bỏ hộp số, ARM bật/tắt; firmware 8 kênh; giao thức n kênh | `d9499f1`, `28678b7`, `7905cac` |
| 26–28/09 | Phần tử hiển thị đọc nguồn dữ liệu; tai thỏ, chỉnh trực tiếp khi đang nối, lưới 48×24 | `e871171` |
| 28–30/09 | Chọn xe kiểu TX, LQ, phần tử kiểu TX, làm mượt servo | `6fba01f` |

### 0.5 Những gì đặc tả cũ đã bị thay

| Đặc tả cũ | Hiện tại |
|---|---|
| Xe 10 kênh (Sprint 3 C2) | Xe **8 kênh** (ESP32-S3 có đúng 8 kênh LEDC). Hồ sơ app vẫn có 10 kênh; giao thức cho tới 16; app cắt theo số kênh xe báo trong INFO |
| Gói v2 header `"RC"` + version (Sprint 3 C1) | Giữ khung cũ `[0xAA][type][len][payload][crc8]`, thêm `CONTROL_US` / `INFO` / `FS_WRITE` / `FS_ACK` (C2) |
| PING/PONG/IDENTIFY ở `0x10–0x12` | `0x30–0x32` (vì `0x10–0x14` đã là CONFIG_*) |
| Hộp số (`GearConfig`, `gearBox`, giới hạn ga theo số) | ❌ **Bỏ.** Muốn giới hạn ga thì hạ Max của kênh ga |
| Ga/Lái cố định CH2/CH1 | Do người dùng chọn theo hồ sơ (`throttleCh`, `steeringCh`), có thể để trống |
| ARM bắt buộc, giữ nút 1 s | ARM **bật/tắt được** (`ArmConfig.enabled`); tắt thì tự lái khi thả ga |
| Tab Cấu hình: Ga · Lái · Kênh · Mix · Chung → Ga · Lái · Input · Mix · Kênh · Chung | **Input · Mix · Kênh · Chung · Bố cục** (bỏ tab Ga/Lái riêng) |
| Lưới 24 × 12, có kích thước lớn nhất | Lưới **48 × 24**, không giới hạn lớn nhất (dừng ở phần tử bên cạnh) |
| Ô đồng hồ có `gaugeKey` | Phần tử hiển thị đọc **nguồn dữ liệu** (`source`, `sourceY`) |
| Chạm 1 lần mở bảng thuộc tính | **1 chạm = chọn**, **2 chạm = mở bảng thuộc tính** |
| Nhịp gửi 25 ms / 40 Hz | WiFi 10 ms, BLE 20 ms |
| Ô Ping đổi màu theo ngưỡng, dải "Kết nối yếu" sau 3 s đỏ | LQ % + ping; "Tín hiệu yếu" trên tai thỏ khi LQ < 70% hoặc ping > 200 ms |
| LED trạng thái 1 GPIO đơn sắc | LED RGB WS2812 trên board, màu theo chế độ + kiểu nháy (FW5) |
| Màn mở app "Xe của tôi" | Tiêu đề **"PCC TX Control"** (màn chính); nhãn launcher vẫn là "RC Controller" |
| Nút Kết nối / Sửa / Kiểm tra / Lái trên thẻ xe | Bấm thẻ → vào màn Lái (tự nối); bỏ nút Kiểm tra và Lái trên thẻ |

### 0.6 Phạm vi

| Trong phạm vi | Ngoài phạm vi |
|---|---|
| App Flutter: Android (chính), Windows (để test) | iOS (có khai báo quyền nhưng không test) |
| Firmware ESP32-S3 (UDP + BLE chạy song song) | Tay điều khiển vật lý, gamepad |
| `tools/fake_car.py` (UDP) | Giả lập BLE |
| Input từ phần tử trên màn và Input hằng số | Input từ cảm biến điện thoại, GPS, telemetry |
| | UART, MAVLink, SBUS/CRSF |

---

## 1. Nhóm A — Giao diện

### A1. Theme tối theo Figma ✅

Code ở `app/lib/theme/`: `tokens.dart` (màu, bo góc, khoảng cách), `app_theme.dart` (`ThemeData`), `app_icons.dart`, `theme_controller.dart`.

**Bảng màu gốc**

| Nhóm | Mã |
|---|---|
| Tuyệt đối | White `#FFFFFF` · Black `#000000` |
| Green (thương hiệu) | 50 `#9EFF00` · 60 `#B1FF33` · 70 `#C5FF66` · 80 `#D8FF99` · 90 `#ECFFCC` · 95 `#F5FFE5` · 97 `#F9FFF0` · 99 `#FDFFFA` |
| Grey | 10 `#191919` · 15 `#262626` · 20 `#333333` · 30 `#4C4C4D` · 35 `#59595A` · 40 `#656567` · 60 `#98989A` · 90 `#E6E6E6` |

**Token theo theme** (theme chỉ dùng token, không dùng mã màu trực tiếp)

| Token | Tối | Sáng | Dùng cho |
|---|---|---|---|
| `bg` | Grey 10 | Green 99 | Nền màn |
| `surface` | Grey 15 | White | Thẻ, app bar, thanh nút dưới |
| `surface2` | Grey 20 | Green 97 | Thẻ lồng, rãnh slider, ô nhập |
| `line` | Grey 20 | Grey 90 | Viền 1px |
| `text` | White | Grey 10 | Chữ chính, số đo |
| `textBody` | Grey 90 | Grey 30 | Đoạn văn |
| `textMuted` | Grey 60 | Grey 35 | Nhãn phụ, đơn vị |
| `disabled` | Grey 35 | Grey 60 | Chữ/icon bị mờ |
| `accent` | Green 50 | `#3D6600` * | Chữ/icon nhấn, tab đang chọn, viền thẻ chọn |
| `accentFill` / `accentFillPressed` | Green 50 / 60 | Green 50 / 60 | Nền nút chính, thumb slider |
| `onAccentFill` | Grey 10 | Grey 10 | Chữ trên nút chính |
| `accentContainer` / `onAccentContainer` | `#9EFF00` @12% / Green 70 | Green 90 / Grey 10 | Nền mục đang chọn |
| `ok` / `warn` / `bad` / `idle` | `#4CAF50` / `#FFC107` / `#F44336` / Grey 60 | `#2E7D32` / `#B26A00` / `#C62828` / Grey 35 | Huy hiệu trạng thái |

\* Green 50 trên nền trắng chỉ ≈ 1.3:1; `#3D6600` đạt ≈ 6.8:1. Huy hiệu trạng thái luôn có chữ đi kèm vì xanh thương hiệu dễ lẫn với `ok`.

**Kiểu chữ:** font **Barlow** (400/500/600/700/800), đóng gói TTF trong `assets/fonts/` (app dùng ngoài bãi, không có mạng). Số đo bật `tabularFigures`.

| Kiểu | Cỡ / độ đậm | Dùng cho |
|---|---|---|
| `display` | 32 / ExtraBold | Số lớn |
| `headline` | 24 / Bold | Tiêu đề màn |
| `title` | 18 / SemiBold | Tiêu đề thẻ, tên xe |
| `body` | 15 / Regular | Nội dung |
| `label` | 14 / Medium | Nút, tab |
| `caption` | 12 / Medium, chữ hoa, giãn 0.08em | Nhãn phụ ô đồng hồ |
| `metric` | 18 / Bold, số đều | V, A, km/h, ms |

**Hình khối:** nút chính viên thuốc (bo 999) nền `accentFill`; nút phụ viên thuốc viền `line`; thẻ bo 16, viền `line`, không bóng; khoảng cách lưới 4 (4/8/12/16/24/32).

**Icon:** Heroicons v2 (Outline 24 mặc định, Solid khi bật/chọn, Mini 20 trong nút nhỏ). Bốn icon tự vẽ theo quy cách Heroicons trong `assets/icons/`: `bluetooth.svg`, `car.svg`, `speedometer.svg`, `steering.svg`.

### A2. Theme sáng ✅

- Cột "Sáng" ở bảng token. Nền hơi ngả xanh (Green 99), thẻ trắng.
- Green 50 không dùng làm màu chữ trên nền sáng; chỉ làm nền nút chính và thumb slider.

### A3. Chuyển giao diện và màu chủ đạo ✅

- 3 lựa chọn **Tối / Sáng / Theo hệ thống**, mặc định Tối; lưu `shared_preferences`, áp ngay (`theme_controller.dart`).
- `AccentColor` (trong `tokens.dart`); `AppTokens.of(accent, brightness)`. Lime = token gốc.
- **Màu app:** không có đỏ/vàng (trùng `bad`/`warn`) — `AccentColor.appChoices`.
- **Màu riêng từng phần tử** trên màn Lái: `ItemStyle.color` (null = màu app), được dùng cả đỏ/vàng. `LayoutCanvas` bọc phần tử trong `Theme(AppTheme.of(color, brightness))` (có cache).

### A4. Song ngữ Việt/Anh ✅

- Mọi chuỗi giao diện viết `tr('tiếng Việt', 'English')` (`lib/l10n/lang.dart`, `LangController.instance`, mặc định VN). Enum dùng `_vi/_en` + `label => tr(...)`.
- Đổi ngôn ngữ dựng lại cả cây widget (`RcApp._relabel`), màn đang mở cập nhật ngay.
- Tên mặc định trong dữ liệu giữ tiếng Việt ("Kênh N"); hiển thị qua `ChannelConfig.displayName` / `hasDefaultName`, không so tên với chuỗi đã dịch.
- Nút VN/EN dạng viên thuốc cạnh nút ⚙ trên màn chính.

### A5. Cài đặt app ✅

`app_settings_screen.dart`, mở từ ⚙ trên màn chính: Ngôn ngữ · Giao diện (Tối/Sáng/Hệ thống) · Màu chủ đạo.

### A6. Màn hình nằm ngang ✅

- Người dùng cầm điện thoại ngang. Màn Cấu hình **không ép dọc**.
- Chiều cao < 500 (`_isCompact`): Lưu / Đồng bộ failsafe / Mặc định lên AppBar, TabBar cao 40, thanh dưới chỉ còn một dòng lỗi.
- Mọi màn mới phải test ở 800 × 360.

### A7. Ô −/+ giữ để lặp ✅

`HoldRepeat` (`widgets/hold_repeat.dart`): giữ nút −/+ thì lặp, giữ lâu thì tăng ×5 (`NumberField`). Trim trên màn Lái lưu trễ 250 ms, lưu ngay trước khi mở Cấu hình / sửa bố cục / thoát.

### A8. Không bật hộp thoại khi đang lái ✅

- Khi xe đang ARMED: không có hộp thoại/bảng che màn Lái, không có cử chỉ nhấn giữ mở bảng (bảng xem luật mix, chọn mục tai thỏ…) — chỉ mở được khi DISARMED.
- Ngoại lệ có chủ ý: bảng trim nổi ở góc (H10) vì không che màn và không phải modal.
- Mọi tính năng mới trên màn Lái phải có test "ARM → không bật".

### A9. Độ tương phản ⬜ (chưa kiểm tra đầy đủ)

Chữ thường ≥ 4.5:1, chữ lớn và icon ≥ 3:1, cả hai theme; kiểm tra riêng chữ phụ, nút mờ, huy hiệu.

---

## 2. Nhóm E — Hồ sơ xe và chọn xe

### E1. Mô hình hồ sơ ✅

```dart
class CarProfile {                 // schemaVersion 2
  String id;                       // uuid
  String name;                     // 1–32 ký tự, không trùng
  String? icon;
  ConnType connType;               // wifi | ble
  WifiConn? wifi;                  // ip, port, ssid?, carId? (MAC gốc của xe, W4)
  BleConn? ble;                    // mac, deviceName
  List<InputDef> inputs;           // I1, ≤ 48
  List<ConditionDef> conditions;   // K3, ≤ 32
  List<MixRule> mixer;             // M1, ≤ 64
  List<ChannelConfig> channels;    // đúng 10 phần tử (O1)
  int? throttleCh, steeringCh;     // vai trò Ga / Lái (O5); vắng mặt trong JSON → 2 / 1
  int failsafeTimeoutMs;
  ArmConfig arm;                   // enabled, autoArm, armCondition? (R)
  OutputConfig output;             // protocol, periodMs
  PingConfig ping;
  List<String> statusItems;        // mục trên tai thỏ (H9), mặc định link·battery·rssi, ≤ 6
  List<ControlLayout> layouts;     // H1
  String activeLayoutId;
  DateTime updatedAt;
  DateTime? lastSyncedAt;          // lần đồng bộ failsafe gần nhất
  String? lastSyncedHash;          // hash failsafe lúc đồng bộ (E5)
  DateTime? lastConnectedAt;
}
```

- Mỗi hồ sơ một file `profiles/<id>.json` trong thư mục dữ liệu app, có `schemaVersion`.
- `ProfileRepository`: `list`, `get`, `save`, `delete`, `duplicate`, `exportToFile`, `import`, `selectedId` / `select`. `save` xếp hàng ghi theo từng hồ sơ và chụp dữ liệu tại lúc gọi.

### E2. Màn chính "PCC TX Control" ✅ 🟡

- Danh sách thẻ hồ sơ: tên, icon, kiểu kết nối (IP:port hoặc tên BLE), "Kết nối lần cuối".
- **Chọn xe kiểu TX (model select):** xe đang chọn nằm đầu danh sách, nhãn *Đang chọn*; xe khác có nút **Chọn xe**. Lưu ở `profiles/selected.txt`; mặc định là xe nối gần nhất. Nối xe nào thì xe đó thành xe đang chọn.
- Mở app tự nối xe đang chọn (`autoConnect`; tắt trong test).
- **Bấm thẻ → vào màn Lái** (`ControlScreen(connectOnOpen: true)`), tự kết nối; nối lỗi thì vẫn ở màn Lái với nút *Kết nối / Nối lại*.
- Menu ⋮: Sửa · Đổi tên · Nhân bản · Xuất · Xoá.
- Nút nổi **+ Tạo xe mới**; chưa có hồ sơ thì hiện màn trống kèm nút tạo.
- Đã bỏ: nút Kiểm tra (ping) và nút Lái trên thẻ.
- Mọi đường nối xe đi qua `CarConnector.connect` để giữ đúng xe đang chọn. `connKey` gồm cả mã hồ sơ, nên hai hồ sơ cùng IP (AP `192.168.4.1`) không cùng hiện "Đã kết nối".

### E3. Tạo xe mới (3 bước) ✅

| Bước | Nội dung |
|---|---|
| 1 | Tên xe; WiFi hoặc Bluetooth |
| 2 | **WiFi:** IP (mặc định `192.168.4.1`), port (mặc định `4210`), SSID tuỳ chọn, nút **Tìm xe** (dò trong mạng, W5) · **BLE:** quét 6 s lọc theo service UUID, hoặc nhập MAC/tên · nút **Kiểm tra** (ping nhanh F4) |
| 3 | Mẫu khởi đầu: **Trống** (mặc định) · Xe cơ bản 2 kênh · Xe có đèn/còi · Sao chép từ xe khác |

| Mẫu | Nội dung |
|---|---|
| Trống | Không có Input, luật mix hay vai trò Ga/Lái; người dùng tự thêm phần tử và gắn vào kênh |
| Xe cơ bản 2 kênh | Lái → CH1, Ga → CH2 |
| Xe có đèn/còi | Như trên + Đèn (CH3, bật/tắt) + Còi (CH4, nhấn giữ) |
| Sao chép từ xe khác | Lấy Input, mix, kênh, ARM, bố cục của một xe có sẵn |

Bước 2 cho lưu dù kiểm tra thất bại (xe có thể đang tắt), có cảnh báo.

### E4. Cấu hình khi chưa và khi đang kết nối ✅ 🟡

- Màn Cấu hình **luôn mở được**, làm việc trên hồ sơ. Không có *Đọc từ xe* / *Áp dụng thử*.
- **Giữ kết nối khi ở màn Cấu hình.** Bản nháp hợp lệ được đẩy trực tiếp xuống pipeline (`CarController.updateLive`).
- **"Thử trên xe"** (`testing`): khi DISARMED, thay vì failsafe app gửi kết quả mix ở trạng thái nghỉ + giá trị xem trước của kênh, để chỉnh servo trực tiếp. Tự tắt khi mất kết nối, rời Cấu hình, app xuống nền.

| Nút | Chưa kết nối | Đã kết nối |
|---|---|---|
| Lưu | Lưu vào máy | Lưu vào máy; có tác dụng ngay. Failsafe đổi thì tự gửi `FS_WRITE` |
| Đồng bộ failsafe | Mờ · "Cần kết nối xe" | Gửi lại failsafe |
| Mặc định | Dùng được | Dùng được |

**5 tab của màn Cấu hình:**

| Tab | Nội dung |
|---|---|
| Input | Danh sách Input (I5) |
| Mix | Luật mix nhóm theo kênh đích (M7, M8) |
| Kênh | 10 kênh, trang chi tiết tinh chỉnh servo (O7) |
| Chung | Kết nối, thẻ **Ping xe** (ping nhanh theo IP/port/MAC đang sửa), nút **Quên mã xe** (khi thay mạch), vai trò Ga/Lái (O5), ARM (R), failsafe, **Mạng của xe** (W6) |
| Bố cục | Xem trước + *Sửa bố cục* (H2) |

Rời màn khi còn thay đổi chưa lưu thì hỏi lại.

### E5. Huy hiệu "Chưa đồng bộ failsafe" ⬜

- `hashFailsafe = hash(failsafeUs, failsafeTimeoutMs)`. Chưa đồng bộ khi `hashFailsafe ≠ lastSyncedHash` hoặc `lastSyncedAt == null` → huy hiệu vàng trên thẻ và app bar Cấu hình.
- Sửa trim, Min/Max, mix, bố cục **không** làm hồ sơ thành chưa đồng bộ.
- Hiện trạng: trường `lastSyncedHash` đã có trong hồ sơ nhưng chưa dùng; huy hiệu chưa làm.

### E6. Đồng bộ failsafe khi kết nối ✅ 🟡

1. Nối xe, dò `INFO` (C3). Xe n kênh: gửi `FS_WRITE` (timeout + failsafe các kênh).
2. Xe lưu NVS, áp ngay, trả `FS_ACK` kèm hash.
3. Hash khớp → cập nhật `lastSynced*`, chuyển READY.
4. Không có ACK sau 1 s thì gửi lại, tối đa 3 lần; vẫn lỗi thì **không cho lái**, báo *"Không đồng bộ được failsafe với xe"* + Thử lại.
5. Đang kết nối mà sửa failsafe rồi Lưu: lặp lại 1–4 (không ngắt lái nếu lỗi, chỉ cảnh báo).
6. `FS_WRITE` chỉ gửi khi hash đổi (hoặc bấm Đồng bộ failsafe).
7. Xe firmware cũ (không trả INFO): đồng bộ bằng `CONFIG_SET` + `CONFIG_SAVE` (giao thức 2 kênh).

### E7. Kiểm tra dữ liệu ✅

Xem nhóm V (mục 13). Lỗi hiện ngay dưới ô nhập, khoá nút Lưu.

### E8. Quản lý hồ sơ ✅

- Đổi tên, nhân bản (hậu tố "(bản sao)"), xoá (xác nhận).
- Xuất/nhập `.json`. Nhập: kiểm tra `schemaVersion` và dữ liệu (V); trùng `id` thì hỏi *Ghi đè* / *Tạo bản mới*. File sai thì báo rõ trường nào sai, không ghi đè hồ sơ đang có.

---

## 3. Nhóm I — Input

### I1. Mô hình ✅

```dart
class InputDef {
  String id;            // [a-z0-9_]{1,24}, duy nhất trong hồ sơ — vd "slider_x", "btn_a"
  String name;          // 1–24 ký tự
  InputType type;       // axis | binary | ternary | constant
  AxisRange range;      // axis: bipolar (−100…+100) | unipolar (0…100)
  InputLevels levels;   // binary / ternary: % đưa vào mixer ở từng trạng thái
  double constPct;      // constant: −100…+100
}
class InputLevels { double offPct = -100, midPct = 0, onPct = 100; }
```

- Input thuộc **hồ sơ**, không thuộc bố cục: nhiều bố cục dùng chung một Input, đổi bố cục không phải cấu hình lại mix.
- `constant` là Input ảo không cần phần tử (vd "CH5 = 30% khi A bật").
- Tối đa **48** Input.

### I2. Loại Input

| `type` | Trạng thái (dùng trong Condition) | Giá trị (vào mixer) | Phần tử gắn được |
|---|---|---|---|
| `axis` bipolar | −100…+100 | −100…+100 % | Cần gạt ngang/dọc, một trục của cần 2 trục, núm xoay |
| `axis` unipolar | 0…100 | 0…100 % (`(p + 100) / 2`) | Như trên; vị trí thấp nhất của cần = 0 |
| `binary` | 0 / 1 | `offPct` / `onPct` | Nút nhấn giữ, nút bật/tắt |
| `ternary` | −1 / 0 / 1 | `offPct` / `midPct` / `onPct` | Công tắc 3 nấc |
| `constant` | `constPct` | `constPct` | Không cần |

Trạng thái và giá trị tách riêng: Condition viết `A == 1` theo trạng thái, không phụ thuộc mức tắt là −100% hay 0%.

### I3. Gắn phần tử vào Input

- `ControlItem.inputId` (và `inputIdY` cho trục Y của cần 2 trục).
- Một Input có tối đa **một** phần tử trên một bố cục.
- Input không có phần tử trên bố cục đang dùng giữ **giá trị nghỉ**: axis = vị trí về mặc định (0%, unipolar = 0), binary = tắt, ternary = giữa.
- Phần tử chưa gắn hiện *"Chưa gắn Input"* và không tác động gì.

### I4. Đơn vị

Mixer làm việc trên **%** (số thực, −100…+100). Chỉ làm tròn ở Channel Stage khi đổi sang µs.

### I5. Tab "Input" ✅

- Danh sách: `tên · id · kiểu · phần tử đang gắn (trên bố cục đang dùng) · số luật dùng`.
- Thêm / sửa / xoá (`input_screen.dart`). Trang sửa: tên, id (**khoá** khi đã có luật dùng), kiểu, bipolar/unipolar, mức bật/tắt/giữa, giá trị hằng số.
- Thanh "giá trị hiện tại" chạy trực tiếp khi đang ở màn Lái hoặc bảng xem trước.

### I6. `InputManager`

```dart
class InputManager {
  void setFromItem(String inputId, double pct);   // từ widget, % vị trí cần
  void resetToRest();
  List<double> get state;                         // trạng thái cho Condition (I2)
  List<double> get value;                         // % cho mixer (I2)
}
```

---

## 4. Nhóm K — Condition

### K1. Biểu thức ✅

```jsonc
{ "op": "cmp", "input": "btn_a", "cmp": "==", "value": 1 }
{ "op": "cmp", "input": "slider_x", "cmp": ">=", "value": 80, "hyst": 10 }
{ "op": "and", "args": [ <expr>, ... ] }
{ "op": "or",  "args": [ <expr>, ... ] }
{ "op": "not", "arg": <expr> }
{ "op": "ref", "id": "cond_arm_ok" }   // Condition đặt tên (K3)
{ "op": "true" }                        // mặc định của luật
```

- `cmp`: `== != > < >= <=`, so với **trạng thái** Input; `==`/`!=` trên axis có sai số ±0,5%.
- Lồng tối đa 4 tầng AND/OR/NOT (`cmp`, `ref`, `true` không tính tầng); tối đa 8 `cmp` mỗi biểu thức.
- Xoá Input đang được dùng: liệt kê luật/Condition bị ảnh hưởng, hỏi xác nhận; luật bị ảnh hưởng chuyển sang tắt.

### K2. Hysteresis ✅

- `hyst` chỉ với `> >= < <=`, mặc định 0, khoảng 0…200.
- `>= 80, hyst 10`: đúng khi ≥ 80; sai khi < 70; ở giữa giữ kết quả trước. Ban đầu sai.
- `<= 20, hyst 10`: đúng khi ≤ 20; sai khi > 30.
- Trạng thái trễ reset về sai khi: mất kết nối, DISARM, thoát màn Lái, xe báo failsafe.

Ví dụ *"CH3 = 100% khi Lái ≥ 80%, về 0% khi < 70%"*:

| Luật | Nguồn | Condition | Kết quả |
|---|---|---|---|
| 1 | `const 0` | `true` | CH3 = 0% |
| 2 | `const 100` | `steer >= 80, hyst 10` | CH3 = 100% (`replace`, priority cao hơn) |

| Lái đi qua | CH3 |
|---|---|
| 0 → 75 | 0% |
| 75 → 82 | **100%** |
| 82 → 72 | 100% (giữ) |
| 72 → 69 | **0%** |
| 69 → 78 | 0% (giữ) |

### K3. Condition đặt tên ✅

```dart
class ConditionDef { String id; String name; Expr expr; }
```

- Dùng lại ở nhiều luật, sửa một chỗ. Tối đa **32**.
- `ref` không được tạo vòng; Condition đặt tên có hysteresis thì mọi luật tham chiếu dùng **chung** một trạng thái.
- AND/OR luôn tính **mọi** nhánh (không dừng sớm) để trạng thái trễ của từng nhánh luôn được cập nhật.

---

## 5. Nhóm M — Mixer

### M1. Luật mix ✅

```dart
class MixRule {
  String id;
  String name;               // trống thì dùng mô tả tự sinh (M6)
  bool enabled;
  String source;             // inputId (kể cả constant)
  Expr condition;            // mặc định {"op":"true"}
  double weightPct;          // −200…+200, mặc định 100
  double offsetPct;          // −100…+100, mặc định 0
  MixCurve curve;            // linear | expo(−100…+100) | points(5 điểm tại −100,−50,0,50,100)
  double minPct, maxPct;     // mặc định −100 / +100, min < max
  int destCh;                // 1..10
  Combine combine;           // replace | add | multiply | max | min
  int priority;              // 0..9, mặc định 0
  SwitchSafety safety;       // requireNeutral (mặc định true nếu nguồn là axis), deadzonePct (mặc định 5)
}
```

Tối đa **64** luật; đủ thì khoá *Thêm luật*.

### M2. Tính một luật

```
if !enabled                        → bỏ qua
active = safety.apply(condition)   // M4
if !active                         → bỏ qua
v = value(source)                  // % theo I2
v = v × weight / 100 + offset
v = curve(clamp(v, −100, 100))
v = clamp(v, minPct, maxPct)
```

### M3. Gộp nhiều luật vào một kênh

Luật cùng `destCh` sắp theo `priority` tăng dần, cùng priority theo thứ tự danh sách. Kênh bắt đầu *chưa có giá trị*:

| `combine` | Kênh chưa có giá trị | Đã có giá trị `c` |
|---|---|---|
| `replace` | `v` | `v` |
| `add` | `v` | `c + v` |
| `multiply` | giữ chưa có | `c × v / 100` |
| `max` | `v` | `max(c, v)` |
| `min` | `v` | `min(c, v)` |

Hết luật: chưa có giá trị → **0%** (Center); rồi kẹp −100…+100. Luật khẩn cấp đặt `priority` cao + `replace` đè mọi thứ:

| Luật | Nguồn | Condition | Combine | Priority |
|---|---|---|---|---|
| Ga | `throttle` | `true` | `replace` | 0 |
| Lái trộn | `steer` × 30% | `true` | `add` | 0 |
| Khẩn cấp | `const 0` | `btn_stop == 1` | `replace` | 9 |

### M4. Khoá an toàn khi đổi đích ✅

Vấn đề: *A = 1 → Slider X → CH1, A = 0 → Slider X → CH8*; đang ga 70% mà gạt A thì CH8 nhảy lên 70%.

Khi `safety.requireNeutral = true`:

- Mỗi luật giữ `activeLatched` (ban đầu = kết quả Condition lúc ARM).
- Condition đổi kết quả mà nguồn **đang lệch tâm** (|v| > `deadzonePct`; unipolar tính từ 0) → giữ `activeLatched` cũ, luật hiện *"Chờ về giữa"*.
- Nguồn về vùng chết → `activeLatched` nhận kết quả mới. Hai luật chung nguồn chuyển **cùng một chu kỳ**.
- Failsafe, DISARM, mất kết nối: huỷ trạng thái chờ.
- Luật `priority` ≥ 8 **không được** bật khoá an toàn (luật khẩn cấp phải tác động ngay).

| Bước | A | Slider X | CH1 | CH8 | Ghi chú |
|---|---|---|---|---|---|
| 1 | 1 | 70 | 70 | 0 | |
| 2 | 0 | 70 | 70 | 0 | Chờ về giữa |
| 3 | 0 | 30 | 30 | 0 | Vẫn chờ |
| 4 | 0 | 3 | 0 | 3 | Về vùng chết → chuyển |
| 5 | 0 | 70 | 0 | 70 | |

Unipolar 0…100: 0% = Center, 100% = Max; muốn cần đi từ Min tới Max thì đặt `weight 200, offset −100` (nút **Toàn dải** trong trình sửa luật).

### M5. Hiệu năng ✅ 🟡

- 64 luật + 32 Condition + 48 Input: một chu kỳ ≤ **2 ms** (p99) trên Android tầm trung. Đã đạt trên PC; **chưa đo trên điện thoại thật**.
- Không cấp phát trong vòng tính: biểu thức **biên dịch** một lần khi nạp hồ sơ thành danh sách phẳng; trạng thái (hysteresis, latch) nằm trong mảng có sẵn.

### M6. Mô tả tự sinh

| Luật | Mô tả |
|---|---|
| Không điều kiện | `Slider X → CH1` |
| Có điều kiện | `Slider X → CH1 · khi Nút A = 1` |
| Weight/offset khác mặc định | `Slider X × 50% + 10% → CH1` |
| Hằng số | `CH3 = 100% · khi Steer ≥ 80% (trễ 10%)` |
| Khoá an toàn | thêm ` · chờ về giữa` |

### M7. Tab "Mix" ✅

- Danh sách **nhóm theo kênh đích** (CH1 … CH10); trong nhóm xếp theo priority rồi thứ tự. Kéo chỉ đổi thứ tự giữa các luật cùng priority trong nhóm.
- Mỗi thẻ (`mix_rule_card.dart`): mô tả tự sinh (M6), công tắc bật/tắt, chấm `accent` khi luật đang active (lúc lái hoặc xem trước), nhãn *Chờ về giữa* khi đang chờ.
- Cuối danh sách: *"14/64 luật · 12 đang bật · priority cao chạy sau"*.
- Sửa được khi chưa nối xe.

### M8. Trình sửa luật ✅

`mix_rule_screen.dart`, `condition_builder.dart`, `mix_preview.dart`:

| Mục | Điều khiển |
|---|---|
| Nguồn | Chọn Input (có mục *Hằng số…*) |
| Điều kiện | Mỗi hàng `Input · toán tử · giá trị · (trễ)`; nhóm hàng bằng **Tất cả (AND)** / **Một trong (OR)**; nút **Phủ định**; chọn Condition đặt tên |
| Weight / Offset | −/+ và ô nhập; nút *Toàn dải* (unipolar: 200 / −100) |
| Curve | Tuyến tính / Expo / 5 điểm, có đồ thị nhỏ |
| Min / Max | Thanh 2 đầu |
| Đích | CH1–CH10 (hiện tên kênh) |
| Gộp / Ưu tiên | `replace · add · multiply · max · min`; priority 0–9 |
| Khoá an toàn | Bật/tắt, vùng chết |
| Xem trước | Thanh kéo cho nguồn, nút giả lập mọi Input dùng trong Condition, cột kết quả cho **mọi kênh bị ảnh hưởng** (chạy cùng `MixerEngine`) |

Hộp thoại xem/sửa luật chỉ mở khi DISARMED (A8).

### M9. `MixerEngine`

```dart
class MixerEngine {
  MixerEngine(CarProfile p);              // biên dịch Condition, sắp luật
  List<double> run(InputManager inputs);  // 10 kênh %, không cấp phát
  Set<String> get activeRuleIds;          // cho M7 / H11
  Set<String> get pendingRuleIds;         // đang "chờ về giữa"
  void reset();                           // hysteresis + latch
}
```

---

## 6. Nhóm O — Kênh và đầu ra

### O1. Kênh ✅

```dart
class ChannelConfig {
  int index;                     // 1..10
  String name;                   // mặc định "Kênh N" (hiển thị qua displayName)
  int minUs, centerUs, maxUs;    // mặc định 1000 / 1500 / 2000
  int trimUs, offsetUs;
  bool reverse;
  int failsafeUs;
  bool enabled;
}
```

- `enabled = false`: kênh luôn ra `failsafeUs`, bị bỏ qua trong mixer (luật ghi vào kênh tắt hiện cảnh báo vàng).
- CH1, CH2 **luôn bật** (`alwaysOn`) vì firmware 2 kênh cũ luôn xuất hai chân này. Quy tắc này độc lập với vai trò Ga/Lái.
- Hồ sơ có 10 kênh; xe hiện có 8 (C3). Kênh vượt số kênh của xe không được gửi.

### O2. Đổi % sang µs

```
p = mixer[ch]                               // −100…+100
nếu reverse: p = −p
center = clamp(centerUs + trimUs + offsetUs, minUs, maxUs)
us = p ≥ 0 ? center + p/100 × (maxUs − center) : center + p/100 × (center − minUs)
us = clamp(round(us), minUs, maxUs)
```

Quy ước %: `pct = (us − center) / (max − center) × 100` khi `us ≥ center`, chia `(center − min)` khi nhỏ hơn.

### O3. Failsafe

`failsafeUs` theo µs từng kênh + `failsafeTimeoutMs` (100–3000 ms). Đồng bộ bằng `FS_WRITE` (E6). Không có failsafe theo % vì xe không biết cấu hình kênh. Xe chưa từng đồng bộ: 1500 µs mọi kênh, timeout 400 ms.

### O4. Giao thức đầu ra

- `CarProfile.output` (`protocol`, `periodMs`); nhịp gửi thật lấy theo đường truyền (`CarTransport.controlPeriod`: WiFi 10 ms, BLE 20 ms).
- `OutputPipeline.run(arm)` → 10 kênh µs: Input → Condition → Mixer → Channel Stage (O2) → ARM gate. `CarController` cắt theo số kênh của xe và gửi `CONTROL_US` (C3), hoặc `CONTROL` 2 kênh với firmware cũ.
- Interface `OutputProtocol` riêng cho UART / MAVLink / SBUS: chưa tách ⬜ (C5).

### O5. Vai trò Ga / Lái ✅

- `CarProfile.throttleCh` / `steeringCh` (`int?`), chọn ở Cấu hình ▸ Chung (trên mục ARM). Có thể để trống (mẫu "Trống").
- **Ga** dùng cho: kiểm tra "thả cần ga" khi ARM và khi vào sửa bố cục; cảnh báo tự về của cần ga (H3b, H5).
- **Lái** chỉ dùng cho ô **Trim lái** (H10).
- Vai trò thiếu luật hoặc thiếu phần tử trên bố cục → **cảnh báo** (`roleWarning`) dưới ô chọn, không chặn lưu.
- Không giả định cứng CH1 = Lái, CH2 = Ga ở bất kỳ đâu trong app.

### O6. Hộp số ❌

Đã bỏ hoàn toàn (`GearConfig`, `ItemKind.gearBox`, `gear` trong controller/pipeline). Bố cục cũ có `gearBox` bị bỏ phần tử đó khi nạp. Firmware cũ vẫn nhận byte `gear = 1`, `gearCount = 1`, giới hạn 100% (định dạng gói không đổi). Migration v1→v2 cảnh báo nếu hộp số cũ có giới hạn ga.

### O7. Tab "Kênh"

- 10 hàng: `CHn · tên · số luật ghi vào kênh · công tắc bật/tắt`.
- Trang chi tiết: tên, Min/Center/Max, Trim/Offset, Reverse, Failsafe, **thanh xem trước** (µs và %), danh sách *các luật ghi vào kênh này*. Tinh chỉnh servo chỉ nằm ở đây.

---

## 7. Nhóm R — Kết nối và ARM

### R1. Máy trạng thái ✅

```
DISCONNECTED ──kết nối──► CONNECTED ──FS_WRITE/FS_ACK ok──► READY ──ARM──► ARMED
     ▲                        │                                │   ◄─DISARM─┘
     └──── mất kết nối ◄──────┴──── đồng bộ lỗi 3 lần ─────────┘      │
                                   (ở lại CONNECTED, không cho ARM)   │
     ◄──────────────────────── mất kết nối / failsafe ───────────────┘
```

| Trạng thái | Gửi xuống xe | Màn Lái |
|---|---|---|
| DISCONNECTED | Không | "Chưa kết nối" |
| CONNECTED | Không gửi CONTROL (đang đồng bộ failsafe) | "Đang đồng bộ…" |
| READY | `CONTROL_US` với `failsafeUs` (hoặc giá trị *Thử trên xe*, E4) | Nút **ARM**; phần tử vẫn kéo được |
| ARMED | `CONTROL_US` với kết quả pipeline | Lái bình thường |

Xe firmware cũ (2 kênh): READY gửi trung tính (0, 0); ARMED gửi CH1/CH2 của mixer dạng −1000…+1000, xe tự áp servo.

### R2. Điều kiện ARM

1. READY (failsafe đã đồng bộ).
2. Hồ sơ hợp lệ (V).
3. Kênh Ga ở **vị trí nghỉ**: giá trị mixer của kênh Ga trong ±5% quanh vị trí nghỉ (`ReturnMotion.restPct`). Không có vai trò Ga thì bỏ qua điều kiện này.
4. Không ở chế độ Sửa bố cục, không ở màn Cấu hình, app không ở nền (`ArmCheck.paused`).
5. Đường truyền tốt, xe không failsafe (`linkOk`).
6. Có `armCondition` thì Condition đó đúng.

Thao tác: **giữ nút ARM 1 s** (vòng tiến trình). `autoArm` (mặc định tắt): tự ARM một lần sau mỗi lần kết nối.

### R3. DISARM

Tự DISARM khi: mất kết nối hoặc không có telemetry quá 1 s, xe báo failsafe, app xuống nền, vào Sửa bố cục, mở Cấu hình, thoát màn Lái, `armCondition` thành sai. Bấm DISARM thì DISARM ngay. Sau DISARM: về READY, reset hysteresis và khoá an toàn.

### R4. Tắt cơ chế ARM ✅

`ArmConfig.enabled` (mặc định bật). Khi tắt:

- Không có nút ARM/DISARM; ô trạng thái lái cũng không hiện (chỗ đó để trống).
- `ArmController.tick` tự ARM lại mỗi chu kỳ khi đủ điều kiện; `autoArm` và `armCondition` bị bỏ qua và ẩn trong Cấu hình.
- **Vẫn giữ an toàn:** phải thả ga (R2.3), và R2.4–R2.5 vẫn chặn.
- Nút **Ngắt kết nối** chỉ bị khoá khi `arm.enabled && armed` (tắt ARM thì vẫn ngắt được).

### R5. Kiểm tra mã xe khi nối 🟡

- `INFO` mang MAC gốc của xe. Hồ sơ đã có `wifi.carId` mà mã khác → **từ chối** kết nối (tránh nối nhầm xe cùng IP).
- Hồ sơ chưa có `carId` thì nhớ mã sau lần nối đầu. Firmware cũ (INFO 2 byte) thì bỏ qua kiểm tra. Nút *Quên mã xe* trong Cấu hình.
- Dò INFO: 500 ms × 3 lần (sau khi vừa mở lại socket, 400 ms × 2 hay nhầm thành firmware cũ và mất trim).

---

## 8. Nhóm H — Màn Lái và bố cục

### H1. Mô hình bố cục ✅

```dart
class ControlLayout {
  String id;
  String name;
  int cols = 48, rows = 24;   // lưới tương đối, không tính pixel
  List<ControlItem> items;
}

class ControlItem {
  String id;
  ItemKind kind;
  String? inputId, inputIdY;  // phần tử điều khiển (I3)
  StickAxes axes;             // cần 2 trục: both | x | y (H8)
  String? source, sourceY;    // phần tử hiển thị (H7); JSON cũ "gaugeKey" đọc thành source
  DisplayConfig display;
  int? trimCh;                // Thanh trim (H10)
  List<int>? chList;          // Bảng kênh (H7), null = mọi kênh đang bật
  int x, y, w, h;             // theo ô lưới
  ItemStyle style;            // nhãn, icon, màu (A3), gimbal, độ trong suốt…
  ReturnConfig? returnCfg;    // cần gạt (H3b)
}
```

- Bố cục 24 × 12 cũ được nhân ×2 khi đọc (`ControlLayout.fromJson`).
- Mỗi hồ sơ có nhiều bố cục + `activeLayoutId`; đi cùng hồ sơ khi xuất/nhập; không ghi xuống xe.

### H1b. Loại phần tử

| Nhóm | `ItemKind` | Mô tả |
|---|---|---|
| Điều khiển | `stickH` Cần gạt ngang | −100…+100, tự về theo H3b; núm dạng viên thuốc dẹp |
| | `stickV` Cần gạt dọc | Như trên |
| | `stick2D` Cần 2 trục | X/Y; 1 trục hoặc 2 trục (H8); kiểu gimbal tay RC |
| | `button` Nút nhấn giữ | Bật khi giữ (còi) |
| | `toggle` Nút bật/tắt | Mỗi lần bấm đổi trạng thái (đèn) |
| | `switch3` Công tắc 3 nấc | ◀ ● ▶ (tời, ben) |
| | `knob` Núm xoay | Giữ nguyên vị trí |
| Hiển thị | `gauge` Ô đồng hồ | Số + đơn vị của một nguồn dữ liệu |
| | `led` Đèn LED | Sáng/tắt theo nguồn |
| | `bar` Thanh giá trị | Thanh ngang/dọc theo nguồn |
| | `vector` Vector 2D | Điểm theo `source` (X) + `sourceY` (Y) |
| | `channels` Bảng kênh | Giá trị các kênh (% / µs / ẩn số), tự chia cột |
| | `statusBadge` Trạng thái | Huy hiệu trạng thái kết nối/ARM |
| Trim | `trim` Trim lái | Ô trim kênh Lái; bấm giữa ô mở bảng trim mọi kênh (H10) |
| | `trimBar` Thanh trim | Một kênh mỗi thanh, thêm được nhiều (H10) |

- Thêm tự do, **không giới hạn số lượng**. Phần tử mới *Chưa gắn Input*.
- Khi thêm kiểu mới (trim, cần…), **thêm bên cạnh, không thay kiểu cũ**.

### H2. Chế độ Sửa bố cục ✅

- Vào từ nút **✎ Sửa** ở góc phải trên màn Lái (cạnh ⚙), hoặc tab **Bố cục** trong Cấu hình (xem trước + *Sửa bố cục*, mở `ControlScreen(editOnly: true)`; bản nháp chưa lưu phải lưu trước).
- **Khoá bố cục** (mặc định bật): khi khoá, nút Sửa **ẩn hẳn**; mở khoá trong menu ⚙.
- **1 chạm = chọn** (hiện tay nắm), **2 chạm = mở bảng thuộc tính**. Chọn dùng `Listener.onPointerDown` để không trễ chờ double-tap. Thêm phần tử mới thì mở bảng luôn.
- **Di chuyển:** kéo, bám lưới, đường gióng khi thẳng hàng.
- **Đổi kích thước:** 8 tay nắm (4 góc + 4 cạnh), nhãn `w × h` khi kéo. Không có kích thước lớn nhất: dừng ở phần tử bên cạnh (`LayoutGrid.largestFree`). Vùng chạm phần tử điều khiển ≥ **48 dp**.
- **Không chồng lấn:** kéo vào chỗ có phần tử khác thì khung đỏ, thả ra thì quay về.
- **Xoá:** thùng rác nổi ở giữa dưới, chỉ hiện khi đang kéo di chuyển; thả vào là xoá. Hoặc nút xoá trong bảng thuộc tính.
- **Hoàn tác / Làm lại** 30 bước; **Lưu / Huỷ**.
- Trong chế độ sửa, phần tử không điều khiển xe; nền lưới hiện mờ.

### H3. Bảng thuộc tính ✅

| Thuộc tính | Áp dụng | Giá trị |
|---|---|---|
| Input | phần tử điều khiển | *Chưa gắn* · Input cùng kiểu · **Tạo Input mới** |
| Gửi tới kênh (lối tắt) | phần tử điều khiển | Chọn CHn → tạo/sửa **một luật mặc định** `Input → CHn, weight 100, replace, priority 0`. Input đã có nhiều luật hoặc có điều kiện → *"Dùng tab Mix"* |
| Nguồn dữ liệu | phần tử hiển thị | Khoá DataSource (H7) |
| Nhãn / Icon / Màu / Độ trong suốt | mọi phần tử | Nhãn hiện/ẩn; Heroicons; màu riêng (A3); 30–100% |
| Hiện giá trị | cần gạt, núm | % / µs / ẩn |
| Kích thước núm cầm | cần gạt | Nhỏ / Vừa / Lớn |
| Vùng chết | cần gạt, núm | 0–20% |
| Rung khi chạm | nút, công tắc, cần ở tâm | Bật / Tắt |
| Tự về | cần gạt | Xem H3b |

### H3b. Tự về của cần gạt ✅

Mỗi cần gạt, mỗi trục có cài đặt riêng (`return_motion.dart`). Mặc định: thả tay là về 0%.

```dart
class ReturnConfig {
  ReturnMode mode;     // spring | hold | halfSpring
  double targetPct;    // vị trí về, mặc định 0 (−100…+100)
  int delayMs;         // 0–1000, mặc định 0
  int durationMs;      // 0–2000, mặc định 0 = về ngay
  ReturnCurve curve;   // linear | easeOut
  bool positiveOnly, negativeOnly;   // halfSpring
  bool rememberOnExit;               // hold, mặc định false
}
```

| Mục đích | Chế độ | Vị trí về | Thời gian về |
|---|---|---|---|
| Lái | Tự về | 0% | 0 |
| Ga xe (tiến/lùi) | Tự về | 0% | 200 ms |
| Ga tàu/thuyền, cần dâng ben | Giữ vị trí | — | — |
| Ga chỉ tiến, lùi giữ | Về một nửa (nửa dương) | 0% | 0 |

- Cài đặt nhanh: *Về 0% ngay* · *Về 0% êm* (300 ms, chậm dần) · *Giữ vị trí*. Có thanh xem trước.
- `positiveOnly` và `negativeOnly` cùng bật, hoặc `targetPct` ngoài khoảng → không cho lưu.

### H4. Bố cục mẫu

| Mẫu | Trạng thái |
|---|---|
| Mặc định: ga dọc trái, lái ngang phải, đồng hồ giữa (dựng bằng Input + luật mặc định) | ✅ |
| Thuận tay trái · Tay cầm (hai cần 2 trục) · Tối giản; nút Lật ngang; nhiều bố cục/hồ sơ, nhấn giữ ⚙ để đổi nhanh | ⬜ |

### H5. An toàn của màn Lái ✅

- Mất kết nối / failsafe: mọi kênh về `failsafeUs`, bỏ qua tự về.
- Thoát màn Lái, vào sửa bố cục, app xuống nền: cần về `targetPct`; cần ga "Giữ vị trí" **bắt buộc** về Center. Nút bật/tắt giữ trạng thái.
- Chỉ vào chế độ sửa khi **ga ở vị trí nghỉ** (`ReturnMotion.restPct` = vị trí về của trục gắn kênh Ga; ga "Giữ vị trí" hoặc không phải cần gạt thì nghỉ = 0%). Báo *"Thả cần ga trước khi sửa bố cục"*.
- Trong suốt chế độ sửa, xe nhận Center ở các kênh cần gạt.
- Cần ga "Giữ vị trí" hoặc "Thời gian về" > 500 ms: cảnh báo *"Xe có thể tiếp tục chạy sau khi thả tay"*.
- Phần tử không đặt vào vùng cử chỉ hệ thống (`viewPadding`, `systemGestureInsets`).
- **Lỗi H5-1 (đã sửa):** đặt *Vị trí về* của cần ga khác 0% (vd −28%) thì không vào được Sửa bố cục, vì điều kiện so ga với 0% cứng. Sửa: so với `ReturnMotion.restPct`.

### H6. Hiển thị trên nhiều cỡ màn ✅

Lưới co giãn theo vùng an toàn (màn Lái luôn ngang). Ô lưới không vuông thì cần 2 trục và núm vẫn tròn, căn giữa. Máy tính bảng: lưới giữ nguyên, phần tử to theo.

### H7. Nguồn dữ liệu (DataSource) ✅

`lib/models/data_source.dart`:

| Nhóm | Khoá |
|---|---|
| Số đo từ xe | `battery` · `current` · `speed` · `ping` · `lq` · `rssi` |
| Trạng thái | `arm` · `link` · `failsafe` |
| Kênh | `ch:N` (% sau mixer) · `channels` (bảng 10 kênh, chỉ ô đồng hồ) |
| Input | `in:<inputId>` |

Hạn chế hiện tại: `current` luôn 0 (firmware chưa đo dòng).

### H8. Phần tử kiểu tay RC 🟡

- **Cần 2 trục:** `axes` = both / x / y. 1 trục = 1 kênh, trục kia khoá và có rãnh dẫn; bỏ trục thì gỡ Input của trục đó. `ItemStyle.gimbal` (mặc định bật) vẽ kiểu gimbal tay RC (`GimbalPainter`).
- **Thanh cần gạt:** rãnh, phần tô và núm đồng tâm với thẻ (bo 16 − 8 = 8), núm mảnh.

### H9. Tai thỏ trạng thái ✅

- `StatusNotch` ở mép trên màn Lái và Cấu hình, hiện các khoá DataSource người dùng chọn (`statusItems`, tối đa 6).
- Bấm để chọn mục (không mở được khi ARMED — A8).
- Ô giá trị **cố định độ rộng** (theo chuỗi dài nhất trong khoảng min…max của nguồn, tràn thì thu nhỏ) để tai thỏ không đổi cỡ khi số nhảy.
- Tai thỏ, nút Kết nối và nút *Thử trên xe* cao bằng nhau (`barPillHeight` = 8,5% cạnh ngắn, kẹp 30–40).
- Hiện *"Tín hiệu yếu"* khi `weakLink` (F6).

### H10. Trim 🟡

- **Trim lái** (`trim`, giữ nguyên kiểu cũ): ◀ / ▶ trim kênh Lái. Bấm vào giữa ô ("Trim X µs") mở **bảng trim nổi** ở góc phải trên: mọi kênh đang bật, mỗi dòng ◀ / ▶ (giữ để lặp), bấm số µs để về 0. Không modal, không chặn cần gạt bên dưới.
- **Thanh trim** (`trimBar`): mỗi thanh một kênh (`trimCh`), thêm được nhiều; khung cao hơn rộng thì nằm dọc.
- Trim lưu trễ 250 ms (A7).

### H11. Chấm mix và xem luật

- Phần tử có Input đang tác động qua luật có điều kiện hoặc nhiều đích có chấm `accent`.
- Nhấn giữ để xem danh sách luật và kênh đích — **chỉ khi DISARMED** (A8).

---

## 9. Nhóm F — Ping và chất lượng tín hiệu

### F1. Gói ✅

`PING(seq, t_gửi)` → `PONG(seq, t_gửi, uptime)`; `IDENTIFY(duration)` cho F8. Mã gói ở C2.

### F2. Firmware ✅

Trả `PONG` **ngay trong vòng nhận**, không xếp hàng chờ `loop()`; cả UDP và BLE.

### F3. `ping_service.dart` ✅

Tham số `timeoutMs` (1000), `intervalMs`, `count` hoặc liên tục. Cửa sổ trượt 20 gói: RTT min/avg/max, jitter (trung bình |RTTᵢ − RTTᵢ₋₁|), % mất gói. Gói về sau timeout tính là mất; gói sai thứ tự ghép theo `seq`.

### F4. Ping nhanh ✅

`quick_ping.dart`: hỏi INFO trước, rồi 3 gói. WiFi gửi thẳng UDP; BLE nối tạm → 3 ping → ngắt. Có ở trình tạo xe (bước 2) và Cấu hình ▸ Chung. Đã bỏ khỏi thẻ xe ở màn chính.

### F5. Chẩn đoán kết nối ⬜

Màn riêng: Bắt đầu/Dừng; 10 / 50 / liên tục gói; cách 100 / 250 / 500 ms; biểu đồ RTT, bảng thống kê, danh sách gói mất/trễ.

### F6. Ping ngầm và LQ 🟡

- `PingService` chạy suốt lúc kết nối, **1 lần/giây**; `pingMs` = trung bình 20 gói. Dừng khi app xuống nền.
- `linkQuality` = % gói telemetry (10 Hz) về trong 2 s (cho lệch 1 gói).
- `weakLink` khi **LQ < 70%** hoặc **ping > 200 ms** → *"Tín hiệu yếu"* trên tai thỏ. Ngưỡng là ước lượng, cần chỉnh khi thử xe thật.
- Ô Ping hiện số ms thật, dòng phụ "LQ x%". `PingConfig` (ngưỡng màu ô Ping) vẫn lưu trong hồ sơ. Ping ngầm không làm lệch nhịp gửi lệnh (< 5%).

### F7. Giả lập trễ ⬜

`fake_car.py --delay <ms> --jitter <ms> --loss <%>`.

### F8. "Tìm xe" (IDENTIFY) ⬜

Gửi `IDENTIFY(3000)`; xe nháy nhanh LED trạng thái 3 s rồi về bình thường. Trong menu thẻ hồ sơ và danh sách BLE khi quét. Hiện mới có mã gói và hàm mã hoá trong app.

---

## 10. Nhóm C — Giao thức

### C1. Khung gói ✅

`[0xAA][type][len][payload … len byte][crc8]` — CRC-8 đa thức 0x07, init 0, tính trên `type + len + payload`; số nhiều byte là little-endian. `MAX_PAYLOAD = 128` (section STA dài nhất 115 byte; BLE MTU 185). Dùng chung cho UDP (port 4210) và BLE.

### C2. Bảng gói

| Mã | Tên | Chiều | Payload |
|---|---|---|---|
| `0x01` | CONTROL (cũ, 2 kênh) | App → Xe | `throttle:i16 · steering:i16` (−1000…1000) · `gear:u8` · `seq:u8` |
| `0x02` | TELEMETRY | Xe → App, 10 Hz | `batteryMv:u16 · currentMa:i16 · speedCms:u16 · rssi:i8 · flags:u8 · gear:u8 · lastSeq:u8` |
| `0x03` | CONTROL_US | App → Xe | `seq:u16 · us[n]:u16`, n = 0…16. **n = 0: chỉ giữ kết nối, xe xuất failsafe** |
| `0x04` | INFO_GET | App → Xe | — |
| `0x05` | INFO | Xe → App | `proto:u8 (=2) · channels:u8 · id[6]` (MAC gốc) |
| `0x10–0x14` | CONFIG_GET / DATA / SET / SAVE / RESET | | Cấu hình servo kiểu cũ (`CarConfig` 34 byte), chỉ dùng với firmware 2 kênh |
| `0x20` | ACK | Xe → App | `type:u8 · status:u8` (1 OK · 0 lỗi · 2 xe đang chạy) |
| `0x21` | FS_WRITE | App → Xe | `timeout_ms:u16 · fs[n]:u16` (µs), n = 1…16 |
| `0x22` | FS_ACK | Xe → App | `status:u8 · hash:u32` (FNV-1a trên payload FS_WRITE) `· channels:u8` |
| `0x30` | PING | App → Xe | `seq:u16 · t_send:u32` |
| `0x31` | PONG | Xe → App | `seq:u16 · t_send:u32 · uptime:u32` |
| `0x32` | IDENTIFY | App → Xe | `duration_ms:u16` |
| `0x40–0x47` | NET_* / DISCOVER / HERE | | Mạng của xe, xem W3 |

Cờ telemetry: `FAILSAFE` 0x01 · `ARMED` 0x02 · `VIA_BLE` 0x04 · `NET_SETUP` 0x08.

Vector test: CONTROL ga 500, lái −250, số 2, seq 7 = `aa 01 06 f4 01 06 ff 02 07 46`. Failsafe hồ sơ mặc định → hash `0xce5e49da`.

### C3. Chế độ n kênh và tương thích ngược ✅ 🟡

- Sau khi nối, app gửi `CONFIG_GET` rồi dò `INFO_GET` (500 ms × 3).
- **Có INFO** → chế độ n kênh: READY gửi `failsafeUs()`, ARMED gửi `toUsList()` cắt còn `channels` của xe, chưa có pipeline thì gửi 0 kênh. Trim không gọi `applyConfig` (app tự tính).
- **Không có INFO** → firmware cũ: `CONTROL` 2 kênh + đồng bộ bằng `CONFIG_SET/SAVE`; app chỉ cho lái 2 kênh.
- Firmware: nhận `CONTROL_US`/`FS_WRITE` thì bật `multiCh`; nhận `CONTROL` cũ thì quay về chế độ 2 kênh (app cũ: CH3–CH8 ra failsafe). Ở chế độ n kênh xe không tự khoá ga (việc ARM do app).
- Gói mới phải thêm đồng thời ở `protocol.h`, `protocol.dart`, `fake_car.py`, `test/support/fake_car.dart`.

### C4. Xe giả `tools/fake_car.py` ✅

- Giao thức n kênh (`CONTROL_US`, `INFO`, `FS_WRITE`/`FS_ACK`), PING/PONG, giao thức 2 kênh cũ. Không chạy mix; in các kênh nhận được (đã mix sẵn từ app) và failsafe khi nhận `FS_WRITE`.
- Giống xe ở chế độ Router: trả lời DISCOVER ở cổng 4211, đọc/ghi cấu hình mạng giả (NET_*, giữ mật khẩu khi nhận `0xFF`); lệnh lưu chỉ ghi log.
- Cờ: `--channels <1..16>` (mặc định 8) · `--legacy` (firmware 2 kênh) · `--no-ack` (không trả FS_ACK, thử nhánh lỗi E6). Chưa có `--delay/--jitter/--loss` (F7).
- Bản Dart cho test: `app/test/support/fake_car.dart`.

### C5. Gói v2 có header "RC" ❌

Đề xuất ở Sprint 3, không làm; giữ khung 0xAA để NET_*/DISCOVER/PING không đổi. Interface `OutputProtocol` (UART/MAVLink/SBUS sau này) chưa tách ⬜.

---

## 11. Nhóm W — WiFi 3 chế độ

### W1. Ba chế độ 🟡

| # | Chế độ | Xe | Điện thoại | Địa chỉ xe | Dùng khi |
|---|---|---|---|---|---|
| 1 | **AP** | Phát WiFi riêng (mặc định `RC-CAR` / `12345678`) | Vào WiFi của xe | IP tĩnh, mặc định `192.168.4.1` | Ngoài trời |
| 2 | **Router** | Vào router băng 2.4 GHz | Cùng router, 2.4 hoặc 5 GHz | DHCP hoặc tĩnh | Trong nhà, vẫn có internet |
| 3 | **Cấu hình** | Phát WiFi tạm `RC-SETUP-A1B2`, không nhận lệnh lái | Vào WiFi tạm | Như IP WiFi riêng | Sửa mạng khi không nối được cách khác |

- `A1B2` = 2 byte cuối MAC. Mật khẩu WiFi tạm = mật khẩu WiFi riêng.
- ESP32-S3 chỉ có 2.4 GHz; điện thoại 5 GHz vẫn tới được xe qua LAN của router. Mạng khách và "AP isolation" sẽ chặn.

### W2. Chọn chế độ khi bật nguồn (`netm::begin`)

```
                        ┌─────── giữ nút BOOT 3 s / lệnh NET_SETUP ────────┐
                        ▼                                                  │
                 ┌──────────────┐  "Lưu" (NET_APPLY) → khởi động lại ┌──────────────┐
                 │ 3. CẤU HÌNH  │ ─────────────────────────────────► │ 2. ROUTER    │
                 └──────────────┘                                    └──────────────┘
                        │ 5 phút không có máy nối                      │    ▲
                        ▼                                   không vào được │    │ "Lưu" với
                 ┌──────────────┐ ◄────────────── router sau 15 s ────────┘    │ chế độ Router
                 │ 1. AP        │ ─────────────────────────────────────────────┘
                 └──────────────┘
```

1. Cờ RTC "vào chế độ cấu hình" (chỉ tin khi reset do phần mềm) → **3**.
2. NVS `rcnet` có `bootMode = Router` và SSID → thử router **15 s**. Được thì **2**; không được thì **1** cho lần chạy này, ghi lý do (không thấy mạng / sai mật khẩu / không nhận IP / lỗi). Lần bật sau lại thử router.
3. Còn lại → **1**. Xe mới (NVS trống) vào AP, lái được ngay.

- Đang ở Router mà rớt router: chỉ thử lại, **không** chuyển sang AP (IP sẽ đổi); failsafe tự xử lý.
- Chế độ 3 không bao giờ được lưu; không thử router tại chỗ.

### W3. Giao thức mạng ✅

| Mã | Tên | Chiều | Payload |
|---|---|---|---|
| `0x40` | NET_GET | App → Xe | `section:u8` |
| `0x41` | NET_DATA | Xe → App | `section:u8 · dữ liệu` |
| `0x42` | NET_SET | App → Xe | `section:u8 · dữ liệu` → ghi vào **bản chờ**, trả ACK |
| `0x43` | NET_APPLY | App → Xe | Kiểm tra bản chờ → lưu NVS → ACK → khởi động lại sau 500 ms |
| `0x44` | NET_SETUP | App → Xe | ACK → khởi động lại vào chế độ cấu hình |
| `0x45` | NET_RESET | App → Xe | ACK → mạng về mặc định, khởi động lại |
| `0x46` | DISCOVER | App → broadcast **:4211** | `nonce:u16` |
| `0x47` | HERE | Xe → App (unicast) | `nonce:u16 · id[6] · ip[4] · udpPort:u16 · mode:u8 · name:str` |

| Section | Dữ liệu |
|---|---|
| 0 STATUS (chỉ đọc) | `mode · fellBack · staResult · rssi:i8 · ip[4] · id[6] · setupLeftS:u16 · clients` |
| 1 GENERAL | `bootMode · udpPort:u16 · name:str` |
| 2 AP | `channel · ip[4] · ssid:str · pass:str` |
| 3 STA | `dhcp · ip[4] · gateway[4] · subnet[4] · dns[4] · ssid:str · pass:str` |

- `str` = `len:u8 · UTF-8`. Mật khẩu `len = 0xFF`: đọc = "có mật khẩu nhưng không gửi ra"; ghi = "giữ mật khẩu cũ".
- `mode`: 0 AP · 1 Router · 2 Cấu hình. `staResult`: 0 chưa thử · 1 đang nối · 2 OK · 3 không thấy mạng · 4 sai mật khẩu · 5 không nhận IP · 6 lỗi.
- DISCOVER dùng **cổng riêng 4211** (`SO_BROADCAST`), không đổi theo port cấu hình.

### W4. Cấu hình lưu trên xe và kiểm tra

| Nhóm | Trường | Kiểm tra |
|---|---|---|
| Chung | `bootMode`, `udpPort` (4210), `name` (tên BLE + hostname) | port 1–65535, khác 4211; tên 1–20 ký tự `A-Z a-z 0-9 -`, không bắt đầu/kết thúc bằng `-` |
| WiFi riêng | `apSsid`, `apPass`, `apChannel`, `apIp` | SSID 1–32 byte; mật khẩu **bắt buộc** 8–63 ASCII in được; kênh 1–13; IP host, số cuối 1–254, /24 |
| WiFi router | `staSsid`, `staPass`, `staDhcp`, `staIp`, `staGateway`, `staSubnet`, `staDns` | SSID bắt buộc khi Router; mật khẩu trống (mạng mở) hoặc 8–63; IP tĩnh: mask liền 8–30 bit, IP và gateway cùng mạng và khác nhau, không phải địa chỉ mạng/broadcast; DNS trống = gateway |

App kiểm tra y hệt (`NetConfig.validate`) để báo lỗi theo từng ô. Firmware Router: `setHostname` trước khi bật STA, `WiFi.setSleep(false)` (tránh giật ~100 ms), `WiFi.persistent(false)`; RSSI telemetry = RSSI tới router.

### W5. Dò xe trong mạng ✅ 🟡

- Mã xe = MAC gốc (`esp_efuse_mac_get_default`), lưu vào `wifi.carId`.
- Bấm thẻ / Kết nối với hồ sơ có `carId`: DISCOVER tới `255.255.255.255` và broadcast /24 của từng mạng trên máy, 3 lần cách 300 ms, dừng khi thấy đúng mã (≤ 1,2 s). Thấy thì cập nhật IP/port; không thấy thì thử IP cũ. IP xe = địa chỉ nguồn của gói HERE.
- Không thấy xe: gợi ý cùng router, không dùng mạng khách, xe không vào được router thì 15 s sau tự phát WiFi riêng.
- Trình tạo xe bước 2: **Tìm xe** liệt kê xe trong mạng.

### W6. Màn "Mạng của xe" ✅

Mở từ **Cấu hình → Chung → Mạng của xe**; cần đang nối xe (WiFi hoặc BLE).

| Phần | Nội dung |
|---|---|
| Trạng thái | Chế độ, IP, port, sóng, số máy nối AP, thời gian còn lại (chế độ cấu hình), kết quả vào router, mã xe; cảnh báo đỏ khi đang dự phòng về AP |
| Khi bật nguồn | WiFi riêng (AP) / Vào router nhà |
| Chung | Tên thiết bị, port UDP |
| WiFi riêng | SSID, mật khẩu (trống = giữ), kênh, IP |
| WiFi router | SSID, *Mạng không có mật khẩu*, mật khẩu (trống = giữ), DHCP / Tĩnh (IP, gateway, subnet, DNS) |
| Nút | **Lưu vào xe & khởi động lại** (chỉ sáng khi có thay đổi hợp lệ; ở chế độ cấu hình chưa sửa gì thì là *Thoát chế độ cấu hình*); menu *Chế độ cấu hình (WiFi tạm)*, *Khôi phục mạng mặc định*; nút đọc lại |

Sau khi lưu: app ngắt, sửa hồ sơ (IP/port/SSID/mã xe; DHCP thì để tự dò), hiện hướng dẫn nối lại.

### W7. Vào chế độ Cấu hình / khôi phục

| Cách | Chi tiết |
|---|---|
| Nút | `PIN_NET_BUTTON` (mặc định GPIO0 = BOOT). Giữ **3 s khi xe đang chạy** → chế độ cấu hình; **10 s** → mạng mặc định. Không giữ lúc cắm điện. `-1` = không dùng |
| App | Mạng của xe → menu |
| Serial | `net info` · `net setup` · `net reset` |

Chế độ cấu hình: bỏ qua CONTROL, xe giữ failsafe, telemetry có `FLAG_NET_SETUP` (app hiện *"Xe đang ở chế độ cấu hình mạng"*). Thoát bằng Lưu trong app hoặc 5 phút không có máy nối.

### W8. An toàn mạng

- NET_SET / APPLY / SETUP / RESET chỉ nhận khi xe **đứng yên** (đang failsafe; hoặc 2 kênh với ga < 5%; hoặc n kênh với mọi kênh lệch failsafe ≤ 20 µs), không thì `ACK(type, 2)`. App chặn thêm khi ARMED: *"DISARM trước khi đổi mạng của xe"*.
- **Mật khẩu không bao giờ rời xe** (NET_DATA gửi `0xFF`). Lý do: BLE chưa ghép đôi, UDP không xác thực.
- Đang có điện thoại lái qua WiFi thì máy khác không chen vào được tới khi xe failsafe (khoá CONTROL theo IP).
- Rủi ro mở: NVS chưa mã hoá; BLE chưa xác thực. Cần xử lý trước khi phát hành.

---

## 12. Nhóm FW — Firmware ESP32-S3

### FW1. Phần cứng

| Chân | Chức năng |
|---|---|
| GPIO 4, 5, 7, 15, 16, 17, 18, 8 | PWM **CH1…CH8** (`PIN_CH`) |
| GPIO 1 | ADC pin, cầu chia R1 100k / R2 10k (tối đa ~36 V) |
| GPIO 6 | Hall đo tốc độ (tuỳ chọn, kéo lên nội) |
| GPIO 0 | Nút BOOT (W7) — **cần xác nhận theo mạch thật** |
| GPIO 48 | LED RGB WS2812 (DevKitC-1 v1.1: GPIO 38) — **cần xác nhận theo board thật** |

- ESP32-S3 có đúng 8 kênh LEDC, đã dùng hết. Nhiều kênh hơn cần PCA9685 / RMT / MCPWM.
- Chip trên xe thật: ESP32-S3 flash 16 MB + PSRAM 8 MB (`platformio.ini` đang để devkitc-1 N8 không PSRAM, vẫn chạy).
- Servo lấy nguồn 5–6 V từ BEC, không lấy từ board; GND chung.

### FW2. Xuất kênh

- Nhận `CONTROL_US`, xuất thẳng µs (kẹp 500–2500). Không chạy mix, không trim/Min/Max/reverse.
- Failsafe từng kênh, lưu NVS `rcfs`; quá `failsafeTimeoutMs` không có gói hoặc BLE ngắt → xuất failsafe. Từ khi bật nguồn tới gói đầu tiên: xuất failsafe.
- Firmware cũ (2 kênh) vẫn chạy được: xe tự áp trim/servo và tự khoá ga sau failsafe tới khi app gửi ga gần 0.

### FW3. Làm mượt servo 🟡

- `servo::Smooth` (`servo_logic.h`): kênh do app điều khiển đi tới giá trị mới trong một khoảng gói (đo trung bình, kẹp 10–60 ms), cập nhật mỗi ms. Failsafe và giá trị gõ tay nhảy ngay.
- `ledcWrite` chỉ gọi khi duty đổi.
- **Tần số PWM từng kênh** 50–333 Hz (tối đa 4 tần số khác nhau vì 4 timer LEDC), NVS `rchz`, mặc định 50 Hz; > 50 Hz chỉ cho servo digital.
- **Vùng chết từng kênh** 0–20 µs (NVS `rcdb`) cho servo analog.

### FW4. Lệnh Serial (debug)

`help` · `ch <n> <us>` (500–2500; trên kênh app đang điều khiển chỉ được khi failsafe, bị xoá khi có lại tín hiệu) · `smooth on|off` · `hz <n> <Hz>` / `hz all <Hz>` · `db <n> <µs>` · `net info|setup|reset`.

- `ARDUINO_USB_CDC_ON_BOOT=1`: `Serial` = USB gốc, cổng CH343 là `Serial0`. Mọi log qua `dbg::log` (ghi cả hai cổng).

### FW5. LED trạng thái 🟡

- **Màu** (đường nối): xanh dương = AP · xanh lá = Router · cam = BLE · tím thở = chế độ cấu hình · đỏ nháy nhanh = mất tín hiệu lúc đang lái (tối đa 10 s rồi về chờ app) · trắng = đang khởi động.
- **Kiểu nháy** (trạng thái): chớp chậm = chờ app · nháy nhanh = đang vào router · thở = app đã nối, chưa lái · sáng đứng = đang lái.
- Logic ở `status_led.h` (không gọi phần cứng, test được trên PC). Nháy "Tìm xe" (F8) chưa làm.

### FW6. Build

- PowerShell: `& "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe" run` trong `firmware/` (Git Bash lỗi toolchain). Nền tảng pioarduino 55.3.312, Arduino core 3.3.12 (NimBLE).
- Nạp: `pio run -t upload --upload-port COMx` (chạy `pio device list` trước; xe là CH343 `1A86:55D3`).
- Host test C++: `C:\msys64\ucrt64\bin\g++ -std=c++17`.
- Có hai bản firmware: `rc_car/firmware` (git) và `D:\PLG_GROUP\firmware` (mở trong IDE). Sửa bản git rồi chép sang.

---

## 13. Nhóm V — Kiểm tra dữ liệu

| Đối tượng | Luật | Mức |
|---|---|---|
| Hồ sơ | Tên 1–32 ký tự, không trùng | Lỗi |
| Kết nối | IPv4 hợp lệ; port 1–65535 | Lỗi |
| Kênh | 500 ≤ Min < Center < Max ≤ 2500 µs; Failsafe trong [Min, Max]; timeout 100–3000 ms | Lỗi |
| Input | `id` đúng mẫu, không trùng; `name` 1–24; kiểu phần tử khớp `type`; ≤ 48 | Lỗi |
| Condition | `input` tồn tại; `hyst` chỉ với so sánh lớn/nhỏ; sâu ≤ 4; ≤ 8 `cmp`; `ref` không vòng; ≤ 32 | Lỗi |
| Luật | `source` tồn tại; `destCh` 1…10; `minPct < maxPct`; giá trị trong khoảng M1; ≤ 64 | Lỗi |
| Luật | Priority ≥ 8 mà bật khoá an toàn | Lỗi |
| Luật | Ghi vào kênh đang tắt | Cảnh báo |
| Vai trò Ga/Lái | Không có luật ghi vào kênh, hoặc Input nguồn không có phần tử trên bố cục | Cảnh báo |
| Bố cục | Input được luật dùng nhưng không có phần tử | Cảnh báo |
| Tự về | `targetPct` ngoài khoảng; `positiveOnly` và `negativeOnly` cùng bật | Lỗi |
| Mạng của xe | Xem W4 | Lỗi |

Lỗi hiện ngay dưới ô nhập và khoá nút Lưu; cảnh báo hiện vàng, vẫn lưu được.

---

## 14. Nhóm J — Dữ liệu hồ sơ và chuyển đổi

### J1. Cấu trúc (schemaVersion 2)

```
CarProfile
├── id, name, icon, connType, wifi{ip, port, ssid?, carId?}, ble{mac, deviceName}
├── updatedAt, lastSyncedAt, lastSyncedHash, lastConnectedAt
├── inputs[]          InputDef        (I1)
├── conditions[]      ConditionDef    (K3)
├── mixer[]           MixRule         (M1)
├── channels[10]      ChannelConfig   (O1)
├── throttleCh?, steeringCh?          (O5)
├── failsafeTimeoutMs
├── arm               { enabled, autoArm, armCondition? }
├── output            { protocol, periodMs }
├── ping              PingConfig
├── statusItems[]     (H9)
├── layouts[]         ControlLayout   (H1)
└── activeLayoutId
```

Trường vắng mặt nhận giá trị mặc định; `channels` khi lưu luôn ghi đủ 10.

### J2. Ví dụ (A / Slider X)

```json
{
  "schemaVersion": 2,
  "id": "3f1c…",
  "name": "CAR_01",
  "connType": "wifi",
  "wifi": { "ip": "192.168.4.1", "port": 4210 },
  "throttleCh": 2, "steeringCh": 1,
  "inputs": [
    { "id": "steer",    "name": "Lái",      "type": "axis",   "range": "bipolar" },
    { "id": "throttle", "name": "Ga",       "type": "axis",   "range": "bipolar" },
    { "id": "slider_x", "name": "Slider X", "type": "axis",   "range": "bipolar" },
    { "id": "btn_a",    "name": "Nút A",    "type": "binary", "levels": { "offPct": -100, "onPct": 100 } }
  ],
  "conditions": [],
  "mixer": [
    { "id": "r_steer", "source": "steer",    "destCh": 1, "combine": "replace" },
    { "id": "r_thr",   "source": "throttle", "destCh": 2, "combine": "replace" },
    { "id": "r_ch1", "source": "slider_x", "destCh": 1, "combine": "replace", "priority": 1,
      "condition": { "op": "cmp", "input": "btn_a", "cmp": "==", "value": 1 },
      "safety": { "requireNeutral": true, "deadzonePct": 5 } },
    { "id": "r_ch8", "source": "slider_x", "destCh": 8, "combine": "replace",
      "condition": { "op": "cmp", "input": "btn_a", "cmp": "==", "value": 0 },
      "safety": { "requireNeutral": true, "deadzonePct": 5 } }
  ],
  "channels": [
    { "index": 1, "name": "Lái", "minUs": 1100, "centerUs": 1500, "maxUs": 1900, "failsafeUs": 1500, "enabled": true },
    { "index": 2, "name": "Ga",  "minUs": 1000, "centerUs": 1500, "maxUs": 2000, "failsafeUs": 1500, "enabled": true },
    { "index": 8, "name": "Phụ", "minUs": 1100, "centerUs": 1500, "maxUs": 1900, "failsafeUs": 1500, "enabled": true }
  ],
  "failsafeTimeoutMs": 400,
  "arm": { "enabled": true, "autoArm": false },
  "statusItems": ["link", "battery", "rssi"],
  "layouts": [
    { "id": "l1", "name": "Mặc định", "cols": 48, "rows": 24, "items": [
      { "id": "i1", "kind": "stickV", "inputId": "throttle", "x": 2,  "y": 4,  "w": 6,  "h": 18 },
      { "id": "i2", "kind": "stickH", "inputId": "steer",    "x": 30, "y": 14, "w": 16, "h": 6 },
      { "id": "i3", "kind": "knob",   "inputId": "slider_x", "x": 20, "y": 14, "w": 8,  "h": 8 },
      { "id": "i4", "kind": "toggle", "inputId": "btn_a",    "x": 20, "y": 6,  "w": 6,  "h": 4 }
    ] }
  ],
  "activeLayoutId": "l1"
}
```

CH1 do `r_steer` điều khiển; khi A = 1, `r_ch1` (priority 1, `replace`) đè lên và Slider X điều khiển CH1.

### J3. JSON Schema ⬜

`app/assets/schema/profile.v2.schema.json` (draft 2020-12) để kiểm tra file khi nhập — chưa có; hiện kiểm tra bằng code (V).

### J4. Chuyển hồ sơ cũ ✅

`profile_migration.dart` chạy khi đọc file `schemaVersion` < 2 (v0 → v1 → v2). File gốc sao lưu `profiles/<id>.v1.bak` (không đuôi `.json` để không bị đọc lại), rồi ghi bản mới. Có **báo cáo chuyển đổi** (hộp thoại một lần ở màn chính, `migrationReports`).

| Sprint 3 | Sprint 4 |
|---|---|
| Kênh N gán vào phần tử | Input `ch{N}` (tên = tên kênh, kiểu theo phần tử đầu tiên) + luật `ch{N} → CHN, replace, priority 0` |
| `channels[N].offValuePct` | `inputs["ch{N}"].levels.offPct` |
| `item.channel` / `channelY` | `item.inputId` / `inputIdY` = `ch{N}` |
| Hai bố cục gán kênh N vào hai **kiểu** phần tử khác nhau | Input thứ hai `ch{N}_2`, không tạo luật; cảnh báo |
| Luật linear / curve | `source = ch{src}`, `weight = gainPct`, `offset = offsetPct`, `curve = points(curvePts)`; override→replace, add→add, max→max; priority 1 |
| `gateCh` | `condition = ch{gate} > 0` |
| Luật threshold | Hai luật hằng số cùng đích, priority 1: `onValue` khi `ch{src} >= onAt, hyst = onAt − offBelow`; `offValue` khi `not (…)` |
| Hằng số / kênh nguồn không có phần tử | Input hằng `k_{giá trị}` (vd `k_100`, `k_m40`, `k_0`) |
| Luật `max` ghi vào kênh không có phần tử | Thêm luật gốc `k_0 → CHn` (priority 0) |
| Luật Sprint 3 (không phải select) | `safety.requireNeutral = false` |
| Luật select | Hai luật: nguồn → `targetOnCh` khi `ch{select} > 0`; → `targetOffCh` khi `not`; safety lấy từ `requireNeutralToSwitch` / `neutralDeadzonePct` |
| Luật đang bật ghi vào kênh tắt | Bật kênh |
| Chuỗi CH1→CH3→CH5 | Dùng Input của kênh nguồn (giá trị trước mix); cảnh báo "kết quả có thể khác" |
| Hộp số có giới hạn ga | Bỏ; cảnh báo |
| Không có `throttleCh` / `steeringCh` | Mặc định 2 / 1 |
| Bố cục 24 × 12 | Nhân ×2 thành 48 × 24 |

Sau khi chuyển: chạy V; có lỗi thì vẫn mở được hồ sơ nhưng hiện danh sách lỗi và khoá lái tới khi sửa.

---

## 15. Mã nguồn

```
app/lib/
  main.dart
  l10n/         lang.dart                                   (A4)
  theme/        app_theme.dart, tokens.dart, app_icons.dart, theme_controller.dart
  models/       car_profile.dart, channel_config.dart, input_def.dart, condition.dart,
                mixer_rule.dart, control_layout.dart, data_source.dart, ping_config.dart
  data/         profile_repository.dart, profile_migration.dart
  protocol/     protocol.dart, net_protocol.dart
  transport/    transport.dart, udp_transport.dart, ble_transport.dart
  controller/   car_controller.dart
  services/     input_manager.dart, condition_engine.dart, mixer_engine.dart, output_pipeline.dart,
                arm_controller.dart, car_connector.dart, car_discovery.dart, ping_service.dart, quick_ping.dart
  screens/      garage_screen.dart (màn chính), profile_wizard_screen.dart, control_screen.dart,
                settings_screen.dart, input_screen.dart, mix_rule_screen.dart, channel_detail_screen.dart,
                network_screen.dart, app_settings_screen.dart
  widgets/      channel_tile.dart, condition_builder.dart, hold_repeat.dart, layout_preview.dart,
                mix_preview.dart, mix_rule_card.dart, number_field.dart, status_badge.dart, status_strip.dart
  layout/       layout_canvas.dart, layout_grid.dart, item_widgets.dart, properties_panel.dart,
                layout_templates.dart, layout_history.dart, return_motion.dart
app/assets/     fonts/ (Barlow), icons/ (bluetooth, car, speedometer, steering)
app/test/       xem mục 16; support/ (fake_car.dart, sprint3_reference.dart), fixtures/sprint3_profile.json
firmware/src/   main.cpp, protocol.h, servo_logic.h, net_config.h, net_manager.{h,cpp}, status_led.h, debug.cpp
tools/          fake_car.py (--channels, --legacy, --no-ack)
preview/        ui_preview.html (mockup HTML, cập nhật sau mỗi thay đổi giao diện)
```

`test/support/sprint3_reference.dart` + `test/fixtures/sprint3_profile.json` là bản đóng băng thuật toán Sprint 3 dùng cho test migration — **không xoá**.

---

## 16. Kiểm thử

### 16.1 Tự động

| File | Nội dung | Trạng thái |
|---|---|---|
| `profile_test.dart` | Lưu → đọc → so sánh; nâng schema; kiểm tra dữ liệu | ✅ |
| `migration_v2_test.dart` | Mỗi dòng bảng J4 một ca; hồ sơ Sprint 3 thật chuyển xong qua V; **so µs Sprint 3 và Sprint 4** trên cùng chuỗi đầu vào | ✅ |
| `condition_engine_test.dart` | 6 toán tử × 4 kiểu Input; AND/OR/NOT 4 tầng; hysteresis (bảng K2, reset khi DISARM); `ref` dùng chung trạng thái; `ref` vòng | ✅ |
| `mixer_engine_test.dart` | 5 kiểu combine; priority; kênh không có luật = 0%; bảng M4; priority 9 tác động ngay; unipolar + Toàn dải; hiệu năng 64/32/48, 10 000 chu kỳ, p99 ≤ 2 ms (PC) | ✅ |
| `output_pipeline_test.dart` | % → µs, reverse, trim, kẹp Min/Max | ✅ |
| `arm_controller_test.dart` | Mọi cạnh R1; không ARM khi ga lệch / đang sửa / `armCondition` sai; tự DISARM khi xuống nền; ARM tắt | ✅ |
| `channel_protocol_test.dart` | CONTROL_US, INFO, FS_WRITE/FS_ACK (hash `0xce5e49da`), lùi về 2 kênh | ✅ |
| `net_protocol_test.dart` | Khớp từng byte với firmware; kiểm tra dữ liệu; CarController với xe giả; CarDiscovery qua UDP loopback | ✅ |
| `network_screen_test.dart` | Màn Mạng của xe: mở, đọc, báo lỗi, đổi chế độ, lưu, sửa hồ sơ | ✅ |
| `layout_test.dart` | Bám lưới, chống chồng lấn, kích thước, tự về, `restPct` (lỗi H5-1) | ✅ |
| `ping_window_test.dart` | Gói mất, về sau timeout, sai thứ tự | ✅ |
| `screens_test.dart`, `widget_test.dart`, `app_settings_test.dart` | Màn hình, nằm ngang 800 × 360, song ngữ, ARM → không bật hộp thoại | ✅ |
| Host test C++ (`net_config.h`, `servo_logic.h`, `status_led.h`) | Kiểm tra dữ liệu, vòng ghi/đọc, giữ mật khẩu, gói hỏng, gói 115 byte; làm mượt | ✅ |
| Build firmware ESP32-S3 | pioarduino, core 3.3.12 | ✅ |

Quy ước: test kiểm chuỗi tiếng Việt (ngôn ngữ mặc định); test đổi sang EN phải trả về VN trong `tearDown`.

### 16.2 Trên thiết bị thật (chưa làm)

| # | Nội dung |
|---|---|
| T1 | Android + ESP32: WiFi và BLE; rút nguồn phát giữa chừng → failsafe |
| T2 | 8 servo trên đúng chân (oscilloscope/servo); làm mượt, `hz`, `db` với servo analog (EMAX ES08MA II giật) |
| T3 | Router: 15 s không vào được → về AP, báo đúng lý do (tắt router / sai mật khẩu) |
| T4 | Điện thoại 5 GHz + xe 2.4 GHz cùng router: Tìm xe + lái |
| T5 | IP tĩnh; ping chế độ Router so với AP; lái 10 phút không failsafe nhầm |
| T6 | Nút BOOT 3 s / 10 s; chế độ cấu hình tự thoát sau 5 phút |
| T7 | LED đúng màu / kiểu nháy ở từng chế độ |
| T8 | Hiệu năng mixer p99 ≤ 2 ms trên Android tầm trung |
| T9 | Ngưỡng LQ 70% / ping 200 ms có hợp lý không |
| T10 | Mất kết nối rồi nối lại: trim vẫn hoạt động (dò INFO 500 ms × 3) |
| T11 | Chọn xe + tự nối khi mở app; từ chối xe sai mã |

---

## 17. Tiêu chí nghiệm thu

**Giao diện**
- [ ] Không còn mã màu viết cứng trong `screens/` và `widgets/`.
- [ ] Đổi theme, ngôn ngữ, màu chủ đạo thì mọi màn đổi đúng ngay.
- [ ] Màn Cấu hình dùng được khi cầm ngang (800 × 360).

**Hồ sơ**
- [ ] Tắt WiFi/BT điện thoại vẫn tạo, sửa, lưu được hồ sơ.
- [ ] Nối xe thì app tự ghi failsafe; sửa trim / mix / Min–Max khi đang nối thì xe đổi ngay.
- [ ] Xuất rồi nhập trên máy khác ra hồ sơ giống hệt; file sai schema thì báo rõ trường sai, không ghi đè.
- [ ] Mở app tự nối xe đang chọn; hai hồ sơ cùng IP không cùng hiện "Đã kết nối".

**Mixer**
- [ ] Hồ sơ J2: A bật thì CH1 theo núm, CH8 = Center; A tắt thì CH8 theo núm, CH1 theo cần lái.
- [ ] Gạt A khi núm 70%: kênh cũ giữ 70% tới khi núm ≤ 5% mới chuyển.
- [ ] Luật khẩn cấp `btn_stop == 1 → CH2 = 0%, priority 9` đè ga ngay khi đang ga hết cỡ.
- [ ] `steer >= 80, hyst 10 → CH3 = 100%` chạy đúng bảng K2.
- [ ] Mở hồ sơ Sprint 3 (đèn, còi, luật select và threshold): tự chuyển, có báo cáo, ra **cùng µs** như Sprint 3.
- [ ] Đổi bố cục dùng chung Input: mix vẫn đúng.

**ARM và an toàn**
- [ ] Vừa nối: xe nhận `failsafeUs`, không chạy tới khi giữ ARM 1 s; đang giữ ga thì không ARM được.
- [ ] Tắt cơ chế ARM: thả ga là lái được; vẫn ngắt kết nối được.
- [ ] App xuống nền khi ARMED: tự DISARM, xe nhận `failsafeUs`.
- [ ] Mất sóng: xe về failsafe đã đồng bộ, không giữ giá trị mix.

**Màn Lái**
- [ ] Bố cục giữ nguyên sau khi thoát và mở lại app; phần tử không chồng nhau; bố cục từ điện thoại 6" mở trên tablet đúng vị trí tương đối.
- [ ] Không vào được sửa bố cục khi đang giữ ga; ga "Vị trí về = −28%" thả tay thì vào được.
- [ ] Cần lái "về 0% trong 300 ms": xe nhận giá trị giảm dần.
- [ ] Đang ARMED không có hộp thoại nào bật lên màn Lái.

**Xe 8 kênh và mạng**
- [ ] App điều khiển đủ 8 kênh; app cũ (2 kênh) vẫn lái được, CH3–CH8 ra failsafe.
- [ ] Đổi xe sang Router, điện thoại 5 GHz vẫn tìm và lái được; router tắt thì 15 s sau xe phát WiFi riêng.
- [ ] Mật khẩu WiFi không bao giờ xuất hiện trong gói từ xe ra.

---

## 18. Việc còn mở

| # | Việc | Nhóm |
|---|---|---|
| 1 | Toàn bộ thử trên xe/máy thật (16.2) | — |
| 2 | Huy hiệu "Chưa đồng bộ failsafe" (dùng `lastSyncedHash`) | E5 |
| 3 | "Tìm xe": IDENTIFY trên firmware + nháy LED + nút trong app | F8, FW5 |
| 4 | Màn Chẩn đoán kết nối | F5 |
| 5 | `fake_car.py --delay / --jitter / --loss` | F7 |
| 6 | Bố cục mẫu Thuận tay trái / Tay cầm / Tối giản, Lật ngang, đổi bố cục nhanh | H4 |
| 7 | JSON Schema cho nhập hồ sơ | J4 |
| 8 | Interface `OutputProtocol` (UART / MAVLink / SBUS sau này) | O4, C5 |
| 9 | Đo dòng thật (INA219); hiện `current` luôn 0 | H7, FW |
| 10 | Xác nhận chân nút BOOT và chân LED theo mạch thật | FW1 |
| 11 | QR WiFi trong app (hiện dùng camera hệ thống với nhãn `WIFI:S:RC-CAR;T:WPA;P:12345678;;`) | W6 |
| 12 | Bảo mật trước khi phát hành: NVS encryption, xác thực BLE | W8 |
| 13 | `preview/ui_preview.html` chưa có phần tử kiểu TX (H8, H10, bảng kênh) | — |
| 14 | Kiểm tra độ tương phản WCAG cả hai theme | A9 |
| 15 | Mở rộng: tự nối lại BLE, OTA, ghi log telemetry, sparkline/đồng hồ kim/vùng màu cho phần tử hiển thị | — |

---

## 19. Các quyết định đã chốt

| # | Câu hỏi | Chốt |
|---|---|---|
| 1 | Mix và cấu hình kênh chạy ở xe hay app? | App. Xe chỉ nhận µs + failsafe (0.3) |
| 2 | Mô hình điều khiển | Input → Condition → Mixer → Kênh → ARM |
| 3 | Giới hạn | 64 luật · 32 Condition đặt tên · 48 Input · 10 kênh trong hồ sơ |
| 4 | Số kênh của xe | 8 (LEDC); PCA9685 nếu cần thêm |
| 5 | Giao thức n kênh | Trên khung 0xAA cũ, không dùng header "RC" |
| 6 | Hộp số | Bỏ |
| 7 | Kênh Ga/Lái | Người dùng chọn theo hồ sơ, có thể trống; mẫu "Trống" mặc định |
| 8 | ARM | Giữ nút 1 s, `autoArm` tắt; có thể tắt cả cơ chế ARM (vẫn phải thả ga) |
| 9 | READY gửi gì? | `failsafeUs` (giống lúc mất sóng) |
| 10 | Nút/công tắc tắt = −100% hay 0%? | Chỉnh được (`InputLevels`), mặc định −100% |
| 11 | Unipolar | 0…100 → Center…Max; nút *Toàn dải* (weight 200, offset −100) |
| 12 | Lưới bố cục | Bám ô, 48 × 24, không giới hạn kích thước lớn nhất |
| 13 | Chạm phần tử khi sửa | 1 chạm chọn, 2 chạm mở bảng thuộc tính |
| 14 | Hộp thoại khi lái | Không có khi ARMED |
| 15 | Ping | 1 lần/giây, LQ từ telemetry, cảnh báo LQ < 70% hoặc ping > 200 ms |
| 16 | Tên AP có hậu tố MAC? | Không (`RC-CAR`, đổi được); WiFi tạm có: `RC-SETUP-A1B2` |
| 17 | Rớt router khi đang chạy | Thử lại mãi; chỉ về AP lúc khởi động |
| 18 | Xe quét danh sách WiFi? | Không, người dùng gõ SSID |
| 19 | Khoá CONTROL theo IP | Có |
| 20 | App xem được mật khẩu đang lưu? | Không; để trống là giữ |
| 21 | Chế độ Cấu hình thử router tại chỗ? | Không; lưu → khởi động lại → lỗi thì tự về AP và báo lý do |
| 22 | Tên hiển thị | Màn chính "PCC TX Control"; nhãn launcher giữ "RC Controller" |

---

## 20. Tra mã mục cũ

Comment trong code còn nhắc mã mục của hai đặc tả đã xoá. Những mã **không** có trong bảng (A1–A3, E1–E8, F1–F8, H1–H6, H3b, H5-1, I1–I3, K1–K3, M1–M6, O1–O3, R1–R3, J1, J2, J4) giữ nguyên số và nội dung trong file này.

| Mã cũ | Ở đặc tả | Nội dung | Nay ở |
|---|---|---|---|
| B1 | Sprint 3 | Mô hình kênh, quy ước % | O1, O2 |
| B2 | Sprint 3 | Loại phần tử điều khiển | H1b |
| B3 | Sprint 3 | Tab Kênh | O7 |
| B4 | Sprint 3 | Chống gán trùng kênh | I3 (một Input một phần tử) |
| B5 | Sprint 3 | Ga/Lái sang hệ kênh, đổi qua lại cấu hình firmware v1 | O5, C3 |
| B6 | Sprint 3 | Kênh phụ trên màn Lái | H1b |
| C1 | Sprint 3 | Định dạng gói (header "RC" v2) | C1–C3 (khung 0xAA), C5 |
| C2 | Sprint 3 | Firmware: xuất µs, kẹp 500–2500, failsafe NVS | FW2 |
| C3 | Sprint 3 | Đồng bộ failsafe | E6 |
| C4 | Sprint 3 | `fake_car.py` | C4 |
| D1–D4 | Sprint 3 | Kiểm thử và bàn giao | 16 |
| G1–G6 | Sprint 3 | Mix 4 loại (`MixRule` cũ) | M1–M6; chuyển đổi ở J4 |
| G2a | Sprint 3 | Ngưỡng có hysteresis (bảng 0→75→82→72→69→78) | K2 |
| G2d | Sprint 3 | Luật select (chuyển kênh bằng nút) | M4 |
| G7 | Sprint 3 | Chấm mix khi lái | H11 |
| G10 | Sprint 3 | Test mix | 16.1 |
| H7, H8 | Sprint 3 | Liên quan nhóm khác / test bố cục | H1b / 16.1 |
| J3 | Sprint 4 | JSON Schema | J3 |
| J4 | Sprint 4 | Chuyển hồ sơ v1 → v2 | J4 |
| O4 | Sprint 4 | Protocol Engine | O4 |
| P1 | Sprint 4 | File mới và file đổi | 15 |
| P2 | Sprint 4 | Giao diện `InputManager` / `MixerEngine` / `OutputPipeline` | I6, M9, O4 |
| R3 | Sprint 4 | DISARM | R3 |
| U1 | Sprint 4 | Tab màn Cấu hình | E4 (nay 5 tab) |
| U2 | Sprint 4 | Tab Input | I5 |
| U3 | Sprint 4 | Tab Mix | M7 |
| U4 | Sprint 4 | Trình sửa luật | M8 |
| U5 | Sprint 4 | Gắn nhanh trên bảng thuộc tính ("Gửi tới kênh"), mẫu dựng bằng Input + luật | H3, E3 |
| U6 | Sprint 4 | Màn Lái: ARM, chấm mix, ô Kênh đầu ra | R1, H11, H1b (`channels`) |
| V | Sprint 4 | Kiểm tra dữ liệu | 13 |
| N1–N7 | Sprint 4 | Kiểm thử | 16.1 (N6, N7 trên thiết bị: 16.2) |
| 0.5 | Sprint 3 | Nguyên tắc app giữ cấu hình | 0.3 |
