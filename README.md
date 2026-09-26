# RC Car: ESP32-S3 + Flutter

Dự án gồm hai phần dùng chung một giao thức nhị phân:

```
rc_car/
├── firmware/                 ESP32-S3 (PlatformIO, Arduino core 3.x)
│   ├── platformio.ini
│   └── src/
│       ├── protocol.h        định nghĩa gói tin (khớp với protocol.dart)
│       ├── servo_logic.h     trim / offset / endpoint / reverse / giới hạn số
│       ├── net_config.h      cấu hình mạng của xe + gói NET_* (test được trên PC)
│       ├── net_manager.*     WiFi 3 chế độ AP / Router / Cấu hình, dò xe, nút BOOT
│       └── main.cpp          UDP, BLE, PWM, failsafe, telemetry, NVS
└── app/                      Flutter
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── protocol/         protocol.dart, net_protocol.dart (mạng của xe, dò xe)
        ├── services/car_discovery.dart   tìm xe trong mạng router
        ├── transport/        transport.dart, udp_transport.dart, ble_transport.dart
        ├── controller/car_controller.dart
        ├── screens/          garage, control, settings, network (Mạng của xe), ...
        └── widgets/          spring_slider, status_badge, number_field
```

## 1. Đấu nối phần cứng

| ESP32-S3 | Nối tới | Ghi chú |
|---|---|---|
| GPIO 4 | Dây tín hiệu servo lái | |
| GPIO 5 | Dây tín hiệu ESC | |
| GPIO 1 | Giữa cầu chia áp pin | R1 = 100k (lên pin +), R2 = 10k (xuống GND), đo tối đa ~36 V |
| GPIO 6 | Cảm biến hall đo tốc độ | Tùy chọn, có kéo lên nội |
| GND | GND chung của ESC, servo, pin | **Bắt buộc** chung mass |

Servo lấy nguồn 5–6 V từ BEC của ESC hoặc BEC riêng, **không** lấy từ chân 3V3/5V của board ESP32. Nếu mạch của bạn khác, sửa các hằng số ở đầu `main.cpp` (chân, `BATT_DIVIDER`, `WHEEL_CIRC_CM`, `PULSES_PER_REV`).

## 2. Nạp firmware

**PlatformIO (khuyên dùng):** mở thư mục `firmware/` trong VS Code có cài PlatformIO, bấm Build rồi Upload. File `platformio.ini` đã trỏ tới nền tảng *pioarduino* để có Arduino core 3.x (bản PlatformIO chính thức vẫn ở core 2.x, không có hàm `ledcAttach`).

**Arduino IDE:** cài *esp32 by Espressif* phiên bản 3.x, chọn board *ESP32S3 Dev Module*, bật *USB CDC On Boot*, rồi đặt các file trong `src/` chung một thư mục sketch (đổi `main.cpp` thành `rc_car.ino`).

Mở Serial Monitor 115200 baud. Khởi động đúng sẽ thấy dòng `Mạng: AP  IP 192.168.4.1  UDP 4210  tên RC-CAR` và `RC car ready`. Gõ `net info` để xem lại trạng thái mạng.

Firmware chạy **WiFi và BLE cùng lúc**. Nếu chỉ dùng một loại, đặt `ENABLE_WIFI` hoặc `ENABLE_BLE` thành 0 để giảm độ trễ và tiết kiệm RAM.

## 3. Chạy app Flutter

`app/` đã là project Flutter hoàn chỉnh, chạy thẳng được:

```bash
cd app
flutter pub get
flutter run
```

Hướng dẫn đầy đủ bằng terminal — cài Flutter và Android SDK, tạo emulator, chạy thử bằng xe giả
lập khi chưa có phần cứng, build APK, xử lý lỗi thường gặp — xem [HUONG_DAN_CHAY.md](HUONG_DAN_CHAY.md).

### Quyền Android — `android/app/src/main/AndroidManifest.xml` (trong thẻ `<manifest>`)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

Đặt `minSdkVersion` ít nhất là 21 trong `android/app/build.gradle`.

