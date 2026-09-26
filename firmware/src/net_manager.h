#pragma once
// Quản lý mạng của xe: 3 chế độ AP / Router (STA) / Cấu hình (AP tạm), lưu NVS,
// tự quay về AP khi không vào được router, nút cấu hình, trả lời DISCOVER.
// Đặc tả: dac_ta_wifi_3_che_do.md
#include "net_config.h"

namespace netm {

// Đọc cấu hình từ NVS (không bật WiFi). begin() tự gọi; dùng riêng khi tắt WiFi mà vẫn cần tên BLE.
void load();
// Gọi trong setup() trước khi mở UDP/BLE. `buttonPin` < 0 = không dùng nút.
void begin(int buttonPin);
// Gọi mỗi vòng loop(): máy trạng thái, nút, DISCOVER. Không chặn.
void loop();

net::Mode mode();                   // chế độ đang chạy
const net::NetConfig& config();     // cấu hình đã lưu (đang dùng)
net::NetConfig& pending();          // bản chờ cho NET_SET
net::NetStatus status();
int8_t rssi();                      // AP: RSSI điện thoại; STA: RSSI tới router
bool allowControl();                // false ở chế độ cấu hình
const char* modeName(uint8_t m);    // "AP" / "Router" / "Cấu hình"
// Lệnh gõ từ Serial Monitor: net info | net setup | net reset. false nếu không phải lệnh net
bool command(const char* line);

// Lệnh từ app. Đều khởi động lại xe sau ~500 ms để ACK kịp đi.
bool applyPending();                // false nếu bản chờ không hợp lệ
void restartIntoSetup();
void resetToDefaults();

}  // namespace netm
