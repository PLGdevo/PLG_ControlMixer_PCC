// Màn Mạng của xe: mở từ tab Chung, đọc từ xe giả, đổi chế độ, lưu → hồ sơ được sửa IP/port/mã xe.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/protocol/net_protocol.dart';
import 'package:rc_controller/screens/network_screen.dart';
import 'package:rc_controller/screens/settings_screen.dart';
import 'package:rc_controller/theme/app_theme.dart';

import 'support/fake_car.dart';

Future<ProfileRepository> repoWith(WidgetTester tester, CarProfile p) async {
  final dir = Directory.systemTemp.createTempSync('rc_net_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final repo = ProfileRepository(dir);
  await tester.runAsync(() async {
    await repo.load();
    await repo.save(p);
  });
  return repo;
}

/// Hồ sơ ghi file thật: cho vòng lặp thật chạy vài nhịp để lệnh ghi xong
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Ô nhập đang chứa `text` (hint trùng nội dung cũng là Text nên lấy ô đầu tiên)
Finder field(String text) => find.widgetWithText(TextField, text).first;

void setSize(WidgetTester tester, Size s) {
  tester.view
    ..physicalSize = s
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockWakelock();
  });

  testWidgets('Chưa nối xe: giải thích, không có form', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = CarProfile(id: 'p1', name: 'Xe thử', connType: ConnType.wifi, wifi: WifiConn());
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: NetworkScreen(controller: CarController(), repo: repo, profileId: 'p1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Chưa kết nối xe'), findsOneWidget);
    expect(find.text('Lưu vào xe & khởi động lại'), findsNothing);
  });

  testWidgets('Cấu hình → Mạng của xe: đọc từ xe, chuyển sang WiFi riêng, lưu', (tester) async {
    setSize(tester, const Size(420, 2600));
    final p = CarProfile(id: 'p1', name: 'Xe thử', connType: ConnType.wifi, wifi: WifiConn(ip: '10.0.0.9'));
    final repo = await repoWith(tester, p);
    final c = CarController();
    final car = FakeCarTransport();
    await c.connect(car, key: p.connKey);
    expect(c.isConnected, isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: SettingsScreen(controller: c, repo: repo, profileId: 'p1', initialTab: 5),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mạng của xe'));
    await settleIo(tester);

    // Đọc từ xe: trạng thái + các ô
    expect(find.text('Đang chạy: Router'), findsOneWidget);
    expect(find.text('Mã xe 24:0A:C4:12:A1:B2'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nha Minh'), findsOneWidget);
    expect(find.widgetWithText(TextField, '192.168.1.50'), findsWidgets, reason: 'IP tĩnh');
    expect(repo.get('p1')!.wifi!.carId, '24:0A:C4:12:A1:B2', reason: 'ghi nhớ mã xe để dò');
    final save = find.widgetWithText(FilledButton, 'Lưu vào xe & khởi động lại');
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'chưa sửa gì');

    // Sửa sai thì báo lỗi, không cho lưu
    await tester.enterText(field('192.168.4.1'), '192.168.4.255');
    await tester.pumpAndSettle();
    expect(find.text('IP dạng 192.168.4.1 (số cuối 1–254)'), findsWidgets);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(field('192.168.4.255'), '192.168.4.1');

    // Chuyển sang WiFi riêng, đổi port
    await tester.tap(find.text('WiFi riêng (AP)').last);
    await tester.enterText(field('4210'), '5000');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu & khởi động lại'));
    await settleIo(tester);
    expect(find.text('Đã lưu cấu hình mạng'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await settleIo(tester);

    // Xe nhận đủ 3 phần + lệnh lưu; mật khẩu giữ nguyên (0xFF)
    expect(car.applied, 1);
    expect(car.netSets.map((b) => b.first), [NetSection.general, NetSection.ap, NetSection.sta]);
    expect(car.netSets[0].sublist(1, 4), [0, 0x88, 0x13], reason: 'AP, port 5000');
    expect(car.netSets[1].last, passHidden);
    expect(car.netSets[2].last, passHidden);
    expect(c.state, LinkState.disconnected);

    // Hồ sơ trỏ tới WiFi riêng của xe; màn Cấu hình nạp lại mà không báo "chưa lưu"
    final w = repo.get('p1')!.wifi!;
    expect([w.ip, w.port, w.ssid, w.carId], ['192.168.4.1', 5000, 'RC-CAR', '24:0A:C4:12:A1:B2']);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, '192.168.4.1'), findsWidgets);
    expect(find.widgetWithText(TextField, '5000'), findsOneWidget);
    expect(find.textContaining('tự tìm xe 24:0A:C4:12:A1:B2'), findsOneWidget);
    final pop = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
    expect(pop.canPop, isTrue, reason: 'không có thay đổi chưa lưu');
    c.dispose();
  });
}
