// Widget test các màn Sprint 4: màn chính (ảnh xe), Cấu hình (5 tab, Bố cục mở Sửa bố cục), sửa luật mix, sửa Input,
// bảng thuộc tính, màn Lái, báo cáo chuyển hồ sơ. Dựng thật để bắt lỗi runtime (dropdown sai giá trị, tràn layout...).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/layout/item_widgets.dart';
import 'package:rc_controller/layout/layout_canvas.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/layout/properties_panel.dart';
import 'package:rc_controller/main.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/data_source.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/screens/channel_detail_screen.dart';
import 'package:rc_controller/screens/control_screen.dart';
import 'package:rc_controller/screens/garage_screen.dart';
import 'package:rc_controller/screens/input_screen.dart';
import 'package:rc_controller/screens/mix_rule_screen.dart';
import 'package:rc_controller/screens/settings_screen.dart';
import 'package:rc_controller/services/arm_controller.dart';
import 'package:rc_controller/theme/app_theme.dart';
import 'package:rc_controller/theme/theme_controller.dart';
import 'package:rc_controller/theme/tokens.dart';
import 'package:rc_controller/widgets/channel_tile.dart';
import 'package:rc_controller/widgets/layout_preview.dart';

import 'support/fake_car.dart';

/// Hồ sơ có đủ loại luật: gắn nhanh, có điều kiện + khoá an toàn, hằng số có trễ
CarProfile sample() {
  final p = CarProfile(id: 'p1', name: 'Xe thử', connType: ConnType.wifi, wifi: WifiConn());
  ProfileTemplate.lightsHorn.applyTo(p);
  final l = p.activeLayout;
  p.inputs.addAll([
    InputDef(id: 'slider_x', name: 'Slider X'),
    InputDef(id: 'btn_a', name: 'Nút A', type: InputType.binary),
    InputDef(id: 'k100', name: 'Hằng 100%', type: InputType.constant, constPct: 100),
  ]);
  LayoutTemplates.addControl(l, ItemKind.knob, inputId: 'slider_x');
  LayoutTemplates.addControl(l, ItemKind.toggle, inputId: 'btn_a');
  l.items.add(ControlItem(id: 'mon', kind: ItemKind.gauge, source: DataSource.channels, x: 28, y: 0, w: 16, h: 6));
  p.mixer.addAll([
    MixRule(id: 'r_x1', source: 'slider_x', destCh: 1, priority: 1,
        condition: const ExprCmp(input: 'btn_a', op: CmpOp.eq, value: 1)),
    MixRule(id: 'r_x8', source: 'slider_x', destCh: 8,
        condition: const ExprCmp(input: 'btn_a', op: CmpOp.eq, value: 0)),
    MixRule(id: 'r_hi', source: 'k100', destCh: 7, curve: MixCurve(type: CurveType.expo, expoPct: 30),
        condition: const ExprAnd([
          ExprCmp(input: 'steer', op: CmpOp.ge, value: 80, hyst: 10),
          ExprNot(ExprCmp(input: 'light', op: CmpOp.eq, value: 1)),
        ])),
  ]);
  for (final n in [7, 8]) {
    p.ch(n).enabled = true;
  }
  return p;
}

/// Nút "Sửa bố cục" ở tab Bố cục của Cấu hình (FilledButton.icon là lớp con của FilledButton)
final editLayoutButton =
    find.ancestor(of: find.text('Sửa bố cục'), matching: find.byWidgetPredicate((w) => w is FilledButton));

