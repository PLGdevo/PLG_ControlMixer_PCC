// Hiển thị bố cục trên lưới và chế độ sửa (H2).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/control_layout.dart';
import '../theme/tokens.dart';
import 'layout_grid.dart';

enum _Corner { tl, tr, bl, br }

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
  _Corner? _corner; // null = di chuyển
  GridRect? _start, _preview;
  Offset _acc = Offset.zero;
  bool _valid = true, _overTrash = false;

  ControlLayout get l => widget.layout;

  bool _isOverTrash(Offset global) {
    final box = widget.trashKey?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(8).contains(global);
  }

  void _begin(ControlItem it, _Corner? corner) {
    widget.onSelect?.call(it.id);
    setState(() {
      _dragId = it.id;
      _corner = corner;
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
    final corner = _corner;
    if (corner == null) {
      r = GridRect((s.x + dx).clamp(0, l.cols - s.w).toInt(), (s.y + dy).clamp(0, l.rows - s.h).toInt(), s.w, s.h);
    } else {
      final lim = SizeLimits.of(it.kind).forCell(cw, ch, touchable: it.touchable);
      final left = corner == _Corner.tl || corner == _Corner.bl;
      final top = corner == _Corner.tl || corner == _Corner.tr;
      var w = (left ? s.w - dx : s.w + dx).clamp(lim.minW, lim.maxW).toInt();
      var h = (top ? s.h - dy : s.h + dy).clamp(lim.minH, lim.maxH).toInt();
      var x = left ? s.right - w : s.x;
      var y = top ? s.bottom - h : s.y;
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
    final over = corner == null && _isOverTrash(d.globalPosition);
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
      _corner = null;
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
        ],
      );
    });
  }

  Widget _item(BuildContext context, ControlItem it, double cw, double ch) {
    final t = context.tokens;
    final content = Padding(
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: (it.style.opacityPct / 100).clamp(0.3, 1.0),
        child: widget.itemBuilder(context, it),
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
        if (selected)
          for (final corner in _Corner.values)
            Positioned(
              left: corner == _Corner.tl || corner == _Corner.bl ? -6 : null,
              right: corner == _Corner.tr || corner == _Corner.br ? -6 : null,
              top: corner == _Corner.tl || corner == _Corner.tr ? -6 : null,
              bottom: corner == _Corner.bl || corner == _Corner.br ? -6 : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _begin(it, corner),
                onPanUpdate: (d) => _update(it, d, cw, ch),
                onPanEnd: (_) => _end(it),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: t.accentFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.onAccentFill, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
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
