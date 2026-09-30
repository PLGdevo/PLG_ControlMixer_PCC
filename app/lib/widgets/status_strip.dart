// Thanh trên cùng của màn Lái / Cấu hình: "tai thỏ" hiện các giá trị người dùng chọn
// (pin, RSSI, kết nối, kênh…) và nút Kết nối / Ngắt của xe đang mở.
import 'dart:math';

import 'package:flutter/material.dart';

import '../controller/car_controller.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../models/data_source.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Giá trị hiện tại của một nguồn (null = chưa có dữ liệu). Trạng thái đúng/sai trả về 1/0.
/// Số đo từ xe chỉ có khi đang nối đúng xe của hồ sơ `p`.
double? readSource(CarController c, CarProfile p, String? key) {
  final here = c.isConnected && c.connectedKey == p.connKey;
  final tel = here ? c.telemetry : null;
  switch (key) {
    case DataSource.battery:
      return tel?.batteryV;
    case DataSource.current:
      return tel?.currentA;
    case DataSource.speed:
      return tel?.speedKmh;
    case DataSource.rssi:
      return tel == null || tel.rssi == 0 ? null : tel.rssi.toDouble();
    case DataSource.ping:
      return here ? c.pingMs : null;
    case DataSource.lq:
      return here ? c.linkQuality?.toDouble() : null;
    case DataSource.arm:
      return c.arm.armed ? 1 : 0;
    case DataSource.link:
      return here && c.state == LinkState.connected ? 1 : 0;
    case DataSource.failsafe:
      return tel == null ? null : (tel.failsafe ? 1 : 0);
  }
  final n = DataSource.chOf(key);
  if (n != null) {
    final out = c.channelPct;
    return out == null || n < 1 || n > out.length ? null : out[n - 1];
  }
  final id = DataSource.inputOf(key);
  if (id != null && p.input(id) != null) return c.pipeline?.inputs.valueOf(id) ?? c.position(id);
  return null;
}

/// Các nguồn chọn được cho thanh trạng thái
List<String> statusOptions(CarProfile p) => [
      ...DataSource.carKeys,
      ...DataSource.stateKeys,
      for (var i = 1; i <= p.channels.length; i++) DataSource.ch(i),
      for (final d in p.inputs) DataSource.input(d.id),
    ];

/// Chiều cao chung của tai thỏ và nút Kết nối / Ngắt: theo cạnh ngắn của màn (điện thoại nhỏ thấp hơn, máy tính bảng cao hơn)
double barPillHeight(BuildContext context) => (MediaQuery.sizeOf(context).shortestSide * 0.085).clamp(30.0, 40.0);

/// "Tai thỏ": viên thuốc tối ở giữa thanh trên cùng. `alarm` (nếu có) hiện đỏ trước các giá trị.
/// Bấm vào để chọn giá trị hiện (`onTap` = null khi không cho sửa, vd đang ARM).
class StatusNotch extends StatelessWidget {
  const StatusNotch({super.key, required this.controller, required this.profile, this.alarm, this.onTap});

  final CarController controller;
  final CarProfile profile;
  final String? alarm;
  final VoidCallback? onTap;

