// ============================================================================
//  RC Car firmware — ESP32-S3 (Arduino core 3.x)
//  - WiFi 3 chế độ (AP / Router / Cấu hình, xem net_manager.h) + UDP  và
//    BLE (GATT kiểu Nordic UART) chạy song song
//  - 8 kênh PWM CH1–CH8, hai kiểu điều khiển:
//    · n kênh (CONTROL_US): app tính mix/trim/reverse/Min-Max, xe xuất thẳng µs từng kênh,
//      failsafe từng kênh do app gửi (FS_WRITE) và lưu NVS; ARM do app quản lý
//    · 2 kênh (CONTROL, app cũ): CH1 servo lái, CH2 ESC ga, xe tự áp trim/offset/endpoint/
//      reverse/giới hạn số và arming (phải nhả ga về 0 mới cho chạy lại)
//  - Failsafe theo timeout
//  - Telemetry: điện áp pin, tốc độ (cảm biến hall), RSSI
//  - Cấu hình servo và cấu hình mạng lưu trong flash (NVS)
// ============================================================================
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <esp_mac.h>

#include "debug.h"
#include "net_manager.h"
#include "protocol.h"
#include "servo_logic.h"

using namespace proto;

// ---------------- Phần cứng (sửa theo mạch của bạn) ----------------
constexpr int   NUM_CH         = 8;      // ESP32-S3 có đúng 8 kênh LEDC
constexpr int   PIN_CH[NUM_CH] = {4, 5, 7, 15, 16, 17, 18, 8};  // CH1..CH8
constexpr int   CH_STEER       = 0;      // CH1 = lái (giao thức 2 kênh)
constexpr int   CH_THR         = 1;      // CH2 = ga
constexpr uint16_t DEFAULT_FS_US = 1500; // failsafe khi app chưa từng gửi FS_WRITE
constexpr uint16_t MANUAL_MIN_US = US_MIN, MANUAL_MAX_US = US_MAX;
constexpr int   PIN_BATTERY    = 1;      // ADC1, qua cầu chia áp
constexpr int   PIN_HALL       = 6;      // cảm biến tốc độ (tùy chọn)
constexpr int   PIN_NET_BUTTON = 0;      // nút BOOT của DevKitC: giữ 3 s = chế độ cấu hình, 10 s = mạng mặc định; -1 = không dùng
constexpr float BATT_DIVIDER   = 11.0f;  // R1=100k, R2=10k -> (100+10)/10
constexpr float WHEEL_CIRC_CM  = 20.4f;  // chu vi bánh xe (cm)
constexpr int   PULSES_PER_REV = 1;      // số xung hall mỗi vòng bánh

constexpr uint32_t PWM_FREQ      = 50;   // servo analog 50 Hz
constexpr uint8_t  PWM_RES_BITS  = 14;
constexpr uint32_t PWM_PERIOD_US = 1000000UL / PWM_FREQ;

// ---------------- Kết nối ----------------
#define ENABLE_WIFI 1
#define ENABLE_BLE  1

// Tên WiFi, mật khẩu, IP, port UDP, tên BLE: chỉnh trong app (Cấu hình → Chung → Mạng của xe),
// mặc định ở net::setDefaults() — AP "RC-CAR" / 12345678, 192.168.4.1, UDP 4210.
#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  // app ghi vào
#define TX_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  // xe notify ra

enum Source : uint8_t { SRC_NONE, SRC_WIFI, SRC_BLE };

struct RxFrame {
  uint8_t len;
  uint8_t data[MAX_FRAME];
};

// ---------------- Trạng thái ----------------
CarConfig   cfg;
Preferences prefs;

WiFiUDP   udp;
IPAddress udpRemoteIp;
uint16_t  udpRemotePort = 0;

BLEServer*         bleServer = nullptr;
BLECharacteristic* txChar    = nullptr;
volatile bool      bleConnected        = false;
volatile bool      bleJustDisconnected = false;
QueueHandle_t      bleQueue  = nullptr;

ControlPayload lastControl   = {0, 0, 1, 0};
uint32_t       lastControlMs = 0;
Source         activeSrc     = SRC_NONE;
bool           armed         = false;  // chỉ dùng ở chế độ 2 kênh; chế độ n kênh do app ARM
bool           failsafe      = true;

// ---------------- Giao thức n kênh ----------------
bool     multiCh          = false;  // true: app gửi CONTROL_US; false: CONTROL 2 kênh (app cũ)
uint16_t appUs[NUM_CH]    = {};     // µs app gửi trong CONTROL_US gần nhất
uint8_t  appCh            = 0;      // số kênh của xe có dữ liệu trong gói đó
int      lastAppN         = -1;     // số kênh app gửi (để log khi đổi)
uint16_t lastSeq16        = 0;
uint16_t fsUs[NUM_CH];              // failsafe từng kênh (FS_WRITE, NVS "rcfs")
uint16_t fsTimeoutMs      = 400;
bool     fsStored         = false;  // flash có failsafe n kênh

