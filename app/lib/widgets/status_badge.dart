import 'package:flutter/material.dart';

import '../controller/car_controller.dart';
import '../l10n/lang.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Huy hiệu trạng thái: luôn có chữ đi kèm, không chỉ dựa vào màu
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, label) = switch (state) {
      LinkState.connected => (t.ok, tr('Đã kết nối', 'Connected')),
      LinkState.connecting => (t.warn, tr('Đang kết nối…', 'Connecting…')),
      LinkState.lost => (t.bad, tr('Mất tín hiệu', 'Signal lost')),
      LinkState.disconnected => (t.idle, tr('Chưa kết nối', 'Not connected')),
    };
    return Pill(color: color, label: label);
  }
}

/// Viên thuốc có chấm màu + chữ
class Pill extends StatelessWidget {
  const Pill({super.key, required this.color, required this.label, this.dot = true});

  final Color color;
  final String label;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.xs + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
