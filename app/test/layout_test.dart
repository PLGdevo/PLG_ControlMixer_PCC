import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/layout/layout_grid.dart';
import 'package:rc_controller/layout/layout_history.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/layout/return_motion.dart';
import 'package:rc_controller/models/control_layout.dart';

void main() {
  group('Lưới bố cục (H2)', () {
    test('bố cục mặc định hợp lệ, có Ga và Lái', () {
      final l = LayoutTemplates.standard();
      expect(LayoutGrid.validate(l), isNull);
      expect(l.itemForChannel(1)?.kind, ItemKind.stickH);
      expect(l.itemForChannel(2)?.kind, ItemKind.stickV);
    });

    test('bám lưới', () {
      expect(LayoutGrid.snap(49, 33.3), 1);
      expect(LayoutGrid.snap(51, 33.3), 2);
      expect(LayoutGrid.snap(-20, 33.3), -1);
    });

    test('chống chồng lấn và giữ trong lưới', () {
      final l = LayoutTemplates.standard();
      final stick = l.itemForChannel(2)!; // 0,1 4x11
      expect(LayoutGrid.fits(l, 'new', const GridRect(1, 2, 2, 2)), isFalse);
      expect(LayoutGrid.fits(l, stick.id, GridRect.of(stick)), isTrue);
      expect(LayoutGrid.fits(l, 'new', const GridRect(22, 11, 3, 2)), isFalse); // tràn lưới
    });

    test('kẹp kích thước theo loại', () {
      final lim = SizeLimits.of(ItemKind.button);
      expect(LayoutGrid.clampSize(const GridRect(0, 0, 1, 9), lim, 24, 12), const GridRect(0, 0, 2, 4));
      expect(LayoutGrid.clampSize(const GridRect(23, 0, 3, 2), lim, 24, 12), const GridRect(21, 0, 3, 2));
    });

    test('vùng chạm ≥ 48 dp nâng kích thước nhỏ nhất', () {
      final lim = SizeLimits.of(ItemKind.button).forCell(20, 20);
      expect(lim.minW, 3);
      expect(lim.minH, 3);
    });

    test('thiếu phần tử Ga thì không cho lưu', () {
      final l = LayoutTemplates.standard();
      l.items.removeWhere((i) => i.channel == 2);
      expect(LayoutGrid.validate(l), contains('Ga'));
    });

    test('một kênh chỉ có một phần tử (H7): gán sang phần tử khác thì chuyển', () {
      final l = LayoutTemplates.standard();
      final a = LayoutTemplates.addControl(l, ItemKind.toggle, channel: 3)!;
      final b = LayoutTemplates.addControl(l, ItemKind.button)!;
      expect(b.channel, isNull);
      expect(l.assignChannel(b, 3)?.id, a.id);
      expect(a.channel, isNull);
      expect(l.itemForChannel(3)?.id, b.id);
    });

    test('thêm nhiều cần gạt cùng loại, cấu hình riêng từng cái', () {
      final l = LayoutTemplates.standard();
      final s1 = LayoutTemplates.addControl(l, ItemKind.stickH, channel: 5)!;
      final s2 = LayoutTemplates.addControl(l, ItemKind.stickH)!;
      s1.returnCfg!.mode = ReturnMode.hold;
      expect(l.items.where((i) => i.kind == ItemKind.stickH).length, 3);
      expect(s2.returnCfg!.mode, ReturnMode.spring);
      expect(s2.channel, isNull);
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

    test('vị trí nghỉ của ga theo vị trí về đã cài (H5)', () {
      ControlLayout mk(ControlItem it) => ControlLayout(id: 'l', name: 'l', items: [it]);
      final v = ControlItem(id: 'v', kind: ItemKind.stickV, channel: 2, x: 0, y: 0, w: 3, h: 8,
          returnCfg: ReturnConfig(targetPct: -28));
      expect(ReturnMotion.restPct(mk(v), 2, isThrottle: true), -28);
      v.returnCfg = ReturnConfig.holdPosition()..targetPct = 30;
      expect(ReturnMotion.restPct(mk(v), 2, isThrottle: true), 0);
      final xy = ControlItem(id: 'xy', kind: ItemKind.stick2D, channel: 1, channelY: 2, x: 0, y: 0, w: 6, h: 6,
          returnCfg: ReturnConfig(targetPct: 10), returnCfgY: ReturnConfig(targetPct: -50));
      expect(ReturnMotion.restPct(mk(xy), 2, isThrottle: true), -50);
      final k = ControlItem(id: 'k', kind: ItemKind.knob, channel: 2, x: 0, y: 0, w: 3, h: 3);
      expect(ReturnMotion.restPct(mk(k), 2, isThrottle: true), 0);
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
}
