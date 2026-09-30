#pragma once
// Tính toán xung servo — không phụ thuộc Arduino nên có thể test trên PC.
#include "protocol.h"

namespace servo {
using proto::CarConfig;
using proto::ChannelConfig;

inline int32_t clampi(int32_t v, int32_t lo, int32_t hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// input -1000..1000  ->  độ rộng xung (µs)
// Thứ tự: reverse -> tâm thực tế (center + trim + offset) -> nội suy tới min/max -> kẹp endpoint
inline uint16_t toMicros(const ChannelConfig& c, int32_t input) {
  int32_t v = clampi(input, -1000, 1000);
  if (c.reverse) v = -v;
  int32_t center = clampi((int32_t)c.centerUs + c.trimUs + c.offsetUs, c.minUs, c.maxUs);
  int32_t us = (v >= 0) ? center + v * ((int32_t)c.maxUs - center) / 1000
                        : center + v * (center - (int32_t)c.minUs) / 1000;
  return (uint16_t)clampi(us, c.minUs, c.maxUs);
}

// Giới hạn ga theo số
inline int32_t applyGear(const CarConfig& cfg, int32_t throttle, uint8_t gear) {
  if (gear < 1) gear = 1;
  if (gear > cfg.gearCount) gear = cfg.gearCount;
  return throttle * cfg.gearLimit[gear - 1] / 100;
}

inline void setDefaults(CarConfig& cfg) {
  cfg.throttle = {1000, 1500, 2000, 0, 0, 0, 1500};  // ESC: 1500 = trung tính
  cfg.steering = {1100, 1500, 1900, 0, 0, 0, 1500};  // Servo lái: failsafe về giữa
  cfg.failsafeTimeoutMs = 400;
  cfg.gearCount = 3;
  const uint8_t g[5] = {30, 60, 100, 100, 100};
  memcpy(cfg.gearLimit, g, 5);
}

inline bool validChannel(const ChannelConfig& c) {
  return c.minUs >= 800 && c.maxUs <= 2200 &&
         c.minUs < c.centerUs && c.centerUs < c.maxUs &&
         c.trimUs >= -200 && c.trimUs <= 200 &&
         c.offsetUs >= -300 && c.offsetUs <= 300 &&
         c.failsafeUs >= c.minUs && c.failsafeUs <= c.maxUs &&
         c.reverse <= 1;
}

inline bool validConfig(const CarConfig& cfg) {
  if (!validChannel(cfg.throttle) || !validChannel(cfg.steering)) return false;
  if (cfg.failsafeTimeoutMs < 100 || cfg.failsafeTimeoutMs > 3000) return false;
  if (cfg.gearCount < 1 || cfg.gearCount > 5) return false;
  for (int i = 0; i < cfg.gearCount; i++)
    if (cfg.gearLimit[i] < 1 || cfg.gearLimit[i] > 100) return false;
  return true;
}

// ---------------- Làm mượt xung ----------------
// App gửi 100 Hz (WiFi) / 50 Hz (BLE), servo đọc xung 50–333 Hz và gói qua mạng đến lúc dồn lúc thưa -> nhảy bậc, lệch nhịp,
// servo nhanh (digital) thấy rõ là giật. Mỗi giá trị mới là một đích: xung đi thẳng từ vị trí hiện tại
// tới đích trong đúng một khoảng giữa hai gói (đo trung bình), cập nhật mỗi ms.
// Đơn vị bên trong: 1/16 µs để bước nhỏ không bị làm tròn mất.
constexpr uint16_t SMOOTH_MIN_MS = 10, SMOOTH_MAX_MS = 60;

struct Smooth {
  int32_t cur = 0;     // xung đang xuất ×16
  int32_t target = 0;  // đích ×16
  int32_t step = 0;    // ×16 mỗi ms
};

// Nhảy ngay (failsafe, gõ tay, lúc khởi động)
inline void smoothJump(Smooth& s, uint16_t us) {
  s.cur = s.target = (int32_t)us << 4;
  s.step = 0;
}

// Đặt đích mới, tới nơi sau spanMs. Cùng đích thì không đổi tốc độ đang chạy.
inline void smoothSet(Smooth& s, uint16_t us, uint16_t spanMs) {
  int32_t t = (int32_t)us << 4;
  if (t == s.target) return;
  s.target = t;
  int32_t d = t > s.cur ? t - s.cur : s.cur - t;
  s.step = spanMs ? (d + spanMs - 1) / spanMs : d;
  if (s.step < 1) s.step = 1;
}

// Tiến dtMs về phía đích, trả về xung (µs) cần xuất
inline uint16_t smoothTick(Smooth& s, uint32_t dtMs) {
  if (dtMs > 1000) dtMs = 1000;
  int32_t d = s.target - s.cur, m = s.step * (int32_t)dtMs;
  if (d >= -m && d <= m) s.cur = s.target;
  else s.cur += d > 0 ? m : -m;
  return (uint16_t)((s.cur + 8) >> 4);
}

// Khoảng giữa hai gói lái, trung bình trượt (×16 ms). gapMs: khoảng vừa đo.
inline uint16_t nextGapAvg(uint16_t avg16, uint32_t gapMs) {
  int32_t g = clampi((int32_t)gapMs, 1, 200) << 4;
  if (!avg16) return (uint16_t)g;
  return (uint16_t)(avg16 + (g - (int32_t)avg16) / 8);
}

// Thời gian đi tới đích mỗi gói: đúng một khoảng gói, kẹp trong [SMOOTH_MIN_MS, SMOOTH_MAX_MS]
inline uint16_t smoothSpan(uint16_t avg16) {
  if (!avg16) return 25;
  return (uint16_t)clampi((avg16 + 8) >> 4, SMOOTH_MIN_MS, SMOOTH_MAX_MS);
}

// ---------------- Vùng chết (deadband) ----------------
// Servo analog (vd EMAX ES08MA II) phản ứng với lệch vài µs bằng một cú đạp động cơ: cần gạt rung nhẹ,
// làm tròn µs hay bước làm mượt nhỏ đều thành giật / rè. Giữ nguyên xung cũ khi giá trị mới lệch không quá db µs.
constexpr uint8_t DEADBAND_MAX_US = 20;

inline uint16_t deadband(uint16_t held, uint16_t target, uint8_t db) {
  int32_t d = (int32_t)target - held;
  return (held && d >= -(int32_t)db && d <= (int32_t)db) ? held : target;
}

// ---------------- Tần số xung từng kênh ----------------
// Servo analog / ESC: 50 Hz. Servo digital nhận được 100–333 Hz: vị trí mới mỗi 3–10 ms thay vì 20 ms,
// cộng với làm mượt ở trên thì chạy mịn hơn hẳn. Chu kỳ phải dài hơn xung lớn nhất (2500 µs).
// ESP32-S3 có 4 timer LEDC -> tối đa 4 tần số khác nhau cùng lúc.
constexpr uint16_t PWM_HZ_MIN = 50, PWM_HZ_MAX = 333, PWM_HZ_DEFAULT = 50;
constexpr int      PWM_TIMERS = 4;

inline bool validHz(int32_t hz) { return hz >= PWM_HZ_MIN && hz <= PWM_HZ_MAX; }

// Số tần số khác nhau trong bảng
inline int distinctHz(const uint16_t* hz, int n) {
  int count = 0;
  for (int i = 0; i < n; i++) {
    bool seen = false;
    for (int j = 0; j < i && !seen; j++) seen = hz[j] == hz[i];
    if (!seen) count++;
  }
  return count;
}

// µs -> duty LEDC theo tần số của kênh
inline uint32_t dutyFor(uint16_t us, uint16_t hz, uint8_t resBits) {
  return (uint32_t)((uint64_t)us * hz * ((1UL << resBits) - 1) / 1000000UL);
}

}  // namespace servo