### Quyền iOS — `ios/Runner/Info.plist`

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Dùng Bluetooth để điều khiển xe</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Dùng mạng WiFi cục bộ để điều khiển xe</string>
```

### Lưu ý khi dùng WiFi

WiFi của xe không có internet, nên một số máy Android sẽ tự chuyển sang dữ liệu di động và gói UDP không tới được xe. Khi Android hỏi "Mạng này không có internet, vẫn giữ kết nối?", hãy chọn **Giữ kết nối**. Nếu vẫn lỗi, tắt dữ liệu di động khi lái, hoặc cho xe vào router nhà (bên dưới).

### WiFi 3 chế độ

| Chế độ | Xe | Điện thoại |
|---|---|---|
| **WiFi riêng (AP)**, mặc định | Phát `RC-CAR` / `12345678`, IP `192.168.4.1` | Vào WiFi của xe |
| **Router** | Vào WiFi nhà băng 2.4 GHz, IP động hoặc tĩnh | Vào cùng router (2.4 hay 5 GHz đều được), vẫn có internet |
| **Cấu hình** | Phát WiFi tạm `RC-SETUP-xxxx` (mật khẩu như WiFi riêng), không nhận lệnh lái | Vào WiFi tạm để sửa |

Chỉnh trong app: **Cấu hình → Chung → Mạng của xe** (cần đang nối xe qua WiFi hoặc Bluetooth). Chỉnh được chế độ khi bật nguồn, tên thiết bị, port UDP, tên / mật khẩu / kênh / IP của WiFi riêng, tên / mật khẩu router và IP động (DHCP) hoặc tĩnh (IP, gateway, subnet, DNS). Bấm **Lưu vào xe & khởi động lại**.

- Ở chế độ Router, bấm **Kết nối** thì app tự tìm xe trong mạng theo mã xe, nên IP động đổi cũng không sao. Trình tạo xe có nút **Tìm xe**.
- Xe không vào được router trong 15 giây thì tự phát lại WiFi riêng, màn Mạng của xe báo lý do (không thấy mạng, sai mật khẩu...).
- Nút BOOT trên board: giữ 3 giây khi xe đang chạy → chế độ cấu hình; giữ 10 giây → mạng về mặc định. Không giữ nút lúc cắm điện.
- Router bật "AP isolation" hoặc điện thoại dùng mạng khách (guest) thì điện thoại không thấy xe.

Chi tiết: `dac_ta_wifi_3_che_do.md`.

## 4. Giao thức

Khung gói: `[0xAA][type][len][payload][crc8]`, little-endian, CRC-8 đa thức 0x07 tính trên `type + len + payload`.

| Type | Tên | Hướng | Payload |
|---|---|---|---|
| 0x01 | CONTROL | App → Xe, 40 Hz | throttle i16, steering i16 (−1000..1000), gear u8, seq u8 |
| 0x02 | TELEMETRY | Xe → App, 10 Hz | pin mV u16, dòng mA i16, tốc độ cm/s u16, rssi i8, flags u8, gear u8, lastSeq u8 |
| 0x10 | CONFIG_GET | App → Xe | không có |
| 0x11 | CONFIG_DATA | Xe → App | CarConfig 34 byte |
| 0x12 | CONFIG_SET | App → Xe | CarConfig; áp dụng ngay, **chưa lưu** |
| 0x13 | CONFIG_SAVE | App → Xe | không có; lưu vào flash |
| 0x14 | CONFIG_RESET | App → Xe | không có; về mặc định, lưu, trả CONFIG_DATA |
| 0x20 | ACK | Xe → App | type được xác nhận, status (1 = ok, 0 = lỗi, 2 = xe đang chạy) |
| 0x30–0x32 | PING / PONG / IDENTIFY | | đo độ trễ, "Tìm xe" |
| 0x40–0x45 | NET_GET / NET_DATA / NET_SET / NET_APPLY / NET_SETUP / NET_RESET | | cấu hình mạng của xe, xem `net_config.h` |
| 0x46 / 0x47 | DISCOVER / HERE | App → broadcast cổng **4211** / Xe → App | tìm xe trong mạng |

Gói mẫu để kiểm tra: CONTROL với throttle 500, steering −250, số 2, seq 7 là
`aa 01 06 f4 01 06 ff 02 07 46`.

## 5. Cách xe xử lý tín hiệu

1. **Giới hạn số:** ga × `gearLimit[số]` %.
2. **Reverse:** đảo dấu nếu bật.
3. **Tâm thực tế** = Center + Trim + Offset.
4. **Nội suy:** −1000 → Min, 0 → tâm thực tế, +1000 → Max. Trim/offset dời điểm giữa nhưng hành trình vẫn không vượt Min/Max.
5. **Failsafe:** quá `failsafeTimeoutMs` không có gói CONTROL, hoặc BLE bị ngắt, thì xuất ngay giá trị Failsafe của từng kênh.
6. **Arming:** sau failsafe hoặc khi mới bật nguồn, ga bị khóa ở 0 cho tới khi app gửi ga gần 0. Nhờ vậy xe không lao đi nếu bạn đang giữ ga lúc tín hiệu quay lại.

## 6. Kiểm tra trước khi chạy thật

Kê bánh xe lên khỏi mặt đất trong suốt quá trình này.

1. Bật xe khi chưa mở app: servo phải về giữa, ESC ở trung tính.
2. Kết nối, kéo từng slider: đúng chiều chưa? Nếu ngược, bật Reverse.
3. Chỉnh Min/Max của lái sao cho servo không kêu rè ở hai đầu hành trình.
4. Kiểm tra ESC: có thể cần calibrate ESC theo hướng dẫn của hãng để khớp 1000/1500/2000 µs.
5. **Test failsafe:** giữ ga ở mức thấp rồi tắt WiFi/Bluetooth trên điện thoại. Xe phải dừng trong khoảng thời gian đã đặt (mặc định 0,4 giây).
6. Kết nối lại khi vẫn đang giữ ga: xe **không** được chạy cho tới khi bạn nhả ga.
7. Chỉnh xong thì bấm **Lưu vào xe**, rồi tắt/bật nguồn xe để chắc cấu hình được giữ.

## 7. Hướng mở rộng

Các phần có thể thêm tiếp:

- Đo dòng thật bằng INA219 (chỗ `TODO` trong `sendTelemetry`).
- Tự kết nối lại BLE khi mất sóng.
- Quét QR trên xe ngay trong app để vào WiFi của xe (hiện dùng camera hệ thống với nhãn QR chuẩn `WIFI:S:...;T:WPA;P:...;;`).
- Cập nhật firmware qua WiFi (OTA).
- Ghi log telemetry ra file trên điện thoại.