/// Đọc/ghi file thật phải chạy ngoài fake-async của testWidgets
Future<ProfileRepository> repoWith(WidgetTester tester, CarProfile p) async {
  final dir = Directory.systemTemp.createTempSync('rc_screens_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final repo = ProfileRepository(dir);
  await tester.runAsync(() async {
    await repo.load();
    await repo.save(p);
  });
  return repo;
}

Widget app(Widget home) => MaterialApp(theme: AppTheme.dark(), home: home);

void setSize(WidgetTester tester, Size s) {
  tester.view
    ..physicalSize = s
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Cho vòng lặp thật chạy vài nhịp để xong các thao tác đọc/ghi file; có [until] thì chờ tới khi đúng (tối đa ~2 s)
Future<void> settleIo(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 10 || (until != null && !until() && i < 100); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Màn chính: tiêu đề PCC TX Control, bấm ảnh xe để chọn ảnh rồi bỏ ảnh', (tester) async {
    setSize(tester, const Size(420, 900));
    final repo = await repoWith(tester, sample());
    final src = File('${repo.dir.path}${Platform.pathSeparator}chon.jpg')..writeAsBytesSync([1, 2, 3]);
    var picks = 0;
    await tester.pumpWidget(app(GarageScreen(
      controller: CarController(),
      repo: repo,
      theme: ThemeController(),
      pickPhoto: () async {
        picks++;
        return src.path;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('PCC TX Control'), findsOneWidget);
    expect(find.text('Xe của tôi'), findsNothing);

    await tester.tap(find.byTooltip('Chọn ảnh cho xe'));
    await settleIo(tester, until: () => repo.get('p1')!.photo != null);
    expect(picks, 1, reason: 'chưa có ảnh thì mở thẳng thư viện ảnh');
    final photo = repo.photoFile(repo.get('p1')!)!;
    expect(await tester.runAsync(photo.exists), isTrue);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byTooltip('Đổi ảnh xe'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn ảnh khác'), findsOneWidget);
    await tester.tap(find.text('Bỏ ảnh'));
    await settleIo(tester, until: () => repo.get('p1')!.photo == null);
    expect(picks, 1);
    expect(repo.get('p1')!.photo, isNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byTooltip('Chọn ảnh cho xe'), findsOneWidget);
  });

  testWidgets('Cấu hình: chọn kênh Ga khác, bỏ kênh Lái ở tab Chung, vẫn lưu được', (tester) async {
    setSize(tester, const Size(420, 1800)); // đủ cao để dựng tới phần Kênh Ga / Lái
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(SettingsScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.tap(find.widgetWithText(Tab, 'Chung'));
    await tester.pumpAndSettle();
    Future<void> pick(Finder field, String item) async {
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    final fields = find.byType(DropdownButtonFormField<int>);
    expect(fields, findsNWidgets(2));
    await pick(fields.first, 'CH5');
    expect(find.text('Chưa có luật mix nào điều khiển kênh Ga (CH5)'), findsOneWidget);
    await pick(fields.last, 'Không có');
    final save = find.ancestor(of: find.text('Lưu'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await settleIo(tester); // Lưu ghi file thật
    expect(find.text('Đã lưu vào máy'), findsOneWidget);
    final p = repo.get('p1')!;
    expect([p.throttleCh, p.steeringCh], [5, null]);
    expect(p.ch(5).enabled, isTrue);
    expect(p.ch(5).name, 'Ga');
  });

  testWidgets('Cấu hình: dựng đủ 5 tab, không còn tab Ga / Lái, hồ sơ mẫu hợp lệ', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = sample();
    expect(p.validateAll(), isEmpty);
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(SettingsScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    expect(find.widgetWithText(Tab, 'Ga'), findsNothing);
    expect(find.widgetWithText(Tab, 'Lái'), findsNothing);
    // Thanh tab cuộn ngang khi không đủ chỗ
    Future<void> tab(String name) async {
      await tester.ensureVisible(find.widgetWithText(Tab, name));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, name));
      await tester.pumpAndSettle();
    }

    for (final name in ['Input', 'Mix', 'Kênh', 'Chung', 'Bố cục']) {
      await tab(name);
      expect(tester.takeException(), isNull, reason: name);
    }
    await tab('Input');
    expect(find.text('Slider X'), findsOneWidget);
    await tab('Mix');
    expect(find.textContaining('CH1 · LÁI'), findsOneWidget); // nhóm theo kênh đích
    setSize(tester, const Size(420, 2400)); // đủ cao để dựng hết danh sách luật
    await tester.pumpAndSettle();
    expect(find.textContaining('Slider X → CH8'), findsOneWidget);
    await tab('Chung');
    await tester.tap(find.text('Điều kiện ARM riêng'));
    await tester.pumpAndSettle();
    expect(find.text('Luôn đúng — luật luôn chạy.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cấu hình ▸ Bố cục: xem trước, Sửa bố cục mở màn Lái ở chế độ sửa kể cả khi khoá, Huỷ quay về', (tester) async {
    setSize(tester, const Size(900, 800));
    final p = sample();
    expect(p.activeLayout.locked, isTrue, reason: 'bố cục mặc định khoá');
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(SettingsScreen(
      controller: CarController(),
      repo: repo,
      profileId: 'p1',
      initialTab: SettingsScreen.layoutTab,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LayoutPreview), findsOneWidget);
    expect(find.descendant(of: find.byType(LayoutPreview), matching: find.text('Slider X')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final edit = editLayoutButton;
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(ControlScreen), findsOneWidget);
    expect(find.text('Sửa bố cục · kéo để di chuyển · nhấn đúp để cấu hình'), findsOneWidget);
    expect(find.byTooltip('Tuỳ chọn'), findsNothing, reason: 'mở từ Cấu hình thì không có thanh lái / menu');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlScreen), findsNothing);
    expect(find.byType(LayoutPreview), findsOneWidget);
  });

  testWidgets('Cấu hình ▸ Bố cục: có thay đổi chưa lưu thì hỏi lưu trước khi sửa bố cục', (tester) async {
    setSize(tester, const Size(900, 800));
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(SettingsScreen(
      controller: CarController(),
      repo: repo,
      profileId: 'p1',
      initialTab: SettingsScreen.layoutTab,
    )));
    await tester.pumpAndSettle();
    final lock = find.widgetWithText(SwitchListTile, 'Khoá bố cục');
    await tester.ensureVisible(lock);
    await tester.tap(lock);
    await tester.pumpAndSettle();

    final edit = editLayoutButton;
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Lưu thay đổi?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Lưu')));
    await settleIo(tester, until: () => find.byType(ControlScreen).evaluate().isNotEmpty);
    expect(repo.get('p1')!.activeLayout.locked, isFalse, reason: 'đã lưu trước khi mở Sửa bố cục');
    expect(find.text('Sửa bố cục · kéo để di chuyển · nhấn đúp để cấu hình'), findsOneWidget);
  });

  testWidgets('Màn Lái ▸ Cấu hình ▸ Bố cục ▸ Sửa bố cục: quay về màn Lái ở chế độ sửa', (tester) async {
    setSize(tester, const Size(900, 800));
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(ControlScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Tuỳ chọn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cấu hình'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(Tab, 'Bố cục'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Bố cục'));
    await tester.pumpAndSettle();
    final edit = editLayoutButton;
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(ControlScreen), findsOneWidget);
    expect(find.text('Sửa bố cục · kéo để di chuyển · nhấn đúp để cấu hình'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlScreen), findsOneWidget, reason: 'mở từ màn Lái thì Huỷ ở lại màn Lái');
    expect(find.byTooltip('Tuỳ chọn'), findsOneWidget);
  });

  testWidgets('Cấu hình nằm ngang: nút Lưu / Đồng bộ / Mặc định lên thanh tiêu đề, 5 tab không tràn, tab Chung có Ping xe', (tester) async {
    setSize(tester, const Size(800, 360));
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(SettingsScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Lưu')), findsOneWidget);
    expect(find.byTooltip('Mặc định'), findsOneWidget);
    expect(find.text('Đồng bộ failsafe'), findsNothing, reason: 'nằm ngang chỉ còn nút biểu tượng');
    Future<void> tab(String name) async {
      await tester.ensureVisible(find.widgetWithText(Tab, name));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, name));
      await tester.pumpAndSettle();
    }

    for (final name in ['Input', 'Mix', 'Kênh', 'Chung', 'Bố cục']) {
      await tab(name);
      expect(tester.takeException(), isNull, reason: name);
    }
    await tab('Chung');
    final vertical = find.descendant(
        of: find.byType(TabBarView),
        matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
    await tester.scrollUntilVisible(find.text('Ping xe'), 150, scrollable: vertical.first);
    expect(find.text('Ping xe'), findsOneWidget);
    expect(find.textContaining('Gửi 3 gói ping tới 192.168.4.1:4210'), findsOneWidget);

    await tab('Kênh');
    await tester.tap(find.byType(ChannelTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ChannelDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'chi tiết kênh khi nằm ngang');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Xoay dọc: thanh nút dưới trở lại
    setSize(tester, const Size(420, 900));
    await tester.pumpAndSettle();
    expect(find.text('Đồng bộ failsafe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nằm ngang: sửa luật mix và sửa Input không tràn', (tester) async {
    setSize(tester, const Size(800, 360));
    final p = sample();
    await tester.pumpWidget(app(MixRuleScreen(rule: p.mixer.firstWhere((r) => r.id == 'r_hi').copy(), profile: p)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'sửa luật mix');
    for (final ty in InputType.values) {
      await tester.pumpWidget(app(InputScreen(input: InputDef(id: 'x', name: 'X', type: ty), takenIds: const {}, idLocked: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'sửa Input ${ty.name}');
    }
  });

  testWidgets('Màn Lái: bố cục khoá thì ẩn nút Sửa; mở khoá thì nút Sửa hiện ở góc phải', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    expect(p.activeLayout.locked, isTrue);
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(ControlScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    final edit = find.widgetWithText(TextButton, 'Sửa');
    expect(edit, findsNothing, reason: 'bố cục đang khoá');
    expect(find.byTooltip('Sửa bố cục'), findsNothing);
    expect(tester.getTopRight(find.byTooltip('Tuỳ chọn')).dx, greaterThan(900 - 48));

    await tester.tap(find.byTooltip('Tuỳ chọn'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa bố cục'), findsNothing, reason: 'menu ⚙ không còn mục Sửa bố cục');
    await tester.tap(find.text('Mở khoá bố cục'));
    await settleIo(tester);
    // Nút Sửa nằm ngay trước menu ⚙, sát mép phải
    final editRight = tester.getTopRight(edit).dx, menuLeft = tester.getTopLeft(find.byTooltip('Tuỳ chọn')).dx;
    expect(menuLeft - editRight, lessThan(16));
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Sửa bố cục · kéo để di chuyển · nhấn đúp để cấu hình'), findsOneWidget);
  });

  testWidgets('Xe của tôi: bấm vào thẻ xe đang nối là vào thẳng màn Lái', (tester) async {
    setSize(tester, const Size(900, 420)); // màn Lái luôn nằm ngang
    mockWakelock();
    final p = sample();
    final repo = await repoWith(tester, p);
    final c = CarController();
    await tester.runAsync(() => c.connect(FakeCarTransport(), key: p.connKey));
    await tester.pumpWidget(app(GarageScreen(controller: c, repo: repo, theme: ThemeController())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xe thử'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlScreen), findsOneWidget);
    await tester.runAsync(c.disconnect);
  });

  testWidgets('Xe của tôi: hai hồ sơ cùng IP/port (chế độ AP) thì chỉ hồ sơ đã nối hiện Đã kết nối', (tester) async {
    setSize(tester, const Size(420, 900));
    mockWakelock();
    final p = sample();
    final q = CarProfile(id: 'p2', name: 'Xe hai', connType: ConnType.wifi, wifi: WifiConn());
    expect((p.wifi!.ip, p.wifi!.port), (q.wifi!.ip, q.wifi!.port));
    expect(p.connKey, isNot(q.connKey));
    final repo = await repoWith(tester, p);
    await tester.runAsync(() => repo.save(q));
    final c = CarController();
    await tester.runAsync(() => c.connect(FakeCarTransport(), key: p.connKey));
    await tester.pumpWidget(app(GarageScreen(controller: c, repo: repo, theme: ThemeController())));
    await tester.pumpAndSettle();
    expect(find.text('Đã kết nối'), findsOneWidget);
    await tester.runAsync(c.disconnect);
  });

  testWidgets('Xe của tôi: xe đang chọn nằm đầu, có nhãn Đang chọn; xe khác có nút Chọn xe', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = sample();
    final repo = await repoWith(tester, p);
    await tester.runAsync(() async {
      await repo.save(CarProfile(id: 'p2', name: 'Xe hai', connType: ConnType.wifi, wifi: WifiConn()));
      await repo.select('p1');
    });
    await tester.pumpWidget(app(GarageScreen(controller: CarController(), repo: repo, theme: ThemeController())));
    await tester.pumpAndSettle();
    expect(find.text('Đang chọn'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Xe thử')).dy, lessThan(tester.getTopLeft(find.text('Xe hai')).dy));
    expect(find.text('Kết nối'), findsOneWidget);
    expect(find.text('Chọn xe'), findsOneWidget);
    await tester.runAsync(() => repo.select('p2'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Xe hai')).dy, lessThan(tester.getTopLeft(find.text('Xe thử')).dy));
  });

  testWidgets('Sửa luật mix: điều kiện, curve, xem trước chạy khoá an toàn', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = sample();
    final rule = p.mixer.firstWhere((r) => r.id == 'r_x8').copy();
    MixRule? result;
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => result = await Navigator.push<MixRule>(
              context,
              MaterialPageRoute(builder: (_) => MixRuleScreen(rule: rule, profile: p)),
            ),
            child: const Text('mở'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Luật mix'), findsOneWidget);
    expect(find.text('Nút A'), findsWidgets);
    // Đổi đường cong sang 5 điểm, rồi xuống xem trước
    await tester.tap(find.text('5 điểm'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('XEM TRƯỚC'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('CH8'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    expect(result?.curve.type, CurveType.points);
  });

  testWidgets('Trình sửa luật hiện được điều kiện lồng AND + NOT', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = sample();
    final rule = p.mixer.firstWhere((r) => r.id == 'r_hi').copy();
    await tester.pumpWidget(app(MixRuleScreen(rule: rule, profile: p)));
    await tester.pumpAndSettle();
    expect(find.text('Tất cả (AND)'), findsOneWidget);
    expect(find.text('Phủ định (KHÔNG)'), findsNWidgets(2));
    expect(find.text('Trễ (hysteresis)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sửa Input: 4 kiểu dựng được, mã trùng thì báo lỗi', (tester) async {
    setSize(tester, const Size(420, 900));
    for (final ty in InputType.values) {
      await tester.pumpWidget(app(InputScreen(
        input: InputDef(id: 'x', name: 'X', type: ty),
        takenIds: const {'x'},
        idLocked: false,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã có Input khác mã'), findsOneWidget, reason: ty.name);
      expect(tester.takeException(), isNull, reason: ty.name);
    }
  });

  testWidgets('Bảng thuộc tính: gắn Input, gắn nhanh tới kênh, Input có luật riêng', (tester) async {
    setSize(tester, const Size(420, 1400));
    final p = sample();
    final l = p.activeLayout;
    Future<void> show(ControlItem it) async {
      await tester.pumpWidget(app(Scaffold(
        body: PropertiesPanel(
          item: it,
          profile: p,
          layout: l,
          beforeChange: () {},
          changed: () {},
          onDelete: () {},
          onClose: () {},
          onMessage: (_) {},
          onOpenMix: () {},
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await show(l.itemForInput('horn')!);
    expect(find.text('Gửi tới kênh'), findsOneWidget);
    await show(l.itemForInput('slider_x')!);
    expect(find.text('Dùng tab Mix'), findsOneWidget);
    await show(ControlItem(id: 'free', kind: ItemKind.stick2D, x: 0, y: 0, w: 12, h: 12));
    expect(find.text('Input trục Y'), findsOneWidget);
  });

  testWidgets('Màn Lái: dựng bố cục, ARM chưa sẵn sàng khi chưa kết nối, có ô kênh đầu ra', (tester) async {
    setSize(tester, const Size(900, 420));
    final repo = await repoWith(tester, sample());
    final c = CarController();
    await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Chưa kết nối'), findsWidgets); // nút ARM + huy hiệu trạng thái
    expect(find.text('KÊNH ĐẦU RA'), findsOneWidget);
    expect(c.pipeline, isNotNull);
    expect(tester.takeException(), isNull);
    // Chưa kết nối: vòng gửi không chạy, nhưng đổi Input vẫn vào mixer
    c.setSwitch('btn_a', 1);
    c.setPosition('slider_x', 60);
    expect(c.pipeline!.mixed()[0], 60);
    await tester.pumpWidget(const SizedBox());
    expect(c.pipeline, isNull); // rời màn Lái: bỏ hồ sơ khỏi vòng gửi
  });

  testWidgets('Màn Lái: đèn LED, thanh giá trị, vector 2D và ô đồng hồ đọc theo nguồn đã chọn', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    final l = p.activeLayout;
    l.items.removeWhere((i) => i.id == 'mon');
    final led = LayoutTemplates.addWidget(l, ItemKind.led, source: 'in:btn_a')!;
    LayoutTemplates.addWidget(l, ItemKind.bar, source: 'in:slider_x')!;
    LayoutTemplates.addWidget(l, ItemKind.vector, source: 'in:slider_x', sourceY: 'in:btn_a')!;
    LayoutTemplates.addWidget(l, ItemKind.gauge, source: 'in:slider_x')!;
    expect(led.source, 'in:btn_a');
    final repo = await repoWith(tester, p);
    final c = CarController();
    await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LedLamp), findsOneWidget);
    expect(find.byType(ValueBar), findsOneWidget);
    expect(find.byType(VectorPad), findsOneWidget);
    expect(tester.widget<LedLamp>(find.byType(LedLamp)).on, isFalse); // nút A tắt = −100% < ngưỡng 0

    c.setSwitch('btn_a', 1);
    c.setPosition('slider_x', 60);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<LedLamp>(find.byType(LedLamp)).on, isTrue);
    expect(tester.widget<ValueBar>(find.byType(ValueBar)).value, 60);
    final pad = tester.widget<VectorPad>(find.byType(VectorPad));
    expect(pad.x, closeTo(0.6, 1e-9));
    expect(pad.y, closeTo(1.0, 1e-9));
    expect(find.text('60% · 100%'), findsOneWidget); // số của vector
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1)); // vệt vector mờ hết
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sửa bố cục: thêm Vector 2D từ mục Hiển thị, có ô chọn nguồn X/Y; kéo tay nắm cạnh phải đổi bề ngang, hiện kích thước', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    p.activeLayout.locked = false;
    final repo = await repoWith(tester, p);
    final c = CarController();
    await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Sửa bố cục'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thêm'));
    await tester.pumpAndSettle();
    final sheet = find.byType(Scrollable).last;
    for (final k in ['Hiển thị', 'Ô đồng hồ', 'Đèn LED', 'Thanh giá trị', 'Vector 2D']) {
      await tester.scrollUntilVisible(find.text(k), 120, scrollable: sheet);
      expect(find.text(k), findsOneWidget, reason: k);
    }
    await tester.tap(find.text('Vector 2D'));
    await tester.pumpAndSettle();
    // Bảng thuộc tính mở ngay: hai ô chọn nguồn X / Y, mặc định Lái / Ga
    expect(find.text('Trục X'), findsOneWidget);
    expect(find.text('Trục Y'), findsOneWidget);
    expect(find.text('Vệt chuyển động'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Kéo tay nắm cạnh phải vào trong: vector 8×8 hẹp lại (lưới dày: vài ô), cao giữ 8, nhãn kích thước hiện khi đang kéo
    final pad = tester.getRect(find.byType(VectorPad));
    final handle = find.byKey(const ValueKey('handle-r'));
    expect(handle, findsOneWidget);
    expect(find.byKey(const ValueKey('handle-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('handle-tl')), findsOneWidget);
    final cw = tester.getRect(find.byType(LayoutCanvas)).width / 48;
    final g = await tester.startGesture(tester.getCenter(handle));
    await g.moveBy(const Offset(-40, 0)); // vượt ngưỡng kéo
    await g.moveBy(Offset(-cw, 0));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^[1-7] × 8$')), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.textContaining(' × 8'), findsNothing);
    final after = tester.getRect(find.byType(VectorPad));
    expect(after.left, closeTo(pad.left, 0.5)); // cạnh trái đứng yên
    expect(after.height, closeTo(pad.height, 0.5)); // kéo cạnh không đổi chiều cao
    expect(after.width, lessThan(pad.width));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sửa bố cục: chạm một lần chỉ chọn (có tay nắm), chạm hai lần mới mở bảng thuộc tính', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    p.activeLayout.locked = false;
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(ControlScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Sửa bố cục'));
    await tester.pumpAndSettle();
    expect(find.byType(PropertiesPanel), findsNothing);

    final knob = find.byType(Knob);
    await tester.tap(knob);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('handle-r')), findsOneWidget, reason: 'đã chọn: có tay nắm đổi cỡ');
    expect(find.byType(PropertiesPanel), findsNothing, reason: 'chạm một lần chưa mở cấu hình');

    await tester.tap(knob);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(knob);
    await tester.pumpAndSettle();
    expect(find.byType(PropertiesPanel), findsOneWidget);

    // Chọn phần tử khác thì bảng cũ đóng; bấm nền trống bỏ chọn
    await tester.tap(find.byType(ChannelButton).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PropertiesPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Màn Lái: bấm giữa ô Trim mở bảng trim các kênh đang bật, trim riêng từng kênh', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(ControlScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Trim từng kênh'), findsNothing);

    await tester.tap(find.text('Trim 0 µs'));
    await tester.pumpAndSettle();
    expect(find.text('Trim từng kênh'), findsOneWidget);
    for (final ch in p.channels) {
      expect(find.byKey(ValueKey('trim-ch${ch.index}')), ch.enabled ? findsOneWidget : findsNothing,
          reason: 'CH${ch.index} ${ch.enabled ? 'đang bật' : 'đang tắt'}');
    }
    expect(p.channels.any((c) => !c.enabled), isTrue, reason: 'mẫu phải có kênh tắt để kiểm tra');

    Finder arrow(int ch, String a) =>
        find.descendant(of: find.byKey(ValueKey('trim-ch$ch')), matching: find.text(a));
    await tester.tap(arrow(7, '▶'));
    await tester.tap(arrow(7, '▶'));
    await tester.tap(arrow(8, '◀'));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('trim-ch7')), matching: find.text('+10 µs')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('trim-ch8')), matching: find.text('-5 µs')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await settleIo(tester, until: () => repo.get('p1')!.ch(7).trimUs == 10);
    expect(repo.get('p1')!.ch(7).trimUs, 10);
    expect(repo.get('p1')!.ch(8).trimUs, -5);
    expect(repo.get('p1')!.ch(1).trimUs, 0, reason: 'kênh khác không đổi');

    // Bấm số µs về 0, nút đóng ẩn bảng
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('trim-ch7')), matching: find.text('+10 µs')));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('trim-ch7')), matching: find.text('0 µs')), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Trim từng kênh'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await settleIo(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Nút Ngắt: tắt cơ chế ARM thì ngắt được cả khi đang lái; bật ARM thì phải DISARM trước', (tester) async {
    setSize(tester, const Size(900, 420));
    mockWakelock();
    for (final armOn in [false, true]) {
      final p = sample()..arm.enabled = armOn;
      final repo = await repoWith(tester, p);
      final c = CarController();
      await tester.runAsync(() => c.connect(FakeCarTransport(), key: p.connKey));
      await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
      await tester.pump(const Duration(milliseconds: 100));
      c.arm.onFailsafeSync(true);
      expect(c.arm.arm(const ArmCheck()), isNull);
      await tester.pump();
      expect(c.arm.armed, isTrue);
      final disconnect = find.ancestor(of: find.text('Ngắt'), matching: find.byWidgetPredicate((w) => w is OutlinedButton));
      expect(tester.widget<OutlinedButton>(disconnect).onPressed, armOn ? isNull : isNotNull, reason: 'ARM ${armOn ? 'bật' : 'tắt'}');
      if (!armOn) {
        await tester.runAsync(() async {
          tester.widget<OutlinedButton>(disconnect).onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(c.state, LinkState.disconnected);
        expect(find.text('Kết nối'), findsOneWidget);
      } else {
        c.arm.disarm();
        await tester.runAsync(c.disconnect);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Cấu hình ▸ Chung: không còn hộp số; tắt "Dùng cơ chế ARM" thì ẩn Tự ARM và điều kiện ARM riêng', (tester) async {
    setSize(tester, const Size(420, 2400));
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(SettingsScreen(
      controller: CarController(),
      repo: repo,
      profileId: 'p1',
      initialTab: SettingsScreen.generalTab,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Số lượng số'), findsNothing);
    expect(find.textContaining('Ga tối đa số'), findsNothing);
    expect(find.text('Tự ARM sau khi kết nối'), findsOneWidget);
    await tester.tap(find.text('Dùng cơ chế ARM'));
    await tester.pumpAndSettle();
    expect(find.text('Tự ARM sau khi kết nối'), findsNothing);
    expect(find.text('Điều kiện ARM riêng'), findsNothing);
    expect(find.textContaining('không có nút ARM'), findsOneWidget);
    await tester.tap(find.text('Lưu'));
    await settleIo(tester); // Lưu ghi file thật
    expect(repo.get('p1')!.arm.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Màn Lái tắt ARM: không có nút "Giữ để ARM", không hiện ô trạng thái lái; thêm phần tử không còn Hộp số', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample()..arm.enabled = false;
    p.activeLayout.locked = false;
    final repo = await repoWith(tester, p);
    final c = CarController();
    await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Giữ để ARM'), findsNothing);
    expect(find.text('Chưa sẵn sàng (Chưa kết nối)'), findsNothing);
    c.arm
      ..onConnected()
      ..onFailsafeSync(true);
    c.arm.tick(c.currentArmCheck()!); // chưa kết nối thật: coi như mất tín hiệu
    await tester.pump();
    expect(c.arm.armed, isFalse);
    expect(c.arm.arm(const ArmCheck()), isNull);
    await tester.pump();
    expect(find.text('Đang lái'), findsNothing);
    c.arm.disarm();

    await tester.tap(find.byTooltip('Sửa bố cục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Cần gạt ngang'), findsOneWidget);
    expect(find.text('Hộp số'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Màn Lái: nhấn giữ cần có luật mix xem luật, trạng thái tự cập nhật; đang ARM thì không bật bảng', (tester) async {
    setSize(tester, const Size(900, 420));
    final repo = await repoWith(tester, sample());
    final c = CarController();
    await tester.pumpWidget(app(ControlScreen(controller: c, repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    final rulesHold = find.byWidgetPredicate((w) => w is GestureDetector && w.onLongPress != null);
    final steer = find.descendant(of: rulesHold, matching: find.byType(StickAxis)); // cần Lái: có luật r_hi theo Lái ≥ 80
    final steerAt = tester.getCenter(steer);

    // DISARM: nhấn giữ Lái → bảng luật
    await tester.longPress(steer);
    await tester.pump(const Duration(milliseconds: 500)); // cần tự về giữa xong
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Luôn áp dụng'), findsOneWidget); // Lái → CH1 không điều kiện: không phải "đang lái"
    expect(find.text('Điều kiện chưa đúng'), findsOneWidget);
    // Lái ≥ 80 rồi thả: bảng đang mở đổi theo mixer, không cần mở lại
    c.setPosition('steer', 90);
    c.pipeline!.mixed();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Điều kiện đúng · đang tác động'), findsOneWidget);
    c.setPosition('steer', 0);
    c.pipeline!.mixed();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Điều kiện chưa đúng'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // bảng có Timer nên không pumpAndSettle được
    expect(find.byType(AlertDialog), findsNothing);

    // ARMED = đang lái: giữ yên cần không được bật bảng che màn Lái
    c.arm
      ..onConnected()
      ..onFailsafeSync(true);
    expect(c.arm.arm(const ArmCheck()), isNull);
    await tester.pump();
    expect(rulesHold, findsNothing);
    await tester.longPressAt(steerAt);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    c.arm.disarm();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Màn Lái: phần tử có màu riêng dựng bằng màu đó, phần tử khác theo màu app; giữ Trim đổi liên tục, lưu một lần', (tester) async {
    setSize(tester, const Size(900, 420));
    final p = sample();
    p.activeLayout.itemForInput('slider_x')!.style.color = AccentColor.red;
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(ControlScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    await tester.pump(const Duration(milliseconds: 100));
    AppTokens tokensOf(Finder f) => Theme.of(tester.element(f)).extension<AppTokens>()!;
    expect(tokensOf(find.byType(Knob)).accentFill, AccentColor.red.fill);
    expect(tokensOf(find.byType(StickAxis).first).accentFill, AppTokens.dark.accentFill);

    // Trim: nhấn giữ ▶ → trim tăng liên tục; hồ sơ chỉ ghi khi ngừng bấm
    expect(p.steering!.trimUs, 0);
    final g = await tester.startGesture(tester.getCenter(find.text('▶')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up();
    await tester.pump();
    final trimText = find.textContaining(RegExp(r'^Trim \d+ µs$'));
    final shown = RegExp(r'Trim (\d+) µs').firstMatch(tester.widget<Text>(trimText).data!)!;
    final trim = int.parse(shown.group(1)!);
    expect(trim, greaterThanOrEqualTo(25), reason: 'giữ ~1 s phải lặp nhiều lần');
    expect(repo.get('p1')!.steering!.trimUs, 0, reason: 'chưa ghi khi vừa thả tay');
    await tester.pump(const Duration(milliseconds: 300)); // hết thời gian gom
    await settleIo(tester, until: () => repo.get('p1')!.steering!.trimUs == trim);
    expect(repo.get('p1')!.steering!.trimUs, trim);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Bảng thuộc tính: chọn màu riêng cho phần tử, chọn lại "Theo màu app" thì bỏ màu riêng', (tester) async {
    setSize(tester, const Size(360, 1400));
    final p = sample();
    final l = p.activeLayout;
    final it = l.itemForInput('horn')!;
    await tester.pumpWidget(app(Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => PropertiesPanel(
          item: it,
          profile: p,
          layout: l,
          beforeChange: () {},
          changed: () => setState(() {}),
          onDelete: () {},
          onClose: () {},
          onMessage: (_) {},
          onOpenMix: () {},
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Theo màu chủ đạo của app'), findsOneWidget);
    await tester.tap(find.byTooltip('Đỏ'));
    await tester.pumpAndSettle();
    expect(it.style.color, AccentColor.red);
    expect(find.text('Đỏ'), findsOneWidget);
    await tester.tap(find.byTooltip('Theo màu app'));
    await tester.pumpAndSettle();
    expect(it.style.color, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bảng thuộc tính: LED theo pin có ngưỡng mặc định, nhập ngưỡng riêng; thanh có khoảng Min/Max', (tester) async {
    setSize(tester, const Size(360, 1600));
    final p = sample();
    final l = p.activeLayout;
    final led = LayoutTemplates.addWidget(l, ItemKind.led, source: DataSource.battery)!;
    final bar = LayoutTemplates.addWidget(l, ItemKind.bar, source: 'ch:1')!;
    var item = led;
    late StateSetter rebuild;
    await tester.pumpWidget(app(Scaffold(
      body: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return PropertiesPanel(
          key: ValueKey(item.id),
          item: item,
          profile: p,
          layout: l,
          beforeChange: () {},
          changed: () => setState(() {}),
          onDelete: () {},
          onClose: () {},
          onMessage: (_) {},
          onOpenMix: () {},
        );
      }),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Pin (V)'), findsOneWidget); // nguồn đang chọn
    expect(find.text('Mặc định 7'), findsOneWidget); // pin yếu < 7 V
    final below = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(below.selected, {true});
    await tester.enterText(find.widgetWithText(TextFormField, 'Ngưỡng'), '6,8');
    expect(led.display.threshold, 6.8);
    await tester.tap(find.text('Nháy nhanh'));
    await tester.pumpAndSettle();
    expect(led.display.blink, LedBlink.fast);
    expect(tester.takeException(), isNull);

    rebuild(() => item = bar);
    await tester.pumpAndSettle();
    expect(find.text('Khoảng thanh'.toUpperCase()), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Min'), '50');
    await tester.enterText(find.widgetWithText(TextFormField, 'Max'), '20');
    await tester.pump();
    expect(find.text('Min phải nhỏ hơn Max'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Max'), '');
    await tester.pump();
    expect((bar.display.min, bar.display.max), (50, null)); // để trống = theo nguồn (100%)
    expect(find.text('Min phải nhỏ hơn Max'), findsNothing);
    expect(find.text('Kênh hiện theo'.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mở app có hồ sơ Sprint 3: hiện báo cáo chuyển đổi một lần', (tester) async {
    final dir = Directory.systemTemp.createTempSync('rc_mig_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/fixture-s3.json').writeAsStringSync(File('test/fixtures/sprint3_profile.json').readAsStringSync());
    final repo = ProfileRepository(dir);
    await tester.runAsync(repo.load);
    await tester.pumpWidget(RcApp(controller: CarController(), repo: repo, theme: ThemeController(), autoConnect: false));
    await tester.pumpAndSettle();
    expect(find.text('Đã cập nhật hồ sơ xe'), findsOneWidget);
    expect(find.text('Không có thay đổi hành vi.'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await tester.pumpAndSettle();
    expect(repo.migrationReports, isEmpty);
  });
}
