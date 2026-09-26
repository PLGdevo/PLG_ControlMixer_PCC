// Bản thu nhỏ của bố cục màn Lái (tab Bố cục trong Cấu hình): chỉ để nhìn, không chạm vào phần tử được.
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../models/control_layout.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class LayoutPreview extends StatelessWidget {
  const LayoutPreview({super.key, required this.layout, required this.labelOf});

  final ControlLayout layout;

  /// Nhãn hiện trên từng phần tử (tên Input, tên ô đồng hồ, ...)
  final String Function(ControlItem item) labelOf;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: tr('Xem trước bố cục màn Lái', 'Drive screen layout preview'),
      child: AspectRatio(
        // Màn Lái nằm ngang, điện thoại phổ biến ~2:1 → ô lưới gần vuông như trên máy
        aspectRatio: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(Radii.field),
            border: Border.all(color: t.line),
          ),
          child: LayoutBuilder(builder: (context, box) {
            final cw = box.maxWidth / layout.cols, ch = box.maxHeight / layout.rows;
            return Stack(children: [
              for (final it in layout.items)
                Positioned(
                  left: it.x * cw + 1.5,
                  top: it.y * ch + 1.5,
                  width: it.w * cw - 3,
                  height: it.h * ch - 3,
                  child: _tile(t, it, Theme.of(context).brightness),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _tile(AppTokens base, ControlItem it, Brightness b) {
    final control = it.kind.isControl;
    final c = it.style.color;
    final t = c == null ? base : AppTokens.of(c, b);
    return Container(
      decoration: BoxDecoration(
        color: control ? t.accentContainer : t.surface2,
        border: Border.all(color: control ? t.accent : t.line),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Text(
          labelOf(it),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(
            fontSize: 10,
            letterSpacing: 0,
            height: 1.1,
            color: control ? t.onAccentContainer : t.textMuted,
          ),
        ),
      ),
    );
  }
}