portMUX_TYPE      hallMux    = portMUX_INITIALIZER_UNLOCKED;
volatile uint32_t hallPulses = 0;
uint16_t          speedCms   = 0;

// ---------------- Debug (Serial Monitor, gõ "help") ----------------
bool     statusLog    = true;   // dòng STAT định kỳ ("st off" để tắt)
uint16_t statPeriodMs = 200;    // chu kỳ STAT khi đang lái ("st 100" để đổi); khi chờ là 1 s
bool     pktLog       = false;  // in hex mọi gói nhận trừ CONTROL/PING ("pkt on")
uint32_t ctrlCount    = 0;      // gói CONTROL đã nhận
uint32_t lostCount    = 0;      // gói CONTROL mất (nhảy seq)
uint32_t badCount     = 0;      // gói sai khung / CRC
bool     haveSeq      = false;  // đã có seq trước đó để so
bool     armHintShown = false;
uint16_t outUs[NUM_CH]    = {};  // xung đang xuất ra từng kênh
uint16_t manualUs[NUM_CH] = {};  // giá trị gõ tay ("ch 3 1800"), 0 = không

const char* srcName(Source s) { return s == SRC_WIFI ? "WiFi" : (s == SRC_BLE ? "BLE" : "-"); }

const char* ackName(uint8_t st) {
  return st == net::ACK_OK ? "OK" : (st == net::ACK_BUSY ? "TỪ CHỐI - xe đang chạy" : "LỖI - dữ liệu không hợp lệ");
}

const char* sectionName(uint8_t s) {
  switch (s) {
    case net::SEC_STATUS:  return "trạng thái";
    case net::SEC_GENERAL: return "chung";
    case net::SEC_AP:      return "AP";
    case net::SEC_STA:     return "router";
    default:               return "?";
  }
}

void printChannel(const char* name, const ChannelConfig& c) {
  dbg::log("CFG", "  %s min %u | giữa %u | max %u | trim %+d | offset %+d | đảo %s | failsafe %u us", name, c.minUs,
           c.centerUs, c.maxUs, c.trimUs, c.offsetUs, c.reverse ? "CÓ" : "không", c.failsafeUs);
}

// ---------------- Lưu cấu hình ----------------
constexpr uint8_t CFG_VERSION = 1;

void printConfig() {
  printChannel("Ga ", cfg.throttle);
  printChannel("Lái", cfg.steering);
  char gears[32];
  int k = 0;
  for (int i = 0; i < cfg.gearCount; i++) k += snprintf(gears + k, sizeof(gears) - k, " %u%%", cfg.gearLimit[i]);
  dbg::log("CFG", "  Failsafe sau %u ms | %u số:%s", cfg.failsafeTimeoutMs, cfg.gearCount, gears);
}

void loadConfig() {
  servo::setDefaults(cfg);
  prefs.begin("rccar", false);
  bool fromFlash = false;
  if (prefs.getUChar("ver", 0) == CFG_VERSION) {
    CarConfig tmp;
    if (prefs.getBytes("cfg", &tmp, sizeof(tmp)) == sizeof(tmp) && servo::validConfig(tmp)) {
      cfg = tmp;
      fromFlash = true;
    }
  }
  dbg::log("CFG", "Cấu hình servo: %s", fromFlash ? "đọc từ flash" : "MẶC ĐỊNH (flash trống hoặc không hợp lệ)");
  printConfig();
}

void saveConfig() {
  prefs.putBytes("cfg", &cfg, sizeof(cfg));
  prefs.putUChar("ver", CFG_VERSION);
}

// ---------------- Failsafe n kênh ----------------
uint16_t failsafeUsFor(int i) {
  if (!multiCh && i == CH_STEER) return cfg.steering.failsafeUs;
  if (!multiCh && i == CH_THR) return cfg.throttle.failsafeUs;
  return fsUs[i];
}

uint16_t failsafeTimeout() { return multiCh ? fsTimeoutMs : cfg.failsafeTimeoutMs; }

// "CH1 1500 CH2 1500 ..."; `mark` != null: dấu * thay dấu cách ở kênh có mark[i] != 0
void formatUs(char* out, size_t size, const uint16_t* us, const uint16_t* mark = nullptr) {
  int k = 0;
  out[0] = 0;
  for (int i = 0; i < NUM_CH && k < (int)size; i++)
    k += snprintf(out + k, size - k, "%sCH%d%c%4u", i ? " " : "", i + 1, mark && mark[i] ? '*' : ' ', us[i]);
}

void printFailsafe() {
  uint16_t fs[NUM_CH];
  for (int i = 0; i < NUM_CH; i++) fs[i] = failsafeUsFor(i);
  char line[96];
  formatUs(line, sizeof(line), fs);
  dbg::log("FS", "Failsafe %s: %s us | sau %u ms", multiCh ? "n kênh" : "2 kênh", line, failsafeTimeout());
}

