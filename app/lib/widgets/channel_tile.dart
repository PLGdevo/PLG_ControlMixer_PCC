import 'package:flutter/material.dart';

import '../models/channel_config.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Một hàng trong tab Kênh: CHn · tên · luật mix ghi vào · công tắc bật/tắt (O1)
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.controlLabel,
    required this.onTap,
    required this.onEnabled,
  });

  final ChannelConfig channel;

  /// Tóm tắt nguồn của kênh (vd "Lái · 2 luật"); null = chưa có luật nào
  final String? controlLabel;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = channel;
    final on = c.enabled;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
          child: Row(
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                decoration: BoxDecoration(
                  color: on ? t.accentContainer : t.surface2,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                alignment: Alignment.center,
                child: Text(c.label,
                    style: AppText.label.copyWith(
                        color: on ? t.onAccentContainer : t.textMuted, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: AppText.title.copyWith(fontSize: 16, color: on ? t.text : t.disabled)),
                    Text(
                      '${controlLabel ?? 'Chưa có luật'} · ${c.minUs}/${c.centerUs}/${c.maxUs} µs${c.reverse ? ' · đảo' : ''}',
                      style: AppText.label.copyWith(color: on ? t.textMuted : t.disabled, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: onEnabled),
            ],
          ),
        ),
      ),
    );
  }
}
