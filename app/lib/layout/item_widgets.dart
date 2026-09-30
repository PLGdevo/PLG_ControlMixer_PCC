// Phần tử trên màn Lái: cần gạt 1 trục, cần 2 trục, nút, nút bật/tắt, công tắc 3 nấc, núm xoay, ô đồng hồ,
// đèn LED, thanh giá trị, vector 2D, thanh trim, bảng kênh.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lang.dart';
import '../models/control_layout.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/hold_repeat.dart';
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

  /// Góc rãnh đồng tâm với góc khung thẻ (ItemFrame: bo Radii.card, lề Gap.s): khung ngoài bo sao
  /// thì rãnh, vệt kéo và núm bên trong bo theo đúng dáng đó
  static const trackRadius = Radii.card - Gap.s;

  /// Lề giữa rãnh và núm
  static const inset = 3.0;

  @override
  void paint(Canvas canvas, Size s) {
    final short = min(s.width, s.height), long = max(s.width, s.height);
    final outer = min(trackRadius, short / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(outer)), Paint()..color = track);
    final mid = Offset(s.width / 2, s.height / 2);
    final p = pos / 100;
    final inner = max(outer - inset, 2.0);
    // Núm dẹp nằm ngang qua rãnh: bề ngang gần hết rãnh, bề dày mỏng theo cỡ núm
    final across = max(short - inset * 2, 4.0);
    final thick = (short * (0.08 + knob * 0.28)).clamp(min(8.0, across), across).toDouble();
    final travel = max(0.0, long / 2 - thick / 2 - inset);
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
    // Đoạn đã kéo: cùng bề ngang và cùng góc bo với núm
    final band = Rect.fromPoints(
      vertical ? Offset(mid.dx - across / 2, mid.dy) : Offset(mid.dx, mid.dy - across / 2),
      vertical ? Offset(mid.dx + across / 2, c.dy) : Offset(c.dx, mid.dy + across / 2),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(band, Radius.circular(inner)), Paint()..color = fill.withValues(alpha: 0.3));
    final knobRect = Rect.fromCenter(
      center: c,
      width: vertical ? across : thick,
      height: vertical ? thick : across,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(knobRect, Radius.circular(min(inner, thick / 2))), Paint()..color = fill);
    // Vạch cầm dọc theo thân núm
    final grip = Paint()
      ..color = thumbEdge.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final g = across / 2 - max(inner, 4.0);
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
    this.axes = StickAxes.both,
    this.gimbal = false,
  });

  final double x, y;
  final void Function(double x, double y) onChanged;
  final ReturnConfig? returnX, returnY;
  final double deadzonePct;
  final bool haptic;
  final KnobSize knobSize;

  /// Trục dùng: chỉ 1 trục thì trục kia bị khoá ở giữa (như cần ga / cần lái của tay RC)
  final StickAxes axes;

  /// Vẽ kiểu tay RC (đế vuông, giếng tối, núm có khía)
  final bool gimbal;

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
    _x = widget.axes.hasX ? x.clamp(-100.0, 100.0).toDouble() : 0;
    _y = widget.axes.hasY ? y.clamp(-100.0, 100.0).toDouble() : 0;
    if (widget.haptic && _pointer != null && !wasCenter && _dz(_x) == 0 && _dz(_y) == 0) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
    widget.onChanged(_dz(_x), _dz(_y));
  }

  void _fromLocal(Offset o, double side, Offset origin) {
    final d = o - origin;
    // Kiểu tay RC: núm đi ít hơn nửa khung, lấy đúng quãng đi để núm nằm ngay dưới ngón tay
    final full = widget.gimbal ? GimbalPainter.travelOf(side, widget.knobSize.factor, widget.axes) : side / 2;
    _emit(d.dx / full * 100, -d.dy / full * 100);
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
          painter: widget.gimbal
              ? GimbalPainter(
                  x: _x,
                  y: _y,
                  side: side,
                  knob: widget.knobSize.factor,
                  axes: widget.axes,
                  accent: t.accentFill,
                  muted: t.textMuted,
                  dark: Theme.of(context).brightness == Brightness.dark,
                )
              : _Stick2DPainter(
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

/// Cần 2 trục kiểu tay RC: tấm đế vuông có ốc, giếng tối có vòng vạch, cao su chắn bụi, trục cần,
/// núm có khía đổ bóng theo hướng nghiêng, vệt sáng trên vòng chỉ hướng đẩy. Chỉ 1 trục thì có rãnh dẫn.
class GimbalPainter extends CustomPainter {
  GimbalPainter({
    required this.x,
    required this.y,
    required this.side,
    required this.knob,
    required this.axes,
    required this.accent,
    required this.muted,
    required this.dark,
  });

  final double x, y, side, knob;
  final StickAxes axes;
  final Color accent, muted;
  final bool dark;

  /// Quãng đi của núm (dp) tính từ tâm. Hai trục: gimbal vuông, góc vẫn nằm trong giếng.
  static double travelOf(double side, double knob, StickAxes axes) {
    final r = side * 0.44, rc = r * (0.18 + knob * 0.3);
    final t = r - rc - r * 0.07;
    return axes == StickAxes.both ? t / sqrt2 * 1.18 : t;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final sz = side;
    final r = sz * 0.44, rc = r * (0.18 + knob * 0.3);
    final travel = travelOf(sz, knob, axes);

    // Tấm đế + 4 ốc
    final plateRect = Rect.fromCenter(center: c, width: sz - 2, height: sz - 2);
    final plate = RRect.fromRectAndRadius(plateRect, Radius.circular(sz * 0.13));
    canvas.drawRRect(
        plate,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark ? const [Color(0xFF2E2F31), Color(0xFF1F2022)] : const [Color(0xFFF7F8F5), Color(0xFFE2E4DE)],
          ).createShader(plateRect));
    canvas.drawRRect(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark ? const Color(0xFF3D3E41) : const Color(0xFFD2D4CE));
    final so = sz * 0.075, sr = sz * 0.022;
    final slot = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (final p in [
      plateRect.topLeft.translate(so, so),
      plateRect.topRight.translate(-so, so),
      plateRect.bottomLeft.translate(so, -so),
      plateRect.bottomRight.translate(-so, -so),
    ]) {
      canvas.drawCircle(
          p,
          sr,
          Paint()
            ..shader = const RadialGradient(center: Alignment(-0.3, -0.3), colors: [Color(0xFF9DA0A6), Color(0xFF3B3D41)])
                .createShader(Rect.fromCircle(center: p, radius: sr)));
      final a = sr * 0.42;
      canvas.drawLine(p.translate(-a, -a), p.translate(a, a), slot);
      canvas.drawLine(p.translate(-a, a), p.translate(a, -a), slot);
    }

    // Viền nổi + giếng tối
    final bez = Rect.fromCircle(center: c, radius: r + 4);
    canvas.drawCircle(
        c,
        r + 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [Colors.white.withValues(alpha: 0.16), Colors.black.withValues(alpha: 0.6)]
                : [Colors.white.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.25)],
          ).createShader(bez));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.2),
            colors: dark ? const [Color(0xFF1B1C1E), Color(0xFF0C0D0E)] : const [Color(0xFF2C2D30), Color(0xFF1A1B1D)],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // Vòng vạch chia
    for (var i = 0; i < 48; i++) {
      final a = i / 48 * 2 * pi;
      final major = i % 12 == 0, mid = i % 6 == 0;
      final r1 = r * (major ? 0.8 : (mid ? 0.85 : 0.885)), r2 = r * 0.93;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(
          c + d * r1,
          c + d * r2,
          Paint()
            ..color = major ? muted : const Color(0xFF4A4B4F)
            ..strokeWidth = major ? 2 : 1);
    }

    final k = c.translate(x / 100 * travel, -y / 100 * travel);
    final mag = min(1.0, sqrt(x * x + y * y) / 100);

    // Vệt sáng trên vòng theo hướng đẩy cần
    if (mag > 0.02) {
      final a = atan2(-y, x), span = 0.25 + mag * 0.35;
      final arc = Rect.fromCircle(center: c, radius: r * 0.965);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5
        ..color = accent.withValues(alpha: 0.35 + mag * 0.65);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = accent.withValues(alpha: 0.5 * mag)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawArc(arc, a - span, span * 2, false, glow);
      canvas.drawArc(arc, a - span, span * 2, false, p);
    }

    // Rãnh dẫn khi chỉ dùng 1 trục, không thì chữ thập mờ
    if (axes != StickAxes.both) {
      final wid = rc * 0.75, len = travel * 2 + wid;
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: axes == StickAxes.x ? len : wid, height: axes == StickAxes.x ? wid : len),
          Radius.circular(wid / 2));
      canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.45));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.08));
    } else {
      final lp = Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = 1;
      canvas.drawLine(c.translate(-r * 0.75, 0), c.translate(r * 0.75, 0), lp);
      canvas.drawLine(c.translate(0, -r * 0.75), c.translate(0, r * 0.75), lp);
    }

    // Cao su chắn bụi: vòng trong lệch theo cần nhiều hơn vòng ngoài
    for (var i = 0; i < 3; i++) {
      final f = i / 2, br = r * (0.3 - f * 0.12);
      final b = Offset.lerp(c, k, f * 0.45)!;
      canvas.drawCircle(
          b,
          br,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: [i.isOdd ? const Color(0xFF2A2B2E) : const Color(0xFF232427), const Color(0xFF0D0E0F)],
            ).createShader(Rect.fromCircle(center: b, radius: br)));
      canvas.drawCircle(
          b,
          br,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.07));
    }

    // Trục cần
    if ((k - c).distance > 0.5) {
      canvas.drawLine(
          c,
          k,
          Paint()
            ..strokeWidth = r * 0.09
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(c, k, const [Color(0xFF1B1C1E), Color(0xFF6E7179)]));
    }

    // Bóng núm lệch theo hướng nghiêng
    canvas.drawCircle(
        k.translate(x / 100 * 6 + 2, -y / 100 * 6 + 5),
        rc,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + mag * 3));

    // Thân núm graphite có khía
    final capRect = Rect.fromCircle(center: k, radius: rc);
    canvas.drawCircle(
        k,
        rc,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A3D43), Color(0xFF131417)],
          ).createShader(capRect));
    final knurl = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.1;
    for (var i = 0; i < 44; i++) {
      final d = Offset(cos(i / 44 * 2 * pi), sin(i / 44 * 2 * pi));
      canvas.drawLine(k + d * rc * 0.74, k + d * rc * 0.97, knurl);
    }
    // Mặt núm lõm + viền sáng + chấm màu nhấn
    final top = rc * 0.7;
    canvas.drawCircle(
        k,
        top,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-0.35, -0.45), colors: [Color(0xFF5A5E66), Color(0xFF1D1F23)])
              .createShader(Rect.fromCircle(center: k, radius: top)));
    canvas.drawCircle(
        k,
        top,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawArc(
        Rect.fromCircle(center: k, radius: rc - 0.8),
        pi * 1.1,
        pi * 0.65,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.22));
    canvas.drawCircle(
        k,
        rc * 0.16,
        Paint()
          ..color = accent
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(k, rc * 0.16, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(GimbalPainter o) =>
      o.x != x || o.y != y || o.side != side || o.knob != knob || o.axes != axes || o.accent != accent || o.dark != dark;
}

// ============================================================================
//  Thanh trim kiểu tay RC: rãnh có vạch chia, vạch sáng chỉ vị trí, nút ◀ ▶ (▲ ▼) hai đầu.
//  Khung cao hơn rộng thì nằm dọc. Bấm vào rãnh: onTapTrack (mở bảng trim từng kênh).
// ============================================================================
class TrimBar extends StatelessWidget {
  const TrimBar({super.key, required this.value, required this.onStep, this.limit = 200, this.step = 5, this.onTapTrack});

  final int value, limit, step;

  /// Đổi trim thêm `delta` µs; null = khoá (vd chưa chọn kênh)
  final ValueChanged<int>? onStep;
  final VoidCallback? onTapTrack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final vertical = c.maxHeight > c.maxWidth;
      final short = vertical ? c.maxWidth : c.maxHeight;
      final btn = min(44.0, max(short, 24.0));
      Widget button(int dir) {
        final can = onStep != null && (dir < 0 ? value > -limit : value < limit);
        final glyph = vertical ? (dir > 0 ? '▲' : '▼') : (dir > 0 ? '▶' : '◀');
        return HoldRepeat(
          onStep: can ? (n) => onStep!(dir * step * n) : null,
          fastTimes: 2,
          child: SizedBox(
            width: vertical ? short : btn,
            height: vertical ? btn : short,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card - Gap.s)),
              ),
              onPressed: can ? () => onStep!(dir * step) : null,
              child: Text(glyph, style: TextStyle(fontSize: min(14.0, btn * 0.4))),
            ),
          ),
        );
      }

      final track = Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapTrack,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: vertical ? 0 : Gap.xs, vertical: vertical ? Gap.xs : 0),
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrimPainter(
                value: value / limit,
                vertical: vertical,
                track: t.surface2,
                tick: t.line,
                center: t.textMuted,
                mark: onStep == null ? t.disabled : t.accentFill,
              ),
            ),
          ),
        ),
      );
      final children = vertical ? [button(1), track, button(-1)] : [button(-1), track, button(1)];
      return vertical ? Column(children: children) : Row(children: children);
    });
  }
}