void loadFailsafe() {
  for (int i = 0; i < NUM_CH; i++) fsUs[i] = DEFAULT_FS_US;
  Preferences p;
  p.begin("rcfs", false);
  uint16_t fs[NUM_CH];
  uint16_t to = p.getUShort("to", 0);
  if (p.getBytes("fs", fs, sizeof(fs)) == sizeof(fs) && to >= FS_TIMEOUT_MIN && to <= FS_TIMEOUT_MAX) {
    bool ok = true;
    for (int i = 0; i < NUM_CH; i++) ok &= fs[i] >= US_MIN && fs[i] <= US_MAX;
    if (ok) {
      memcpy(fsUs, fs, sizeof(fs));
      fsTimeoutMs = to;
      fsStored = true;
    }
  }
  p.end();
  multiCh = fsStored;  // đã từng dùng app n kênh: khởi động xuất failsafe n kênh
  dbg::log("FS", "Failsafe n kênh: %s", fsStored ? "đọc từ flash" : "chưa có (app chưa gửi FS_WRITE)");
  printFailsafe();
}

// Lưu flash khi khác bản đang có; trả về true nếu đã ghi
bool saveFailsafe(uint16_t to, const uint16_t* fs) {
  bool same = fsStored && to == fsTimeoutMs && !memcmp(fs, fsUs, sizeof(fsUs));
  memcpy(fsUs, fs, sizeof(fsUs));
  fsTimeoutMs = to;
  if (same) return false;
  Preferences p;
  p.begin("rcfs", false);
  p.putBytes("fs", fsUs, sizeof(fsUs));
  p.putUShort("to", fsTimeoutMs);
  p.end();
  fsStored = true;
  return true;
}

void setMultiCh(bool on) {
  if (multiCh == on) return;
  multiCh = on;
  haveSeq = false;
  lastAppN = -1;
  if (on) dbg::log("CH", "Chế độ N KÊNH: app gửi µs từng kênh, xe xuất thẳng (không tự áp servo / ARM)");
  else dbg::log("CH", "Chế độ 2 KÊNH (app cũ): CH1 lái, CH2 ga, xe tự áp servo + ARM");
}

// Kênh đang do app điều khiển (không gõ tay được khi app đang nối)
bool appDriven(int i) { return multiCh ? i < appCh : i < 2; }

// ---------------- Gửi gói ----------------
void sendFrame(Source dst, uint8_t type, const void* payload, uint8_t len) {
  uint8_t buf[MAX_FRAME];
  size_t n = encode(type, payload, len, buf);
  if (!n) return;
  if (dst == SRC_WIFI && udpRemotePort) {
    udp.beginPacket(udpRemoteIp, udpRemotePort);
    udp.write(buf, n);
    udp.endPacket();
  } else if (dst == SRC_BLE && bleConnected && txChar) {
    txChar->setValue(buf, n);
    txChar->notify();
  }
}

void sendAck(Source dst, uint8_t type, uint8_t status) {  // status: net::AckStatus (1 = ok)
  uint8_t p[2] = {type, status};
  sendFrame(dst, ACK, p, 2);
}

// Xe đứng yên: chỉ khi đó mới cho đổi cấu hình mạng (xe sẽ khởi động lại).
// n kênh: xe không biết kênh nào là ga, coi là đứng yên khi mọi kênh ở failsafe (app READY gửi failsafe).
bool carIdle() {
  if (failsafe) return true;
  if (!multiCh) return abs(lastControl.throttle) < 50;
  for (int i = 0; i < NUM_CH; i++)
    if (abs((int)outUs[i] - (int)fsUs[i]) > 20) return false;
  return true;
}

