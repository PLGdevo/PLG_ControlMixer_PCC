import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/layout/layout_grid.dart';
import 'package:rc_controller/layout/layout_history.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/layout/return_motion.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/data_source.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/theme/tokens.dart';

void main() {
  test('Cần 2 trục dùng 1/2 trục, thanh trim theo kênh, bảng kênh chọn kênh: lưu và đọc lại', () {
    ControlItem mk(ItemKind k) => ControlItem(id: 'a', kind: k, x: 0, y: 0, w: 4, h: 4);
    final stick = mk(ItemKind.stick2D)..axes = StickAxes.y;
    expect(ControlItem.fromJson(stick.toJson()).axes, StickAxes.y);
    expect(ControlItem.fromJson(mk(ItemKind.stick2D).toJson()).axes, StickAxes.both);
    expect(StickAxes.x.hasY || StickAxes.y.hasX, isFalse);
    // Bố cục cũ chưa có khoá kiểu vẽ: cần 2 trục vẽ kiểu tay RC
    expect(ItemStyle.fromJson({}).gimbal, isTrue);
    expect(ItemStyle.fromJson((ItemStyle()..gimbal = false).toJson()).gimbal, isFalse);

    final trim = mk(ItemKind.trimBar)..trimCh = 3;
    expect(ControlItem.fromJson(trim.toJson()).trimCh, 3);
    expect(ControlItem.fromJson(trim.toJson()).touchable, isTrue);

    final mon = mk(ItemKind.channels)..chList = [1, 2, 5];
    expect(ControlItem.fromJson(mon.toJson()).chList, [1, 2, 5]);
    expect(ControlItem.fromJson(mk(ItemKind.channels).toJson()).chList, isNull); // null = mọi kênh đang bật
    expect(ItemKind.channels.isControl || ItemKind.trimBar.isControl, isFalse);
  });

  test('Màu riêng của phần tử: lưu theo tên màu, không có / tên lạ thì theo màu app', () {
    final st = ItemStyle(color: AccentColor.red);
    expect(st.toJson()['color'], 'red');
    expect(ItemStyle.fromJson(st.toJson()).color, AccentColor.red);
    expect(ItemStyle().toJson().containsKey('color'), isFalse);
    expect(ItemStyle.fromJson({'color': 'rainbow'}).color, isNull);
    expect(ItemStyle.fromJson(null).color, isNull);
  });

  group('Lưới bố cục (H2)', () {
    test('bố cục mặc định hợp lệ, có Ga và Lái', () {
      final l = LayoutTemplates.standard();
      expect(LayoutGrid.validate(l, throttleInputs: {'throttle'}, steerInputs: {'steer'}), isNull);
      expect(l.itemForInput('steer')?.kind, ItemKind.stickH);
      expect(l.itemForInput('throttle')?.kind, ItemKind.stickV);
    });

    test('bám lưới', () {
      expect(LayoutGrid.snap(49, 33.3), 1);
      expect(LayoutGrid.snap(51, 33.3), 2);
      expect(LayoutGrid.snap(-20, 33.3), -1);
    });

    test('chống chồng lấn và giữ trong lưới', () {
      final l = LayoutTemplates.standard();
      final stick = l.itemForInput('throttle')!; // 0,1 4x11
      expect(LayoutGrid.fits(l, 'new', const GridRect(1, 2, 2, 2)), isFalse);
      expect(LayoutGrid.fits(l, stick.id, GridRect.of(stick)), isTrue);
      expect(LayoutGrid.fits(l, 'new', const GridRect(22, 11, 3, 2)), isFalse); // tràn lưới
    });

    test('không giới hạn cỡ lớn nhất, chỉ kẹp trong lưới và cỡ nhỏ nhất', () {
      final lim = SizeLimits.of(ItemKind.stick2D);
      expect(LayoutGrid.clampSize(const GridRect(0, 0, 1, 20), lim, 48, 24), const GridRect(0, 0, 2, 20));
      expect(LayoutGrid.clampSize(const GridRect(40, 0, 60, 30), lim, 48, 24), const GridRect(0, 0, 48, 24));
      expect(LayoutGrid.clampSize(const GridRect(47, 0, 3, 2), lim, 48, 24), const GridRect(45, 0, 3, 2));
    });

    test('kéo to đụng phần tử khác thì dừng sát phần tử đó', () {
      final l = ControlLayout(id: 'l', name: 'l', items: [
        ControlItem(id: 'a', kind: ItemKind.button, x: 0, y: 0, w: 4, h: 4),
        ControlItem(id: 'b', kind: ItemKind.button, x: 10, y: 0, w: 4, h: 4),
      ]);
      // Kéo cạnh phải của a tới cột 20: dừng ở cột 10 (sát b)
      final r = LayoutGrid.largestFree(l, 'a', const GridRect(0, 0, 4, 4), const GridRect(0, 0, 20, 4), 1, 0);
      expect(r, const GridRect(0, 0, 10, 4));
      // Kéo góc dưới phải: được cao hết lưới, bề ngang vẫn dừng sát b
      final r2 = LayoutGrid.largestFree(l, 'a', const GridRect(0, 0, 4, 4), const GridRect(0, 0, 20, 24), 1, 1);
      expect(r2, const GridRect(0, 0, 10, 24));
    });

    test('bố cục lưới thưa cũ 24×12 được nhân lên lưới dày, giữ nguyên hình', () {
      final old = {
        'id': 'l', 'name': 'l', 'cols': 24, 'rows': 12,
        'items': [ControlItem(id: 'a', kind: ItemKind.stickV, x: 1, y: 2, w: 3, h: 8).toJson()],
      };
      final l = ControlLayout.fromJson(old);
      expect((l.cols, l.rows), (48, 24));
      expect(GridRect.of(l.items.first), const GridRect(2, 4, 6, 16));
      // Đã là lưới dày thì giữ nguyên
      expect(GridRect.of(ControlLayout.fromJson(l.toJson()).items.first), const GridRect(2, 4, 6, 16));
    });

    test('vùng chạm ≥ 48 dp nâng kích thước nhỏ nhất', () {
      final lim = SizeLimits.of(ItemKind.button).forCell(20, 20);
      expect(lim.minW, 3);
      expect(lim.minH, 3);
    });

    test('thiếu phần tử cho Input điều khiển Ga thì không cho lưu', () {
      final l = LayoutTemplates.standard();
      l.items.removeWhere((i) => i.inputId == 'throttle');
      expect(LayoutGrid.validate(l, throttleInputs: {'throttle'}, steerInputs: {'steer'}), contains('Ga'));
      // Ga có hai nguồn: chỉ cần một trong hai có mặt
      final k = LayoutTemplates.addControl(l, ItemKind.knob, inputId: 'thr2')!;
      expect(LayoutGrid.validate(l, throttleInputs: {'throttle', 'thr2'}, steerInputs: {'steer'}), isNull);
      expect(k.inputId, 'thr2');
    });

    test('một Input chỉ có một phần tử (I3): gắn sang phần tử khác thì chuyển', () {
      final l = LayoutTemplates.standard();
      final a = LayoutTemplates.addControl(l, ItemKind.toggle, inputId: 'light')!;
      final b = LayoutTemplates.addControl(l, ItemKind.button)!;
      expect(b.inputId, isNull);
      expect(l.bindInput(b, 'light')?.id, a.id);
      expect(a.inputId, isNull);
      expect(l.itemForInput('light')?.id, b.id);
      l.renameInput('light', 'lamp');
      expect(b.inputId, 'lamp');
      l.unbindInput('lamp');
      expect(l.itemForInput('lamp'), isNull);
    });

    test('một Input trên hai phần tử thì không cho lưu', () {
      final l = LayoutTemplates.standard();
      l.items.add(ControlItem(id: 'dup', kind: ItemKind.knob, inputId: 'steer', x: 36, y: 0, w: 6, h: 6));
      expect(LayoutGrid.validate(l), contains('nhiều hơn một phần tử'));
    });

    test('thêm nhiều cần gạt cùng loại, cấu hình riêng từng cái', () {
      final l = LayoutTemplates.standard();
      final s1 = LayoutTemplates.addControl(l, ItemKind.stickH, inputId: 'aux')!;
      final s2 = LayoutTemplates.addControl(l, ItemKind.stickH)!;
      s1.returnCfg!.mode = ReturnMode.hold;
      expect(l.items.where((i) => i.kind == ItemKind.stickH).length, 3);
      expect(s2.returnCfg!.mode, ReturnMode.spring);
      expect(s2.inputId, isNull);
      expect(LayoutGrid.validate(l), isNull);
    });

    test('đường gióng', () {
      final l = ControlLayout(id: 'l', name: 'l', items: [
        ControlItem(id: 'a', kind: ItemKind.button, x: 4, y: 0, w: 2, h: 2),
      ]);
      final g = LayoutGrid.guides(l, 'b', const GridRect(4, 5, 3, 2));
      expect(g.xs, contains(4));
    });

    test('hoàn tác / làm lại tối đa 30 bước', () {
      final h = LayoutHistory();
      var l = ControlLayout(id: 'l', name: 'l');
      for (var i = 0; i < 35; i++) {
        h.push(l);
        l = l.copy()..name = 'v$i';
      }
      var n = 0;
      while (h.canUndo) {
        l = h.undo(l)!;
        n++;
      }
      expect(n, 30);
      expect(h.canRedo, isTrue);
      l = h.redo(l)!;
      expect(l.name, isNot('l'));
    });
  });

  group('Tự về (H3b)', () {
    test('về 0% ngay', () {
      expect(ReturnMotion.valueAt(ReturnConfig(), 80, 0), 0);
    });

    test('trễ và thời gian về đúng mili-giây', () {
      final c = ReturnConfig(delayMs: 100, durationMs: 300);
      expect(ReturnMotion.valueAt(c, 90, 50), 90);
      expect(ReturnMotion.valueAt(c, 90, 250), closeTo(45, 0.001));
      expect(ReturnMotion.valueAt(c, 90, 400), 0);
      expect(ReturnMotion.totalMs(c), 400);
    });

    test('chậm dần cuối đi nhanh hơn tuyến tính lúc đầu', () {
      final lin = ReturnConfig(durationMs: 300);
      final ease = ReturnConfig(durationMs: 300, curve: ReturnCurve.easeOut);
      expect(ReturnMotion.valueAt(ease, 100, 100), lessThan(ReturnMotion.valueAt(lin, 100, 100)));
    });

    test('về vị trí khác 0', () {
      expect(ReturnMotion.valueAt(ReturnConfig(targetPct: -100), 40, 0), -100);
    });

    test('giữ vị trí không tự về', () {
      expect(ReturnMotion.valueAt(ReturnConfig.holdPosition(), 55, 5000), 55);
    });

    test('về một nửa: chỉ nửa dương', () {
      final c = ReturnConfig(mode: ReturnMode.halfSpring, positiveOnly: true);
      expect(ReturnMotion.valueAt(c, 60, 0), 0);
      expect(ReturnMotion.valueAt(c, -60, 0), -60);
    });

    test('thoát màn: ga "Giữ vị trí" bắt buộc về Center', () {
      final hold = ReturnConfig.holdPosition()..targetPct = 30;
      expect(ReturnMotion.onExit(hold, isThrottle: true), 0);
      expect(ReturnMotion.onExit(ReturnConfig(targetPct: -100), isThrottle: true), -100);
    });

    test('vị trí nghỉ của Input ga theo vị trí về đã cài (H5)', () {
      ControlLayout mk(ControlItem it) => ControlLayout(id: 'l', name: 'l', items: [it]);
      final v = ControlItem(id: 'v', kind: ItemKind.stickV, inputId: 'thr', x: 0, y: 0, w: 3, h: 8,
          returnCfg: ReturnConfig(targetPct: -28));
      expect(ReturnMotion.restPct(mk(v), 'thr', isThrottle: true), -28);
      v.returnCfg = ReturnConfig.holdPosition()..targetPct = 30;
      expect(ReturnMotion.restPct(mk(v), 'thr', isThrottle: true), 0);
      final xy = ControlItem(id: 'xy', kind: ItemKind.stick2D, inputId: 'x', inputIdY: 'thr', x: 0, y: 0, w: 6, h: 6,
          returnCfg: ReturnConfig(targetPct: 10), returnCfgY: ReturnConfig(targetPct: -50));
      expect(ReturnMotion.restPct(mk(xy), 'thr', isThrottle: true), -50);
      expect(ReturnMotion.restPct(mk(xy), 'x', isThrottle: false), 10);
      final k = ControlItem(id: 'k', kind: ItemKind.knob, inputId: 'thr', x: 0, y: 0, w: 3, h: 3);
      expect(ReturnMotion.restPct(mk(k), 'thr', isThrottle: true), 0);
    });

    test('nhớ vị trí khi vào lại màn', () {
      final c = ReturnConfig.holdPosition()..rememberOnExit = true;
      expect(ReturnMotion.initial(c, 42), 42);
      expect(ReturnMotion.initial(ReturnConfig.holdPosition(), 42), 0);
    });

    test('không cho bật cả nửa dương và nửa âm', () {
      expect(ReturnConfig(positiveOnly: true, negativeOnly: true).validate(), isNotNull);
      expect(ReturnConfig(targetPct: 120).validate(), isNotNull);
    });

    test('vùng chết', () {
      expect(ReturnMotion.deadzone(5, 10), 0);
      expect(ReturnMotion.deadzone(100, 10), 100);
      expect(ReturnMotion.deadzone(-55, 10), closeTo(-50, 0.001));
    });
  });

  group('Phần tử hiển thị', () {
    test('bố cục cũ: ô đồng hồ đọc "gaugeKey" thành nguồn giá trị', () {
      final old = ControlItem.fromJson({'id': 'g', 'kind': 'gauge', 'gaugeKey': 'speed', 'x': 0, 'y': 0, 'w': 4, 'h': 2});
      expect(old.source, DataSource.speed);
      expect(old.toJson()['source'], DataSource.speed);
      expect(old.toJson().containsKey('gaugeKey'), isFalse);
    });

    test('cấu hình hiển thị lưu / đọc lại; phần tử điều khiển không lưu', () {
      final led = ControlItem(
        id: 'l',
        kind: ItemKind.led,
        source: DataSource.battery,
        x: 0,
        y: 0,
        w: 3,
        h: 1,
        display: DisplayConfig(threshold: 6.8, below: true, blink: LedBlink.fast),
      );
      final l2 = ControlItem.fromJson(led.toJson());
      expect(l2.display.threshold, 6.8);
      expect(l2.display.below, isTrue);
      expect(l2.display.blink, LedBlink.fast);
      final v = ControlItem(
          id: 'v', kind: ItemKind.vector, source: 'ch:1', sourceY: 'ch:2', x: 0, y: 0, w: 4, h: 4, display: DisplayConfig(trail: false));
      final v2 = ControlItem.fromJson(v.toJson());
      expect((v2.source, v2.sourceY, v2.display.trail), ('ch:1', 'ch:2', false));
      final bar = ControlItem.fromJson(
          ControlItem(id: 'b', kind: ItemKind.bar, source: 'ch:2', x: 0, y: 0, w: 6, h: 2, display: DisplayConfig(min: -50, max: 50))
              .toJson());
      expect((bar.display.min, bar.display.max), (-50, 50));
      expect(bar.display.threshold, isNull);
      final btn = ControlItem(id: 'x', kind: ItemKind.button, x: 0, y: 0, w: 3, h: 2).toJson();
      expect(btn.containsKey('display'), isFalse);
      expect(btn.containsKey('source'), isFalse);
    });

    test('nguồn giá trị: kênh, Input, khoá không hợp lệ, định dạng', () {
      final p = CarProfile(id: 'p', name: 'Xe', connType: ConnType.wifi, wifi: WifiConn());
      p.inputs.add(InputDef(id: 'thr', name: 'Ga', range: AxisRange.unipolar));
      expect(DataSource.info('ch:3', p)!.label, p.chLabel(3));
      expect(DataSource.info('ch:0', p), isNull);
      expect(DataSource.info('ch:11', p), isNull);
      expect(DataSource.info('in:thr', p)!.label, 'Ga');
      expect(DataSource.info('in:thr', p)!.min, 0);
      expect(DataSource.info('in:gone', p), isNull);
      expect(DataSource.info(null, p), isNull);
      expect(DataSource.info(DataSource.battery, p)!.format(7.456), '7.46 V');
      expect(DataSource.info('ch:1', p)!.format(-42.4), '-42%');
      expect(DataSource.info(DataSource.arm, p)!.format(1), 'ARMED');
      expect(DataSource.info(DataSource.arm, p)!.format(0), 'DISARMED');
      // Pin: đèn LED mặc định báo pin yếu
      expect((DataSource.info(DataSource.battery, p)!.alarm, DataSource.info(DataSource.battery, p)!.alarmBelow), (7, true));
      // Ô theo dõi 10 kênh và trạng thái đúng/sai không vẽ được thành thanh / vector
      expect(DataSource.options(p, ItemKind.gauge), containsAll([DataSource.channels, DataSource.arm, 'ch:10', 'in:thr']));
      expect(DataSource.options(p, ItemKind.bar), isNot(contains(DataSource.channels)));
      expect(DataSource.options(p, ItemKind.vector), isNot(contains(DataSource.arm)));
      expect(DataSource.options(p, ItemKind.led), contains(DataSource.failsafe));
    });

    test('nhãn mặc định theo nguồn; vector ghép hai trục', () {
      final p = CarProfile(id: 'p', name: 'Xe', connType: ConnType.wifi, wifi: WifiConn());
      final v = ControlItem(id: 'v', kind: ItemKind.vector, source: 'ch:1', sourceY: DataSource.speed, x: 0, y: 0, w: 4, h: 4);
      expect(DataSource.labelOf(v, p), '${p.chLabel(1)} / Tốc độ');
    });

    test('kích thước mặc định của mọi loại phần tử nằm trong giới hạn', () {
      for (final k in ItemKind.values) {
        final (w, h) = LayoutTemplates.defaultSize(k);
        final lim = SizeLimits.of(k);
        expect(w, inInclusiveRange(lim.minW, lim.maxW), reason: k.name);
        expect(h, inInclusiveRange(lim.minH, lim.maxH), reason: k.name);
      }
      expect(ItemKind.led.isControl || ItemKind.bar.isControl || ItemKind.vector.isControl, isFalse);
    });
  });
}
