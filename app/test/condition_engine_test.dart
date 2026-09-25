// N1: ConditionEngine — toán tử, AND/OR/NOT, hysteresis, Condition đặt tên.
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/services/condition_engine.dart';
import 'package:rc_controller/services/input_manager.dart';

InputManager inputs() => InputManager([
      InputDef(id: 'steer', name: 'Lái'),
      InputDef(id: 'slider', name: 'Slider', range: AxisRange.unipolar),
      InputDef(id: 'a', name: 'A', type: InputType.binary),
      InputDef(id: 'b', name: 'B', type: InputType.binary),
      InputDef(id: 'sw', name: 'SW', type: InputType.ternary),
    ]);

Expr cmp(String i, CmpOp op, double v, {double hyst = 0}) => ExprCmp(input: i, op: op, value: v, hyst: hyst);

void main() {
  late InputManager im;
  late ConditionEngine ce;
  bool ev(Expr e) {
    ce.beginCycle();
    return ce.eval(ce.compile(e), im.state);
  }

  setUp(() {
    im = inputs();
    ce = ConditionEngine(im.index, const []);
  });

  test('6 toán tử trên trạng thái của 4 kiểu Input', () {
    im.setPosition('steer', 40);
    im.setPosition('slider', 0); // unipolar: vị trí 0 → trạng thái 50
    im.setSwitch('a', 1);
    im.setSwitch('sw', 0); // nấc trái → −1
    expect(ev(cmp('steer', CmpOp.gt, 30)), isTrue);
    expect(ev(cmp('steer', CmpOp.lt, 30)), isFalse);
    expect(ev(cmp('steer', CmpOp.ge, 40)), isTrue);
    expect(ev(cmp('steer', CmpOp.le, 39)), isFalse);
    expect(ev(cmp('steer', CmpOp.eq, 40.3)), isTrue); // sai số ±0,5
    expect(ev(cmp('steer', CmpOp.ne, 41)), isTrue);
    expect(ev(cmp('slider', CmpOp.eq, 50)), isTrue);
    expect(ev(cmp('a', CmpOp.eq, 1)), isTrue);
    expect(ev(cmp('b', CmpOp.eq, 0)), isTrue);
    expect(ev(cmp('sw', CmpOp.eq, -1)), isTrue);
  });

  test('trạng thái không phụ thuộc mức bật/tắt người dùng đặt', () {
    im = InputManager([InputDef(id: 'a', name: 'A', type: InputType.binary, levels: InputLevels(offPct: 0, onPct: 60))]);
    ce = ConditionEngine(im.index, const []);
    im.setSwitch('a', 0);
    expect(im.valueOf('a'), 0);
    expect(ev(cmp('a', CmpOp.eq, 0)), isTrue);
    im.setSwitch('a', 1);
    expect(im.valueOf('a'), 60);
    expect(ev(cmp('a', CmpOp.eq, 1)), isTrue);
  });

  test('AND / OR / NOT lồng 4 tầng', () {
    im.setSwitch('a', 1);
    im.setSwitch('b', 0);
    im.setPosition('steer', 10);
    final e = ExprOr([
      ExprAnd([
        cmp('a', CmpOp.eq, 1),
        ExprNot(ExprOr([cmp('b', CmpOp.eq, 1), cmp('steer', CmpOp.gt, 50)])),
      ]),
      cmp('sw', CmpOp.eq, 1),
    ]);
    expect(e.depth, 4);
    expect(ev(e), isTrue);
    im.setPosition('steer', 60);
    expect(ev(e), isFalse);
    im.setSwitch('sw', 2);
    expect(ev(e), isTrue);
  });

  test('hysteresis >= 80, trễ 10: bảng G2a', () {
    final n = ce.compile(cmp('steer', CmpOp.ge, 80, hyst: 10));
    bool at(double v) {
      im.setPosition('steer', v);
      ce.beginCycle();
      return ce.eval(n, im.state);
    }

    expect(at(0), isFalse);
    expect(at(75), isFalse); // chưa chạm 80
    expect(at(82), isTrue);
    expect(at(72), isTrue); // vẫn ≥ 70, giữ
    expect(at(69), isFalse);
    expect(at(78), isFalse); // chưa chạm 80, giữ
  });

  test('hysteresis <= 20, trễ 10; dao động trong vùng giữ không đổi', () {
    final n = ce.compile(cmp('steer', CmpOp.le, 20, hyst: 10));
    bool at(double v) {
      im.setPosition('steer', v);
      ce.beginCycle();
      return ce.eval(n, im.state);
    }

    expect(at(25), isFalse);
    expect(at(20), isTrue);
    for (final v in [21.0, 29.0, 22.0, 30.0]) {
      expect(at(v), isTrue);
    }
    expect(at(31), isFalse);
  });

  test('reset đưa trạng thái trễ về sai', () {
    final n = ce.compile(cmp('steer', CmpOp.ge, 80, hyst: 10));
    im.setPosition('steer', 90);
    ce.beginCycle();
    expect(ce.eval(n, im.state), isTrue);
    ce.reset();
    im.setPosition('steer', 75);
    ce.beginCycle();
    expect(ce.eval(n, im.state), isFalse);
  });

  test('Condition đặt tên: nhiều luật dùng chung một trạng thái trễ', () {
    ce = ConditionEngine(im.index, [
      ConditionDef(id: 'hi', name: 'Lái cao', expr: cmp('steer', CmpOp.ge, 80, hyst: 10)),
    ]);
    final a = ce.compile(const ExprRef('hi'));
    final b = ce.compile(const ExprNot(ExprRef('hi')));
    im.setPosition('steer', 85);
    ce.beginCycle();
    expect([ce.eval(a, im.state), ce.eval(b, im.state)], [true, false]);
    im.setPosition('steer', 75);
    ce.beginCycle();
    expect([ce.eval(a, im.state), ce.eval(b, im.state)], [true, false]);
  });

  test('phát hiện tham chiếu vòng và kiểm tra dữ liệu', () {
    final defs = [
      ConditionDef(id: 'x', name: 'X', expr: const ExprRef('y')),
      ConditionDef(id: 'y', name: 'Y', expr: ExprAnd([const ExprRef('x'), cmp('a', CmpOp.eq, 1)])),
    ];
    expect(ConditionDef.findRefCycle(defs), ['x', 'y', 'x']);
    final byId = {for (final d in im.defs) d.id: d};
    expect(cmp('nope', CmpOp.eq, 1).validate(byId, {}), contains('không tồn tại'));
    expect(cmp('a', CmpOp.eq, 1, hyst: 5).validate(byId, {}), contains('lớn/nhỏ'));
    expect(const ExprRef('z').validate(byId, {}), contains('không tồn tại'));
    final deep = ExprNot(ExprNot(ExprNot(ExprNot(ExprNot(cmp('a', CmpOp.eq, 1))))));
    expect(deep.validate(byId, {}), contains('tầng'));
  });

  test('JSON đi một vòng không đổi', () {
    final e = ExprAnd([
      cmp('steer', CmpOp.ge, 80, hyst: 10),
      const ExprNot(ExprRef('c')),
      ExprOr([cmp('a', CmpOp.eq, 1), const ExprTrue()]),
    ]);
    expect(Expr.fromJson(e.toJson()).toJson(), e.toJson());
  });
}
