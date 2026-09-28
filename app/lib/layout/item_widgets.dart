// Phần tử trên màn Lái: cần gạt 1 trục, cần 2 trục, nút, nút bật/tắt, công tắc 3 nấc, núm xoay, ô đồng hồ,
// đèn LED, thanh giá trị, vector 2D.
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lang.dart';
import '../models/control_layout.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'return_motion.dart';

/// Khung thẻ chung cho mọi phần tử
class ItemFrame extends StatelessWidget {
  const ItemFrame({super.key, required this.child, this.label, this.trailing, this.highlight = false, this.padding});

  final Widget child;
  final String? label;
  final String? trailing;
  final bool highlight;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: padding ?? const EdgeInsets.all(Gap.s),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: highlight ? t.accent : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              // Khung hẹp: nhãn nhường chỗ trước, số thu nhỏ chữ cho vừa chứ không tràn
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  children: [
                    if (label != null)
                      Expanded(
                        child: Text(label!.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: t.textMuted)),
                      ),
                    if (trailing != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(trailing!,
                              style: AppText.caption.copyWith(color: t.text, fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ============================================================================
//  Tự về cho một trục (dùng chung cho cần 1 trục và 2 trục)
// ============================================================================
class _AxisReturn {
  ReturnConfig? cfg;
  double from = 0;
  bool active = false;

  void begin(double pos) {
    final c = cfg;
    active = c != null && c.returnsFrom(pos);
    from = pos;
  }

  /// Trả về vị trí mới, hoặc null nếu trục này không chạy
  double? at(int ms) {
    final c = cfg;
    if (!active || c == null) return null;
    final v = ReturnMotion.valueAt(c, from, ms);
    if (ms >= ReturnMotion.totalMs(c)) active = false;
    return v;
  }
}

// ============================================================================
//  Cần gạt 1 trục (ngang/dọc)
// ============================================================================
class StickAxis extends StatefulWidget {
  const StickAxis({
    super.key,
    required this.value,
    required this.onChanged,
    required this.vertical,
    this.returnCfg,
    this.deadzonePct = 0,
    this.haptic = true,
    this.knobSize = KnobSize.medium,
  });

  /// Vị trí hiện tại (%), −100…+100; dương = phải / lên
  final double value;
  final ValueChanged<double> onChanged;
  final bool vertical;
  final ReturnConfig? returnCfg;
  final double deadzonePct;
  final bool haptic;
  final KnobSize knobSize;

  @override
  State<StickAxis> createState() => _StickAxisState();
}

class _StickAxisState extends State<StickAxis> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _ret = _AxisReturn();
  int? _pointer;
  late double _pos = widget.value;

  @override
  void didUpdateWidget(StickAxis old) {
    super.didUpdateWidget(old);
    // Giá trị bị đặt từ ngoài (thoát màn, failsafe…) khi không chạm → đi theo
    if (_pointer == null && !_ticker.isActive && _out(_pos) != widget.value) _pos = widget.value;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _out(double p) => ReturnMotion.deadzone(p, widget.deadzonePct);

  void _emit(double p) {
    final old = _pos;
    _pos = p.clamp(-100.0, 100.0).toDouble();
    if (widget.haptic && _pointer != null && (old.sign != _pos.sign || (old != 0 && _pos == 0))) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
    widget.onChanged(_out(_pos));
  }

  void _fromLocal(Offset o, Size s) {
    final p = widget.vertical ? (1 - o.dy / s.height * 2) * 100 : (o.dx / s.width * 2 - 1) * 100;
    _emit(p);
  }

  void _onTick(Duration d) {
    final v = _ret.at(d.inMilliseconds);
    if (v != null) _emit(v);
    if (!_ret.active) _ticker.stop();
  }

  void _release() {
    _pointer = null;
    _ret
      ..cfg = widget.returnCfg
      ..begin(_pos);
    if (_ret.active) {
      _ticker
        ..stop()
        ..start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _ticker.stop();
          _fromLocal(e.localPosition, size);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _fromLocal(e.localPosition, size);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _release();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _release();
        },
        child: CustomPaint(
          size: size,
          painter: _AxisPainter(
            pos: _pos,
            vertical: widget.vertical,
            knob: widget.knobSize.factor,
            track: t.surface2,
            fill: t.accentFill,
            center: t.line,
            thumbEdge: t.onAccentFill,
          ),
        ),
      );
    });
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.pos,
    required this.vertical,
    required this.knob,
    required this.track,
    required this.fill,
    required this.center,
    required this.thumbEdge,
  });

