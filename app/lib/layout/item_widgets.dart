// Phần tử trên màn Lái: cần gạt 1 trục, cần 2 trục, nút, nút bật/tắt, công tắc 3 nấc, núm xoay, ô đồng hồ.
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
              child: Row(
                children: [
                  if (label != null)
                    Expanded(
                      child: Text(label!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: t.textMuted)),
                    ),
                  if (trailing != null)
                    Text(trailing!, style: AppText.caption.copyWith(color: t.text, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
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
    final short = min(s.width, s.height);
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(short / 2));
    canvas.drawRRect(r, Paint()..color = track);
    final mid = Offset(s.width / 2, s.height / 2);
    final p = pos / 100;
    final thumbR = (short * (0.45 + knob) / 2).clamp(10.0, short / 2);
    final along = vertical ? s.height / 2 - thumbR : s.width / 2 - thumbR;
    final c = vertical ? mid.translate(0, -p * along) : mid.translate(p * along, 0);
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
    canvas.drawCircle(c, thumbR, Paint()..color = fill);
    canvas.drawCircle(
        c,
        thumbR * 0.35,
        Paint()
          ..color = thumbEdge.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
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