// ---------------- Xử lý gói nhận ----------------
void handleFrame(const uint8_t* buf, size_t n, Source src) {
  uint8_t type, len;
  const uint8_t* p;
  if (!decode(buf, n, type, p, len)) {
    badCount++;
    if (pktLog) dbg::hex("PKT", "!! gói lỗi (sai khung / CRC):", buf, n);
    return;
  }
  if (pktLog && type != CONTROL && type != CONTROL_US) dbg::hex("PKT", src == SRC_BLE ? "<- BLE :" : "<- WiFi:", buf, n);

  switch (type) {
    case CONTROL:
      if (len != sizeof(ControlPayload)) return;
      if (!netm::allowControl()) {  // chế độ cấu hình: không lái, vẫn gửi telemetry (cờ NET_SETUP) cho app
        activeSrc = src;
        return;
      }
      setMultiCh(false);
      {
        uint8_t prevSeq = lastControl.seq;
        memcpy(&lastControl, p, sizeof(ControlPayload));
        uint8_t gap = (uint8_t)(lastControl.seq - prevSeq - 1);
        if (haveSeq && gap < 128) lostCount += gap;  // gap lớn = gói trùng / đảo thứ tự, không tính
        haveSeq = true;
        ctrlCount++;
      }
      lastControlMs = millis();
      activeSrc = src;
      // Arming: sau failsafe/khởi động phải nhả ga về ~0 mới cho chạy
      if (!armed && abs(lastControl.throttle) < 50) {
        armed = true;
        armHintShown = false;
        dbg::log("ARM", "Đã ARM - ga về 0, xe được chạy");
      } else if (!armed && !armHintShown) {
        armHintShown = true;
        dbg::log("ARM", "Chưa ARM: ga đang %+d, nhả ga về 0 để chạy", lastControl.throttle);
      }
      break;

    case CONTROL_US: {
      uint16_t seq, us[NUM_CH];
      int n = parseControlUs(p, len, seq, us, NUM_CH);
      if (n < 0) {
        badCount++;
        return;
      }
      if (!netm::allowControl()) {
        activeSrc = src;
        return;
      }
      setMultiCh(true);
      uint16_t gap = (uint16_t)(seq - lastSeq16 - 1);
      if (haveSeq && gap < 0x8000) lostCount += gap;
      haveSeq = true;
      lastSeq16 = seq;
      lastControl.seq = (uint8_t)seq;  // telemetry lastSeq
      appCh = n < NUM_CH ? n : NUM_CH;
      memcpy(appUs, us, appCh * sizeof(uint16_t));
      if (n != lastAppN) {
        lastAppN = n;
        if (n == 0) dbg::log("CH", "App gửi 0 kênh (chưa ARM / chưa vào màn Lái): xe xuất failsafe");
        else dbg::log("CH", "App gửi %d kênh, xe có %d%s", n, NUM_CH, n > NUM_CH ? " - bỏ các kênh thừa" : "");
      }
      ctrlCount++;
      lastControlMs = millis();
      activeSrc = src;
      break;
    }

    case INFO_GET: {
      InfoPayload info = {PROTO_N_CH, NUM_CH};
      dbg::log("CH", "App hỏi thông tin xe -> giao thức n kênh v%u, %d kênh", PROTO_N_CH, NUM_CH);
      sendFrame(src, INFO, &info, sizeof(info));
      break;
    }

    case FS_WRITE: {
      uint16_t to = 0, fs[NUM_CH];
      for (int i = 0; i < NUM_CH; i++) fs[i] = DEFAULT_FS_US;  // kênh app không gửi
      int n = parseFsWrite(p, len, to, fs, NUM_CH);
      FsAckPayload ack = {0, fnv1a(p, len), NUM_CH};
      if (n > 0) {
        ack.status = 1;
        setMultiCh(true);
        bool wrote = saveFailsafe(to, fs);
        char line[96];
        formatUs(line, sizeof(line), fsUs);
        dbg::log("FS", "App gửi failsafe %d kênh: %s us | sau %u ms | %s", n, line, to,
                 wrote ? "đã lưu flash" : "không đổi");
      } else {
        dbg::log("FS", "!! Failsafe không hợp lệ (%u byte): timeout phải %u..%u ms, xung %u..%u us", len,
                 FS_TIMEOUT_MIN, FS_TIMEOUT_MAX, US_MIN, US_MAX);
      }
      sendFrame(src, FS_ACK, &ack, sizeof(ack));
      break;
    }

    case CONFIG_GET:
      dbg::log("CFG", "App đọc cấu hình servo");
      sendFrame(src, CONFIG_DATA, &cfg, sizeof(cfg));
      break;

    case CONFIG_SET: {
      bool ok = false;
      if (len == sizeof(CarConfig)) {
        CarConfig tmp;
        memcpy(&tmp, p, sizeof(tmp));
        if (servo::validConfig(tmp)) { cfg = tmp; ok = true; }
      }
      if (ok) dbg::log("CFG", "Áp dụng cấu hình mới (chưa lưu) | trim ga %+d lái %+d", cfg.throttle.trimUs, cfg.steering.trimUs);
      else dbg::log("CFG", "!! Cấu hình không hợp lệ (%u byte), bỏ qua", len);
      sendAck(src, CONFIG_SET, ok);
      break;
    }

    case CONFIG_SAVE:
      saveConfig();
      dbg::log("CFG", "Đã lưu cấu hình servo vào flash");
      sendAck(src, CONFIG_SAVE, true);
      break;

    case CONFIG_RESET:
      servo::setDefaults(cfg);
      saveConfig();
      dbg::log("CFG", "Cấu hình servo về mặc định và đã lưu");
      sendFrame(src, CONFIG_DATA, &cfg, sizeof(cfg));
      break;

    // ---- Cấu hình mạng (net_config.h) ----
    case NET_GET: {
      if (len != 1) return;
      dbg::log("NET", "App đọc cấu hình mạng: phần %s", sectionName(p[0]));
      uint8_t out[MAX_PAYLOAD];
      size_t on = net::encodeSection(p[0], netm::config(), netm::status(), out, sizeof(out));
      if (on) sendFrame(src, NET_DATA, out, (uint8_t)on);
      break;
    }

    case NET_SET: {
      uint8_t st = net::ACK_BUSY;
      if (carIdle()) st = net::decodeSection(p, len, netm::pending(), netm::config()) ? net::ACK_OK : net::ACK_FAIL;
      dbg::log("NET", "App ghi cấu hình mạng phần %s: %s", len ? sectionName(p[0]) : "?", ackName(st));
      sendAck(src, NET_SET, st);
      break;
    }

    case NET_APPLY: {
      uint8_t st = net::ACK_BUSY;
      if (carIdle()) st = netm::applyPending() ? net::ACK_OK : net::ACK_FAIL;
      dbg::log("NET", "App yêu cầu áp dụng cấu hình mạng: %s", ackName(st));
      sendAck(src, NET_APPLY, st);
      break;
    }

    case NET_SETUP:
    case NET_RESET:
      if (!carIdle()) {
        dbg::log("NET", "App yêu cầu %s: %s", type == NET_SETUP ? "chế độ cấu hình" : "mạng mặc định", ackName(net::ACK_BUSY));
        sendAck(src, type, net::ACK_BUSY);
        break;
      }
      sendAck(src, type, net::ACK_OK);
      if (type == NET_SETUP) netm::restartIntoSetup(); else netm::resetToDefaults();
      break;
  }
}

