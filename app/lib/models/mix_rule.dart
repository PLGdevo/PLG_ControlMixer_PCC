// Mô hình luật mix kênh (G1).
import 'dart:collection';
import 'dart:math';

import 'channel_config.dart';

enum MixType {
  threshold('Ngưỡng'),
  linear('Tỉ lệ'),
  curve('Đường cong'),
  select('Chuyển kênh');

  const MixType(this.label);
  final String label;
}

enum MixMode {
  override('Thay thế'),
  add('Cộng dồn'),
  max('Lấy lớn hơn');

  const MixMode(this.label);
  final String label;
}

class MixRule {
  static const maxRules = 20; // chạy đồng thời tối thiểu 10 luật, giới hạn 20 (G1)
  static const curveXs = [-100.0, -50.0, 0.0, 50.0, 100.0];

  String id;
  bool enabled;
  MixType type;
  int sourceCh;
  int targetCh; // không dùng khi type = select
  int? gateCh; // không dùng khi type = select
  MixMode mode;

  // threshold
  double onAtPct, offBelowPct, onValuePct, offValuePct;
  // linear
  double gainPct, offsetPct;
  // curve: 5 điểm tại −100, −50, 0, 50, 100
  List<double> curvePts;
  // select
  int selectCh, targetOnCh, targetOffCh;
  bool requireNeutralToSwitch;
  double neutralDeadzonePct;

  MixRule({
    required this.id,
    this.enabled = true,
    this.type = MixType.threshold,
    this.sourceCh = 1,
    this.targetCh = 3,
    this.gateCh,
    this.mode = MixMode.override,
    this.onAtPct = 80,
    this.offBelowPct = 70,
    this.onValuePct = 100,
    this.offValuePct = 0,
    this.gainPct = 100,
    this.offsetPct = 0,
    List<double>? curvePts,
    this.selectCh = 3,
    this.targetOnCh = 1,
    this.targetOffCh = 4,
    this.requireNeutralToSwitch = true,
    this.neutralDeadzonePct = 5,
  }) : curvePts = curvePts ?? [-100, -50, 0, 50, 100];

  static String newId() {
    final r = Random();
    return 'mix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${r.nextInt(1 << 20).toRadixString(36)}';
  }

  /// Các cạnh nguồn → đích để dò vòng lặp (G4)
  List<(int, int)> get edges => type == MixType.select
      ? [(sourceCh, targetOnCh), (sourceCh, targetOffCh)]
      : [(sourceCh, targetCh)];

  /// Các kênh mà luật này ghi vào
  Set<int> get targets => type == MixType.select ? {targetOnCh, targetOffCh} : {targetCh};

  /// Mô tả tự sinh cho thẻ luật (G5)
  String describe(List<ChannelConfig> channels) {
    String ch(int n) {
      final c = channels.where((c) => c.index == n).firstOrNull;
      final isDefaultName = c == null || c.name == 'Kênh $n';
      return isDefaultName ? 'CH$n' : 'CH$n (${c.name})';
    }

    String pct(double v) => '${v.round()}%';
    final gate = gateCh != null && type != MixType.select ? ' · khi ${ch(gateCh!)} bật' : '';
    return switch (type) {
      MixType.threshold => '${ch(sourceCh)} ≥ ${pct(onAtPct)} → ${ch(targetCh)} = ${pct(onValuePct)}'
          ' · < ${pct(offBelowPct)} → ${pct(offValuePct)}$gate',
      MixType.linear => '${ch(targetCh)} = ${ch(sourceCh)} × ${pct(gainPct)}'
          '${offsetPct >= 0 ? ' + ' : ' − '}${pct(offsetPct.abs())}$gate',
      MixType.curve => '${ch(targetCh)} = đường cong(${ch(sourceCh)})$gate',
      MixType.select => '${ch(selectCh)} bật → ${ch(sourceCh)} vào ${ch(targetOnCh)}'
          ' · tắt → vào ${ch(targetOffCh)}${requireNeutralToSwitch ? ' (khoá an toàn)' : ''}',
    };
  }