  final double pos, knob;
  final bool vertical;
  final Color track, fill, center, thumbEdge;

  @override
  void paint(Canvas canvas, Size s) {
    final short = min(s.width, s.height), long = max(s.width, s.height);
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(short / 2));
    canvas.drawRRect(r, Paint()..color = track);
    final mid = Offset(s.width / 2, s.height / 2);
    final p = pos / 100;
    // Núm hình viên thuốc dẹp nằm ngang qua rãnh: bề ngang gần hết rãnh, bề dày theo cỡ núm
    final across = short * 0.84;
    final thick = (short * (0.2 + knob * 0.6)).clamp(min(14.0, across), across).toDouble();
    final travel = max(0.0, long / 2 - thick / 2 - (short - across) / 2);
    final c = vertical ? mid.translate(0, -p * travel) : mid.translate(p * travel, 0);
    // Vạch tâm
    final cp = Paint()
      ..color = center
      ..strokeWidth = 2;
    if (vertical) {
      canvas.drawLine(Offset(s.width * 0.2, mid.dy), Offset(s.width * 0.8, mid.dy), cp);
    } else {
      canvas.drawLine(Offset(mid.dx, s.height * 0.2), Offset(mid.dx, s.height * 0.8), cp);
    }
    // Đoạn đã kéo
    final bar = Paint()
      ..color = fill.withValues(alpha: 0.35)
      ..strokeWidth = short * 0.3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(mid, c, bar);
    final pill = Rect.fromCenter(
      center: c,
      width: vertical ? across : thick,
      height: vertical ? thick : across,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(thick / 2)), Paint()..color = fill);
    // Vạch cầm dọc theo thân viên thuốc
    final grip = Paint()
      ..color = thumbEdge.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final g = across / 2 - thick / 2;
    if (g > 2) {
      if (vertical) {
        canvas.drawLine(c.translate(-g, 0), c.translate(g, 0), grip);
      } else {
        canvas.drawLine(c.translate(0, -g), c.translate(0, g), grip);
      }
    }
  }

  @override
  bool shouldRepaint(_AxisPainter o) =>
      o.pos != pos || o.vertical != vertical || o.knob != knob || o.track != track || o.fill != fill;
}

// ============================================================================
//  Cần 2 trục
// ============================================================================
class Stick2D extends StatefulWidget {
  const Stick2D({
    super.key,
    required this.x,
    required this.y,
    required this.onChanged,
    this.returnX,
    this.returnY,
    this.deadzonePct = 0,
    this.haptic = true,
    this.knobSize = KnobSize.medium,
  });

  final double x, y;
  final void Function(double x, double y) onChanged;
  final ReturnConfig? returnX, returnY;
  final double deadzonePct;
  final bool haptic;
  final KnobSize knobSize;

  @override
  State<Stick2D> createState() => _Stick2DState();
}

class _Stick2DState extends State<Stick2D> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _rx = _AxisReturn(), _ry = _AxisReturn();
  int? _pointer;
  late double _x = widget.x, _y = widget.y;

  @override
  void didUpdateWidget(Stick2D old) {
    super.didUpdateWidget(old);
    if (_pointer == null && !_ticker.isActive) {
      if (_dz(_x) != widget.x) _x = widget.x;
      if (_dz(_y) != widget.y) _y = widget.y;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _dz(double v) => ReturnMotion.deadzone(v, widget.deadzonePct);

  void _emit(double x, double y) {
    final wasCenter = _x == 0 && _y == 0;
    _x = x.clamp(-100.0, 100.0).toDouble();
    _y = y.clamp(-100.0, 100.0).toDouble();
    if (widget.haptic && _pointer != null && !wasCenter && _dz(_x) == 0 && _dz(_y) == 0) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
    widget.onChanged(_dz(_x), _dz(_y));
  }

  void _fromLocal(Offset o, double side, Offset origin) {
    final d = o - origin;
    _emit(d.dx / (side / 2) * 100, -d.dy / (side / 2) * 100);
  }

  void _onTick(Duration d) {
    final ms = d.inMilliseconds;
    final nx = _rx.at(ms), ny = _ry.at(ms);
    if (nx != null || ny != null) _emit(nx ?? _x, ny ?? _y);
    if (!_rx.active && !_ry.active) _ticker.stop();
  }

  void _release() {
    _pointer = null;
    _rx
      ..cfg = widget.returnX
      ..begin(_x);
    _ry
      ..cfg = widget.returnY
      ..begin(_y);
    if (_rx.active || _ry.active) {
      _ticker
        ..stop()
        ..start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      // Giữ hình tròn, căn giữa trong khung (H6)
      final side = min(c.maxWidth, c.maxHeight);
      final origin = Offset(c.maxWidth / 2, c.maxHeight / 2);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _ticker.stop();
          _fromLocal(e.localPosition, side, origin);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _fromLocal(e.localPosition, side, origin);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _release();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _release();
        },
        child: CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _Stick2DPainter(
            x: _x,
            y: _y,
            side: side,
            knob: widget.knobSize.factor,
            base: t.surface2,
            line: t.line,
            fill: t.accentFill,
          ),
        ),
      );
    });
  }
}

