// Smoke test: app dựng được, màn "Xe của tôi" hiện trạng thái trống và đổi được giao diện.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/main.dart';
import 'package:rc_controller/theme/theme_controller.dart';

void main() {
  testWidgets('App mở ra màn Xe của tôi, chưa có xe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rc_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = ThemeController();
    await tester.pumpWidget(RcApp(controller: CarController(), repo: ProfileRepository(dir), theme: theme));
    await tester.pump();

    expect(find.text('Xe của tôi'), findsOneWidget);
    expect(find.text('Chưa có xe nào'), findsOneWidget);
    expect(find.text('Tạo xe mới'), findsOneWidget);

    expect(Theme.of(tester.element(find.text('Xe của tôi'))).brightness, Brightness.dark);
    await theme.setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Xe của tôi'))).brightness, Brightness.light);
  });
}
