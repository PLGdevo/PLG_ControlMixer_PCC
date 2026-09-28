// Hiển thị bố cục trên lưới và chế độ sửa (H2).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/control_layout.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'layout_grid.dart';

/// Tay nắm đổi cỡ: 4 góc + 4 cạnh. `hx`/`hy`: −1 kéo cạnh trái/trên, 1 cạnh phải/dưới, 0 giữ nguyên trục đó.
enum _Handle {
  t(0, -1),
  r(1, 0),
  b(0, 1),
  l(-1, 0),
  tl(-1, -1),
  tr(1, -1),
  br(1, 1),
  bl(-1, 1);

  const _Handle(this.hx, this.hy);
  final int hx, hy;

  bool get corner => hx != 0 && hy != 0;
}

class LayoutCanvas extends StatefulWidget {
  const LayoutCanvas({
    super.key,
    required this.layout,
    required this.editing,
    required this.itemBuilder,
    this.selectedId,
    this.onSelect,
    this.onRectChanged,
    this.onDelete,
    this.trashKey,
    this.onDragState,
  });

  final ControlLayout layout;
  final bool editing;
  final Widget Function(BuildContext context, ControlItem item) itemBuilder;
  final String? selectedId;
  final ValueChanged<String?>? onSelect;

  /// Kết thúc kéo/đổi cỡ hợp lệ → vị trí mới (cha lưu lịch sử rồi áp dụng)
  final void Function(String id, GridRect rect)? onRectChanged;

  /// Thả phần tử vào thùng rác
  final ValueChanged<String>? onDelete;
  final GlobalKey? trashKey;

  /// (đang kéo, đang ở trên thùng rác)
  final void Function(bool dragging, bool overTrash)? onDragState;

  @override
  State<LayoutCanvas> createState() => _LayoutCanvasState();
}

class _LayoutCanvasState extends State<LayoutCanvas> {
  String? _dragId;
  _Handle? _handle; // null = di chuyển
  GridRect? _start, _preview;
  Offset _acc = Offset.zero;
  bool _valid = true, _overTrash = false;

  ControlLayout get l => widget.layout;

  bool _isOverTrash(Offset global) {
    final box = widget.trashKey?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(8).contains(global);
  }

  void _begin(ControlItem it, _Handle? handle) {
    widget.onSelect?.call(it.id);
    setState(() {
      _dragId = it.id;
      _handle = handle;
      _start = GridRect.of(it);
      _preview = _start;
      _acc = Offset.zero;
      _valid = true;
      _overTrash = false;
    });
    widget.onDragState?.call(true, false);
  }

  void _update(ControlItem it, DragUpdateDetails d, double cw, double ch) {
    final s = _start;
    if (s == null) return;
    _acc += d.delta;
    final dx = LayoutGrid.snap(_acc.dx, cw), dy = LayoutGrid.snap(_acc.dy, ch);
    GridRect r;
    final handle = _handle;
    if (handle == null) {
      r = GridRect((s.x + dx).clamp(0, l.cols - s.w).toInt(), (s.y + dy).clamp(0, l.rows - s.h).toInt(), s.w, s.h);
    } else {
      final lim = SizeLimits.of(it.kind).forCell(cw, ch, touchable: it.touchable);
      var x = s.x, y = s.y, w = s.w, h = s.h;
      if (handle.hx != 0) {
        w = (handle.hx < 0 ? s.w - dx : s.w + dx).clamp(lim.minW, lim.maxW).toInt();
        if (handle.hx < 0) x = s.right - w;
      }
      if (handle.hy != 0) {
        h = (handle.hy < 0 ? s.h - dy : s.h + dy).clamp(lim.minH, lim.maxH).toInt();
        if (handle.hy < 0) y = s.bottom - h;
      }
      if (x < 0) {
        w += x;
        x = 0;
      }
      if (y < 0) {
        h += y;
        y = 0;
      }
      if (x + w > l.cols) w = l.cols - x;
      if (y + h > l.rows) h = l.rows - y;
      r = GridRect(x, y, w, h);
    }
    final over = handle == null && _isOverTrash(d.globalPosition);
    if (r != _preview || over != _overTrash) {
      if (r != _preview) HapticFeedback.selectionClick();
      final lim = SizeLimits.of(it.kind);
      setState(() {
        _preview = r;
        _overTrash = over;
        _valid = LayoutGrid.fits(l, it.id, r) && r.w >= lim.minW && r.h >= lim.minH;
      });
      widget.onDragState?.call(true, over);
    }
  }