  static const _bg = Color(0xFF0B0B0D);
  static const _fg = Color(0xFFF2F2F4);
  static const _muted = Color(0xFF9A9AA2);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = [
      for (final k in profile.statusItems)
        if (DataSource.info(k, profile) != null) k,
    ];
    final children = <Widget>[
      if (alarm != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(AppIcons.warning, color: t.bad, size: 16),
          const SizedBox(width: Gap.xs),
          Text(alarm!, style: AppText.label.copyWith(color: t.bad, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      for (final k in items) _item(context, k),
      if (items.isEmpty && alarm == null && onTap != null)
        Text(tr('Bấm để chọn giá trị hiện', 'Tap to choose values'),
            style: AppText.label.copyWith(color: _muted, fontSize: 12)),
    ];
    return Semantics(
      button: onTap != null,
      label: tr('Thanh trạng thái', 'Status bar'),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: barPillHeight(context),
          padding: const EdgeInsets.symmetric(horizontal: Gap.m),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: alarm != null ? Border.all(color: t.bad, width: 1.5) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: Gap.m),
                children[i],
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, String key) {
    final t = context.tokens;
    final info = DataSource.info(key, profile)!;
    final v = readSource(controller, profile, key);
    var color = _fg;
    if (v != null && info.flag) {
      color = switch (key) {
        DataSource.link => v >= 0.5 ? t.ok : t.bad,
        DataSource.failsafe => v >= 0.5 ? t.bad : _fg,
        _ => v >= 0.5 ? t.accent : _muted,
      };
    } else if (v != null && info.group == SourceGroup.car && (info.alarmBelow ? v < info.alarm : v > info.alarm)) {
      color = t.warn;
    }
    final Widget icon = switch (key) {
      DataSource.battery => AppIcon(v == null ? AppIcons.batteryEmpty : AppIcons.batteryHalf, size: 16, color: _muted),
      DataSource.current => const AppIcon(AppIcons.current, size: 16, color: _muted),
      DataSource.speed => const CustomIconView(CustomIcon.speedometer, size: 16, color: _muted),
      DataSource.ping || DataSource.lq || DataSource.rssi =>
        AppIcon(v == null ? AppIcons.signalOff : AppIcons.signal, size: 16, color: _muted),
      DataSource.arm => AppIcon(v == 1 ? AppIcons.unlocked : AppIcons.locked, size: 16, color: _muted),
      DataSource.link => AppIcon(v == 1 ? AppIcons.connect : AppIcons.disconnect, size: 16, color: _muted),
      DataSource.failsafe => const AppIcon(AppIcons.warning, size: 16, color: _muted),
      _ => Text(info.label, style: AppText.caption.copyWith(color: _muted, letterSpacing: 0)),
    };
    final style = AppText.label.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Ô giá trị rộng cố định theo chuỗi dài nhất của nguồn: số đổi không làm tai thỏ co giãn;
    // số vượt khuôn (vd ping 1500 ms) thu nhỏ trong ô thay vì đẩy tai thỏ ra ngoài màn
    return Row(mainAxisSize: MainAxisSize.min, children: [
      icon,
      const SizedBox(width: 4),
      SizedBox(
        width: _slotWidth(context, info, style),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(v == null ? '--' : info.format(v), maxLines: 1, style: style),
        ),
      ),
    ]);
  }

  /// Bề rộng chuỗi dài nhất nguồn này hiện ra trong khoảng min..max (chữ số dạng bảng nên '8' đại diện mọi số)
  static double _slotWidth(BuildContext context, SourceInfo info, TextStyle style) {
    final String widest;
    if (info.flag) {
      widest = [info.onText, info.offText, '--'].reduce((a, b) => a.length >= b.length ? a : b);
    } else {
      final digits = max(info.min.abs(), info.max.abs()).truncate().toString().length;
      widest = info.format(0).replaceFirst(
          RegExp(r'^[0-9.]+'), '${info.min < 0 ? '-' : ''}${'8' * digits}${info.decimals > 0 ? '.${'8' * info.decimals}' : ''}');
    }
    final tp = TextPainter(
      text: TextSpan(text: widest, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return tp.width.ceilToDouble() + 1;
  }
}

/// Chọn giá trị hiện trên tai thỏ (thứ tự theo lúc chọn, tối đa [CarProfile.maxStatusItems]).
/// Trả về danh sách mới, null nếu huỷ.
Future<List<String>?> pickStatusItems(BuildContext context, CarProfile p) {
  final picked = [...p.statusItems];
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final t = ctx.tokens;
      final full = picked.length >= CarProfile.maxStatusItems;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.s, Gap.s),
              child: Row(children: [
                Expanded(
                  child: Text(tr('Thanh trạng thái (${picked.length}/${CarProfile.maxStatusItems})',
                      'Status bar (${picked.length}/${CarProfile.maxStatusItems})'),
                      style: AppText.title.copyWith(color: t.text)),
                ),
                TextButton(
                  onPressed: () => setS(() => picked
                    ..clear()
                    ..addAll(CarProfile.defaultStatusItems)),
                  child: Text(tr('Mặc định', 'Defaults')),
                ),
                FilledButton(onPressed: () => Navigator.pop(ctx, picked), child: Text(tr('Xong', 'Done'))),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final k in statusOptions(p))
                  if (DataSource.info(k, p) case final info?)
                    CheckboxListTile(
                      dense: true,
                      value: picked.contains(k),
                      title: Text(info.label),
                      subtitle: Text(info.group.label),
                      secondary: picked.contains(k)
                          ? CircleAvatar(radius: 12, child: Text('${picked.indexOf(k) + 1}', style: const TextStyle(fontSize: 12)))
                          : null,
                      onChanged: !picked.contains(k) && full
                          ? null
                          : (on) => setS(() => on == true ? picked.add(k) : picked.remove(k)),
                    ),
              ]),
            ),
          ]),
        ),
      );
    }),
  );
}

