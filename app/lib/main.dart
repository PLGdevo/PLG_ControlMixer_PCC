import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller/car_controller.dart';
import 'data/profile_repository.dart';
import 'l10n/lang.dart';
import 'screens/garage_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = ThemeController();
  await theme.load();
  await LangController.instance.load();
  final repo = await ProfileRepository.open();
  runApp(RcApp(controller: CarController(), repo: repo, theme: theme));
}

class RcApp extends StatefulWidget {
  const RcApp({super.key, required this.controller, required this.repo, required this.theme});

  final CarController controller;
  final ProfileRepository repo;
  final ThemeController theme;

  @override
  State<RcApp> createState() => _RcAppState();
}

class _RcAppState extends State<RcApp> {
  final lang = LangController.instance;

  @override
  void initState() {
    super.initState();
    lang.addListener(_relabel);
  }

  @override
  void dispose() {
    lang.removeListener(_relabel);
    super.dispose();
  }

  /// Chuỗi lấy qua `tr()` không gắn với widget nào → đổi ngôn ngữ thì dựng lại toàn bộ cây,
  /// các màn đang mở và trạng thái của chúng giữ nguyên
  void _relabel() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, lang]),
      builder: (context, _) => MaterialApp(
        title: 'RC Controller',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(theme.accent),
        darkTheme: AppTheme.dark(theme.accent),
        themeMode: theme.mode,
        locale: lang.lang.locale,
        supportedLocales: [for (final l in AppLang.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: GarageScreen(controller: widget.controller, repo: widget.repo, theme: theme),
      ),
    );
  }
}
