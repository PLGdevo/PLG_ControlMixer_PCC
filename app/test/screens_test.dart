// Widget test các màn Sprint 4: Cấu hình (6 tab), sửa luật mix, sửa Input, bảng thuộc tính,
// màn Lái, báo cáo chuyển hồ sơ. Dựng thật để bắt lỗi runtime (dropdown sai giá trị, tràn layout...).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/layout/properties_panel.dart';
import 'package:rc_controller/main.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/screens/control_screen.dart';
import 'package:rc_controller/screens/input_screen.dart';
import 'package:rc_controller/screens/mix_rule_screen.dart';
import 'package:rc_controller/screens/settings_screen.dart';
import 'package:rc_controller/theme/app_theme.dart';
import 'package:rc_controller/theme/theme_controller.dart';

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
  l.items.add(ControlItem(id: 'mon', kind: ItemKind.gauge, gaugeKey: GaugeKey.channels.name, x: 14, y: 0, w: 8, h: 3));
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Cấu hình: chọn kênh Ga khác, bỏ kênh Lái, vẫn lưu được', (tester) async {
    setSize(tester, const Size(420, 900));
    final repo = await repoWith(tester, sample());
    await tester.pumpWidget(app(SettingsScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    Future<void> pick(String item) async {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await pick('CH5');
    expect(find.text('Chưa có luật mix nào điều khiển kênh Ga (CH5)'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Lái'));
    await tester.pumpAndSettle();
    await pick('Không có');
    expect(find.text('Min'), findsNothing);
    final save = find.ancestor(of: find.text('Lưu'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    for (var i = 0; i < 10; i++) {
      // Lưu ghi file thật: cho vòng lặp thật chạy vài nhịp
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu vào máy'), findsOneWidget);
    final p = repo.get('p1')!;
    expect([p.throttleCh, p.steeringCh], [5, null]);
    expect(p.ch(5).enabled, isTrue);
    expect(p.ch(5).name, 'Ga');
  });

  testWidgets('Cấu hình: dựng đủ 6 tab, hồ sơ mẫu hợp lệ', (tester) async {
    setSize(tester, const Size(420, 900));
    final p = sample();
    expect(p.validateAll(), isEmpty);
    final repo = await repoWith(tester, p);
    await tester.pumpWidget(app(SettingsScreen(controller: CarController(), repo: repo, profileId: 'p1')));
    for (final tab in ['Ga', 'Lái', 'Input', 'Mix', 'Kênh', 'Chung']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.tap(find.widgetWithText(Tab, 'Input'));
    await tester.pumpAndSettle();
    expect(find.text('Slider X'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Mix'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CH1 · LÁI'), findsOneWidget); // nhóm theo kênh đích
    setSize(tester, const Size(420, 2400)); // đủ cao để dựng hết danh sách luật
    await tester.pumpAndSettle();
    expect(find.textContaining('Slider X → CH8'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Chung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điều kiện ARM riêng'));
    await tester.pumpAndSettle();
    expect(find.text('Luôn đúng — luật luôn chạy.'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await show(ControlItem(id: 'free', kind: ItemKind.stick2D, x: 0, y: 0, w: 6, h: 6));
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

  testWidgets('Mở app có hồ sơ Sprint 3: hiện báo cáo chuyển đổi một lần', (tester) async {
    final dir = Directory.systemTemp.createTempSync('rc_mig_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/fixture-s3.json').writeAsStringSync(File('test/fixtures/sprint3_profile.json').readAsStringSync());
    final repo = ProfileRepository(dir);
    await tester.runAsync(repo.load);
    await tester.pumpWidget(RcApp(controller: CarController(), repo: repo, theme: ThemeController()));
    await tester.pumpAndSettle();
    expect(find.text('Đã cập nhật hồ sơ xe'), findsOneWidget);
    expect(find.text('Không có thay đổi hành vi.'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await tester.pumpAndSettle();
    expect(repo.migrationReports, isEmpty);
  });
}
