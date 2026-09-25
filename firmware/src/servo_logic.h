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

}  // namespace servo