class _Stick2DPainter extends CustomPainter {
  _Stick2DPainter({
    required this.x,
    required this.y,
    required this.side,
    required this.knob,
    required this.base,
    required this.line,
    required this.fill,
  });

  final double x, y, side, knob;
  final Color base, line, fill;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = side / 2;
    canvas.drawCircle(c, r, Paint()..color = base);
    final lp = Paint()
      ..color = line
      ..strokeWidth = 1.5;
    canvas.drawLine(c.translate(-r * 0.8, 0), c.translate(r * 0.8, 0), lp);
    canvas.drawLine(c.translate(0, -r * 0.8), c.translate(0, r * 0.8), lp);
    final kr = r * (0.25 + knob * 0.5);
    final travel = r - kr;
    final k = c.translate(x / 100 * travel, -y / 100 * travel);
    canvas.drawCircle(k, kr, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_Stick2DPainter o) => o.x != x || o.y != y || o.side != side || o.fill != fill || o.base != base;
}

// ============================================================================
//  Nút nhấn giữ / nút bật tắt
// ============================================================================
class ChannelButton extends StatelessWidget {
  const ChannelButton({
    super.key,
    required this.on,
    required this.label,
    required this.momentary,
    required this.onChanged,
    this.icon,
    this.haptic = true,
  });

  final bool on;
  final String? label;
  final bool momentary;
  final ValueChanged<bool> onChanged;
  final HeroIcons? icon;
  final bool haptic;

  void _set(bool v) {
    if (haptic) HapticFeedback.lightImpact();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = on ? t.onAccentFill : t.text;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: on ? t.accentFill : t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: on ? t.accentFill : t.line),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Gap.xs),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) AppIcon(icon!, color: fg, solid: on),
            if (label != null)
              Text(label!, style: AppText.label.copyWith(color: fg, fontWeight: FontWeight.w600)),
            if (!momentary)
              Text(on ? tr('BẬT', 'ON') : tr('TẮT', 'OFF'), style: AppText.caption.copyWith(color: on ? fg : t.textMuted)),
          ],
        ),
      ),
    );
    if (momentary) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: body,
      );
    }
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _set(!on), child: body);
  }
}

// ============================================================================
//  Công tắc 3 nấc: ◀ ● ▶
// ============================================================================
class Switch3 extends StatelessWidget {
  const Switch3({super.key, required this.position, required this.onChanged, this.haptic = true});

  final int position; // 0 thấp, 1 giữa, 2 cao
  final ValueChanged<int> onChanged;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const marks = ['◀', '●', '▶'];
    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: t.line),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i == position) return;
                  if (haptic) HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == position ? t.accentFill : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(marks[i],
                      style: AppText.label.copyWith(color: i == position ? t.onAccentFill : t.textMuted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
//  Núm xoay: kéo dọc để xoay, giữ nguyên vị trí
// ============================================================================
class Knob extends StatelessWidget {
  const Knob({super.key, required this.value, required this.onChanged, this.deadzonePct = 0, this.haptic = true});

  final double value;
  final ValueChanged<double> onChanged;
  final double deadzonePct;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final side = min(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          if (haptic) HapticFeedback.selectionClick();
          onChanged(0);
        },
        onVerticalDragUpdate: (d) {
          final nv = (value - d.delta.dy / side * 200).clamp(-100.0, 100.0).toDouble();
          if (haptic && value.sign != nv.sign) HapticFeedback.selectionClick();
          onChanged(nv);
        },
        child: CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _KnobPainter(value: value, side: side, base: t.surface2, fill: t.accentFill, line: t.line),
        ),
      );
    });
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({required this.value, required this.side, required this.base, required this.fill, required this.line});

  final double value, side;
  final Color base, fill, line;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = side / 2 - 4;
    const start = -pi / 2 - pi * 0.75, sweep = pi * 1.5;
    final arc = Rect.fromCircle(center: c, radius: r);
    final bg = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, start, sweep, false, bg);
    const mid = -pi / 2;
    final a = value / 100 * sweep / 2;
    canvas.drawArc(arc, a >= 0 ? mid : mid + a, a.abs(), false, bg..color = fill);
    canvas.drawCircle(c, r * 0.72, Paint()..color = base);
    final ang = mid + a;
    canvas.drawLine(
      c + Offset(cos(ang), sin(ang)) * r * 0.25,
      c + Offset(cos(ang), sin(ang)) * r * 0.62,
      Paint()
        ..color = fill
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter o) => o.value != value || o.side != side || o.fill != fill || o.base != base;
}