  void _end(ControlItem it) {
    final r = _preview, s = _start;
    if (_overTrash) {
      widget.onDelete?.call(it.id);
    } else if (r != null && s != null && r != s && _valid) {
      widget.onRectChanged?.call(it.id, r);
    }
    // Không hợp lệ → phần tử quay về chỗ cũ
    setState(() {
      _dragId = null;
      _handle = null;
      _start = null;
      _preview = null;
      _overTrash = false;
      _valid = true;
    });
    widget.onDragState?.call(false, false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final cw = c.maxWidth / l.cols, ch = c.maxHeight / l.rows;
      final dragging = _dragId != null && _preview != null;
      final guides = dragging ? LayoutGrid.guides(l, _dragId!, _preview!) : null;
      final selected = widget.editing ? l.items.where((i) => i.id == widget.selectedId).firstOrNull : null;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.editing) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelect?.call(null),
                child: CustomPaint(painter: _GridPainter(l.cols, l.rows, t.line)),
              ),
            ),
          ],
          for (final it in l.items)
            () {
              final r = it.id == _dragId && _preview != null ? _preview! : GridRect.of(it);
              return Positioned(
                key: ValueKey(it.id),
                left: r.x * cw,
                top: r.y * ch,
                width: r.w * cw,
                height: r.h * ch,
                child: _item(context, it, cw, ch),
              );
            }(),
          if (guides != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GuidePainter(guides.xs, guides.ys, cw, ch, t.accent)),
              ),
            ),
          if (selected != null) ..._handles(context, selected, cw, ch),
        ],
      );
    });
  }

  Widget _item(BuildContext context, ControlItem it, double cw, double ch) {
    final t = context.tokens;
    // Phần tử có màu riêng: dựng trong theme của màu đó (widget điều khiển lấy màu qua context.tokens)
    final itemColor = it.style.color;
    Widget built = Builder(builder: (context) => widget.itemBuilder(context, it));
    if (itemColor != null) built = Theme(data: AppTheme.of(itemColor, Theme.of(context).brightness), child: built);
    final content = Padding(
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: (it.style.opacityPct / 100).clamp(0.3, 1.0),
        child: built,
      ),
    );
    if (!widget.editing) return content;

    final selected = widget.selectedId == it.id;
    final isDragging = _dragId == it.id;
    final color = isDragging && (!_valid || _overTrash) ? t.bad : (selected ? t.accent : t.textMuted);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Trong chế độ sửa, phần tử không điều khiển xe
        Positioned.fill(child: IgnorePointer(child: content)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect?.call(it.id),
            onPanStart: (_) => _begin(it, null),
            onPanUpdate: (d) => _update(it, d, cw, ch),
            onPanEnd: (_) => _end(it),
            onPanCancel: () {
              if (_dragId == it.id) _end(it);
            },
            child: Container(
              decoration: BoxDecoration(
                color: isDragging && !_valid ? t.bad.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: color, width: selected || isDragging ? 2 : 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tay nắm đổi cỡ và nhãn kích thước của phần tử đang chọn. Vẽ ở lớp trên cùng của lưới
  /// (không nằm trong khung phần tử) để phần nhô ra ngoài khung vẫn nhận chạm và không bị phần tử
  /// bên cạnh che. Có key để giữ cử chỉ đang kéo khi danh sách con của Stack đổi (đường gióng hiện ra).
  List<Widget> _handles(BuildContext context, ControlItem it, double cw, double ch) {
    final t = context.tokens;
    final g = it.id == _dragId && _preview != null ? _preview! : GridRect.of(it);
    final rect = Rect.fromLTWH(g.x * cw, g.y * ch, g.w * cw, g.h * ch);
    const corner = 32.0, out = 16.0; // vùng chạm góc; `out` = phần dải cạnh nằm ngoài khung
    // Phần dải cạnh nằm trong khung; khung thấp / hẹp thì dải nằm hẳn bên ngoài để còn chỗ kéo di chuyển
    final inX = rect.width >= 64 ? 10.0 : 0.0, inY = rect.height >= 64 ? 10.0 : 0.0;
    final bad = _dragId == it.id && (!_valid || _overTrash);
    final fill = bad ? t.bad : t.accentFill;

    /// Vùng chạm của tay nắm `h`; hình tay nắm cỡ `size`, tâm tại `at` (toạ độ trong vùng chạm, nằm trên cạnh khung)
    Widget grip(_Handle h, Rect area, Size size, Offset at) => Positioned(
          key: ValueKey('handle-${h.name}'),
          left: area.left,
          top: area.top,
          width: area.width,
          height: area.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _begin(it, h),
            onPanUpdate: (d) => _update(it, d, cw, ch),
            onPanEnd: (_) => _end(it),
            onPanCancel: () {
              if (_dragId == it.id) _end(it);
            },
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: at.dx - size.width / 2,
                top: at.dy - size.height / 2,
                width: size.width,
                height: size.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(h.corner ? 4 : 3),
                    border: Border.all(color: t.onAccentFill, width: 1.5),
                  ),
                ),
              ),
            ]),
          ),
        );

    final widgets = <Widget>[];
    // Cạnh trước, góc sau (góc nằm trên khi hai vùng chạm chồng nhau)
    final lenX = max(rect.width - corner, 16.0), lenY = max(rect.height - corner, 16.0);
    final barX = Size(min(28.0, lenX), 7), barY = Size(7, min(28.0, lenY));
    widgets
      ..add(grip(_Handle.t, Rect.fromLTWH(rect.center.dx - lenX / 2, rect.top - out, lenX, out + inY), barX,
          Offset(lenX / 2, out)))
      ..add(grip(_Handle.b, Rect.fromLTWH(rect.center.dx - lenX / 2, rect.bottom - inY, lenX, out + inY), barX,
          Offset(lenX / 2, inY)))
      ..add(grip(_Handle.l, Rect.fromLTWH(rect.left - out, rect.center.dy - lenY / 2, out + inX, lenY), barY,
          Offset(out, lenY / 2)))
      ..add(grip(_Handle.r, Rect.fromLTWH(rect.right - inX, rect.center.dy - lenY / 2, out + inX, lenY), barY,
          Offset(inX, lenY / 2)));
    for (final h in _Handle.values.where((h) => h.corner)) {
      final c = Offset(h.hx < 0 ? rect.left : rect.right, h.hy < 0 ? rect.top : rect.bottom);
      widgets.add(grip(h, Rect.fromCenter(center: c, width: corner, height: corner), const Size(14, 14),
          const Offset(corner / 2, corner / 2)));
    }
    // Nhãn kích thước (số ô) khi đang kéo / đổi cỡ
    if (_dragId == it.id) {
      final above = rect.top >= 30;
      widgets.add(Positioned(
        key: const ValueKey('handle-size'),
        left: rect.center.dx - 60,
        width: 120,
        top: above ? rect.top - 30 : rect.bottom + 6,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 2),
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Text(
                '${g.w} × ${g.h}',
                style: AppText.caption.copyWith(
                  color: t.onAccentFill,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.cols, this.rows, this.color);

  final int cols, rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final cw = s.width / cols, ch = s.height / rows;
    for (var i = 0; i <= cols; i++) {
      canvas.drawLine(Offset(i * cw, 0), Offset(i * cw, s.height), p);
    }
    for (var j = 0; j <= rows; j++) {
      canvas.drawLine(Offset(0, j * ch), Offset(s.width, j * ch), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.cols != cols || o.rows != rows || o.color != color;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.xs, this.ys, this.cw, this.ch, this.color);

  final Set<int> xs, ys;
  final double cw, ch;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (final x in xs) {
      canvas.drawLine(Offset(x * cw, 0), Offset(x * cw, s.height), p);
    }
    for (final y in ys) {
      canvas.drawLine(Offset(0, y * ch), Offset(s.width, y * ch), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter o) => true;
}
