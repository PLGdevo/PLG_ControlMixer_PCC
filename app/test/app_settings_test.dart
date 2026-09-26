// Cài đặt chung của app: ngôn ngữ VN/EN (đổi ngay, cả màn đang mở), chế độ sáng/tối, màu chủ đạo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/l10n/lang.dart';
import 'package:rc_controller/main.dart';
import 'package:rc_controller/models/channel_config.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/theme/theme_controller.dart';
import 'package:rc_controller/theme/tokens.dart';
import 'package:rc_controller/widgets/number_field.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Future<void> pumpApp(WidgetTester tester, ThemeController theme) async {
  final dir = Directory.systemTemp.createTempSync('rc_app_');
  addTearDown(() => dir.deleteSync(recursive: true));
  await tester.pumpWidget(RcApp(controller: CarController(), repo: ProfileRepository(dir), theme: theme));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => LangController.instance.setLang(AppLang.vi));

  testWidgets('Màn chính: nút VN/EN đổi ngôn ngữ ngay; đổi trong Cài đặt thì cả màn đang mở cũng đổi', (tester) async {
    await pumpApp(tester, ThemeController());
    expect(find.text('Chưa có xe nào'), findsOneWidget);
    expect(find.text('VN'), findsOneWidget);

    await tester.tap(find.byTooltip('Ngôn ngữ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('No cars yet'), findsOneWidget);
    expect(find.text('New car'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('app_lang'), 'en');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Accent color'), findsOneWidget);
    await tester.tap(find.text('VN · Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(find.text('Màu chủ đạo'), findsOneWidget);
    // Nhãn của Material cũng theo ngôn ngữ (pageBack() tìm tooltip "Back" nên không dùng được)
    expect(find.byTooltip('Quay lại'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có xe nào'), findsOneWidget, reason: 'màn chính bên dưới cũng đổi theo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cài đặt: chọn chế độ Sáng và màu chủ đạo, áp dụng ngay và lưu lại', (tester) async {
    final theme = ThemeController();
    await pumpApp(tester, theme);
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sáng'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Màu chủ đạo'))).brightness, Brightness.light);

    expect(find.text('Đỏ'), findsNothing, reason: 'đỏ / vàng chỉ dùng cho phần tử, không làm màu chủ đạo');
    await tester.tap(find.text('Xanh dương'));
    await tester.pumpAndSettle();
    expect(theme.accent, AccentColor.blue);
    final scheme = Theme.of(tester.element(find.text('Màu chủ đạo'))).colorScheme;
    expect(scheme.primary, AccentColor.blue.fill);
    expect(tester.takeException(), isNull);

    final again = ThemeController();
    await again.load();
    expect(again.mode, ThemeMode.light);
    expect(again.accent, AccentColor.blue);
  });

  testWidgets('Ô số: bấm = một bước, nhấn giữ = đổi liên tục, giữ lâu nhảy 5 bước; dừng ở giới hạn', (tester) async {
    var v = 1500;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => NumberField(
            label: 'Center',
            value: v,
            min: 500,
            max: 2500,
            step: 10,
            onChanged: (x) => setState(() => v = x),
          ),
        ),
      ),
    ));
    final plus = find.byType(IconButton).last, minus = find.byType(IconButton).first;
    await tester.tap(plus);
    await tester.pump();
    expect(v, 1510);

    final g = await tester.startGesture(tester.getCenter(plus));
    await tester.pump(const Duration(milliseconds: 300));
    expect(v, 1510, reason: 'chưa đủ lâu thì chưa lặp');
    await tester.pump(const Duration(milliseconds: 100)); // 350 ms: bắt đầu lặp
    expect(v, 1520);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(v, 1540);
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    expect(v, 1540, reason: 'thả tay thì dừng, không cộng thêm');

    // Giữ lâu: sau 15 lần lặp mỗi lần nhảy 5 bước (50 µs), tới Max thì dừng
    final g2 = await tester.startGesture(tester.getCenter(plus));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(v, 2500);
    await g2.up();
    await tester.pump();

    final g3 = await tester.startGesture(tester.getCenter(minus));
    await tester.pump(const Duration(milliseconds: 400));
    expect(v, 2490);
    await g3.up();
    await tester.pump(const Duration(seconds: 1));
    expect(v, 2490);
  });

  test('Màu chủ đạo: xanh chanh giữ bảng gốc, mọi màu đủ tương phản ở cả hai chế độ', () {
    expect(identical(AppTokens.of(AccentColor.lime, Brightness.dark), AppTokens.dark), isTrue);
    expect(identical(AppTokens.of(AccentColor.lime, Brightness.light), AppTokens.light), isTrue);
    for (final a in AccentColor.values) {
      final d = AppTokens.of(a, Brightness.dark), l = AppTokens.of(a, Brightness.light);
      expect(contrast(d.accent, d.bg), greaterThanOrEqualTo(4.5), reason: '${a.name}: chữ nhấn trên nền tối');
      expect(contrast(l.accent, l.surface), greaterThanOrEqualTo(4.5), reason: '${a.name}: chữ nhấn trên nền sáng');
      expect(contrast(d.onAccentFill, d.accentFill), greaterThanOrEqualTo(4.5), reason: '${a.name}: chữ trên nút');
      expect(d.bad, AppTokens.dark.bad, reason: 'màu trạng thái không đổi theo màu chủ đạo');
    }
  });

  test('tr() và nhãn theo ngôn ngữ; tên kênh mặc định hiển thị theo ngôn ngữ, dữ liệu không đổi', () async {
    final ch = ChannelConfig.defaults(3);
    expect(tr('Lưu', 'Save'), 'Lưu');
    expect(ch.displayName, 'Kênh 3');
    await LangController.instance.setLang(AppLang.en);
    expect(tr('Lưu', 'Save'), 'Save');
    expect(ItemKind.knob.label, 'Knob');
    expect(ch.displayName, 'Channel 3');
    expect(ch.name, 'Kênh 3');
    expect(ChannelConfig.defaults(4).name, 'Kênh 4', reason: 'tên mặc định lưu cố định');
    ch.name = 'Đèn';
    expect(ch.displayName, 'Đèn');
  });
}