// ---------------- BLE ----------------
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected = true; }
  void onDisconnect(BLEServer*) override {
    bleConnected = false;
    bleJustDisconnected = true;
  }
};

class RxCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    // Chạy trong task BLE -> đẩy vào queue, xử lý ở loop()
    RxFrame f;
    size_t n = c->getLength();
    if (n == 0 || n > MAX_FRAME) return;
    // PING trả lời ngay tại đây, không xếp hàng chờ loop() (F2)
    uint8_t pong[MAX_FRAME];
    size_t pn = makePong(c->getData(), n, millis(), pong);
    if (pn) {
      if (bleConnected && txChar) {
        txChar->setValue(pong, pn);
        txChar->notify();
      }
      return;
    }
    memcpy(f.data, c->getData(), n);
    f.len = (uint8_t)n;
    xQueueSend(bleQueue, &f, 0);
  }
};

void setupBle() {
  bleQueue = xQueueCreate(16, sizeof(RxFrame));
  BLEDevice::init(netm::config().name);
  BLEDevice::setMTU(185);  // gói cấu hình 38 byte > MTU mặc định 23
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCB());

  BLEService* svc = bleServer->createService(SERVICE_UUID);
  BLECharacteristic* rx = svc->createCharacteristic(
      RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCB());
  txChar = svc->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());
  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  dbg::log("BLE", "Đang quảng bá BLE tên \"%s\"", netm::config().name);
}

// ---------------- WiFi / UDP ----------------
void setupWifi() {
  netm::begin(PIN_NET_BUTTON);  // chọn AP / Router / Cấu hình theo NVS
  udp.begin(netm::config().udpPort);
}

void handleUdp() {
  int n;
  while ((n = udp.parsePacket()) > 0) {
    uint8_t buf[MAX_FRAME];
    int r = udp.read(buf, sizeof(buf));
    if (n > (int)sizeof(buf) || r <= 0) continue;  // gói quá dài -> bỏ
    // PING: trả PONG ngay về đúng địa chỉ gửi, không đổi địa chỉ nhận telemetry
    // (ping nhanh từ màn "Xe của tôi" mở socket riêng)
    uint8_t pong[MAX_FRAME];
    size_t pn = makePong(buf, r, millis(), pong);
    if (pn) {
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      udp.write(pong, pn);
      udp.endPacket();
      continue;
    }
    // Đang có một điện thoại lái qua WiFi thì máy khác trong cùng mạng không chen vào được,
    // tới khi xe vào failsafe (quan trọng ở chế độ Router: ai cùng mạng LAN cũng gửi UDP tới xe được)
    bool otherSender = udp.remoteIP() != udpRemoteIp || udp.remotePort() != udpRemotePort;
    if (activeSrc == SRC_WIFI && !failsafe && otherSender) {
      static IPAddress blockedIp;
      if (udp.remoteIP() != blockedIp) {
        blockedIp = udp.remoteIP();
        dbg::log("UDP", "!! Bỏ qua gói từ %s: đang có máy %s lái", blockedIp.toString().c_str(),
                 udpRemoteIp.toString().c_str());
      }
      continue;
    }
    if (otherSender) dbg::log("UDP", "Máy gửi lệnh: %s:%u", udp.remoteIP().toString().c_str(), udp.remotePort());
    udpRemoteIp = udp.remoteIP();
    udpRemotePort = udp.remotePort();
    handleFrame(buf, r, SRC_WIFI);
  }
}

// ---------------- Xuất PWM ----------------
void writeMicros(int pin, uint16_t us) {
  uint32_t duty = (uint32_t)us * ((1UL << PWM_RES_BITS) - 1) / PWM_PERIOD_US;
  ledcWrite(pin, duty);
}

