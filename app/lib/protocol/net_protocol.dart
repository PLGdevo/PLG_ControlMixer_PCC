// Cấu hình mạng của xe (NET_*) và dò xe trong mạng (DISCOVER / HERE).
// Bố cục byte phải khớp firmware/src/net_config.h. Đặc tả: dac_ta_wifi_3_che_do.md
import 'dart:convert';
import 'dart:typed_data';

import 'protocol.dart';

/// Cổng cố định cho DISCOVER/HERE, không đổi theo cấu hình (firmware: proto::DISCOVERY_PORT)
const discoveryPort = 4211;

/// Độ dài mật khẩu 0xFF: xe có mật khẩu nhưng không gửi ra (đọc) / giữ mật khẩu cũ (ghi)
const passHidden = 0xFF;

abstract final class NetSection {
  static const status = 0;
  static const general = 1;
  static const ap = 2;
  static const sta = 3;
}

abstract final class NetAck {
  static const fail = 0;
  static const ok = 1;
  static const busy = 2;
}

/// Chế độ mạng; `index` là giá trị trên dây
enum NetMode {
  ap('WiFi riêng (AP)'),
  sta('Router'),
  setup('Cấu hình');

  const NetMode(this.label);
  final String label;

  static NetMode of(int v) => v >= 0 && v < values.length ? values[v] : ap;
}

/// Kết quả lần vào router gần nhất; `index` là giá trị trên dây
enum StaResult {
  none('Chưa thử'),
  connecting('Đang kết nối'),
  ok('Đã vào router'),
  noSsid('Không thấy mạng'),
  wrongPass('Sai mật khẩu'),
  noIp('Không nhận được IP'),
  fail('Lỗi kết nối');

  const StaResult(this.label);
  final String label;

  bool get isError => index >= noSsid.index;

  static StaResult of(int v) => v >= 0 && v < values.length ? values[v] : fail;
}

// ---------------- IP / MAC ----------------
/// "192.168.1.5" → [192, 168, 1, 5]; null nếu sai dạng
List<int>? parseIpv4(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return null;
  final out = <int>[];
  for (final p in parts) {
    if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) return null;
    if (p.length > 1 && p.startsWith('0')) return null;
    final v = int.parse(p);
    if (v > 255) return null;
    out.add(v);
  }
  return out;
}

String ipToString(List<int> b) => b.take(4).join('.');

