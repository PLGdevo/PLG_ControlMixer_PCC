import 'package:flutter/material.dart';

import '../models/car_profile.dart';
import '../models/mixer_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Thẻ luật mix (Sprint 4 — U3): mô tả tự sinh, bật/tắt, sửa, xoá, kéo đổi thứ tự trong nhóm kênh
class MixRuleCard extends StatelessWidget {
  const MixRuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.profile,
    required this.onEdit,
    required this.onDelete,
    required this.onEnabled,
    this.error,
  });

  /// Vị trí trong nhóm (cho ReorderableDragStartListener)
  final int index;
  final MixRule rule;
  final CarProfile profile;
  final VoidCallback onEdit, onDelete;
  final ValueChanged<bool> onEnabled;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = rule.enabled;
    final names = {for (final c in profile.conditions) c.id: c.name};
    final head = [
      if (rule.name.isNotEmpty) rule.name.toUpperCase(),
      rule.combine.label.toLowerCase(),
      if (rule.priority > 0) 'priority ${rule.priority}',
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.s, Gap.xs, Gap.s),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.s),
                  child: AppIcon(AppIcons.drag, color: t.textMuted),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head, style: AppText.caption.copyWith(color: on ? t.accent : t.disabled)),
                    const SizedBox(height: 2),
                    Text(rule.describe(profile.inputMap, chName: profile.chLabel, condName: (id) => names[id] ?? id),
                        style: AppText.body.copyWith(color: on ? t.text : t.disabled)),
                    if (error != null)
                      Text(error!, style: AppText.label.copyWith(color: t.bad, fontSize: 12)),
                  ],
                ),
              ),
              Switch(value: on, onChanged: onEnabled),
              IconButton(
                tooltip: 'Xoá',
                onPressed: onDelete,
                icon: AppIcon(AppIcons.delete, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
