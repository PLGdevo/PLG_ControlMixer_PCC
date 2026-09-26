// Widget test các màn Sprint 4: màn chính (ảnh xe), Cấu hình (5 tab, Bố cục mở Sửa bố cục), sửa luật mix, sửa Input,
// bảng thuộc tính, màn Lái, báo cáo chuyển hồ sơ. Dựng thật để bắt lỗi runtime (dropdown sai giá trị, tràn layout...).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/layout/item_widgets.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/layout/properties_panel.dart';
import 'package:rc_controller/main.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/screens/control_screen.dart';
import 'package:rc_controller/screens/garage_screen.dart';
import 'package:rc_controller/screens/input_screen.dart';
import 'package:rc_controller/screens/mix_rule_screen.dart';
import 'package:rc_controller/screens/settings_screen.dart';
import 'package:rc_controller/theme/app_theme.dart';
import 'package:rc_controller/theme/theme_controller.dart';
import 'package:rc_controller/theme/tokens.dart';
import 'package:rc_controller/widgets/layout_preview.dart';

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
    expect(find.text('Sửa bố cục · kéo để di chuyển'), findsOneWidget);
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
    expect(find.text('Sửa bố cục · kéo để di chuyển'), findsOneWidget);
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
    expect(find.text('Sửa bố cục · kéo để di chuyển'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlScreen), findsOneWidget, reason: 'mở từ màn Lái thì Huỷ ở lại màn Lái');
    expect(find.byTooltip('Tuỳ chọn'), findsOneWidget);
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
