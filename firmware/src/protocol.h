#pragma once
// ============================================================================
//  Giao thức truyền thông App <-> Xe  (dùng chung cho WiFi UDP và BLE)
//
//  Khung gói:  [0xAA][type][len][payload ... len byte][crc8]
//  crc8: đa thức 0x07, init 0x00, tính trên (type, len, payload)
//  Tất cả số nhiều byte đều là little-endian.
// ============================================================================
#include <stdint.h>
#include <stddef.h>
#include <string.h>

namespace proto {

constexpr uint8_t HEADER      = 0xAA;
constexpr size_t  MAX_PAYLOAD = 64;
constexpr size_t  MAX_FRAME   = MAX_PAYLOAD + 4;

enum Type : uint8_t {
  CONTROL      = 0x01,  // app -> xe : ControlPayload, gửi 30-50 Hz (cũng là heartbeat)
  TELEMETRY    = 0x02,  // xe -> app : TelemetryPayload, 10 Hz
  CONFIG_GET   = 0x10,  // app -> xe : không payload
  CONFIG_DATA  = 0x11,  // xe -> app : CarConfig
  CONFIG_SET   = 0x12,  // app -> xe : CarConfig, áp dụng ngay (CHƯA lưu flash)
  CONFIG_SAVE  = 0x13,  // app -> xe : lưu cấu hình hiện tại vào flash
  CONFIG_RESET = 0x14,  // app -> xe : về mặc định + lưu, trả lời CONFIG_DATA
  ACK          = 0x20,  // xe -> app : [type được xác nhận][status: 1=ok, 0=lỗi]
  // Ping (F1/F2). Đặc tả v2 đặt PING ở 0x10 nhưng khung v1 đã dùng 0x10–0x14,
  // nên tới khi có giao thức v2 ping dùng 0x30–0x32.
  PING         = 0x30,  // app -> xe : PingPayload, trả PONG ngay trong vòng nhận
  PONG         = 0x31,  // xe -> app : PongPayload
  IDENTIFY     = 0x32,  // app -> xe : uint16 duration_ms ("Tìm xe", F8 — Sprint 4)
};

enum TelemetryFlags : uint8_t {
  FLAG_FAILSAFE = 1 << 0,
  FLAG_ARMED    = 1 << 1,
  FLAG_VIA_BLE  = 1 << 2,
};

#pragma pack(push, 1)
struct ControlPayload {        // 6 byte
  int16_t throttle;            // -1000..1000
  int16_t steering;            // -1000..1000
  uint8_t gear;                // 1..gearCount
  uint8_t seq;                 // tăng dần, để phát hiện mất gói
};

struct TelemetryPayload {      // 10 byte
  uint16_t batteryMv;
  int16_t  currentMa;
  uint16_t speedCms;           // cm/s
  int8_t   rssi;               // dBm (WiFi), 0 = không có
  uint8_t  flags;              // TelemetryFlags
  uint8_t  gear;
  uint8_t  lastSeq;
};

struct PingPayload {           // 6 byte
  uint16_t seq;
  uint32_t tSendMs;            // thời điểm gửi theo đồng hồ app, xe gửi lại nguyên vẹn
};

struct PongPayload {           // 10 byte
  uint16_t seq;
  uint32_t tSendMs;
  uint32_t uptimeMs;           // millis() của xe
};

struct ChannelConfig {         // 13 byte
  uint16_t minUs;              // giới hạn hành trình dưới
  uint16_t centerUs;           // điểm giữa / trung tính
  uint16_t maxUs;              // giới hạn hành trình trên
  int16_t  trimUs;             // tinh chỉnh khi chạy (±200)
  int16_t  offsetUs;           // bù lệch cơ khí (±300)
  uint8_t  reverse;            // 1 = đảo chiều
  uint16_t failsafeUs;         // xung xuất ra khi mất tín hiệu
};

struct CarConfig {             // 34 byte
  ChannelConfig throttle;
  ChannelConfig steering;
  uint16_t failsafeTimeoutMs;  // 100..3000
  uint8_t  gearCount;          // 1..5
  uint8_t  gearLimit[5];       // % ga tối đa cho từng số
};
#pragma pack(pop)

static_assert(sizeof(ControlPayload)   == 6,  "ControlPayload size");
static_assert(sizeof(TelemetryPayload) == 10, "TelemetryPayload size");
static_assert(sizeof(ChannelConfig)    == 13, "ChannelConfig size");
static_assert(sizeof(PingPayload)      == 6,  "PingPayload size");
static_assert(sizeof(PongPayload)      == 10, "PongPayload size");
static_assert(sizeof(CarConfig)        == 34, "CarConfig size");

inline uint8_t crc8(const uint8_t* data, size_t len) {
  uint8_t crc = 0;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (int b = 0; b < 8; b++)
      crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
  }
  return crc;
}

// Đóng gói; trả về số byte, 0 nếu lỗi
inline size_t encode(uint8_t type, const void* payload, uint8_t len, uint8_t* out) {
  if (len > MAX_PAYLOAD) return 0;
  out[0] = HEADER;
  out[1] = type;
  out[2] = len;
  if (len) memcpy(out + 3, payload, len);
  out[3 + len] = crc8(out + 1, 2 + len);
  return 4 + len;
}

// Giải gói; buf phải chứa đúng 1 khung
inline bool decode(const uint8_t* buf, size_t n, uint8_t& type,
                   const uint8_t*& payload, uint8_t& len) {
  if (n < 4 || buf[0] != HEADER) return false;
  len = buf[2];
  if (len > MAX_PAYLOAD || n != (size_t)len + 4) return false;
  if (crc8(buf + 1, 2 + len) != buf[3 + len]) return false;
  type = buf[1];
  payload = buf + 3;
  return true;
}

// Nếu buf là gói PING hợp lệ thì dựng gói PONG vào out; trả về số byte, 0 nếu không phải PING
inline size_t makePong(const uint8_t* buf, size_t n, uint32_t uptimeMs, uint8_t* out) {
  uint8_t type, len;
  const uint8_t* p;
  if (!decode(buf, n, type, p, len) || type != PING || len != sizeof(PingPayload)) return 0;
  PingPayload in;
  memcpy(&in, p, sizeof(in));
  PongPayload pong = {in.seq, in.tSendMs, uptimeMs};
  return encode(PONG, &pong, sizeof(pong), out);
}

}  // namespace proto
