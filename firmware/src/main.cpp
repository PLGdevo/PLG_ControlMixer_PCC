// ============================================================================
//  RC Car firmware — ESP32-S3 (Arduino core 3.x)
//  - WiFi 3 chế độ (AP / Router / Cấu hình, xem net_manager.h) + UDP  và
//    BLE (GATT kiểu Nordic UART) chạy song song
//  - PWM servo lái + ESC ga, trim/offset/endpoint/reverse, giới hạn ga theo số
//  - Failsafe theo timeout + arming (phải nhả ga về 0 mới cho chạy lại)
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

#include "net_manager.h"
#include "protocol.h"
#include "servo_logic.h"

using namespace proto;

// ---------------- Phần cứng (sửa theo mạch của bạn) ----------------
constexpr int   PIN_STEERING   = 4;
constexpr int   PIN_THROTTLE   = 5;
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
bool           armed         = false;
bool           failsafe      = true;

portMUX_TYPE      hallMux    = portMUX_INITIALIZER_UNLOCKED;
volatile uint32_t hallPulses = 0;

// ---------------- Lưu cấu hình ----------------
constexpr uint8_t CFG_VERSION = 1;

void loadConfig() {
  servo::setDefaults(cfg);
  prefs.begin("rccar", false);
  if (prefs.getUChar("ver", 0) == CFG_VERSION) {
    CarConfig tmp;
    if (prefs.getBytes("cfg", &tmp, sizeof(tmp)) == sizeof(tmp) && servo::validConfig(tmp))
      cfg = tmp;
  }
}

void saveConfig() {
  prefs.putBytes("cfg", &cfg, sizeof(cfg));
  prefs.putUChar("ver", CFG_VERSION);
}

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

// Xe đứng yên: chỉ khi đó mới cho đổi cấu hình mạng (xe sẽ khởi động lại)
bool carIdle() { return failsafe || abs(lastControl.throttle) < 50; }

// ---------------- Xử lý gói nhận ----------------
void handleFrame(const uint8_t* buf, size_t n, Source src) {
  uint8_t type, len;
  const uint8_t* p;
  if (!decode(buf, n, type, p, len)) return;

  switch (type) {
    case CONTROL:
      if (len != sizeof(ControlPayload)) return;
      if (!netm::allowControl()) {  // chế độ cấu hình: không lái, vẫn gửi telemetry (cờ NET_SETUP) cho app
        activeSrc = src;
        return;
      }
      memcpy(&lastControl, p, sizeof(ControlPayload));
      lastControlMs = millis();
      activeSrc = src;
      // Arming: sau failsafe/khởi động phải nhả ga về ~0 mới cho chạy
      if (!armed && abs(lastControl.throttle) < 50) armed = true;
      break;

    case CONFIG_GET:
      sendFrame(src, CONFIG_DATA, &cfg, sizeof(cfg));
      break;

    case CONFIG_SET: {
      bool ok = false;
      if (len == sizeof(CarConfig)) {
        CarConfig tmp;
        memcpy(&tmp, p, sizeof(tmp));
        if (servo::validConfig(tmp)) { cfg = tmp; ok = true; }
      }
      sendAck(src, CONFIG_SET, ok);
      break;
    }

    case CONFIG_SAVE:
      saveConfig();
      sendAck(src, CONFIG_SAVE, true);
      break;

    case CONFIG_RESET:
      servo::setDefaults(cfg);
      saveConfig();
      sendFrame(src, CONFIG_DATA, &cfg, sizeof(cfg));
      break;

    // ---- Cấu hình mạng (net_config.h) ----
    case NET_GET: {
      if (len != 1) return;
      uint8_t out[MAX_PAYLOAD];
      size_t on = net::encodeSection(p[0], netm::config(), netm::status(), out, sizeof(out));
      if (on) sendFrame(src, NET_DATA, out, (uint8_t)on);
      break;
    }

    case NET_SET: {
      uint8_t st = net::ACK_BUSY;
      if (carIdle()) st = net::decodeSection(p, len, netm::pending(), netm::config()) ? net::ACK_OK : net::ACK_FAIL;
      sendAck(src, NET_SET, st);
      break;
    }

    case NET_APPLY: {
      uint8_t st = net::ACK_BUSY;
      if (carIdle()) st = netm::applyPending() ? net::ACK_OK : net::ACK_FAIL;
      sendAck(src, NET_APPLY, st);
      break;
    }

    case NET_SETUP:
    case NET_RESET:
      if (!carIdle()) {
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
    if (activeSrc == SRC_WIFI && !failsafe && otherSender) continue;
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
  bool lost = (activeSrc == SRC_NONE) || (now - lastControlMs > cfg.failsafeTimeoutMs);

  if (lost && !failsafe) { failsafe = true; armed = false; Serial.println("FAILSAFE"); }
  if (!lost && failsafe) { failsafe = false; Serial.println("Link OK"); }

  if (failsafe) {
    writeMicros(PIN_THROTTLE, cfg.throttle.failsafeUs);
    writeMicros(PIN_STEERING, cfg.steering.failsafeUs);
    return;
  }
  int32_t thr = armed ? servo::applyGear(cfg, lastControl.throttle, lastControl.gear) : 0;
  writeMicros(PIN_THROTTLE, servo::toMicros(cfg.throttle, thr));
  writeMicros(PIN_STEERING, servo::toMicros(cfg.steering, lastControl.steering));
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

  if (activeSrc == SRC_NONE) return;

  TelemetryPayload t;
  t.batteryMv = (uint16_t)(analogReadMilliVolts(PIN_BATTERY) * BATT_DIVIDER);
  t.currentMa = 0;  // TODO: đọc INA219 / ACS712 nếu có
  t.speedCms  = (uint16_t)(pulses * WHEEL_CIRC_CM * 1000.0f / (PULSES_PER_REV * dt));
  t.rssi      = (activeSrc == SRC_WIFI) ? netm::rssi() : 0;
  t.flags     = (failsafe ? FLAG_FAILSAFE : 0) | (armed ? FLAG_ARMED : 0) |
                (activeSrc == SRC_BLE ? FLAG_VIA_BLE : 0) |
                (netm::allowControl() ? 0 : FLAG_NET_SETUP);
  t.gear      = lastControl.gear;
  t.lastSeq   = lastControl.seq;
  sendFrame(activeSrc, TELEMETRY, &t, sizeof(t));
}

// ============================================================================
void setup() {
  Serial.begin(115200);
  loadConfig();

  ledcAttach(PIN_THROTTLE, PWM_FREQ, PWM_RES_BITS);
  ledcAttach(PIN_STEERING, PWM_FREQ, PWM_RES_BITS);
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
  Serial.println("RC car ready");
}

void loop() {
#if ENABLE_WIFI
  netm::loop();
  handleUdp();
#endif
#if ENABLE_BLE
  RxFrame f;
  while (xQueueReceive(bleQueue, &f, 0) == pdTRUE) handleFrame(f.data, f.len, SRC_BLE);
  if (bleJustDisconnected) {
    bleJustDisconnected = false;
    if (activeSrc == SRC_BLE) activeSrc = SRC_NONE;  // failsafe ngay, không chờ timeout
    BLEDevice::startAdvertising();
  }
#endif
  updateOutputs();
  sendTelemetry();
  delay(1);
}
