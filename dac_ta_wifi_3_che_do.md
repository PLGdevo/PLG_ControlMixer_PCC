# Đặc tả WiFi 3 chế độ — AP · Router · Cấu hình

> Xe có 3 chế độ mạng: phát WiFi riêng để lái trực tiếp (**AP**), vào router nhà để lái qua router (**Router**), và phát WiFi tạm để sửa cấu hình mạng (**Cấu hình**). Mọi thông số mạng của xe chỉnh được trong app, màn **Mạng của xe**.
>
> Phiên bản: **0.2 — đã làm, chưa test trên xe thật** · Ngày: 26/09/2026 · Dự án: `rc_car`
>
> **Thay đổi so với bản 0.1 (phác thảo):** app chỉnh được toàn bộ cấu hình mạng (tên, port, WiFi riêng, WiFi router, IP động/tĩnh), không chỉ SSID + mật khẩu router. Chế độ Cấu hình chỉ là WiFi tạm để nối vào sửa, **không** thử router tại chỗ: xe lưu rồi khởi động lại, không vào được router thì tự về AP và báo lý do. Gói tin đổi thành đọc/ghi theo section (N2). Tên WiFi riêng mặc định giữ `RC-CAR` vì giờ đã đổi được trong app.
>
> Giữ nguyên: khung gói v1 `[0xAA][type][len][payload][crc8]`, BLE chạy song song, failsafe và ARM phía xe.

---

## 0. Tổng quan

### 0.1 Ba chế độ

| # | Chế độ | Xe | Điện thoại | Địa chỉ xe | Dùng khi |
|---|---|---|---|---|---|
| 1 | **AP** | Phát WiFi riêng (mặc định `RC-CAR` / `12345678`) | Vào WiFi của xe | IP tĩnh, mặc định `192.168.4.1` | Ngoài trời, không có router |
| 2 | **Router** | Vào router, băng 2.4 GHz | Vào cùng router, băng 2.4 hoặc 5 GHz | IP động (DHCP) hoặc tĩnh | Trong nhà, điện thoại vẫn có internet |
| 3 | **Cấu hình** | Phát WiFi tạm `RC-SETUP-A1B2`, không nhận lệnh lái | Vào WiFi tạm | Như IP của WiFi riêng | Sửa mạng khi không nối được bằng cách khác |

`A1B2` là 2 byte cuối MAC của xe. Mật khẩu WiFi tạm = mật khẩu WiFi riêng.

ESP32-S3 chỉ có sóng 2.4 GHz. Điện thoại ở băng 5 GHz vẫn tới được xe vì router nối hai băng vào cùng một mạng LAN. Ngoại lệ: mạng khách (guest) và router bật "AP isolation" sẽ chặn.

### 0.2 Chuyển chế độ

```
                        ┌─────── giữ nút BOOT 3 s / lệnh NET_SETUP ────────┐
                        ▼                                                  │
  bật nguồn      ┌──────────────┐  "Lưu" (NET_APPLY) → khởi động lại ┌──────────────┐
  ─────────────► │ 3. CẤU HÌNH  │ ─────────────────────────────────► │ 2. ROUTER    │
                 │ WiFi tạm     │   (vào chế độ đã chọn khi bật)      │ STA          │
                 └──────────────┘                                    └──────────────┘
                        │ 5 phút không có máy nối                      │    ▲
                        ▼                                   không vào được │    │ "Lưu" với
                 ┌──────────────┐ ◄────────────── router sau 15 s ────────┘    │ chế độ Router
                 │ 1. AP        │ ─────────────────────────────────────────────┘
                 └──────────────┘
```

Khi bật nguồn (`netm::begin`):

1. Vừa khởi động lại bằng lệnh / nút vào chế độ cấu hình (cờ trong RTC, chỉ tin khi reset do phần mềm) → **chế độ 3**.
2. NVS `rcnet` có `bootMode = Router` và có SSID → thử vào router trong **15 s**. Được thì ở chế độ 2. Không được thì **về chế độ 1** cho lần chạy này, ghi lại lý do (không thấy mạng / sai mật khẩu / không nhận IP / lỗi), lần bật sau thử lại.
3. Còn lại → chế độ 1. Xe mới (NVS trống) vào chế độ 1 nên lái được ngay.