// ============================================================================
//  Ô đồng hồ
// ============================================================================
class GaugeTile extends StatelessWidget {
  const GaugeTile({super.key, required this.label, required this.value, this.sub, this.icon, this.color});

  final String label;
  final String value;
  final String? sub;
  final Widget? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: color ?? t.line),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                IconTheme(data: IconThemeData(color: t.textMuted, size: 14), child: icon!),
                const SizedBox(width: Gap.xs),
              ],
              Text(label.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
            ]),
            Text(value, style: AppText.metric.copyWith(color: color ?? t.text)),
            if (sub != null) Text(sub!, style: AppText.caption.copyWith(color: t.textMuted, letterSpacing: 0)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  Đèn LED trạng thái
// ============================================================================
class LedLamp extends StatefulWidget {
  const LedLamp({super.key, required this.on, this.label, this.blink = LedBlink.off});

  /// null = chưa có dữ liệu (đèn rỗng)
  final bool? on;
  final String? label;
  final LedBlink blink;

  @override
  State<LedLamp> createState() => _LedLampState();
}

class _LedLampState extends State<LedLamp> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this);

  bool get _blinking => widget.on == true && widget.blink != LedBlink.off;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LedLamp old) {
    super.didUpdateWidget(old);
    if (old.on != widget.on || old.blink != widget.blink) _sync();
  }

  void _sync() {
    if (_blinking) {
      final d = Duration(milliseconds: widget.blink.periodMs);
      if (!_anim.isAnimating || _anim.duration != d) {
        _anim
          ..duration = d
          ..repeat();
      }
    } else {
      _anim.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 2),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: t.line),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final d = (c.maxHeight * 0.62).clamp(8.0, 40.0);
        final lamp = AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final lit = widget.on == true && (!_blinking || _anim.value < 0.5);
            return Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lit ? t.accentFill : (widget.on == null ? Colors.transparent : t.surface2),
                border: Border.all(color: lit ? t.accentFill : t.line, width: 1.5),
                boxShadow: lit ? [BoxShadow(color: t.accentFill.withValues(alpha: 0.6), blurRadius: d * 0.6)] : null,
              ),
            );
          },
        );
        final label = widget.label;
        if (label == null || c.maxWidth < d * 2.5) return Center(child: lamp);
        return Row(children: [
          lamp,
          const SizedBox(width: Gap.s),
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: widget.on == true ? t.text : t.textMuted)),
          ),
        ]);
      }),
    );
  }
}

// ============================================================================
//  Thanh giá trị (chỉ hiển thị): ngang hoặc dọc theo hình khung
// ============================================================================
class ValueBar extends StatelessWidget {
  const ValueBar({super.key, required this.value, required this.min, required this.max});

  /// null = chưa có dữ liệu
  final double? value;
  final double min, max;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return CustomPaint(
        size: size,
        painter: _BarPainter(
          value: value,
          min: min,
          max: max,
          vertical: size.height > size.width,
          track: t.surface2,
          fill: t.accentFill,
          line: t.line,
        ),
      );
    });
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.vertical,
    required this.track,
    required this.fill,
    required this.line,
  });

  final double? value;
  final double min, max;
  final bool vertical;
  final Color track, fill, line;

  /// Vị trí 0…1 của `v` trên thanh
  double _f(double v) => max > min ? ((v - min) / (max - min)).clamp(0.0, 1.0) : 0;

  @override
  void paint(Canvas canvas, Size s) {
    // Thanh bo tròn hai đầu như rãnh cần gạt, không dày quá 28
    final thick = (vertical ? s.width : s.height).clamp(0.0, 28.0);
    final r = vertical
        ? Rect.fromCenter(center: s.center(Offset.zero), width: thick, height: s.height)
        : Rect.fromCenter(center: s.center(Offset.zero), width: s.width, height: thick);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(thick / 2));
    canvas.drawRRect(rr, Paint()..color = track);
    Offset at(double f) =>
        vertical ? Offset(r.center.dx, r.bottom - f * r.height) : Offset(r.left + f * r.width, r.center.dy);
    Offset lo(Offset p) => vertical ? Offset(r.left, p.dy) : Offset(p.dx, r.top);
    Offset hi(Offset p) => vertical ? Offset(r.right, p.dy) : Offset(p.dx, r.bottom);
    // Khoảng có cả số âm: tô từ vạch 0; toàn dương: tô từ đầu thanh
    final zero = min < 0 && max > 0 ? _f(0) : 0.0;
    if (zero > 0) {
      final z = at(zero);
      canvas.drawLine(lo(z), hi(z), Paint()
        ..color = line
        ..strokeWidth = 2);
    }
    final v = value;
    if (v == null) return;
    final a = at(zero), b = at(_f(v));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(Rect.fromPoints(lo(a), hi(b)), Paint()..color = fill.withValues(alpha: 0.55));
    canvas.restore();
    // Vạch giá trị
    canvas.drawLine(lo(b), hi(b), Paint()
      ..color = fill
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.value != value || o.min != min || o.max != max || o.vertical != vertical || o.fill != fill || o.track != track;
}

