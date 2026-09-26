// Kênh đầu ra (Sprint 4 — O1): Min/Center/Max, trim, offset, reverse, failsafe.
// Kênh nhận giá trị từ luật mix (M); kênh tắt luôn ra failsafeUs.

import '../l10n/lang.dart';

class ChannelConfig {
  static const minLimitUs = 500;
  static const maxLimitUs = 2500;

  int index; // 1..10
  String name;
  int minUs, centerUs, maxUs;
  int trimUs, offsetUs;
  bool reverse;
  int failsafeUs;
  bool enabled;

  ChannelConfig({
    required this.index,
    required this.name,
    this.minUs = 1000,
    this.centerUs = 1500,
    this.maxUs = 2000,
    this.trimUs = 0,
    this.offsetUs = 0,
    this.reverse = false,
    this.failsafeUs = 1500,
    this.enabled = false,
  });

  /// Kênh chưa gán vai trò. CH1/CH2 bật sẵn vì firmware v1 luôn xuất hai kênh này, CH3–CH10 tắt.
  factory ChannelConfig.defaults(int index) => ChannelConfig(index: index, name: 'Kênh $index', enabled: index <= 2);

  /// Kênh Lái / Ga kiểu servo lái và ESC (mẫu "Xe cơ bản", hồ sơ cũ)
  factory ChannelConfig.steering(int index) =>
      ChannelConfig(index: index, name: tr('Lái', 'Steering'), enabled: true, minUs: 1100, maxUs: 1900);
  factory ChannelConfig.throttle(int index) => ChannelConfig(index: index, name: tr('Ga', 'Throttle'), enabled: true);

  /// 10 kênh mặc định; kênh `steeringCh` / `throttleCh` (nếu có) dựng theo kiểu Lái / Ga
  static List<ChannelConfig> defaultList({int? steeringCh, int? throttleCh}) => List.generate(10, (i) {
        final n = i + 1;
        if (n == steeringCh) return ChannelConfig.steering(n);
        if (n == throttleCh) return ChannelConfig.throttle(n);
        return ChannelConfig.defaults(n);
      });

  /// Firmware v1 luôn xuất CH1/CH2 (chân lái / ga của xe) nên hai kênh này không tắt được
  bool get alwaysOn => index <= 2;

  String get label => 'CH$index';

  /// Tên mặc định "Kênh N" (lưu cố định trong hồ sơ, không theo ngôn ngữ) — hiển thị theo ngôn ngữ đang chọn
  bool get hasDefaultName => name == 'Kênh $index' || name == 'Channel $index';
  String get displayName => hasDefaultName ? tr('Kênh $index', 'Channel $index') : name;

  int get effectiveCenter => (centerUs + trimUs + offsetUs).clamp(minUs, maxUs).toInt();

  /// % (−100…+100) → µs theo quy ước B1 (tính quanh Center)
  int pctToUs(double pct) {
    final p = pct.clamp(-100.0, 100.0);
    final us = p >= 0 ? centerUs + p / 100 * (maxUs - centerUs) : centerUs + p / 100 * (centerUs - minUs);
    return us.round();
  }

  /// µs → % (−100…+100)
  double usToPct(int us) {
    final double p;
    if (us >= centerUs) {
      p = maxUs == centerUs ? 0 : (us - centerUs) / (maxUs - centerUs) * 100;
    } else {
      p = centerUs == minUs ? 0 : (us - centerUs) / (centerUs - minUs) * 100;
    }
    return p.clamp(-100.0, 100.0).toDouble();
  }

  /// Kiểm tra theo E7. Trả về {tên trường: lỗi}; rỗng là hợp lệ.
  Map<String, String> validate() {
    final e = <String, String>{};
    if (name.trim().isEmpty) e['name'] = tr('Tên kênh không được trống', 'Channel name cannot be empty');
    if (minUs < minLimitUs) e['min'] = tr('Min tối thiểu $minLimitUs µs', 'Min is at least $minLimitUs µs');
    if (maxUs > maxLimitUs) e['max'] = tr('Max tối đa $maxLimitUs µs', 'Max is at most $maxLimitUs µs');
    if (minUs >= centerUs) e['center'] = tr('Cần Min < Center', 'Min must be below Center');
    if (centerUs >= maxUs) e['center'] = tr('Cần Center < Max', 'Center must be below Max');
    if (failsafeUs < minUs || failsafeUs > maxUs) e['failsafe'] = tr('Failsafe phải nằm trong [Min, Max]', 'Failsafe must be within [Min, Max]');
    if (trimUs.abs() > 200) e['trim'] = tr('Trim trong khoảng ±200 µs', 'Trim must be within ±200 µs');
    if (offsetUs.abs() > 300) e['offset'] = tr('Offset trong khoảng ±300 µs', 'Offset must be within ±300 µs');
    return e;
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'minUs': minUs,
        'centerUs': centerUs,
        'maxUs': maxUs,
        'trimUs': trimUs,
        'offsetUs': offsetUs,
        'reverse': reverse,
        'failsafeUs': failsafeUs,
        'enabled': enabled,
      };

  factory ChannelConfig.fromJson(Map<String, dynamic> j) => ChannelConfig(
        index: j['index'] as int,
        name: j['name'] as String? ?? 'Kênh ${j['index']}',
        minUs: j['minUs'] as int? ?? 1000,
        centerUs: j['centerUs'] as int? ?? 1500,
        maxUs: j['maxUs'] as int? ?? 2000,
        trimUs: j['trimUs'] as int? ?? 0,
        offsetUs: j['offsetUs'] as int? ?? 0,
        reverse: j['reverse'] as bool? ?? false,
        failsafeUs: j['failsafeUs'] as int? ?? 1500,
        enabled: j['enabled'] as bool? ?? false,
      );

  ChannelConfig copy() => ChannelConfig.fromJson(toJson());
}
