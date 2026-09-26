# Hướng dẫn cài và chạy app bằng terminal

Toàn bộ hướng dẫn này chạy bằng dòng lệnh, không cần mở Android Studio hay VS Code.
Lệnh viết cho **PowerShell trên Windows**; bản Linux/macOS ghi kèm ở cuối mỗi mục khi có khác biệt.

Thư mục app là `app/`, đó là một project Flutter hoàn chỉnh (đã có sẵn `android/`, `windows/`),
**không cần** `flutter create` lại.

---

## 1. Kiểm tra máy đã có gì

```powershell
flutter --version          # cần Flutter 3.3 trở lên
java -version              # cần JDK 17
adb version                # thuộc Android SDK platform-tools
```

Nếu cả ba chạy được thì nhảy thẳng xuống [mục 3](#3-chạy-app).
Nếu `flutter` báo *not recognized*, có hai khả năng: chưa cài, hoặc đã cài nhưng chưa vào PATH.
Kiểm tra trước khi tải về cho đỡ mất công:

```powershell
# tìm SDK Flutter nằm đâu đó trên máy
Get-ChildItem C:\, D:\ -Filter "flutter" -Directory -Depth 2 -ErrorAction SilentlyContinue |
    Where-Object { Test-Path "$($_.FullName)\bin\flutter.bat" } |
    Select-Object -ExpandProperty FullName
```

> Trên máy đang dùng để viết tài liệu này, kết quả là `D:\flutter` — SDK đã có sẵn, chỉ thiếu PATH.

---

## 2. Cài đặt

### 2.1 Flutter SDK

Nếu lệnh tìm ở trên không ra gì thì cài mới. Cách gọn nhất là clone, khỏi phải tra link tải:

```powershell
git clone https://github.com/flutter/flutter.git -b stable D:\flutter
D:\flutter\bin\flutter.bat --version      # lần đầu chạy sẽ tự tải Dart SDK, hơi lâu
```

Không có git thì tải file zip tại <https://docs.flutter.dev/release/archive> (chọn channel
**Stable**, bản Windows mới nhất) rồi giải nén ra `D:\flutter`.

> Đặt SDK ở thư mục không có dấu cách và không cần quyền admin. `C:\Program Files\` hay gây lỗi
> lúc build.

### 2.2 Thêm Flutter vào PATH

```powershell
$old = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "D:\flutter\bin;" + $old, "User")
```

Đóng terminal, mở lại, rồi kiểm tra `flutter --version`.

> Chỉ sửa PATH của **User**, không đụng PATH hệ thống. Muốn gỡ thì xóa đoạn `D:\flutter\bin;` khỏi
> biến `Path` trong *Edit environment variables for your account*.

Linux/macOS — thêm vào `~/.bashrc` hoặc `~/.zshrc`:

```bash
export PATH="$HOME/flutter/bin:$PATH"
```

### 2.3 Android SDK và JDK

Cần cho việc build APK. Nếu máy đã cài Android Studio thì SDK thường nằm ở
`%LOCALAPPDATA%\Android\Sdk`. Không có thì cài bằng command line tools:

Tải *Command line tools only* ở cuối trang <https://developer.android.com/studio>, giải nén sao cho
đường dẫn thành `D:\dev-tools\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat`
(thư mục trong file zip tên là `cmdline-tools`, phải đổi tên thành `latest`).

Rồi cài các gói bắt buộc:

```powershell
$sdk = "D:\dev-tools\android-sdk"
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="$sdk" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="$sdk" --licenses
```

JDK 17 (Temurin) tải tại <https://adoptium.net/temurin/releases/?version=17>.

Chỉ cho Flutter biết SDK nằm đâu (chỉ cần khi Flutter không tự tìm ra):

```powershell
flutter config --android-sdk "D:\dev-tools\android-sdk"
[Environment]::SetEnvironmentVariable("JAVA_HOME", "D:\dev-tools\jdk\jdk-17.0.20.1+1", "User")
```

### 2.4 Xác nhận môi trường

```powershell
flutter doctor
```

Cần thấy dấu `[√]` ở **Flutter** và **Android toolchain**. Hai mục này có thể bỏ qua:

| Cảnh báo | Có sao không |
|---|---|
| `[X] Visual Studio not installed` | Không sao, trừ khi muốn chạy bản Windows desktop |
| `[!] Some Android licenses not accepted` | Chạy `flutter doctor --android-licenses` rồi bấm `y`; thực tế build APK vẫn chạy được |

---

## 3. Chạy app

```powershell
cd D:\PLG_GROUP\rc_car\app
flutter pub get
flutter devices          # xem có thiết bị nào
flutter run
```

Có nhiều thiết bị thì chỉ rõ:

```powershell
flutter run -d emulator-5554
```

### Phím tắt khi `flutter run` đang chạy

| Phím | Tác dụng |
|---|---|
| `r` | Hot reload — nạp lại code, giữ nguyên trạng thái màn hình |
| `R` | Hot restart — chạy lại app từ đầu |
| `q` | Thoát |

Lần build đầu tiên Gradle phải tải dependency nên mất **khoảng 6–7 phút**. Những lần sau dưới 1 phút.

---

## 4. Chọn thiết bị để chạy

### 4.1 Điện thoại Android thật — **khuyên dùng**

Đây là cách duy nhất test được WiFi và Bluetooth thật với xe.

1. Trên điện thoại: *Cài đặt → Giới thiệu*, bấm 7 lần vào *Số bản dựng* để mở Developer options.
2. Bật *USB debugging*.
3. Cắm cáp USB, chọn **Cho phép** khi máy hỏi.

```powershell
adb devices              # phải thấy máy, trạng thái "device"
flutter run
```

### 4.2 Android emulator

Xem được giao diện nhưng **không có Bluetooth**, và **không nối được tới xe thật**.

```powershell
$sdk = "D:\dev-tools\android-sdk"