class _TrimPainter extends CustomPainter {
  _TrimPainter({
    required this.value,
    required this.vertical,
    required this.track,
    required this.tick,
    required this.center,
    required this.mark,
  });

  final double value; // −1…+1
  final bool vertical;
  final Color track, tick, center, mark;

  @override
  void paint(Canvas canvas, Size s) {
    final long = vertical ? s.height : s.width, across = vertical ? s.width : s.height;
    final th = min(10.0, across * 0.4);
    Offset at(double along, double off) => vertical ? Offset(s.width / 2 + off, along) : Offset(along, s.height / 2 + off);
    final rect = vertical
        ? Rect.fromCenter(center: s.center(Offset.zero), width: th, height: long)
        : Rect.fromCenter(center: s.center(Offset.zero), width: long, height: th);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(th / 2)), Paint()..color = track);
    // 21 vạch, vạch giữa đậm
    const n = 21;
    final pad = th / 2;
    for (var i = 0; i < n; i++) {
      final a = pad + (long - pad * 2) * i / (n - 1);
      final mid = i == n ~/ 2;
      final h = th / 2 + (mid ? 5 : 3);
      canvas.drawLine(
          at(a, -h),
          at(a, h),
          Paint()
            ..color = mid ? center : tick
            ..strokeWidth = mid ? 1.5 : 1);
    }
    // Vạch sáng vị trí trim (dọc: dương ở trên)
    final p = (value.clamp(-1.0, 1.0) + 1) / 2;
    final a = vertical ? long - pad - (long - pad * 2) * p : pad + (long - pad * 2) * p;
    final m = vertical ? Rect.fromCenter(center: at(a, 0), width: th + 6, height: 6) : Rect.fromCenter(center: at(a, 0), width: 6, height: th + 6);
    final mr = RRect.fromRectAndRadius(m, const Radius.circular(3));
    canvas.drawRRect(
        mr,
        Paint()
          ..color = mark.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(mr, Paint()..color = mark);
  }

  @override
  bool shouldRepaint(_TrimPainter o) => o.value != value || o.vertical != vertical || o.mark != mark || o.track != track;
}

