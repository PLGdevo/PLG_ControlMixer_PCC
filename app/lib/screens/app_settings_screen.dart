// Cài đặt chung của app, không thuộc hồ sơ xe nào: ngôn ngữ, chế độ sáng/tối, màu chủ đạo. Áp dụng ngay.
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final lang = LangController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, lang]),
      builder: (context, _) {
        final t = context.tokens;
        Widget heading(HeroIcons icon, String s) => Padding(
              padding: const EdgeInsets.only(bottom: Gap.m),
              child: Row(children: [
                AppIcon(icon, color: t.textMuted, mini: true),
                const SizedBox(width: Gap.s),
                Text(s, style: AppText.title.copyWith(color: t.text)),
              ]),
            );
        return Scaffold(
          appBar: AppBar(title: Text(tr('Cài đặt', 'Settings'))),
          body: ListView(
            padding: const EdgeInsets.all(Gap.l),
            children: [
              heading(AppIcons.language, tr('Ngôn ngữ', 'Language')),
              SegmentedButton<AppLang>(
                showSelectedIcon: false,
                segments: [
                  for (final l in AppLang.values) ButtonSegment(value: l, label: Text('${l.short} · ${l.nativeName}')),
                ],
                selected: {lang.lang},
                onSelectionChanged: (s) => lang.setLang(s.first),
              ),
              const Divider(height: 40),
              heading(AppIcons.themeDark, tr('Chế độ hiển thị', 'Appearance')),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: ThemeMode.dark, label: Text(tr('Tối', 'Dark')), icon: const AppIcon(AppIcons.themeDark, mini: true)),
                  ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(tr('Sáng', 'Light')),
                      icon: const AppIcon(AppIcons.themeLight, mini: true)),
                  ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(tr('Hệ thống', 'System')),
                      icon: const AppIcon(AppIcons.themeSystem, mini: true)),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
              const Divider(height: 40),
              heading(AppIcons.palette, tr('Màu chủ đạo', 'Accent color')),
              Wrap(
                spacing: Gap.m,
                runSpacing: Gap.m,
                children: [
                  for (final a in AccentColor.appChoices)
                    _Swatch(accent: a, selected: theme.accent == a, onTap: () => theme.setAccent(a)),
                ],
              ),
              const SizedBox(height: Gap.m),
              Text(tr('Màu của nút, công tắc và điểm nhấn trên mọi màn, kể cả màn Lái.',
                      'Color of buttons, switches and highlights on every screen, including the drive screen.'),
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.selected, required this.onTap});

  final AccentColor accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: accent.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.field),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Column(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? t.text : t.line, width: selected ? 3 : 1),
                ),
                alignment: Alignment.center,
                child: selected ? AppIcon(AppIcons.check, color: AppTokens.of(accent, Brightness.dark).onAccentFill) : null,
              ),
              const SizedBox(height: Gap.xs),
              ExcludeSemantics(
                child: Text(accent.label,
                    textAlign: TextAlign.center,
                    style: AppText.label.copyWith(color: selected ? t.text : t.textMuted, fontSize: 13)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
