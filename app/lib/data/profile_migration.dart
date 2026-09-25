// Nâng JSON hồ sơ cũ lên `CarProfile.schemaVersion` hiện tại (B5, E1).
import '../models/car_profile.dart';
import '../models/channel_config.dart';

class ProfileFormatException implements Exception {
  ProfileFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class ProfileMigration {
  /// Trả về bản JSON ở định dạng mới nhất; ném [ProfileFormatException] nếu không đọc được.
  static Map<String, dynamic> migrate(Map<String, dynamic> input) {
    var j = Map<String, dynamic>.from(input);
    var v = j['schemaVersion'] as int? ?? 0;
    if (v > CarProfile.schemaVersion) {
      throw ProfileFormatException('Hồ sơ được tạo bởi bản app mới hơn (định dạng $v)');
    }
    if (v == 0) {
      j = _v0ToV1(j);
      v = 1;
    }
    if (j['id'] is! String || (j['id'] as String).isEmpty) {
      throw ProfileFormatException('Hồ sơ thiếu mã (id)');
    }
    return j;
  }

  /// Định dạng trước sprint (chỉ có servo ga/lái như gói CarConfig của firmware v1):
  /// { name, ip, port, config: { throttle: {...}|[...], steering: ..., failsafeTimeoutMs, gearCount, gearLimit } }
  static Map<String, dynamic> _v0ToV1(Map<String, dynamic> old) {
    final cfg = (old['config'] ?? old['servo'] ?? old) as Map<String, dynamic>;
    final channels = ChannelConfig.defaultList();

    void load(ChannelConfig c, Object? raw) {
      if (raw is List && raw.length >= 7) {
        // [min, center, max, trim, offset, reverse, failsafe] như fake_car.py
        c
          ..minUs = raw[0] as int
          ..centerUs = raw[1] as int
          ..maxUs = raw[2] as int
          ..trimUs = raw[3] as int
          ..offsetUs = raw[4] as int
          ..reverse = raw[5] == true || raw[5] == 1
          ..failsafeUs = raw[6] as int;
      } else if (raw is Map) {
        c
          ..minUs = raw['minUs'] as int? ?? c.minUs
          ..centerUs = raw['centerUs'] as int? ?? c.centerUs
          ..maxUs = raw['maxUs'] as int? ?? c.maxUs
          ..trimUs = raw['trimUs'] as int? ?? c.trimUs
          ..offsetUs = raw['offsetUs'] as int? ?? c.offsetUs
          ..reverse = raw['reverse'] as bool? ?? c.reverse
          ..failsafeUs = raw['failsafeUs'] as int? ?? c.failsafeUs;
      }
    }

    load(channels[0], cfg['steering']);
    load(channels[1], cfg['throttle']);

    final gearLimit = (cfg['gearLimit'] ?? cfg['gear_limit']) as List?;
    return {
      'schemaVersion': 1,
      'id': old['id'] as String? ?? CarProfile.newId(),
      'name': old['name'] as String? ?? 'Xe cũ',
      'connType': old['connType'] ?? (old['mac'] != null ? 'ble' : 'wifi'),
      'wifi': {'ip': old['ip'] ?? '192.168.4.1', 'port': old['port'] ?? 4210},
      if (old['mac'] != null) 'ble': {'mac': old['mac'], 'deviceName': old['deviceName'] ?? ''},
      'gears': {
        'gearCount': cfg['gearCount'] ?? cfg['gear_count'] ?? 3,
        'maxThrottle': gearLimit ?? [30, 60, 100, 100, 100],
      },
      'failsafeTimeoutMs': cfg['failsafeTimeoutMs'] ?? cfg['failsafe_timeout_ms'] ?? 400,
      'channels': channels.map((c) => c.toJson()).toList(),
      'mixes': <Object>[],
      'layouts': <Object>[],
    };
  }
}