Đang ở chế độ 2 mà rớt router thì chỉ thử lại, **không** chuyển AP (IP sẽ đổi); failsafe của xe tự lo. Chế độ 3 không bao giờ được lưu: mất điện giữa chừng thì lần sau về chế độ đã lưu.

---

## 1. Nhóm W — Firmware

| File | Nội dung |
|---|---|
| `net_config.h` | Cấu hình mạng (struct lưu NVS), mặc định, kiểm tra (`validConfig`), mã hoá section / HERE. Không phụ thuộc Arduino, test được trên PC |
| `net_manager.{h,cpp}` | Máy trạng thái 3 chế độ, NVS, quay về AP, nút, DISCOVER, lệnh Serial |
| `main.cpp` | Nhận gói NET_*, khoá CONTROL theo IP, telemetry RSSI/cờ cấu hình, tên BLE lấy từ cấu hình |

### W1. Cấu hình lưu trên xe

| Nhóm | Trường | Kiểm tra |
|---|---|---|
| Chung | `bootMode` (AP/Router), `udpPort`, `name` (tên BLE + hostname) | port 1–65535, khác 4211; tên 1–20 ký tự `A-Z a-z 0-9 -`, không bắt đầu/kết thúc bằng `-` |
| WiFi riêng | `apSsid`, `apPass`, `apChannel`, `apIp` | SSID 1–32 byte; mật khẩu 8–63 ký tự ASCII; kênh 1–13; IP host hợp lệ, số cuối 1–254, mạng /24 |
| WiFi router | `staSsid`, `staPass`, `staDhcp`, `staIp`, `staGateway`, `staSubnet`, `staDns` | SSID bắt buộc khi `bootMode = Router`; mật khẩu trống (mạng mở) hoặc 8–63; IP tĩnh: mask liền 8–30 bit, IP và gateway cùng mạng, khác nhau, không phải địa chỉ mạng/broadcast; DNS trống = dùng gateway |

App kiểm tra giống hệt (`NetConfig.validate`) để báo lỗi theo ô trước khi gửi.

Cấu hình mạng **nằm trên xe**, không nằm trong hồ sơ app (xe cần nó lúc khởi động; hồ sơ xuất ra file không mang mật khẩu). Đây là ngoại lệ của nguyên tắc 0.5 Sprint 3.

### W2. Chế độ Router

- `WiFi.setHostname(name)` trước khi bật STA; IP tĩnh qua `WiFi.config(ip, gateway, subnet, dns)`.
- **`WiFi.setSleep(false)`**: ở STA, ESP32 mặc định bật modem sleep, gây giật khoảng 100 ms.
- `WiFi.persistent(false)`: thư viện WiFi không tự lưu thông tin vào NVS riêng của nó.
- RSSI telemetry = `WiFi.RSSI()` (tới router). Chế độ AP vẫn là RSSI điện thoại.

### W3. Chế độ Cấu hình

- Phát `RC-SETUP-A1B2`, kênh / IP / mật khẩu như WiFi riêng. UDP ở port đã cấu hình.
- Bỏ CONTROL, xe giữ failsafe, nhưng vẫn gửi telemetry có cờ `FLAG_NET_SETUP` (0x08) để app hiện *"Xe đang ở chế độ cấu hình mạng"*.
- Thoát: bấm Lưu trong app (khởi động lại vào chế độ đã chọn), hoặc 5 phút không có máy nối thì tự khởi động lại.

### W4. Vào chế độ Cấu hình / khôi phục

| Cách | Chi tiết |
|---|---|
| Nút | `PIN_NET_BUTTON` (mặc định GPIO0 = nút BOOT của DevKitC). Giữ **3 s khi xe đang chạy** rồi nhả → chế độ cấu hình; giữ **10 s** → mạng về mặc định. Không giữ nút lúc cắm điện (chip vào chế độ nạp firmware). Đặt `-1` nếu mạch dùng GPIO0 việc khác |
| App | Màn Mạng của xe → menu → *Chế độ cấu hình* / *Khôi phục mạng mặc định* |
| Serial | `net info` · `net setup` · `net reset` |

### W5. An toàn

