#pragma once
// Cấu hình mạng của xe (lưu NVS) và bố cục payload NET_* / HERE.
// Không phụ thuộc Arduino nên có thể test trên PC. Phải khớp app/lib/protocol/net_protocol.dart.
//
//  Section (byte đầu của NET_GET / NET_DATA / NET_SET):
//   0 STATUS  (chỉ đọc) mode:u8 · fellBack:u8 · staResult:u8 · rssi:i8 · ip[4] · id[6] · setupLeftS:u16 · clients:u8
//   1 GENERAL bootMode:u8 · udpPort:u16 · name:str
//   2 AP      channel:u8 · ip[4] · ssid:str · pass:str
//   3 STA     dhcp:u8 · ip[4] · gateway[4] · subnet[4] · dns[4] · ssid:str · pass:str
//  str = len:u8 · byte UTF-8. Mật khẩu: len 0xFF = "có nhưng không gửi ra" (đọc) / "giữ mật khẩu cũ" (ghi).
//  IP gửi theo thứ tự a.b.c.d.
#include "protocol.h"

namespace net {

enum Mode : uint8_t { MODE_AP = 0, MODE_STA = 1, MODE_SETUP = 2 };

enum Section : uint8_t { SEC_STATUS = 0, SEC_GENERAL = 1, SEC_AP = 2, SEC_STA = 3 };

enum StaResult : uint8_t {
  STA_NONE       = 0,  // chưa thử vào router
  STA_CONNECTING = 1,
  STA_OK         = 2,
  STA_NO_SSID    = 3,  // không thấy mạng
  STA_WRONG_PASS = 4,
  STA_NO_IP      = 5,  // vào được router nhưng không nhận được IP
  STA_FAIL       = 6,  // lỗi khác / hết giờ
};

enum AckStatus : uint8_t { ACK_FAIL = 0, ACK_OK = 1, ACK_BUSY = 2 };

constexpr uint8_t NAME_LEN    = 20;  // độ dài tối đa (không gồm NUL)
constexpr uint8_t SSID_LEN    = 32;
constexpr uint8_t PASS_LEN    = 63;
constexpr uint8_t PASS_HIDDEN = 0xFF;

struct NetConfig {
  uint8_t  bootMode;                // MODE_AP / MODE_STA
  uint16_t udpPort;
  char     name[NAME_LEN + 1];      // tên BLE, cũng là hostname trong mạng router
  char     apSsid[SSID_LEN + 1];
  char     apPass[PASS_LEN + 1];
  uint8_t  apChannel;               // 1..13
  uint8_t  apIp[4];                 // mạng /24, xe cũng là gateway
  char     staSsid[SSID_LEN + 1];
  char     staPass[PASS_LEN + 1];   // rỗng = mạng mở
  uint8_t  staDhcp;                 // 1 = IP động
  uint8_t  staIp[4], staGateway[4], staSubnet[4], staDns[4];  // dns 0.0.0.0 = dùng gateway
};

struct NetStatus {
  uint8_t  mode;        // chế độ đang chạy (Mode)
  uint8_t  fellBack;    // 1 = cấu hình là router nhưng không vào được, đang phát AP
  uint8_t  staResult;   // StaResult của lần vào router gần nhất
  int8_t   rssi;
  uint8_t  ip[4];       // IP hiện tại của xe
  uint8_t  id[6];       // MAC gốc, định danh xe khi dò trong mạng
  uint16_t setupLeftS;  // chế độ cấu hình: số giây còn lại
  uint8_t  clients;     // số máy đang nối vào AP của xe
};

// ---------------- Mặc định & kiểm tra ----------------
inline void copyStr(char* dst, size_t cap, const char* src) {
  size_t n = strlen(src);
  if (n >= cap) n = cap - 1;
  memcpy(dst, src, n);
  dst[n] = 0;
}

inline void setIp(uint8_t* dst, uint8_t a, uint8_t b, uint8_t c, uint8_t d) {
  dst[0] = a; dst[1] = b; dst[2] = c; dst[3] = d;
}

inline void setDefaults(NetConfig& c) {
  memset(&c, 0, sizeof(c));
  c.bootMode = MODE_AP;
  c.udpPort = 4210;
  copyStr(c.name, sizeof(c.name), "RC-CAR");
  copyStr(c.apSsid, sizeof(c.apSsid), "RC-CAR");
  copyStr(c.apPass, sizeof(c.apPass), "12345678");
  c.apChannel = 1;
  setIp(c.apIp, 192, 168, 4, 1);
  c.staDhcp = 1;
  setIp(c.staSubnet, 255, 255, 255, 0);
}

inline uint32_t ipU32(const uint8_t* ip) {
  return (uint32_t)ip[0] << 24 | (uint32_t)ip[1] << 16 | (uint32_t)ip[2] << 8 | ip[3];
}

// Địa chỉ unicast dùng được cho máy trong mạng (không 0.x, 127.x, multicast)
inline bool validHost(const uint8_t* ip) { return ip[0] != 0 && ip[0] != 127 && ip[0] < 224; }

// Số bit 1 của mặt nạ mạng; -1 nếu không liền mạch
inline int maskPrefix(const uint8_t* m) {
  uint32_t v = ipU32(m), inv = ~v;
  if (inv & (inv + 1)) return -1;
  int n = 0;
  while (v) { n += v & 1; v >>= 1; }
  return n;
}

// Tên BLE / hostname: 1..20 ký tự A-Z a-z 0-9 '-', không bắt đầu/kết thúc bằng '-'
inline bool validName(const char* s) {
  size_t n = strlen(s);
  if (n < 1 || n > NAME_LEN || s[0] == '-' || s[n - 1] == '-') return false;
  for (size_t i = 0; i < n; i++) {
    char ch = s[i];
    bool ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-';
    if (!ok) return false;
  }
  return true;
}

inline bool validSsid(const char* s, bool allowEmpty) {
  size_t n = strlen(s);
  return n <= SSID_LEN && (allowEmpty || n > 0);
}

// WPA2: 8..63 ký tự ASCII in được
inline bool validPass(const char* s, bool allowEmpty) {
  size_t n = strlen(s);
  if (n == 0) return allowEmpty;
  if (n < 8 || n > PASS_LEN) return false;
  for (size_t i = 0; i < n; i++)
    if ((uint8_t)s[i] < 0x20 || (uint8_t)s[i] > 0x7E) return false;
  return true;
}

inline bool validStaticIp(const NetConfig& c) {
  int prefix = maskPrefix(c.staSubnet);
  if (prefix < 8 || prefix > 30) return false;
  if (!validHost(c.staIp) || !validHost(c.staGateway)) return false;
  uint32_t ip = ipU32(c.staIp), gw = ipU32(c.staGateway), m = ipU32(c.staSubnet);
  if ((ip & m) != (gw & m) || ip == gw) return false;
  uint32_t ipHost = ip & ~m, gwHost = gw & ~m;
  if (ipHost == 0 || ipHost == ~m || gwHost == 0 || gwHost == ~m) return false;  // địa chỉ mạng / broadcast
  bool noDns = ipU32(c.staDns) == 0;
  return noDns || validHost(c.staDns);
}

inline bool validConfig(const NetConfig& c) {
  if (c.bootMode > MODE_STA) return false;
  if (c.udpPort == 0 || c.udpPort == proto::DISCOVERY_PORT) return false;
  if (!validName(c.name)) return false;
  if (!validSsid(c.apSsid, false) || !validPass(c.apPass, false)) return false;
  if (c.apChannel < 1 || c.apChannel > 13) return false;
  if (!validHost(c.apIp) || c.apIp[3] == 0 || c.apIp[3] == 255) return false;
  if (!validSsid(c.staSsid, c.bootMode != MODE_STA) || !validPass(c.staPass, true)) return false;
  if (c.staDhcp > 1) return false;
  return c.staDhcp || validStaticIp(c);
}

// ---------------- Đọc / ghi payload ----------------
struct Writer {
  uint8_t* p;
  size_t cap, n = 0;
  bool ok = true;

