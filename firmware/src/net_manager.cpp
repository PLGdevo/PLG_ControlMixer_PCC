#include "net_manager.h"

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <esp_mac.h>
#include <esp_system.h>
#include <esp_wifi.h>
#include <lwip/sockets.h>

namespace netm {
using namespace net;

namespace {
constexpr uint32_t STA_TIMEOUT_MS   = 15000;           // không vào được router trong 15 s -> về AP (lúc khởi động)
constexpr uint32_t SETUP_IDLE_MS    = 5UL * 60 * 1000;  // chế độ cấu hình: 5 phút không có máy nối thì thoát
constexpr uint32_t BTN_SETUP_MS     = 3000;            // giữ nút 3 s rồi nhả -> chế độ cấu hình
constexpr uint32_t BTN_RESET_MS     = 10000;           // giữ nút 10 s -> mạng về mặc định
constexpr uint32_t RESTART_DELAY_MS = 500;             // chờ ACK đi hết rồi mới khởi động lại
constexpr uint8_t  CFG_VERSION      = 1;
constexpr uint32_t SETUP_MAGIC      = 0x5E7C0DE1;

// Giữ qua ESP.restart(), là rác khi vừa cắm điện nên chỉ tin khi reset do phần mềm
RTC_NOINIT_ATTR uint32_t bootIntoSetup;

NetConfig cfg, pend;
bool      loaded     = false;
Mode      curMode    = MODE_AP;
bool      staReady   = false;  // STA: đã có IP
bool      fellBack   = false;
StaResult staResult  = STA_NONE;
uint32_t  staStartMs = 0;      // != 0: đang thử vào router lần đầu sau khởi động
uint32_t  setupSeenMs = 0, restartAtMs = 0, lastPollMs = 0;
uint8_t   clientCount = 0;
uint8_t   carId[6];
int       btnPin = -1;
uint32_t  btnDownMs = 0;
bool      btnResetDone = false;
int       discSock = -1;
char      serialLine[48];
uint8_t   serialLen = 0;

volatile bool    staAssoc  = false;
volatile uint8_t staReason = 0;

IPAddress toIp(const uint8_t* b) { return IPAddress(b[0], b[1], b[2], b[3]); }

const char* modeName(uint8_t m) {
  return m == MODE_STA ? "Router" : (m == MODE_SETUP ? "Cấu hình" : "AP");
}

const char* resultName(uint8_t r) {
  switch (r) {
    case STA_CONNECTING: return "đang kết nối";
    case STA_OK:         return "OK";
    case STA_NO_SSID:    return "không thấy mạng";
    case STA_WRONG_PASS: return "sai mật khẩu";
    case STA_NO_IP:      return "không nhận được IP";
    case STA_FAIL:       return "lỗi";
    default:             return "chưa thử";
  }
}

StaResult fromReason(uint8_t r) {
  switch (r) {
    case WIFI_REASON_NO_AP_FOUND:
    case WIFI_REASON_NO_AP_FOUND_W_COMPATIBLE_SECURITY:
    case WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD:
    case WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD:
      return STA_NO_SSID;
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_AUTH_FAIL:
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
      return STA_WRONG_PASS;
    default:
      return STA_FAIL;
  }
}

// Chạy trong task sự kiện của Arduino
void onWifiEvent(arduino_event_id_t e, arduino_event_info_t info) {
  if (e == ARDUINO_EVENT_WIFI_STA_CONNECTED) {
    staAssoc = true;
  } else if (e == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    staAssoc = false;
    staReason = info.wifi_sta_disconnected.reason;
  }
}

// ---------------- NVS ----------------
void saveConfig(const NetConfig& c) {
  Preferences p;
  p.begin("rcnet", false);
  p.putBytes("cfg", &c, sizeof(c));
  p.putUChar("ver", CFG_VERSION);
  p.end();
}

void scheduleRestart() { restartAtMs = (millis() + RESTART_DELAY_MS) | 1; }

// ---------------- Chế độ ----------------
void startAp(const char* ssid) {
  WiFi.setSleep(false);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid, cfg.apPass, cfg.apChannel);
  IPAddress ip = toIp(cfg.apIp);
  WiFi.softAPConfig(ip, ip, IPAddress(255, 255, 255, 0));
  WiFi.setSleep(false);  // giảm độ trễ
}

void startSta() {
  WiFi.setHostname(cfg.name);  // phải đặt trước khi bật STA
  WiFi.setSleep(false);        // STA mặc định bật modem sleep, gây giật ~100 ms
  WiFi.mode(WIFI_STA);
  if (!cfg.staDhcp) {
    IPAddress gw = toIp(cfg.staGateway);
    WiFi.config(toIp(cfg.staIp), gw, toIp(cfg.staSubnet), ipU32(cfg.staDns) ? toIp(cfg.staDns) : gw);
  }
  WiFi.setAutoReconnect(true);
  staAssoc = false;
  staReason = 0;
  staResult = STA_CONNECTING;
  staStartMs = millis() | 1;
  WiFi.begin(cfg.staSsid, cfg.staPass[0] ? cfg.staPass : nullptr);
}

void setupSsid(char* out) { snprintf(out, SSID_LEN + 1, "RC-SETUP-%02X%02X", carId[4], carId[5]); }

void printInfo() {
  NetStatus s = status();
  Serial.printf("Mạng: %s%s  IP %u.%u.%u.%u  UDP %u  tên %s\n", modeName(s.mode), fellBack ? " (dự phòng)" : "",
                s.ip[0], s.ip[1], s.ip[2], s.ip[3], cfg.udpPort, cfg.name);
  if (curMode == MODE_STA) {
    Serial.printf("  Router \"%s\" (%s)  RSSI %d dBm\n", cfg.staSsid, resultName(staResult), s.rssi);
  } else {
    char ssid[SSID_LEN + 1];
    if (curMode == MODE_SETUP) setupSsid(ssid); else snprintf(ssid, sizeof(ssid), "%s", cfg.apSsid);
    Serial.printf("  Phát WiFi \"%s\" kênh %u  %u máy đang nối\n", ssid, cfg.apChannel, s.clients);
    if (cfg.staSsid[0]) Serial.printf("  Router đã lưu \"%s\" (%s)\n", cfg.staSsid, resultName(staResult));
  }
}

// ---------------- DISCOVER ----------------
// Socket riêng có SO_BROADCAST để chắc chắn nhận được gói broadcast (socket WiFiUDP không bật cờ này)
void discBegin() {
  discSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (discSock < 0) return;
  int yes = 1;
  setsockopt(discSock, SOL_SOCKET, SO_BROADCAST, &yes, sizeof(yes));
  setsockopt(discSock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
  sockaddr_in a = {};
  a.sin_family = AF_INET;
  a.sin_port = htons(proto::DISCOVERY_PORT);
  a.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(discSock, (sockaddr*)&a, sizeof(a)) < 0) {
    close(discSock);
    discSock = -1;
    return;
  }
  fcntl(discSock, F_SETFL, O_NONBLOCK);
}

void discPoll() {
  if (discSock < 0) return;
  uint8_t buf[proto::MAX_FRAME];
  sockaddr_in from;
  socklen_t fromLen = sizeof(from);
  int n = recvfrom(discSock, buf, sizeof(buf), 0, (sockaddr*)&from, &fromLen);
  if (n <= 0) return;
  uint8_t type, len;
  const uint8_t* p;
  if (!proto::decode(buf, n, type, p, len) || type != proto::DISCOVER || len != 2) return;
  uint8_t payload[proto::MAX_PAYLOAD];
  size_t pn = encodeHere((uint16_t)(p[0] | p[1] << 8), status(), cfg, payload, sizeof(payload));
  uint8_t out[proto::MAX_FRAME];
  size_t on = pn ? proto::encode(proto::HERE, payload, pn, out) : 0;
  if (on) sendto(discSock, out, on, 0, (sockaddr*)&from, fromLen);  // trả thẳng về máy hỏi
}

// ---------------- Nút / Serial ----------------
void buttonPoll(uint32_t now) {
  if (btnPin < 0) return;
  bool down = digitalRead(btnPin) == LOW;
  if (down && !btnDownMs) btnDownMs = now | 1;
  if (down && !btnResetDone && now - btnDownMs >= BTN_RESET_MS) {
    btnResetDone = true;
    Serial.println("Nút: mạng về mặc định");
    resetToDefaults();
  }
  if (!down && btnDownMs) {
    uint32_t held = now - btnDownMs;
    btnDownMs = 0;
    if (held >= BTN_SETUP_MS && !btnResetDone) {
      Serial.println("Nút: vào chế độ cấu hình");
      restartIntoSetup();
    }
  }
}

void serialPoll() {
  while (Serial.available()) {
    char ch = (char)Serial.read();
    if (ch == '\r') continue;
    if (ch != '\n') {
      if (serialLen < sizeof(serialLine) - 1) serialLine[serialLen++] = ch;
      continue;
    }
    serialLine[serialLen] = 0;
    serialLen = 0;
    if (!strcmp(serialLine, "net info")) printInfo();
    else if (!strcmp(serialLine, "net setup")) restartIntoSetup();
    else if (!strcmp(serialLine, "net reset")) resetToDefaults();
    else if (serialLine[0]) Serial.println("Lệnh: net info | net setup | net reset");
  }
}

void staPoll(uint32_t now) {
  bool up = WiFi.status() == WL_CONNECTED;
  if (up != staReady) {
    staReady = up;
    staResult = up ? STA_OK : STA_CONNECTING;
    if (up) {
      staStartMs = 0;  // từ giờ rớt router chỉ thử lại, không chuyển AP (IP sẽ đổi)
      Serial.printf("Đã vào router  IP %s  RSSI %d dBm\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    } else {
      Serial.println("Mất router, đang thử lại");
    }
  }
  if (!staReady && staStartMs && now - staStartMs > STA_TIMEOUT_MS) {
    staResult = staAssoc ? STA_NO_IP : fromReason(staReason);
    Serial.printf("Không vào được router \"%s\" (%s), chuyển sang AP\n", cfg.staSsid, resultName(staResult));
    staStartMs = 0;
    WiFi.setAutoReconnect(false);
    WiFi.disconnect(true);
    fellBack = true;
    curMode = MODE_AP;
    startAp(cfg.apSsid);
    printInfo();
  }
}
}  // namespace

// ============================================================================
void load() {
  if (loaded) return;
  loaded = true;
  esp_efuse_mac_get_default(carId);
  setDefaults(cfg);
  Preferences p;
  p.begin("rcnet", false);
  NetConfig tmp;
  if (p.getUChar("ver", 0) == CFG_VERSION && p.getBytes("cfg", &tmp, sizeof(tmp)) == sizeof(tmp) && validConfig(tmp))
    cfg = tmp;
  p.end();
  pend = cfg;
}

void begin(int buttonPin) {
  load();
  btnPin = buttonPin;
  if (btnPin >= 0) pinMode(btnPin, INPUT_PULLUP);

  bool setup = esp_reset_reason() == ESP_RST_SW && bootIntoSetup == SETUP_MAGIC;
  bootIntoSetup = 0;  // chỉ một lần: mất điện giữa chừng thì lần sau về chế độ đã lưu

  WiFi.persistent(false);  // cấu hình WiFi nằm trong namespace rcnet, không để thư viện tự lưu
  WiFi.onEvent(onWifiEvent);
  if (setup) {
    curMode = MODE_SETUP;
    char ssid[SSID_LEN + 1];
    setupSsid(ssid);
    startAp(ssid);
    setupSeenMs = millis();
  } else if (cfg.bootMode == MODE_STA && cfg.staSsid[0]) {
    curMode = MODE_STA;
    startSta();
  } else {
    curMode = MODE_AP;
    startAp(cfg.apSsid);
  }
  discBegin();
  printInfo();
}

void loop() {
  uint32_t now = millis();
  if (restartAtMs && (int32_t)(now - restartAtMs) >= 0) ESP.restart();

  if (curMode == MODE_STA) staPoll(now);
  if (now - lastPollMs >= 500) {  // hỏi số máy nối AP 2 lần/giây là đủ
    lastPollMs = now;
    clientCount = curMode == MODE_STA ? 0 : WiFi.softAPgetStationNum();
    if (curMode == MODE_SETUP) {
      if (clientCount) {
        setupSeenMs = now;
      } else if (now - setupSeenMs > SETUP_IDLE_MS) {
        Serial.println("Hết thời gian chế độ cấu hình, khởi động lại");
        ESP.restart();
      }
    }
  }
  buttonPoll(now);
  discPoll();
  serialPoll();
}

Mode mode() { return curMode; }
const NetConfig& config() { return cfg; }
NetConfig& pending() { return pend; }
bool allowControl() { return curMode != MODE_SETUP; }

int8_t rssi() {
  if (curMode == MODE_STA) return staReady ? (int8_t)WiFi.RSSI() : 0;
  wifi_sta_list_t list;
  if (esp_wifi_ap_get_sta_list(&list) == ESP_OK && list.num > 0) return list.sta[0].rssi;
  return 0;
}

NetStatus status() {
  NetStatus s = {};
  s.mode = curMode;
  s.fellBack = fellBack;
  s.staResult = staResult;
  s.rssi = rssi();
  IPAddress ip = curMode == MODE_STA ? WiFi.localIP() : WiFi.softAPIP();
  for (int i = 0; i < 4; i++) s.ip[i] = ip[i];
  memcpy(s.id, carId, 6);
  if (curMode == MODE_SETUP) {
    uint32_t idle = millis() - setupSeenMs;
    s.setupLeftS = idle >= SETUP_IDLE_MS ? 0 : (uint16_t)((SETUP_IDLE_MS - idle) / 1000);
  }
  s.clients = clientCount;
  return s;
}

bool applyPending() {
  if (!validConfig(pend)) return false;
  saveConfig(pend);  // cfg giữ nguyên tới khi khởi động lại
  Serial.println("Đã lưu cấu hình mạng mới, khởi động lại");
  scheduleRestart();
  return true;
}

void restartIntoSetup() {
  bootIntoSetup = SETUP_MAGIC;
  scheduleRestart();
}

void resetToDefaults() {
  Preferences p;
  p.begin("rcnet", false);
  p.clear();
  p.end();
  Serial.println("Mạng về mặc định, khởi động lại");
  scheduleRestart();
}

}  // namespace netm
