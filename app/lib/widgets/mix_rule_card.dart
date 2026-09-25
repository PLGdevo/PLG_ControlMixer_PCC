import 'package:flutter/material.dart';

import '../models/channel_config.dart';
import '../models/mix_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Thẻ luật mix: mô tả tự sinh, bật/tắt, sửa, xoá, kéo đổi thứ tự (G5)
class MixRuleCard extends StatelessWidget {
  const MixRuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.channels,
    required this.onEdit,
    required this.onDelete,
    required this.onEnabled,
  });

  final int index;
  final MixRule rule;
  final List<ChannelConfig> channels;
  final VoidCallback onEdit, onDelete;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = rule.enabled;
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
                    Text('${index + 1}. ${rule.type.label.toUpperCase()} · ${rule.mode.label.toLowerCase()}',
                        style: AppText.caption.copyWith(color: on ? t.accent : t.disabled)),
                    const SizedBox(height: 2),
                    Text(rule.describe(channels), style: AppText.body.copyWith(color: on ? t.text : t.disabled)),
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