  /// Kiểm tra riêng một luật (E7/G4). Trả về lỗi đầu tiên hoặc null.
  String? validate() {
    bool okCh(int c) => c >= 1 && c <= 10;
    if (type == MixType.select) {
      final chs = [sourceCh, selectCh, targetOnCh, targetOffCh];
      if (!chs.every(okCh)) return 'Kênh phải trong khoảng CH1–CH10';
      if (chs.toSet().length != 4) return 'Nguồn, nút chọn và hai kênh đích phải khác nhau';
      if (neutralDeadzonePct < 0 || neutralDeadzonePct > 50) return 'Vùng chết trong khoảng 0–50%';
      return null;
    }
    if (!okCh(sourceCh) || !okCh(targetCh)) return 'Kênh phải trong khoảng CH1–CH10';
    if (sourceCh == targetCh) return 'Kênh nguồn và kênh đích phải khác nhau';
    if (gateCh != null && (!okCh(gateCh!) || gateCh == targetCh)) return 'Kênh điều kiện không hợp lệ';
    bool inRange(double v) => v >= -100 && v <= 100;
    switch (type) {
      case MixType.threshold:
        if (![onAtPct, offBelowPct, onValuePct, offValuePct].every(inRange)) {
          return 'Giá trị phải trong khoảng −100…+100%';
        }
        if (offBelowPct > onAtPct) return 'Ngưỡng tắt phải ≤ ngưỡng bật';
      case MixType.linear:
        if (gainPct < -200 || gainPct > 200) return 'Hệ số trong khoảng −200…+200%';
        if (!inRange(offsetPct)) return 'Độ lệch trong khoảng −100…+100%';
      case MixType.curve:
        if (curvePts.length != 5 || !curvePts.every(inRange)) return 'Đường cong cần 5 điểm trong −100…+100%';
      case MixType.select:
        break;
    }
    return null;
  }

  /// Kiểm tra cả danh sách: từng luật + số lượng + vòng lặp (G4)
  static String? validateAll(List<MixRule> rules) {
    if (rules.length > maxRules) return 'Tối đa $maxRules luật mix';
    for (var i = 0; i < rules.length; i++) {
      final e = rules[i].validate();
      if (e != null) return 'Luật ${i + 1}: $e';
    }
    final cycle = findCycle(rules.where((r) => r.enabled).toList());
    if (cycle != null) return 'Mix bị vòng lặp: ${cycle.map((c) => 'CH$c').join(' → ')}';
    return null;
  }

  /// Tìm chu trình trên đồ thị nguồn → đích; trả về đường đi (đầu = cuối) hoặc null
  static List<int>? findCycle(List<MixRule> rules) {
    final adj = <int, Set<int>>{};
    for (final r in rules) {
      for (final (a, b) in r.edges) {
        adj.putIfAbsent(a, () => {}).add(b);
      }
    }
    final state = <int, int>{}; // 0 chưa thăm, 1 đang thăm, 2 xong
    final stack = <int>[];
    List<int>? dfs(int u) {
      state[u] = 1;
      stack.add(u);
      for (final v in adj[u] ?? const <int>{}) {
        if (state[v] == 1) return [...stack.sublist(stack.indexOf(v)), v];
        if ((state[v] ?? 0) == 0) {
          final c = dfs(v);
          if (c != null) return c;
        }
      }
      stack.removeLast();
      state[u] = 2;
      return null;
    }

    for (final u in adj.keys.toList()..sort()) {
      if ((state[u] ?? 0) == 0) {
        final c = dfs(u);
        if (c != null) return c;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'type': type.name,
        'sourceCh': sourceCh,
        'targetCh': targetCh,
        'gateCh': gateCh,
        'mode': mode.name,
        'onAtPct': onAtPct,
        'offBelowPct': offBelowPct,
        'onValuePct': onValuePct,
        'offValuePct': offValuePct,
        'gainPct': gainPct,
        'offsetPct': offsetPct,
        'curvePts': curvePts,
        'selectCh': selectCh,
        'targetOnCh': targetOnCh,
        'targetOffCh': targetOffCh,
        'requireNeutralToSwitch': requireNeutralToSwitch,
        'neutralDeadzonePct': neutralDeadzonePct,
      };

  factory MixRule.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return MixRule(
      id: j['id'] as String? ?? newId(),
      enabled: j['enabled'] as bool? ?? true,
      type: MixType.values.asNameMap()[j['type']] ?? MixType.threshold,
      sourceCh: j['sourceCh'] as int? ?? 1,
      targetCh: j['targetCh'] as int? ?? 3,
      gateCh: j['gateCh'] as int?,
      mode: MixMode.values.asNameMap()[j['mode']] ?? MixMode.override,
      onAtPct: d('onAtPct', 80),
      offBelowPct: d('offBelowPct', 70),
      onValuePct: d('onValuePct', 100),
      offValuePct: d('offValuePct', 0),
      gainPct: d('gainPct', 100),
      offsetPct: d('offsetPct', 0),
      curvePts: (j['curvePts'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      selectCh: j['selectCh'] as int? ?? 3,
      targetOnCh: j['targetOnCh'] as int? ?? 1,
      targetOffCh: j['targetOffCh'] as int? ?? 4,
      requireNeutralToSwitch: j['requireNeutralToSwitch'] as bool? ?? true,
      neutralDeadzonePct: d('neutralDeadzonePct', 5),
    );
  }

  MixRule copy() => MixRule.fromJson(toJson());
}
