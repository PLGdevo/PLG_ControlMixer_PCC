// Kênh đầu ra (Sprint 4 — O1): Min/Center/Max, trim, offset, reverse, failsafe.
// Kênh nhận giá trị từ luật mix (M); kênh tắt luôn ra failsafeUs.

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

  /// CH1 = Lái, CH2 = Ga, CH3–CH10 tắt
  factory ChannelConfig.defaults(int index) => switch (index) {
        1 => ChannelConfig(index: 1, name: 'Lái', enabled: true, minUs: 1100, maxUs: 1900),
        2 => ChannelConfig(index: 2, name: 'Ga', enabled: true),
        _ => ChannelConfig(index: index, name: 'Kênh $index'),
      };

  static List<ChannelConfig> defaultList() =>
      List.generate(10, (i) => ChannelConfig.defaults(i + 1));

  String get label => 'CH$index';

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
    if (name.trim().isEmpty) e['name'] = 'Tên kênh không được trống';
    if (minUs < minLimitUs) e['min'] = 'Min tối thiểu $minLimitUs µs';
    if (maxUs > maxLimitUs) e['max'] = 'Max tối đa $maxLimitUs µs';
    if (minUs >= centerUs) e['center'] = 'Cần Min < Center';
    if (centerUs >= maxUs) e['center'] = 'Cần Center < Max';
    if (failsafeUs < minUs || failsafeUs > maxUs) e['failsafe'] = 'Failsafe phải nằm trong [Min, Max]';
    if (trimUs.abs() > 200) e['trim'] = 'Trim trong khoảng ±200 µs';
    if (offsetUs.abs() > 300) e['offset'] = 'Offset trong khoảng ±300 µs';
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