String macToString(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

int _u32(List<int> ip) => (ip[0] << 24) | (ip[1] << 16) | (ip[2] << 8) | ip[3];

/// Địa chỉ unicast dùng được cho máy trong mạng (không 0.x, 127.x, multicast)
bool _validHost(List<int> ip) => ip[0] != 0 && ip[0] != 127 && ip[0] < 224;

/// Số bit 1 của mặt nạ mạng; -1 nếu không liền mạch
int maskPrefix(List<int> m) {
  final v = _u32(m);
  final inv = ~v & 0xFFFFFFFF;
  if ((inv & ((inv + 1) & 0xFFFFFFFF)) != 0) return -1;
  var n = 0;
  for (var x = v; x != 0; x >>= 1) {
    n += x & 1;
  }
  return n;
}

// ---------------- Đọc / ghi payload ----------------
class _Writer {
  final _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void bytes(List<int> v) => _b.add(v);
  void str(String s) {
    final b = utf8.encode(s);
    u8(b.length);
    _b.add(b);
  }

  /// null = giữ mật khẩu cũ
  void pass(String? s) => s == null ? u8(passHidden) : str(s);

  Uint8List done() => _b.toBytes();
}

class _Reader {
  _Reader(this.p);
  final Uint8List p;
  int n = 0;
  bool ok = true;

  int u8() {
    if (n + 1 > p.length) return _fail();
    return p[n++];
  }

  int i8() {
    final v = u8();
    return v >= 128 ? v - 256 : v;
  }

  int u16() {
    if (n + 2 > p.length) return _fail();
    final v = p[n] | (p[n + 1] << 8);
    n += 2;
    return v;
  }

  List<int> bytes(int count) {
    if (n + count > p.length) {
      _fail();
      return List.filled(count, 0);
    }
    final v = p.sublist(n, n + count);
    n += count;
    return v;
  }

  String str() {
    final l = u8();
    if (!ok) return '';
    final b = bytes(l);
    return ok ? utf8.decode(b, allowMalformed: true) : '';
  }

  /// true nếu xe đang lưu mật khẩu (xe không bao giờ gửi mật khẩu ra)
  bool passSet() {
    final l = u8();
    if (!ok || l == passHidden) return true;
    bytes(l);
    return l > 0;
  }

  int _fail() {
    ok = false;
    return 0;
  }

  bool get done => ok && n == p.length;
}

// ---------------- Trạng thái ----------------
class NetStatus {
  final NetMode mode;
  final bool fellBack; // định vào router nhưng không được, đang phát WiFi riêng
  final StaResult staResult;
  final int rssi;
  final String ip;
  final String id; // MAC gốc của xe, dùng để dò trong mạng
  final int setupLeftS;
  final int clients;

  const NetStatus({
    required this.mode,
    required this.fellBack,
    required this.staResult,
    required this.rssi,
    required this.ip,
    required this.id,
    required this.setupLeftS,
    required this.clients,
  });

  /// Payload NET_DATA section 0
  static NetStatus? parse(Uint8List p) {
    final r = _Reader(p);
    if (r.u8() != NetSection.status) return null;
    final s = NetStatus(
      mode: NetMode.of(r.u8()),
      fellBack: r.u8() != 0,
      staResult: StaResult.of(r.u8()),
      rssi: r.i8(),
      ip: ipToString(r.bytes(4)),
      id: macToString(r.bytes(6)),
      setupLeftS: r.u16(),
      clients: r.u8(),
    );
    return r.done ? s : null;
  }

  /// Tên WiFi tạm ở chế độ cấu hình: RC-SETUP + 2 byte cuối MAC
  String get setupSsid => 'RC-SETUP-${id.replaceAll(':', '').substring(8)}';
}

// ---------------- Cấu hình ----------------
class NetConfig {
  static const nameMax = 20;
  static const ssidMax = 32;
  static const passMax = 63;

  NetMode bootMode; // chỉ ap hoặc sta
  int udpPort;
  String name; // tên BLE + hostname

  String apSsid;
  String? apPass; // null = giữ mật khẩu cũ
  int apChannel;
  String apIp;

  String staSsid;
  String? staPass; // null = giữ mật khẩu cũ, '' = mạng mở
  bool staHasPass; // xe đang lưu mật khẩu router
  bool staDhcp;
  String staIp, staGateway, staSubnet, staDns;

  NetConfig({
    this.bootMode = NetMode.ap,
    this.udpPort = 4210,
    this.name = 'RC-CAR',
    this.apSsid = 'RC-CAR',
    this.apPass,
    this.apChannel = 1,
    this.apIp = '192.168.4.1',
    this.staSsid = '',
    this.staPass,
    this.staHasPass = false,
    this.staDhcp = true,
    this.staIp = '',
    this.staGateway = '',
    this.staSubnet = '255.255.255.0',
    this.staDns = '',
  });

  NetConfig copy() => NetConfig(
        bootMode: bootMode,
        udpPort: udpPort,
        name: name,
        apSsid: apSsid,
        apPass: apPass,
        apChannel: apChannel,
        apIp: apIp,
        staSsid: staSsid,
        staPass: staPass,
        staHasPass: staHasPass,
        staDhcp: staDhcp,
        staIp: staIp,
        staGateway: staGateway,
        staSubnet: staSubnet,
        staDns: staDns,
      );

  /// So sánh để biết người dùng đã sửa gì chưa
  String get signature => [
        bootMode.index, udpPort, name, apSsid, apPass, apChannel, apIp, //
        staSsid, staPass, staHasPass, staDhcp, staIp, staGateway, staSubnet, staDns,
      ].join('\u0000');

  /// Ghép 3 payload NET_DATA (general, ap, sta)
  static NetConfig? parse(Uint8List general, Uint8List ap, Uint8List sta) {
    final c = NetConfig();
    final g = _Reader(general);
    if (g.u8() != NetSection.general) return null;
    c.bootMode = NetMode.of(g.u8());
    c.udpPort = g.u16();
    c.name = g.str();

    final a = _Reader(ap);
    if (a.u8() != NetSection.ap) return null;
    c.apChannel = a.u8();
    c.apIp = ipToString(a.bytes(4));
    c.apSsid = a.str();
    a.passSet();
    c.apPass = null;

    final s = _Reader(sta);
    if (s.u8() != NetSection.sta) return null;
    c.staDhcp = s.u8() != 0;
    String ipOrEmpty(List<int> b) => b.every((x) => x == 0) ? '' : ipToString(b);
    c.staIp = ipOrEmpty(s.bytes(4));
    c.staGateway = ipOrEmpty(s.bytes(4));
    c.staSubnet = ipOrEmpty(s.bytes(4));
    c.staDns = ipOrEmpty(s.bytes(4));
    c.staSsid = s.str();
    c.staHasPass = s.passSet();
    c.staPass = null;
    if (c.staSubnet.isEmpty) c.staSubnet = '255.255.255.0';

    return g.done && a.done && s.done ? c : null;
  }

  /// Payload NET_SET cho một section (đã gồm byte section)
  Uint8List sectionBytes(int section) {
    final w = _Writer()..u8(section);
    List<int> ip(String s) => parseIpv4(s) ?? const [0, 0, 0, 0];
    switch (section) {
      case NetSection.general:
        w
          ..u8(bootMode == NetMode.sta ? 1 : 0)
          ..u16(udpPort)
          ..str(name);
      case NetSection.ap:
        w
          ..u8(apChannel)
          ..bytes(ip(apIp))
          ..str(apSsid)
          ..pass(apPass);
      case NetSection.sta:
        w
          ..u8(staDhcp ? 1 : 0)
          ..bytes(ip(staIp))
          ..bytes(ip(staGateway))
          ..bytes(ip(staSubnet))
          ..bytes(ip(staDns))
          ..str(staSsid)
          ..pass(staPass);
      default:
        throw ArgumentError('section $section');
    }
    return w.done();
  }

  static const sections = [NetSection.general, NetSection.ap, NetSection.sta];

  /// Kiểm tra giống firmware (net::validConfig); trả lỗi theo ô nhập
  Map<String, String> validate() {
    final e = <String, String>{};

    final n = name;
    if (n.isEmpty || n.length > nameMax || !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(n) || n.startsWith('-') || n.endsWith('-')) {
      e['name'] = 'Tên 1–$nameMax ký tự: chữ không dấu, số, dấu "-" (không ở đầu/cuối)';
    }
    if (udpPort < 1 || udpPort > 65535) {
      e['udpPort'] = 'Port trong khoảng 1–65535';
    } else if (udpPort == discoveryPort) {
      e['udpPort'] = 'Port $discoveryPort dành cho tìm xe, chọn port khác';
    }

    final apLen = utf8.encode(apSsid).length;
    if (apLen < 1 || apLen > ssidMax) e['apSsid'] = 'Tên WiFi 1–$ssidMax byte';
    final ap = apPass;
    if (ap != null) {
      final err = _passError(ap, allowEmpty: false);
      if (err != null) e['apPass'] = err;
    }
    if (apChannel < 1 || apChannel > 13) e['apChannel'] = 'Kênh 1–13';
    final apIpB = parseIpv4(apIp);
    if (apIpB == null || !_validHost(apIpB) || apIpB[3] == 0 || apIpB[3] == 255) {
      e['apIp'] = 'IP dạng 192.168.4.1 (số cuối 1–254)';
    }

    final staLen = utf8.encode(staSsid).length;
    if (staLen > ssidMax) {
      e['staSsid'] = 'Tên WiFi tối đa $ssidMax byte';
    } else if (bootMode == NetMode.sta && staLen == 0) {
      e['staSsid'] = 'Nhập tên WiFi router';
    }
    final sp = staPass;
    if (sp != null) {
      final err = _passError(sp, allowEmpty: true);
      if (err != null) e['staPass'] = err;
    }

    if (!staDhcp) {
      final ip = parseIpv4(staIp), gw = parseIpv4(staGateway), m = parseIpv4(staSubnet);
      final prefix = m == null ? -1 : maskPrefix(m);
      if (m == null || prefix < 8 || prefix > 30) e['staSubnet'] = 'Subnet mask dạng 255.255.255.0';
      if (ip == null || !_validHost(ip)) e['staIp'] = 'IP không hợp lệ';
      if (gw == null || !_validHost(gw)) e['staGateway'] = 'Gateway không hợp lệ';
      if (ip != null && gw != null && m != null && prefix >= 8 && prefix <= 30 && !e.containsKey('staIp')) {
        final mask = _u32(m), ipv = _u32(ip), gwv = _u32(gw), host = ~mask & 0xFFFFFFFF;
        if ((ipv & mask) != (gwv & mask)) {
          e['staGateway'] = 'Gateway phải cùng mạng với IP';
        } else if (ipv == gwv) {
          e['staIp'] = 'IP phải khác gateway';
        } else if ((ipv & host) == 0 || (ipv & host) == host) {
          e['staIp'] = 'Đây là địa chỉ mạng/broadcast, chọn IP khác';
        } else if ((gwv & host) == 0 || (gwv & host) == host) {
          e['staGateway'] = 'Gateway không hợp lệ';
        }
      }
      if (staDns.trim().isNotEmpty) {
        final d = parseIpv4(staDns);
        if (d == null || !_validHost(d)) e['staDns'] = 'DNS không hợp lệ (để trống = dùng gateway)';
      }
    }
    return e;
  }

  static String? _passError(String s, {required bool allowEmpty}) {
    if (s.isEmpty) return allowEmpty ? null : 'Mật khẩu 8–$passMax ký tự';
    if (s.length < 8 || s.length > passMax) return 'Mật khẩu 8–$passMax ký tự';
    if (s.codeUnits.any((c) => c < 0x20 || c > 0x7E)) return 'Mật khẩu chỉ dùng chữ không dấu, số, ký hiệu';
    return null;
  }
}

// ---------------- Dò xe ----------------
/// DISCOVER: `nonce:u16`
Uint8List encodeDiscover(int nonce) => encodeFrame(PacketType.discover, [nonce & 0xFF, (nonce >> 8) & 0xFF]);

/// HERE: `nonce:u16` · `id[6]` · `ip[4]` · `udpPort:u16` · `mode:u8` · `name:str`
class HereInfo {
  final int nonce;
  final String id, ip, name;
  final int port;
  final NetMode mode;

  const HereInfo({
    required this.nonce,
    required this.id,
    required this.ip,
    required this.port,
    required this.mode,
    required this.name,
  });

  static HereInfo? parse(Uint8List p) {
    final r = _Reader(p);
    final h = HereInfo(
      nonce: r.u16(),
      id: macToString(r.bytes(6)),
      ip: ipToString(r.bytes(4)),
      port: r.u16(),
      mode: NetMode.of(r.u8()),
      name: r.str(),
    );
    return r.done ? h : null;
  }
}