  void u8(uint8_t v) { bytes(&v, 1); }
  void u16(uint16_t v) { uint8_t b[2] = {(uint8_t)v, (uint8_t)(v >> 8)}; bytes(b, 2); }
  void bytes(const void* src, size_t len) {
    if (!ok || n + len > cap) { ok = false; return; }
    memcpy(p + n, src, len);
    n += len;
  }
  void str(const char* s) { size_t len = strlen(s); u8((uint8_t)len); bytes(s, len); }
  void pass(const char* s) { u8(s[0] ? PASS_HIDDEN : 0); }  // không bao giờ gửi mật khẩu ra
};

struct Reader {
  const uint8_t* p;
  size_t len, n = 0;
  bool ok = true;

  uint8_t u8() { uint8_t v = 0; bytes(&v, 1); return v; }
  uint16_t u16() { uint8_t b[2] = {0, 0}; bytes(b, 2); return (uint16_t)(b[0] | b[1] << 8); }
  void bytes(void* dst, size_t count) {
    if (!ok || n + count > len) { ok = false; return; }
    memcpy(dst, p + n, count);
    n += count;
  }
  // `keep` != nullptr: len 0xFF nghĩa là giữ chuỗi `keep` (mật khẩu cũ)
  void str(char* dst, size_t cap, const char* keep = nullptr) {
    uint8_t l = u8();
    if (!ok) return;
    if (l == PASS_HIDDEN && keep) { copyStr(dst, cap, keep); return; }
    if (l >= cap || n + l > len) { ok = false; return; }
    for (size_t i = 0; i < l; i++)
      if (p[n + i] == 0) { ok = false; return; }
    memcpy(dst, p + n, l);
    dst[l] = 0;
    n += l;
  }
  bool done() const { return ok && n == len; }
};

// Dựng payload NET_DATA cho `section`; trả số byte, 0 nếu section không hợp lệ
inline size_t encodeSection(uint8_t section, const NetConfig& c, const NetStatus& s, uint8_t* out, size_t cap) {
  Writer w{out, cap};
  w.u8(section);
  switch (section) {
    case SEC_STATUS:
      w.u8(s.mode); w.u8(s.fellBack); w.u8(s.staResult); w.u8((uint8_t)s.rssi);
      w.bytes(s.ip, 4); w.bytes(s.id, 6); w.u16(s.setupLeftS); w.u8(s.clients);
      break;
    case SEC_GENERAL:
      w.u8(c.bootMode); w.u16(c.udpPort); w.str(c.name);
      break;
    case SEC_AP:
      w.u8(c.apChannel); w.bytes(c.apIp, 4); w.str(c.apSsid); w.pass(c.apPass);
      break;
    case SEC_STA:
      w.u8(c.staDhcp); w.bytes(c.staIp, 4); w.bytes(c.staGateway, 4); w.bytes(c.staSubnet, 4); w.bytes(c.staDns, 4);
      w.str(c.staSsid); w.pass(c.staPass);
      break;
    default:
      return 0;
  }
  return w.ok ? w.n : 0;
}

// Ghi payload NET_SET vào `out` (bản chờ). Mật khẩu 0xFF lấy lại từ `saved`.
// Chỉ kiểm tra khuôn dạng; kiểm tra giá trị để tới NET_APPLY (validConfig).
inline bool decodeSection(const uint8_t* p, size_t len, NetConfig& out, const NetConfig& saved) {
  Reader r{p, len};
  NetConfig t = out;
  switch (r.u8()) {
    case SEC_GENERAL:
      t.bootMode = r.u8(); t.udpPort = r.u16(); r.str(t.name, sizeof(t.name));
      break;
    case SEC_AP:
      t.apChannel = r.u8(); r.bytes(t.apIp, 4);
      r.str(t.apSsid, sizeof(t.apSsid)); r.str(t.apPass, sizeof(t.apPass), saved.apPass);
      break;
    case SEC_STA:
      t.staDhcp = r.u8(); r.bytes(t.staIp, 4); r.bytes(t.staGateway, 4); r.bytes(t.staSubnet, 4); r.bytes(t.staDns, 4);
      r.str(t.staSsid, sizeof(t.staSsid)); r.str(t.staPass, sizeof(t.staPass), saved.staPass);
      break;
    default:
      return false;
  }
  if (!r.done()) return false;
  out = t;
  return true;
}

// HERE: nonce:u16 · id[6] · ip[4] · udpPort:u16 · mode:u8 · name:str
inline size_t encodeHere(uint16_t nonce, const NetStatus& s, const NetConfig& c, uint8_t* out, size_t cap) {
  Writer w{out, cap};
  w.u16(nonce); w.bytes(s.id, 6); w.bytes(s.ip, 4); w.u16(c.udpPort); w.u8(s.mode); w.str(c.name);
  return w.ok ? w.n : 0;
}

}  // namespace net
