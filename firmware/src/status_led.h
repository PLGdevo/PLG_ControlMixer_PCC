#pragma once
// LED RGB báo trạng thái (WS2812 trên board). Màu = đường kết nối, kiểu nháy = trạng thái:
//   AP xanh dương · Router xanh lá · BLE cam · Cấu hình tím · mất tín hiệu đỏ · khởi động trắng
//   chớp chậm: chờ app · nháy nhanh: đang vào router / mất tín hiệu · thở: app đã nối, chưa lái ·
//   sáng đứng: đang lái
// Chỉ logic thuần (không gọi phần cứng), main.cpp chọn trạng thái và ghi ra LED.
#include <stdint.h>

namespace led {

struct Rgb {
  uint8_t r, g, b;
};

enum Pattern : uint8_t { SOLID, BLINK_SLOW, BLINK_FAST, BREATHE };

struct Look {
  Rgb     color;
  Pattern pattern;
};

constexpr Rgb WHITE  = {255, 255, 255};
constexpr Rgb BLUE   = {0, 0, 255};
constexpr Rgb GREEN  = {0, 255, 0};
constexpr Rgb ORANGE = {255, 90, 0};
constexpr Rgb PURPLE = {160, 0, 255};
constexpr Rgb RED    = {255, 0, 0};

// Độ sáng 0..255 của kiểu nháy tại thời điểm ms
inline uint8_t level(Pattern p, uint32_t ms) {
  switch (p) {
    case BLINK_SLOW: return ms % 1000 < 150 ? 255 : 0;  // chớp ngắn 1 lần/giây
    case BLINK_FAST: return ms % 250 < 125 ? 255 : 0;   // 4 lần/giây
    case BREATHE: {                                     // sáng dần rồi tối dần, chu kỳ 2 s
      uint32_t t = ms % 2000;
      uint32_t x = (t < 1000 ? t : 2000 - t) * 255 / 1000;
      return (uint8_t)(x * x / 255);  // bình phương: mắt thấy sáng/tối đều hơn
    }
    default: return 255;
  }
}

// Màu sau khi nhân độ sáng kiểu nháy (lv) và độ sáng chung (bright), cùng thang 0..255
inline Rgb scale(Rgb c, uint8_t lv, uint8_t bright) {
  uint32_t k = (uint32_t)lv * bright;
  return {(uint8_t)(c.r * k / 65025), (uint8_t)(c.g * k / 65025), (uint8_t)(c.b * k / 65025)};
}

}  // namespace led
