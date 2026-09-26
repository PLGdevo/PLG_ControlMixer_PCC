// Nâng JSON hồ sơ cũ lên `CarProfile.schemaVersion` hiện tại (B5, E1, Sprint 4 — J4).
import 'dart:convert';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/condition.dart';
import '../models/control_layout.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';

class ProfileFormatException implements Exception {
  ProfileFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class ProfileMigration {
  /// Trả về bản JSON ở định dạng mới nhất; ném [ProfileFormatException] nếu không đọc được.
  /// Cảnh báo của bước chuyển v1 → v2 (báo cáo chuyển đổi — J4) được thêm vào `warnings`.
  static Map<String, dynamic> migrate(Map<String, dynamic> input, {List<String>? warnings}) {
    var j = Map<String, dynamic>.from(input);
    var v = j['schemaVersion'] as int? ?? 0;
    if (v > CarProfile.schemaVersion) {
      throw ProfileFormatException(tr('Hồ sơ được tạo bởi bản app mới hơn (định dạng $v)', 'Profile was made by a newer app version (format $v)'));
    }
    if (v == 0) {
      j = _v0ToV1(j);
      v = 1;
    }
    if (v == 1) {
      final r = v1ToV2(j);
      j = r.json;
      warnings?.addAll(r.warnings);
      v = 2;
    }
    if (j['id'] is! String || (j['id'] as String).isEmpty) {
      throw ProfileFormatException(tr('Hồ sơ thiếu mã (id)', 'Profile has no ID'));
    }
    return j;
  }

  /// Định dạng trước sprint (chỉ có servo ga/lái như gói CarConfig của firmware v1):
  /// { name, ip, port, config: { throttle: {...}|[...], steering: ..., failsafeTimeoutMs, gearCount, gearLimit } }
  static Map<String, dynamic> _v0ToV1(Map<String, dynamic> old) {
    final cfg = (old['config'] ?? old['servo'] ?? old) as Map<String, dynamic>;
    final channels = ChannelConfig.defaultList(steeringCh: 1, throttleCh: 2);

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
      'name': old['name'] as String? ?? tr('Xe cũ', 'Old car'),
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

  /// Sprint 3 (v1: kênh gán 1:1 vào phần tử, MixRule 4 loại) → Sprint 4 (v2: Input → Condition → Mixer).
  /// Bảng J4 trong `dac_ta_sprint_4_mixer.md`. Trả về JSON v2 và danh sách cảnh báo cho báo cáo chuyển đổi.
  static ({Map<String, dynamic> json, List<String> warnings}) v1ToV2(Map<String, dynamic> v1) {
    final j = jsonDecode(jsonEncode(v1)) as Map<String, dynamic>;
    final warnings = <String>[];

    // Kênh: đủ 10, bỏ offValuePct (chuyển sang mức của Input). Sprint 3: CH1 là Lái, CH2 là Ga.
    final chList = (j['channels'] as List? ?? const []).cast<Map<String, dynamic>>();
    final defaults = ChannelConfig.defaultList(steeringCh: 1, throttleCh: 2);
    final ch = <int, Map<String, dynamic>>{
      for (var n = 1; n <= 10; n++) n: chList.where((c) => c['index'] == n).firstOrNull ?? defaults[n - 1].toJson(),
    };
    double offPct(int n) => (ch[n]!['offValuePct'] as num?)?.toDouble() ?? -100;
    String chName(int n) => ch[n]!['name'] as String? ?? 'Kênh $n';

    final inputs = <String, InputDef>{};
    final primary = <int, String>{}; // kênh → Input có luật gốc
    String newInput(String id, String name, InputType type, int n) {
      inputs[id] = InputDef(
        id: id,
        name: name.length > 24 ? name.substring(0, 24) : name,
        type: type,
        levels: InputLevels(offPct: offPct(n)),
      );
      return id;
    }

    // 1. Phần tử → Input
    for (final l in (j['layouts'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      for (final it in (l['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final kind = ItemKind.values.asNameMap()[it['kind']] ?? ItemKind.button;
        void bind(String from, String to) {
          final n = it.remove(from) as int?;
          if (n == null || n < 1 || n > 10) return;
          final type = InputDef.typeFor(kind);
          final p = primary[n];
          if (p == null) {
            primary[n] = newInput('ch$n', chName(n), type, n);
            it[to] = 'ch$n';
          } else if (inputs[p]!.type == type) {
            it[to] = p;
          } else {
            var id = inputs.values
                .where((d) => d.id.startsWith('ch${n}_') && d.type == type)
                .map((d) => d.id)
                .firstOrNull;
            if (id == null) {
              id = newInput(InputDef.uniqueId('ch${n}_2', inputs.keys), '${chName(n)} (${kind.label})', type, n);
              warnings.add(tr(
                  'CH$n được gán vào hai kiểu phần tử khác nhau. ${kind.label} ở bố cục '
                      '"${l['name']}" gắn vào Input riêng "$id", chưa có luật mix.',
                  'CH$n was assigned to two different control types. ${kind.label} on layout '
                      '"${l['name']}" now uses its own Input "$id", with no mix rule yet.'));
            }
            it[to] = id;
          }
        }

        bind('channel', 'inputId');
        bind('channelY', 'inputIdY');
      }
    }

    // 2. Luật gốc: mỗi kênh có phần tử → Input ch{N} → CHN
    MixRule rule(String id, String src, int dest,
            {Expr cond = const ExprTrue(),
            Combine combine = Combine.replace,
            int priority = 0,
            bool? neutral = false,
            double dz = 5}) =>
        MixRule(
          id: id,
          source: src,
          destCh: dest,
          condition: cond,
          combine: combine,
          priority: priority,
          safety: SwitchSafety(requireNeutral: neutral, deadzonePct: dz),
        );
    final rules = <MixRule>[
      for (var n = 1; n <= 10; n++)
        if (primary[n] != null) rule('r_ch$n', primary[n]!, n),
    ];

    String constInput(double v) {
      final whole = v == v.roundToDouble();
      final s = (whole ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('-', 'm').replaceAll('.', '_');
      final id = 'k_$s';
      inputs.putIfAbsent(
          id, () => InputDef(id: id, name: tr('Hằng ${whole ? v.round() : v}%', 'Constant ${whole ? v.round() : v}%'), type: InputType.constant, constPct: v));
      return id;
    }

    // Kênh không có phần tử: Sprint 3 đọc là 0% → Input hằng số 0
    String source(int n) => primary[n] ?? constInput(0);

    // Luật max vào kênh không có phần tử: Sprint 3 so với 0% → thêm luật gốc hằng 0
    final zeroBase = <int>{};
    void ensureBase(int n) {
      if (primary[n] != null || !zeroBase.add(n)) return;
      rules.add(rule('r_ch${n}_0', constInput(0), n));
    }

    // 3. Luật mix Sprint 3 → luật mới, priority 1, giữ thứ tự
    const thr = 2; // Sprint 3: Ga luôn là CH2
    final written = <int>{};
    final mixes = (j['mixes'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (var i = 0; i < mixes.length; i++) {
      final m = mixes[i];
      final no = i + 1;
      final enabled = m['enabled'] as bool? ?? true;
      final type = m['type'] as String? ?? 'threshold';
      final combine = switch (m['mode']) { 'add' => Combine.add, 'max' => Combine.max, _ => Combine.replace };
      double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
      final src = m['sourceCh'] as int? ?? 1;
      final base = 'm${no}_';
      Expr gtZero(int n) => ExprCmp(input: source(n), op: CmpOp.gt, value: 0);

      void checkRead(int n, String role) {
        if (!enabled) return;
        if (written.contains(n)) {
          warnings.add(tr(
              'Luật mix $no đọc CH$n ($role) đã bị luật trước ghi vào; '
                  'nay đọc giá trị trước mix, kết quả có thể khác.',
              'Mix rule $no reads CH$n ($role), which an earlier rule wrote to; '
                  'it now reads the value before mixing, results may differ.'));
        }
        if (n == thr) warnings.add(tr('Luật mix $no đọc CH$thr (Ga): hộp số nay áp sau mix, kết quả có thể khác.', 'Mix rule $no reads CH$thr (throttle): gears now apply after mixing, results may differ.'));
      }

      void checkLevels(int n, String role) {
        final inp = inputs[source(n)];
        if (enabled && inp != null && !inp.isAxis && inp.type != InputType.constant && inp.levels.offPct > 0) {
          warnings.add(tr('Luật mix $no: $role CH$n có mức tắt > 0%; điều kiện nay so theo trạng thái bật/tắt.', 'Mix rule $no: $role CH$n has an off level > 0%; the condition now compares on/off state.'));
        }
      }

      final added = <MixRule>[];
      final gateCh = type == 'select' ? null : m['gateCh'] as int?;
      Expr? gate;
      if (gateCh != null) {
        checkRead(gateCh, tr('điều kiện', 'condition'));
        checkLevels(gateCh, tr('điều kiện', 'condition'));
        gate = gtZero(gateCh);
      }
      Expr withGate(Expr e) => gate == null ? e : (e is ExprTrue ? gate : ExprAnd([gate, e]));

      switch (type) {
        case 'linear' || 'curve':
          checkRead(src, tr('nguồn', 'source'));
          final r = rule('$base${type == 'linear' ? 'lin' : 'curve'}', source(src), m['targetCh'] as int? ?? 3,
              cond: withGate(const ExprTrue()), combine: combine, priority: 1);
          if (type == 'linear') {
            r
              ..weightPct = d('gainPct', 100)
              ..offsetPct = d('offsetPct', 0);
          } else {
            r.curve = MixCurve(
              type: CurveType.points,
              points: (m['curvePts'] as List?)?.map((e) => (e as num).toDouble()).toList(),
            );
          }
          added.add(r);
        case 'threshold':
          checkRead(src, tr('nguồn', 'source'));
          final inp = inputs[source(src)];
          if (enabled && inp != null && !inp.isAxis && inp.type != InputType.constant) {
            warnings.add(tr('Luật mix $no: ngưỡng trên nút/công tắc nay so theo trạng thái (0/1), không theo %.', 'Mix rule $no: thresholds on buttons/switches now compare state (0/1), not %.'));
          }
          if (enabled && gate != null) {
            warnings.add(tr('Luật mix $no: trạng thái trễ không còn reset khi điều kiện CH$gateCh tắt.', 'Mix rule $no: hysteresis state no longer resets when the CH$gateCh condition turns off.'));
          }
          final onAt = d('onAtPct', 80), offBelow = d('offBelowPct', 70);
          final cmp = ExprCmp(input: source(src), op: CmpOp.ge, value: onAt, hyst: onAt - offBelow);
          final dest = m['targetCh'] as int? ?? 3;
          added
            ..add(rule('${base}off', constInput(d('offValuePct', 0)), dest,
                cond: withGate(ExprNot(cmp)), combine: combine, priority: 1))
            ..add(rule('${base}on', constInput(d('onValuePct', 100)), dest,
                cond: withGate(cmp), combine: combine, priority: 1));
        case 'select':
          checkRead(src, tr('nguồn', 'source'));
          final sel = m['selectCh'] as int? ?? 3;
          checkRead(sel, tr('nút chọn', 'selector'));
          checkLevels(sel, tr('nút chọn', 'selector'));
          final tOn = m['targetOnCh'] as int? ?? 1, tOff = m['targetOffCh'] as int? ?? 4;
          if (enabled && [tOn, tOff].any((t) => primary[t] != null || written.contains(t))) {
            warnings.add(tr(
                'Luật mix $no (chuyển kênh): kênh đích không active trước đây bị ép 0%, '
                    'nay giữ giá trị của phần tử/luật khác.',
                'Mix rule $no (channel switch): inactive target channels used to be forced to 0%, '
                    'now they keep the value from other controls/rules.'));
          }
          final neutral = m['requireNeutralToSwitch'] as bool? ?? true;
          final dz = d('neutralDeadzonePct', 5);
          added
            ..add(rule('${base}on', source(src), tOn,
                cond: gtZero(sel), combine: combine, priority: 1, neutral: neutral, dz: dz))
            ..add(rule('${base}off', source(src), tOff,
                cond: ExprNot(gtZero(sel)), combine: combine, priority: 1, neutral: neutral, dz: dz));
      }

      for (final r in added) {
        r.enabled = enabled;
        if (!enabled) continue;
        if (r.combine == Combine.max) ensureBase(r.destCh);
        if (r.destCh == thr) {
          warnings.add(tr('Luật mix $no ghi vào CH$thr (Ga): hộp số nay áp sau mix, kết quả có thể khác.', 'Mix rule $no writes to CH$thr (throttle): gears now apply after mixing, results may differ.'));
        }
        ch[r.destCh]!['enabled'] = true; // Sprint 4: kênh tắt ra failsafe; Sprint 3 vẫn xuất giá trị mix
      }
      rules.addAll(added);
      if (enabled) written.addAll(added.map((r) => r.destCh));
    }

    for (final c in ch.values) {
      c.remove('offValuePct');
    }
    j
      ..['schemaVersion'] = 2
      ..['channels'] = [for (var n = 1; n <= 10; n++) ch[n]]
      ..['throttleCh'] = thr
      ..['steeringCh'] = 1
      ..['inputs'] = [
        for (var n = 1; n <= 10; n++)
          if (primary[n] != null) inputs[primary[n]]!.toJson(),
        for (final d in inputs.values)
          if (!primary.containsValue(d.id)) d.toJson(),
      ]
      ..['conditions'] = <Object>[]
      ..['mixer'] = [for (final r in rules) r.toJson()]
      ..['arm'] = {'autoArm': false}
      ..['output'] = {'protocol': 'rc_v2', 'periodMs': 25}
      ..remove('mixes');
    return (json: j, warnings: warnings);
  }
}
