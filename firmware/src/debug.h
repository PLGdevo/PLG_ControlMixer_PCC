#pragma once
// Log ra Serial Monitor, mỗi dòng dạng "[   12.345] NHÃN nội dung".
// Có ARDUINO_USB_CDC_ON_BOOT thì Serial là cổng USB gốc của ESP32-S3, còn cổng qua chip
// USB-UART (CH343) là Serial0 -> log ghi ra cả hai, cắm cổng nào cũng đọc được.
#include <stddef.h>
#include <stdint.h>

namespace dbg {

void begin(uint32_t baud);
// tag: tối đa 4 ký tự ASCII (SYS, CFG, NET, BLE, UDP, LINK, ARM, PKT, STAT...)
void log(const char* tag, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
// Dòng không có thời gian/nhãn (khung banner)
void raw(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
// In gói dạng hex: "<tag> <prefix> AA 01 06 ..."
void hex(const char* tag, const char* prefix, const uint8_t* data, size_t n);
// Gom ký tự gõ vào từ các cổng; true khi đủ một dòng lệnh (đã bỏ \r\n) trong out
bool readLine(char* out, size_t size);
const char* resetReason();

}  // namespace dbg
