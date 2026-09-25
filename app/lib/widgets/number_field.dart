import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Hàng chỉnh số: nhấn −/+ để đổi theo bước, giữ lâu để đổi gấp 10 lần. Lỗi hiện ngay dưới hàng.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
    this.error,
    this.enabled = true,
  });

  final String label;
  final int value, min, max, step;
  final String unit;
  final String? error;
  final bool enabled;
  final ValueChanged<int> onChanged;

  void _set(int v) => onChanged(v.clamp(min, max).toInt());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppText.body.copyWith(color: enabled ? t.text : t.disabled))),
              GestureDetector(
                onLongPress: enabled ? () => _set(value - step * 10) : null,
                child: IconButton.outlined(
                  onPressed: enabled && value > min ? () => _set(value - step) : null,
                  icon: const AppIcon(AppIcons.minus, mini: true),
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(
                  '$value$unit',
                  textAlign: TextAlign.center,
                  style: AppText.metric.copyWith(fontSize: 16, color: error != null ? t.bad : t.text),
                ),
              ),
              GestureDetector(
                onLongPress: enabled ? () => _set(value + step * 10) : null,
                child: IconButton.outlined(
                  onPressed: enabled && value < max ? () => _set(value + step) : null,
                  icon: const AppIcon(AppIcons.plus, mini: true),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(error!, style: AppText.label.copyWith(color: t.bad, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