// ============================================================================
//  Bảng kênh: mỗi kênh một dòng gọn — tên · thanh lệch từ giữa · số (µs hoặc %).
//  Nhiều kênh mà khung thấp thì tự chia cột.
// ============================================================================
class ChannelRow {
  const ChannelRow({required this.name, required this.pct, required this.value, this.on = true});
  final String name;
  final double pct; // −100…+100
  final String? value; // null = ẩn số
  final bool on;
}

class ChannelMonitor extends StatelessWidget {
  const ChannelMonitor({super.key, required this.rows});

  final List<ChannelRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (rows.isEmpty) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(tr('Chưa chọn kênh', 'No channel picked'), style: AppText.label.copyWith(color: t.textMuted)),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      const minRow = 14.0, minColW = 96.0;
      final maxCols = max(1, (c.maxWidth / minColW).floor());
      var cols = 1;
      while (cols < maxCols && rows.length / cols * minRow > c.maxHeight) {
        cols++;
      }
      final perCol = (rows.length / cols).ceil();
      final rowH = c.maxHeight / perCol;
      final fs = (rowH * 0.62).clamp(8.0, 13.0);
      final colW = (c.maxWidth - (cols - 1) * Gap.s) / cols;
      final nameW = min(colW * 0.34, fs * 5.2);
      final showNum = rows.any((r) => r.value != null);
      final valW = showNum ? min(colW * 0.3, fs * 3.4) : 0.0;
      final style = TextStyle(fontSize: fs, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()], height: 1);
      Widget row(ChannelRow r) => SizedBox(
            height: rowH,
            child: Row(children: [
              SizedBox(
                width: nameW,
                child: Text(r.name,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: style.copyWith(color: t.textMuted, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ChBarPainter(
                    pct: r.pct,
                    h: (rowH * 0.42).clamp(3.0, 8.0),
                    track: t.surface2,
                    center: t.textMuted,
                    fill: r.on ? t.accentFill : t.disabled,
                  ),
                ),
              ),
              if (showNum)
                SizedBox(
                  width: valW,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(r.value ?? '', maxLines: 1, softWrap: false, style: style.copyWith(color: r.on ? t.text : t.textMuted)),
                  ),
                ),
            ]),
          );
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var col = 0; col < cols; col++) ...[
          if (col > 0) const SizedBox(width: Gap.s),
          Expanded(
            child: Column(children: [
              for (final r in rows.skip(col * perCol).take(perCol)) row(r),
            ]),
          ),
        ],
      ]);
    });
  }
}

class _ChBarPainter extends CustomPainter {
  _ChBarPainter({required this.pct, required this.h, required this.track, required this.center, required this.fill});

  final double pct, h;
  final Color track, center, fill;

  @override
  void paint(Canvas canvas, Size s) {
    const pad = 4.0;
    final w = max(0.0, s.width - pad * 2);
    final r = Rect.fromLTWH(pad, (s.height - h) / 2, w, h);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)), Paint()..color = track);
    final mid = r.center.dx, v = (pct / 100).clamp(-1.0, 1.0);
    if (v != 0) {
      final f = Rect.fromLTRB(min(mid, mid + v * w / 2), r.top, max(mid, mid + v * w / 2), r.bottom);
      canvas.drawRRect(RRect.fromRectAndRadius(f, Radius.circular(h / 2)), Paint()..color = fill);
    }
    canvas.drawLine(
        Offset(mid, r.top - 2),
        Offset(mid, r.bottom + 2),
        Paint()
          ..color = center.withValues(alpha: 0.7)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ChBarPainter o) => o.pct != pct || o.fill != fill || o.h != h || o.track != track;
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