# tải system image (~1.5 GB, chỉ làm một lần)
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="$sdk" "emulator" "system-images;android-36;google_apis;x86_64"

# tạo máy ảo tên rc_phone
& "$sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n rc_phone -k "system-images;android-36;google_apis;x86_64" -d pixel_6

# khởi động
& "$sdk\emulator\emulator.exe" -avd rc_phone
```

Mở terminal thứ hai rồi `flutter run`.

Muốn xem danh sách máy ảo đã tạo: `avdmanager list avd`. Xóa: `avdmanager delete avd -n rc_phone`.

### 4.3 Windows desktop

Cần cài Visual Studio kèm workload **Desktop development with C++** (~7 GB), sau đó:

```powershell
flutter run -d windows
```

### 4.4 Chrome / web — **không chạy được**

`udp_transport.dart` và `ble_transport.dart` đều `import 'dart:io'`, thư viện này không tồn tại
trên web nên sẽ lỗi lúc biên dịch. Đừng mất công thử.

---

## 5. Chạy thử không cần xe thật

`tools/fake_car.py` là một xe ESP32 giả lập, nói đúng giao thức UDP trong
[README](README.md#4-giao-thức). App không phân biệt được với xe thật.

```powershell
# terminal 1 — xe giả
cd D:\PLG_GROUP\rc_car
$env:PYTHONIOENCODING = "utf-8"
python tools\fake_car.py

# terminal 2 — app
cd D:\PLG_GROUP\rc_car\app
flutter run
```

Trong app, ở màn hình *Kết nối xe*, tab **WiFi**, sửa ô *Địa chỉ IP của xe*:

| Chạy trên | Điền IP |
|---|---|
| Android emulator | `10.0.2.2` — đây là địa chỉ máy tính nhìn từ bên trong emulator |
| Điện thoại thật | IP LAN của máy tính, hai máy phải chung WiFi (xem bằng `ipconfig`) |

Port giữ nguyên `4210`. Bấm **Kết nối**, badge phải chuyển sang xanh *Đã kết nối*.

Xe giả trả lời đủ `CONFIG_GET/SET/SAVE/RESET`, đẩy telemetry 10 Hz với pin, dòng, tốc độ mô phỏng
theo ga, và tự vào failsafe khi ngừng nhận lệnh quá 400 ms.

Xe giả chạy trên máy tính trong mạng LAN nên giống xe ở chế độ **Router**:

- Trình tạo xe, bước 2, nút **Tìm xe** thấy xe giả (cổng `4211`), chọn là điền sẵn IP của máy tính.
- **Cấu hình → Chung → Mạng của xe** đọc và sửa được cấu hình mạng giả. Bấm Lưu thì xe giả chỉ ghi
  log (xe thật sẽ khởi động lại), không đổi port hay chế độ thật.
- Firewall Windows phải cho Python nhận UDP cả cổng `4210` và `4211`.

> Chỉ giả lập được **WiFi/UDP**. Nhánh BLE không giả bằng script được vì `flutter_blue_plus` nói
> chuyện thẳng với Bluetooth stack của hệ điều hành chứ không qua socket.

Chạy với xe ESP32 thật thì bỏ qua mục này: nối điện thoại vào WiFi `RC-CAR` (mật khẩu `12345678`)
và giữ nguyên IP mặc định `192.168.4.1`.

---

## 6. Build file APK

```powershell
cd D:\PLG_GROUP\rc_car\app

