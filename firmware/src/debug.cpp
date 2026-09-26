#include "debug.h"

#include <Arduino.h>
#include <esp_system.h>
#include <stdarg.h>

namespace dbg {
namespace {
char    cmdLine[64];
uint8_t cmdLen = 0;

// Ghi nguyên dòng một lần để log từ task khác không chen vào giữa dòng
void out(const char* s, size_t n) {
  Serial.write((const uint8_t*)s, n);
#if ARDUINO_USB_CDC_ON_BOOT
  Serial0.write((const uint8_t*)s, n);
#endif
}

void vprint(const char* tag, const char* fmt, va_list ap) {
  char buf[384];
  int n = 0;
  if (tag) {
    uint32_t ms = millis();
    n = snprintf(buf, sizeof(buf), "[%5lu.%03lu] %-4s ", (unsigned long)(ms / 1000), (unsigned long)(ms % 1000), tag);
  }
  int m = vsnprintf(buf + n, sizeof(buf) - n - 2, fmt, ap);  // chừa chỗ cho \r\n
  if (m < 0) m = 0;
  size_t len = n + m;
  if (len > sizeof(buf) - 3) len = sizeof(buf) - 3;  // dòng quá dài bị cắt
  if (tag) {
    buf[len++] = '\r';
    buf[len++] = '\n';
  }
  out(buf, len);
}

bool feed(Stream& s, char* out, size_t size) {
  while (s.available()) {
    char ch = (char)s.read();
    if (ch != '\r' && ch != '\n') {  // monitor gửi CR, LF hay CRLF đều được
      if (cmdLen < sizeof(cmdLine) - 1) cmdLine[cmdLen++] = ch;
      continue;
    }
    if (!cmdLen) continue;
    cmdLine[cmdLen] = 0;
    cmdLen = 0;
    snprintf(out, size, "%s", cmdLine);
    return true;
  }
  return false;
}
}  // namespace

void begin(uint32_t baud) {
  // Bộ đệm gửi lớn: log dày không chặn loop() chờ UART đẩy từng byte (115200 baud ~ 11 KB/s)
  Serial.setTxBufferSize(4096);
  Serial.begin(baud);
#if ARDUINO_USB_CDC_ON_BOOT
  Serial0.setTxBufferSize(4096);
  Serial0.begin(baud);
#endif
}

void log(const char* tag, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vprint(tag, fmt, ap);
  va_end(ap);
}

void raw(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vprint(nullptr, fmt, ap);
  va_end(ap);
}

void hex(const char* tag, const char* prefix, const uint8_t* data, size_t n) {
  char buf[200];
  int k = snprintf(buf, sizeof(buf), "%s", prefix);
  for (size_t i = 0; i < n && k < (int)sizeof(buf) - 4; i++) k += snprintf(buf + k, sizeof(buf) - k, " %02X", data[i]);
  log(tag, "%s", buf);
}

bool readLine(char* out, size_t size) {
  if (feed(Serial, out, size)) return true;
#if ARDUINO_USB_CDC_ON_BOOT
  if (feed(Serial0, out, size)) return true;
#endif
  return false;
}

const char* resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON:    return "bật nguồn / nút RESET";
    case ESP_RST_EXT:        return "chân EN (nút RESET)";
    case ESP_RST_SW:         return "phần mềm (ESP.restart)";
    case ESP_RST_PANIC:      return "!! CRASH (panic) - xem backtrace lần trước";
    case ESP_RST_INT_WDT:    return "!! WATCHDOG ngắt (treo trong ISR)";
    case ESP_RST_TASK_WDT:   return "!! WATCHDOG task (loop bị chặn quá lâu)";
    case ESP_RST_WDT:        return "!! WATCHDOG khác";
    case ESP_RST_DEEPSLEEP:  return "thức dậy từ deep sleep";
    case ESP_RST_BROWNOUT:   return "!! SỤT ÁP (brownout) - kiểm tra nguồn / pin";
    case ESP_RST_USB:        return "USB (nạp code / mở cổng USB)";
    case ESP_RST_JTAG:       return "JTAG";
    case ESP_RST_PWR_GLITCH: return "!! nhiễu nguồn (power glitch)";
    case ESP_RST_CPU_LOCKUP: return "!! CPU kẹt (double exception)";
    default:                 return "không rõ";
  }
}

}  // namespace dbg