// ============================================================================
//  Vector 2D (chỉ hiển thị): chấm X/Y trong ô vuông, có vệt chuyển động
// ============================================================================
class VectorPad extends StatefulWidget {
  const VectorPad({super.key, required this.x, required this.y, this.trail = true});

  /// −1…+1 mỗi trục; null = chưa có dữ liệu
  final double? x, y;
  final bool trail;

  @override
  State<VectorPad> createState() => _VectorPadState();
}

class _VectorPadState extends State<VectorPad> with SingleTickerProviderStateMixin {
  static const trailMs = 600;
  late final Ticker _ticker = createTicker((_) => _prune());
  final _points = <(Offset, int)>[];

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void didUpdateWidget(VectorPad old) {
    super.didUpdateWidget(old);
    final x = widget.x, y = widget.y;
    if (!widget.trail || x == null || y == null) {
      _points.clear();
      return;
    }
    if (x != old.x || y != old.y) {
      _points.add((Offset(x, y), _now));
      if (_points.length > 48) _points.removeAt(0);
      if (!_ticker.isActive) _ticker.start();
    }
  }

  /// Vệt mờ dần theo thời gian; hết vệt thì dừng ticker
  void _prune() {
    final now = _now;
    _points.removeWhere((p) => now - p.$2 > trailMs);
    if (_points.isEmpty) _ticker.stop();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final x = widget.x, y = widget.y;
    final now = _now;
    return CustomPaint(
      size: Size.infinite,
      painter: _VectorPainter(
        dot: x == null || y == null ? null : Offset(x, y),
        trail: [for (final p in _points) (p.$1, 1 - (now - p.$2) / trailMs)],
        base: t.surface2,
        line: t.line,
        fill: t.accentFill,
      ),
    );
  }
}

class _VectorPainter extends CustomPainter {
  _VectorPainter({required this.dot, required this.trail, required this.base, required this.line, required this.fill});

  final Offset? dot;
  final List<(Offset, double)> trail; // (điểm, độ đậm 0…1)
  final Color base, line, fill;

  @override
  void paint(Canvas canvas, Size s) {
    final side = min(s.width, s.height);
    final sq = Rect.fromCenter(center: s.center(Offset.zero), width: side, height: side);
    canvas.drawRRect(RRect.fromRectAndRadius(sq, const Radius.circular(8)), Paint()..color = base);
    final lp = Paint()
      ..color = line
      ..strokeWidth = 1;
    final c = sq.center;
    canvas.drawLine(Offset(sq.left + 6, c.dy), Offset(sq.right - 6, c.dy), lp);
    canvas.drawLine(Offset(c.dx, sq.top + 6), Offset(c.dx, sq.bottom - 6), lp);
    final dr = (side * 0.06).clamp(4.0, 12.0);
    final half = side / 2 - dr - 2;
    Offset at(Offset v) => c.translate(v.dx.clamp(-1.0, 1.0) * half, -v.dy.clamp(-1.0, 1.0) * half);
    for (var i = 1; i < trail.length; i++) {
      final (pa, _) = trail[i - 1];
      final (pb, alpha) = trail[i];
      canvas.drawLine(
        at(pa),
        at(pb),
        Paint()
          ..color = fill.withValues(alpha: (alpha * 0.5).clamp(0.0, 1.0))
          ..strokeWidth = dr * 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
    final d = dot;
    if (d != null) canvas.drawCircle(at(d), dr, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_VectorPainter o) => true;
}