flutter build apk --release                  # một file universal, chạy mọi máy, nặng hơn
flutter build apk --release --split-per-abi  # tách theo kiến trúc, mỗi file nhẹ hơn nhiều
```

File ra nằm ở `build\app\outputs\flutter-apk\`. Bản `arm64-v8a` hợp với gần như mọi điện thoại
Android đời mới.

Cài thẳng vào máy đang cắm:

```powershell
adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Thư mục `dist/` ở gốc repo chứa sẵn các bản APK đã build của phiên bản 1.0.0.

---

## 7. Dọn dẹp khi chạy xong

```powershell
# trong terminal đang chạy flutter run: bấm q
adb emu kill                    # tắt emulator
# trong terminal xe giả: bấm Ctrl+C

flutter clean                   # xóa thư mục build/ khi cần build lại từ đầu
taskkill /F /IM java.exe        # tắt Gradle daemon nếu muốn giải phóng RAM
```

---

## 8. Lỗi thường gặp

**`flutter: command not found` dù đã cài**
PATH chưa có hoặc terminal chưa mở lại. Xem [mục 2.2](#22-thêm-flutter-vào-path).

**`UnicodeEncodeError: 'charmap' codec can't encode character` khi chạy `fake_car.py`**
Console Windows mặc định dùng cp1252, không in được tiếng Việt. Đặt `$env:PYTHONIOENCODING = "utf-8"`
trước khi chạy.

**App báo "Kết nối thất bại: Xe không phản hồi"**
App gửi `CONFIG_GET` và chờ `CONFIG_DATA` ba lần, mỗi lần 800 ms. Không có trả lời nghĩa là gói
không tới đích. Kiểm tra theo thứ tự: xe giả đang chạy chưa, IP có đúng `10.0.2.2` trên emulator
chưa, firewall Windows có chặn Python không, port 4210 có bị chiếm không:

```powershell
netstat -ano -p UDP | Select-String ":4210"
```

**Android tự chuyển sang 4G làm mất kết nối với xe thật**
WiFi của xe không có internet nên Android bỏ qua. Khi có thông báo *Mạng này không có internet*,
chọn **Giữ kết nối**. Vẫn lỗi thì tắt dữ liệu di động lúc lái.

**Gradle build đứng rất lâu lần đầu**
Bình thường, nó đang tải dependency. Trên máy viết tài liệu này mất 385 giây. Nếu quá 15 phút
thì nhiều khả năng mạng bị chặn, thử `flutter clean` rồi chạy lại.

**Emulator không thấy xe nào ở tab Bluetooth**
Đúng như vậy, máy ảo không có phần cứng Bluetooth. Phải dùng điện thoại thật.

**Emulator hiện "System UI isn't responding", màn hình đen, hoặc ảnh chụp bị nhiễu sọc**
Máy ảo hết tài nguyên, thường xảy ra sau khi chạy nhiều phiên liên tiếp. Tắt hẳn rồi mở lại:

```powershell
adb emu kill
taskkill /F /IM java.exe        # giải phóng Gradle daemon, thường chiếm 400 MB
& "D:\dev-tools\android-sdk\emulator\emulator.exe" -avd rc_phone -no-snapshot
```

Đừng dùng `-gpu swiftshader_indirect` để chữa: render bằng phần mềm chậm tới mức System UI
treo ngay lúc khởi động. Giữ `-gpu auto`.

**Đừng dùng `adb shell monkey` để mở app**
`monkey` bơm cả sự kiện xoay màn hình, làm app đổi hướng ngoài ý muốn. Dùng
`adb shell am start -n com.plg.rc_controller/.MainActivity`, hoặc đơn giản nhất là `flutter run`.