void updateOutputs() {
  uint32_t now = millis();
  bool lost = (activeSrc == SRC_NONE) || (now - lastControlMs > failsafeTimeout());

  if (lost && !failsafe) {
    failsafe = true;
    armed = false;
    armHintShown = false;
    haveSeq = false;
    if (activeSrc == SRC_NONE)
      dbg::log("LINK", "!! MẤT TÍN HIỆU (ngắt kết nối) -> FAILSAFE");
    else
      dbg::log("LINK", "!! MẤT TÍN HIỆU %s: %lu ms không có lệnh (ngưỡng %u ms) -> FAILSAFE", srcName(activeSrc),
               (unsigned long)(now - lastControlMs), failsafeTimeout());
  }
  if (!lost && failsafe) {
    failsafe = false;
    dbg::log("LINK", "Có tín hiệu qua %s", srcName(activeSrc));
    bool cleared = false;
    for (int i = 0; i < NUM_CH; i++)  // app luôn thắng gõ tay trên kênh app điều khiển
      if (manualUs[i] && appDriven(i)) {
        manualUs[i] = 0;
        cleared = true;
      }
    if (cleared) dbg::log("CH", "App đã nối: bỏ giá trị gõ tay trên các kênh app điều khiển");
  }

  for (int i = 0; i < NUM_CH; i++) outUs[i] = failsafeUsFor(i);
  if (!failsafe && multiCh) {
    memcpy(outUs, appUs, appCh * sizeof(uint16_t));  // kênh app không gửi giữ failsafe
  } else if (!failsafe) {
    int32_t thr = armed ? servo::applyGear(cfg, lastControl.throttle, lastControl.gear) : 0;
    outUs[CH_THR] = servo::toMicros(cfg.throttle, thr);
    outUs[CH_STEER] = servo::toMicros(cfg.steering, lastControl.steering);
  }
  for (int i = 0; i < NUM_CH; i++) {
    if (manualUs[i]) outUs[i] = manualUs[i];
    writeMicros(PIN_CH[i], outUs[i]);
  }
}

// ---------------- Telemetry ----------------
void IRAM_ATTR onHall() {
  portENTER_CRITICAL_ISR(&hallMux);
  hallPulses++;
  portEXIT_CRITICAL_ISR(&hallMux);
}

void sendTelemetry() {
  static uint32_t lastMs = 0;
  uint32_t now = millis();
  uint32_t dt = now - lastMs;
  if (dt < 100) return;  // 10 Hz
  lastMs = now;

  portENTER_CRITICAL(&hallMux);
  uint32_t pulses = hallPulses;
  hallPulses = 0;
  portEXIT_CRITICAL(&hallMux);
  speedCms = (uint16_t)(pulses * WHEEL_CIRC_CM * 1000.0f / (PULSES_PER_REV * dt));

  if (activeSrc == SRC_NONE) return;

  TelemetryPayload t;
  t.batteryMv = (uint16_t)(analogReadMilliVolts(PIN_BATTERY) * BATT_DIVIDER);
  t.currentMa = 0;  // TODO: đọc INA219 / ACS712 nếu có
  t.speedCms  = speedCms;
  t.rssi      = (activeSrc == SRC_WIFI) ? netm::rssi() : 0;
  t.flags     = (failsafe ? FLAG_FAILSAFE : 0) | ((multiCh ? !failsafe : armed) ? FLAG_ARMED : 0) |
                (activeSrc == SRC_BLE ? FLAG_VIA_BLE : 0) |
                (netm::allowControl() ? 0 : FLAG_NET_SETUP);
  t.gear      = lastControl.gear;
  t.lastSeq   = lastControl.seq;
  sendFrame(activeSrc, TELEMETRY, &t, sizeof(t));
}

// ---------------- Debug: dòng STAT và lệnh gõ tay ----------------
void printSystem() {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  dbg::log("SYS", "%s | %u nhân %lu MHz | MAC %02X:%02X:%02X:%02X:%02X:%02X | build %s %s", ESP.getChipModel(),
           ESP.getChipCores(), (unsigned long)ESP.getCpuFreqMHz(), mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
           __DATE__, __TIME__);
  dbg::log("SYS", "Heap trống %lu KB (thấp nhất %lu KB) | stack loop còn %u B | đã chạy %lu s",
           (unsigned long)(ESP.getFreeHeap() / 1024), (unsigned long)(ESP.getMinFreeHeap() / 1024),
           (unsigned)uxTaskGetStackHighWaterMark(nullptr), (unsigned long)(millis() / 1000));
  dbg::log("SYS", "Lý do khởi động: %s", dbg::resetReason());
}