- NET_SET / NET_APPLY / NET_SETUP / NET_RESET chỉ nhận khi xe **đứng yên** (failsafe hoặc ga < 5%); không thì `ACK(type, 2)`. App còn chặn thêm khi đang ARM.
- Mật khẩu không bao giờ gửi ra app (độ dài `0xFF`).
- Đang có điện thoại lái qua WiFi thì máy khác không chen vào được tới khi xe failsafe (quan trọng ở chế độ Router: ai cùng LAN cũng gửi UDP tới xe được).
- NVS **chưa mã hoá**: ai đọc được flash là đọc được mật khẩu. Đủ cho bản thử; sản phẩm thật cần NVS encryption.

---

## 2. Nhóm N — Giao thức

### N1. `MAX_PAYLOAD` 64 → 128

Section STA dài nhất 115 byte (SSID 32 + mật khẩu 63). BLE đã đặt MTU 185. Đổi ở `protocol.h`; app không giới hạn độ dài khi mã hoá.

### N2. Gói mới

| Mã | Tên | Chiều | Payload |
|---|---|---|---|
| `0x40` | NET_GET | App → Xe | `section:u8` |
| `0x41` | NET_DATA | Xe → App | `section:u8` · dữ liệu (bảng dưới) |
| `0x42` | NET_SET | App → Xe | `section:u8` · dữ liệu → ghi vào **bản chờ**, trả ACK |
| `0x43` | NET_APPLY | App → Xe | Kiểm tra bản chờ → lưu NVS → ACK → khởi động lại sau 500 ms |
| `0x44` | NET_SETUP | App → Xe | ACK → khởi động lại vào chế độ cấu hình |
| `0x45` | NET_RESET | App → Xe | ACK → mạng về mặc định, khởi động lại |
| `0x46` | DISCOVER | App → broadcast **:4211** | `nonce:u16` |
| `0x47` | HERE | Xe → App (unicast) | `nonce:u16` · `id[6]` · `ip[4]` · `udpPort:u16` · `mode:u8` · `name:str` |

ACK status: `1` OK · `0` dữ liệu sai · `2` xe đang chạy.

| Section | Dữ liệu |
|---|---|
| 0 STATUS (chỉ đọc) | `mode:u8` · `fellBack:u8` · `staResult:u8` · `rssi:i8` · `ip[4]` · `id[6]` · `setupLeftS:u16` · `clients:u8` |
| 1 GENERAL | `bootMode:u8` · `udpPort:u16` · `name:str` |
| 2 AP | `channel:u8` · `ip[4]` · `ssid:str` · `pass:str` |
| 3 STA | `dhcp:u8` · `ip[4]` · `gateway[4]` · `subnet[4]` · `dns[4]` · `ssid:str` · `pass:str` |

`str` = `len:u8` · byte UTF-8. Mật khẩu `len = 0xFF`: khi đọc là "có nhưng không gửi ra", khi ghi là "giữ mật khẩu cũ". IP theo thứ tự a.b.c.d. `staResult`: 0 chưa thử · 1 đang kết nối · 2 OK · 3 không thấy mạng · 4 sai mật khẩu · 5 không nhận IP · 6 lỗi.

DISCOVER dùng **cổng riêng 4211** (socket có `SO_BROADCAST`), không đổi theo port đã cấu hình, để app tìm được xe chưa biết port.

---

## 3. Nhóm D — Dò xe trong mạng

- Mã xe = MAC gốc (`esp_efuse_mac_get_default`), lưu vào hồ sơ (`wifi.carId`) khi mở màn Mạng của xe.
- Bấm **Kết nối** / **Kiểm tra** ở màn Xe của tôi, hồ sơ WiFi có mã xe: gửi DISCOVER tới `255.255.255.255` và broadcast /24 của từng mạng trên máy, 3 lần cách 300 ms, dừng ngay khi thấy đúng mã (tối đa 1,2 s). Thấy thì cập nhật IP/port trong hồ sơ, không thấy thì thử IP cũ.
- Không nối được và không thấy xe → báo kèm gợi ý: cùng router, không dùng mạng khách, xe không vào được router thì 15 s sau tự phát WiFi riêng.
- Trình tạo xe, bước 2 (WiFi): nút **Tìm xe** liệt kê xe trong mạng, chọn để điền IP / port / mã xe.
- App dùng địa chỉ gửi gói HERE làm IP của xe (đường chắc chắn tới được).

---

## 4. Nhóm S — Màn "Mạng của xe"

Mở từ **Cấu hình → Chung → Mạng của xe**. Cần đang nối xe (WiFi hoặc Bluetooth), vì cấu hình nằm trên xe.