/// Nút Kết nối / Ngắt / Nối lại của xe đang mở. Đang ARM thì không cho ngắt (DISARM trước).
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.controller, required this.connKey, required this.onConnect, this.compact = false});

  final CarController controller;
  final String connKey;
  final VoidCallback onConnect;

  /// Màn hẹp: chỉ icon
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final here = c.isConnected && c.connectedKey == connKey;
    final connecting = c.connectingKey == connKey;
    final busy = c.connectingKey != null || c.state == LinkState.connecting;
    // Viên thuốc cao bằng tai thỏ; màn hẹp chỉ còn nút tròn icon cùng cỡ
    final h = barPillHeight(context);
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(h, h)),
      fixedSize: compact ? WidgetStatePropertyAll(Size(h, h)) : WidgetStatePropertyAll(Size.fromHeight(h)),
      padding: WidgetStatePropertyAll(compact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: Gap.m)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(AppText.label.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
      iconSize: const WidgetStatePropertyAll(16),
    );
    Widget pill({required bool filled, required VoidCallback? onPressed, required Widget icon, required String label}) {
      if (compact) {
        return filled
            ? IconButton.filled(onPressed: onPressed, style: style, icon: icon)
            : IconButton.outlined(onPressed: onPressed, style: style, icon: icon);
      }
      final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
      return filled
          ? FilledButton.icon(onPressed: onPressed, style: style, icon: icon, label: text)
          : OutlinedButton.icon(onPressed: onPressed, style: style, icon: icon, label: text);
    }

    if (connecting) {
      const spin = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      return pill(filled: false, onPressed: null, icon: spin, label: tr('Đang nối', 'Connecting'));
    }
    if (here && c.state == LinkState.connected) {
      // Tắt cơ chế ARM thì xe tự ARM ngay khi đủ điều kiện và không có nút DISARM: không chặn việc ngắt
      final locked = c.arm.enabled && c.arm.armed;
      final msg = locked ? tr('DISARM trước khi ngắt', 'DISARM before disconnecting') : tr('Ngắt kết nối', 'Disconnect');
      return Tooltip(
        message: msg,
        child: pill(
          filled: false,
          onPressed: locked ? null : c.disconnect,
          icon: const AppIcon(AppIcons.disconnect, mini: true, size: 16),
          label: tr('Ngắt', 'Disconnect'),
        ),
      );
    }
    // Chưa nối / rớt kết nối / mất tín hiệu → nối (lại)
    final label = here ? tr('Nối lại', 'Reconnect') : tr('Kết nối', 'Connect');
    return Tooltip(
      message: label,
      child: pill(
        filled: true,
        onPressed: busy ? null : onConnect,
        icon: const AppIcon(AppIcons.connect, mini: true, size: 16),
        label: label,
      ),
    );
  }
}

/// Công tắc "Thử trên xe" ở màn Cấu hình: bật thì chưa ARM xe vẫn xuất kênh theo cấu hình đang sửa
/// (cần gạt ở vị trí nghỉ, kênh đang kéo thử theo thanh Xem trước). Bấm khi chưa được thì báo lý do.
class LiveTestToggle extends StatelessWidget {
  const LiveTestToggle({super.key, required this.controller, this.compact = false});

  final CarController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = controller;
    final on = c.testing;
    final block = c.testBlock;
    void toggle() {
      if (!on && block != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(block)));
        return;
      }
      c.setTesting(!on);
    }

    final color = on ? t.onAccentFill : (block == null ? t.text : t.disabled);
    return Tooltip(
      message: on
          ? tr('Đang thử: kênh ra theo cấu hình đang sửa. Bấm để tắt', 'Testing: channels follow the settings being edited. Tap to stop')
          : (block ?? tr('Thử trên xe: kênh ra theo cấu hình đang sửa', 'Test on car: channels follow the settings being edited')),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: toggle,
        child: Container(
          height: barPillHeight(context),
          padding: const EdgeInsets.symmetric(horizontal: Gap.m),
          decoration: BoxDecoration(
            color: on ? t.accentFill : Colors.transparent,
            border: Border.all(color: on ? t.accentFill : t.line),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(on ? AppIcons.signal : AppIcons.signalOff, mini: true, color: color),
            if (!compact) ...[
              const SizedBox(width: Gap.xs),
              Text(on ? tr('Đang thử', 'Testing') : tr('Thử trên xe', 'Test on car'),
                  style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }
}