void printStatus() {
  static uint32_t lastMs = 0, lastCtrl = 0, lastLost = 0, lastBad = 0;
  uint32_t now = millis(), dt = now - lastMs;
  unsigned long rate = dt ? (ctrlCount - lastCtrl) * 1000UL / dt : 0;
  unsigned long lost = lostCount - lastLost, bad = badCount - lastBad;
  lastMs = now;
  lastCtrl = ctrlCount;
  lastLost = lostCount;
  lastBad = badCount;

  float batt = analogReadMilliVolts(PIN_BATTERY) * BATT_DIVIDER / 1000.0f;
  unsigned long heapKb = ESP.getFreeHeap() / 1024;
  net::NetStatus s = netm::status();
  char ch[96];
  formatUs(ch, sizeof(ch), outUs, manualUs);
  const char* mode = multiCh ? "n kênh" : "2 kênh";

  if (!netm::allowControl()) {
    dbg::log("STAT", "CẤU HÌNH MẠNG (không lái) | %s us | %u máy nối | tự thoát sau %u s | heap %lu KB", ch,
             s.clients, s.setupLeftS, heapKb);
  } else if (failsafe) {
    char wifi[24];
    if (s.mode == net::MODE_STA) snprintf(wifi, sizeof(wifi), "Router %s", s.staResult == net::STA_OK ? "OK" : "chưa vào");
    else snprintf(wifi, sizeof(wifi), "AP %u máy", s.clients);
    dbg::log("STAT", "FAILSAFE %s | %s us | %s | BLE %s | pin %.2f V | lỗi gói %lu | heap %lu KB", mode, ch, wifi,
             bleConnected ? "đã nối" : "chưa nối", batt, bad, heapKb);
  } else if (multiCh) {
    dbg::log("STAT", "%-4s %s | %s us | app gửi %d kênh | %2lu gói/s mất %lu lỗi %lu | pin %.2f V %u cm/s RSSI %d | "
             "heap %lu KB",
             srcName(activeSrc), mode, ch, lastAppN, rate, lost, bad, batt, speedCms, s.rssi, heapKb);
  } else {
    dbg::log("STAT", "%-4s %s %s | %s us | ga %+5d lái %+5d số %u | %2lu gói/s mất %lu lỗi %lu | "
             "pin %.2f V %u cm/s RSSI %d | heap %lu KB",
             srcName(activeSrc), mode, armed ? "ARM       " : "CHỜ NHẢ GA", ch, lastControl.throttle,
             lastControl.steering, lastControl.gear, rate, lost, bad, batt, speedCms, s.rssi, heapKb);
  }
}

void printChannels() {
  dbg::log("CH", "Chế độ %s | Kênh  GPIO  Xung     Failsafe  Nguồn", multiCh ? "n kênh" : "2 kênh (app cũ)");
  for (int i = 0; i < NUM_CH; i++) {
    const char* from = manualUs[i] ? "gõ tay"
                       : failsafe ? "failsafe"
                       : appDriven(i) ? "app"
                       : multiCh ? "failsafe (app không gửi kênh này)"
                                 : "failsafe (app cũ chỉ gửi CH1/CH2)";
    dbg::log("CH", "  CH%-2d  %-4d  %4u us  %4u us   %s%s", i + 1, PIN_CH[i], outUs[i], failsafeUsFor(i), from,
             multiCh ? "" : (i == CH_STEER ? " - lái" : (i == CH_THR ? " - ga" : "")));
  }
}

// ch | ch off | ch <n> off | ch <n> <us>. false nếu không phải lệnh ch
bool channelCommand(const char* line) {
  if (strncmp(line, "ch", 2) || (line[2] && line[2] != ' ')) return false;
  const char* arg = line + 2;
  while (*arg == ' ') arg++;
  if (!*arg) {
    printChannels();
    return true;
  }
  if (!strcmp(arg, "off")) {
    memset(manualUs, 0, sizeof(manualUs));
    dbg::log("CH", "Bỏ gõ tay mọi kênh");
    return true;
  }
  int n = 0;
  char val[8] = "";
  if (sscanf(arg, "%d %7s", &n, val) != 2 || n < 1 || n > NUM_CH) {
    dbg::log("CH", "Cú pháp: ch | ch off | ch <1-%d> off | ch <1-%d> <%u-%u>", NUM_CH, NUM_CH, MANUAL_MIN_US, MANUAL_MAX_US);
    return true;
  }
  int i = n - 1;
  if (!strcmp(val, "off")) {
    manualUs[i] = 0;
    dbg::log("CH", "CH%d bỏ gõ tay", n);
    return true;
  }
  int us = atoi(val);
  if (us < MANUAL_MIN_US || us > MANUAL_MAX_US) {
    dbg::log("CH", "!! Xung phải trong %u..%u us", MANUAL_MIN_US, MANUAL_MAX_US);
  } else if (appDriven(i) && !failsafe) {
    dbg::log("CH", "!! CH%d đang do app điều khiển, ngắt app (hoặc DISARM) rồi mới gõ tay được", n);
  } else {
    manualUs[i] = us;
    dbg::log("CH", "CH%d (GPIO%d) = %d us, gõ tay - !! kênh ga/ESC thì kê bánh xe lên trước", n, PIN_CH[i], us);
  }
  return true;
}