| Phần | Nội dung |
|---|---|
| Trạng thái | Chế độ đang chạy, IP, port, sóng, số máy nối AP, thời gian còn lại (chế độ cấu hình), kết quả vào router, mã xe. Cảnh báo đỏ khi xe đang dự phòng vì không vào được router |
| Khi bật nguồn | WiFi riêng (AP) / Vào router nhà |
| Chung | Tên thiết bị, port UDP |
| WiFi riêng | SSID, mật khẩu (trống = giữ), kênh 1–13, IP của xe |
| WiFi router | SSID, *Mạng không có mật khẩu*, mật khẩu (trống = giữ), IP **Động (DHCP)** / **Tĩnh** (IP, gateway, subnet mask, DNS) |
| Nút | **Lưu vào xe & khởi động lại** (chỉ sáng khi có thay đổi hợp lệ; ở chế độ cấu hình là *Thoát chế độ cấu hình*). Menu: *Chế độ cấu hình (WiFi tạm)*, *Khôi phục mạng mặc định* |

Sau khi lưu: app ngắt kết nối, sửa hồ sơ (IP / port / SSID / mã xe; IP động thì để app dò) và hiện hướng dẫn nối lại theo chế độ mới. Màn Cấu hình tự nạp lại các ô kết nối.

**QR:** chưa làm trong app. Có thể in nhãn QR chuẩn WiFi lên xe, vd `WIFI:S:RC-CAR;T:WPA;P:12345678;;`, để camera điện thoại vào WiFi riêng / WiFi tạm mà không phải gõ mật khẩu.

---

## 5. Nhóm F — `fake_car.py`

Xe giả chạy trên máy tính trong LAN nên giống xe ở chế độ Router: trả lời DISCOVER ở cổng 4211, đọc/ghi được cấu hình mạng giả. Lệnh lưu chỉ ghi log, xe giả không đổi port hay chế độ thật.

---

## 6. Kiểm thử

| # | Nội dung | Trạng thái |
|---|---|---|
| T1 | `net_config.h`: kiểm tra dữ liệu, vòng ghi/đọc, giữ mật khẩu, gói hỏng, gói lớn nhất 115 byte | Host test C++ (g++) — qua |
| T2 | App: khớp từng byte với payload firmware in ra, kiểm tra dữ liệu, CarController với xe giả, CarDiscovery qua UDP loopback | `test/net_protocol_test.dart` — qua |
| T3 | Màn Mạng của xe: mở từ Chung, đọc, báo lỗi, đổi chế độ, lưu, hồ sơ được sửa | `test/network_screen_test.dart` — qua |
| T4 | Build firmware ESP32-S3 (pioarduino, Arduino core 3.3.12) | Qua |
| T5 | Xe thật: 15 s không vào được router → về AP, báo đúng lý do (tắt router / sai mật khẩu) | **Chưa** |
| T6 | Xe thật: điện thoại 5 GHz, xe 2.4 GHz cùng router, Tìm xe + lái | **Chưa** |
| T7 | Xe thật: IP tĩnh; độ trễ ping chế độ 2 so với 1, lái 10 phút không failsafe nhầm | **Chưa** |
| T8 | Xe thật: nút BOOT 3 s / 10 s; chế độ cấu hình tự thoát sau 5 phút | **Chưa** |

---

## 7. Đã chốt khi làm

| # | Câu hỏi | Chốt |
|---|---|---|
| Q1 | Tên AP có hậu tố MAC? | Không, giữ `RC-CAR` (đổi được trong app). WiFi tạm có hậu tố `RC-SETUP-A1B2` |
| Q2 | Mật khẩu WiFi tạm | Bằng mật khẩu WiFi riêng |
| Q3 | Rớt router khi đang chạy | Thử lại mãi; chỉ về AP lúc khởi động |
| Q4 | Xe quét danh sách WiFi? | Không, người dùng gõ SSID |
| Q5 | Nút cấu hình | GPIO0 (BOOT) mặc định, đổi ở `PIN_NET_BUTTON` — **cần xem lại theo mạch thật** |
| Q6 | LED báo chế độ | Chưa làm (mạch chưa có chân LED) |
| Q7 | Khoá CONTROL theo IP | Có |
| Q8 | App tự vào WiFi tạm / quét QR | Chưa; người dùng tự vào WiFi (hoặc quét QR bằng camera) |
