import 'package:flutter/material.dart';

import 'controller/car_controller.dart';
import 'data/profile_repository.dart';
import 'screens/garage_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = ThemeController();
  await theme.load();
  final repo = await ProfileRepository.open();
  runApp(RcApp(controller: CarController(), repo: repo, theme: theme));
}

class RcApp extends StatelessWidget {
  const RcApp({super.key, required this.controller, required this.repo, required this.theme});

  final CarController controller;
  final ProfileRepository repo;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'RC Controller',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: theme.mode,
        home: GarageScreen(controller: controller, repo: repo, theme: theme),
      ),
    );
  }
}