void printHelp() {
  dbg::log("CMD", "Lệnh (gõ rồi Enter):");
  dbg::log("CMD", "  help              danh sách lệnh");
  dbg::log("CMD", "  st                in trạng thái ngay");
  dbg::log("CMD", "  st on | st off    bật/tắt dòng STAT định kỳ");
  dbg::log("CMD", "  st <ms>           chu kỳ STAT khi lái, 50..5000 (đang %u ms; khi chờ 1 s)", statPeriodMs);
  dbg::log("CMD", "  pkt on | pkt off  in hex mọi gói nhận (trừ CONTROL/PING)");
  dbg::log("CMD", "  ch                bảng CH1-CH8: chân, xung, nguồn");
  dbg::log("CMD", "  ch <n> <us>       gõ tay xung kênh n (500..2500); kênh app đang điều khiển thì chỉ khi failsafe");
  dbg::log("CMD", "  ch <n> off | ch off  bỏ gõ tay một kênh / mọi kênh");
  dbg::log("CMD", "  cfg               cấu hình servo (chế độ 2 kênh) và failsafe từng kênh");
  dbg::log("CMD", "  sys               chip, bộ nhớ, lý do khởi động");
  dbg::log("CMD", "  net info | net setup | net reset");
  dbg::log("CMD", "  reboot            khởi động lại");
}

void runCommand(const char* line) {
  dbg::log("CMD", "> %s", line);
  if (!strcmp(line, "help") || !strcmp(line, "?")) printHelp();
  else if (!strcmp(line, "st")) printStatus();
  else if (!strcmp(line, "st on")) { statusLog = true; dbg::log("CMD", "Bật dòng STAT"); }
  else if (!strcmp(line, "st off")) { statusLog = false; dbg::log("CMD", "Tắt dòng STAT"); }
  else if (!strncmp(line, "st ", 3) && atoi(line + 3) > 0) {
    statPeriodMs = constrain(atoi(line + 3), 50, 5000);
    statusLog = true;
    dbg::log("CMD", "Dòng STAT mỗi %u ms khi lái", statPeriodMs);
  }
  else if (!strcmp(line, "pkt on")) { pktLog = true; dbg::log("CMD", "Bật in gói"); }
  else if (!strcmp(line, "pkt off")) { pktLog = false; dbg::log("CMD", "Tắt in gói"); }
  else if (!strcmp(line, "cfg")) {
    printConfig();
    printFailsafe();
  }
  else if (!strcmp(line, "sys")) printSystem();
  else if (!strcmp(line, "reboot")) { dbg::log("CMD", "Khởi động lại..."); delay(100); ESP.restart(); }
  else if (!channelCommand(line) && !netm::command(line)) dbg::log("CMD", "Không hiểu lệnh \"%s\" - gõ help", line);
}

void debugLoop() {
  static uint32_t lastStatMs = 0;
  uint32_t now = millis();
  if (statusLog && now - lastStatMs >= (failsafe ? 1000UL : statPeriodMs)) {
    lastStatMs = now;
    printStatus();
  }
  char line[64];
  if (dbg::readLine(line, sizeof(line))) runCommand(line);
}

// ============================================================================
void setup() {
  dbg::begin(115200);
  dbg::raw("\r\n\r\n==================== RC CAR khởi động ====================\r\n");
  printSystem();
  dbg::log("PIN", "CH1-CH8 = GPIO %d %d %d %d %d %d %d %d (CH1 lái, CH2 ga) | Pin GPIO%d | Hall GPIO%d | Nút mạng GPIO%d",
           PIN_CH[0], PIN_CH[1], PIN_CH[2], PIN_CH[3], PIN_CH[4], PIN_CH[5], PIN_CH[6], PIN_CH[7], PIN_BATTERY, PIN_HALL,
           PIN_NET_BUTTON);
  loadConfig();
  loadFailsafe();

  for (int i = 0; i < NUM_CH; i++)
    if (!ledcAttach(PIN_CH[i], PWM_FREQ, PWM_RES_BITS)) dbg::log("PIN", "!! Không gắn được PWM cho CH%d (GPIO%d)", i + 1, PIN_CH[i]);
  updateOutputs();  // xuất giá trị failsafe ngay khi bật nguồn

  pinMode(PIN_HALL, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_HALL), onHall, FALLING);

#if ENABLE_WIFI
  setupWifi();
#else
  netm::load();  // vẫn cần tên BLE, và vẫn đổi được cấu hình mạng qua BLE
#endif
#if ENABLE_BLE
  setupBle();
#endif
  dbg::log("SYS", "Sẵn sàng. Gõ \"help\" để xem lệnh");
  dbg::raw("==========================================================\r\n");
}

void loop() {
#if ENABLE_WIFI
  netm::loop();
  handleUdp();
#endif
#if ENABLE_BLE
  static bool bleWasConnected = false;
  if (bleConnected != bleWasConnected) {
    bleWasConnected = bleConnected;
    if (bleWasConnected) dbg::log("BLE", "Điện thoại đã nối BLE");
  }
  RxFrame f;
  while (xQueueReceive(bleQueue, &f, 0) == pdTRUE) handleFrame(f.data, f.len, SRC_BLE);
  if (bleJustDisconnected) {
    bleJustDisconnected = false;
    dbg::log("BLE", "Điện thoại ngắt BLE, quảng bá lại");
    if (activeSrc == SRC_BLE) activeSrc = SRC_NONE;  // failsafe ngay, không chờ timeout
    BLEDevice::startAdvertising();
  }
#endif
  updateOutputs();
  sendTelemetry();
  debugLoop();
  delay(1);
}
