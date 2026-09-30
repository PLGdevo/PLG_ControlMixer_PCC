// Nguồn giá trị cho phần tử hiển thị (ô đồng hồ, đèn LED, thanh giá trị, vector 2D).
// Khoá lưu trong bố cục: số đo từ xe ('battery', 'speed'…), trạng thái ('arm', 'link', 'failsafe'),
// 'ch:N' kênh N sau mixer, 'in:<mã>' giá trị Input, 'channels' ô theo dõi 10 kênh.
import '../l10n/lang.dart';
import 'car_profile.dart';
import 'control_layout.dart';

enum SourceGroup {
  car('Đo từ xe', 'From the car'),
  state('Trạng thái', 'State'),
  channel('Kênh ra (sau mixer)', 'Output channels (after mixer)'),
  input('Input', 'Input');

  const SourceGroup(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

class SourceInfo {
  const SourceInfo(
    this.key,
    this.label,
    this.group, {
    this.unit = '',
    this.decimals = 0,
    this.min = -100,
    this.max = 100,
    this.flag = false,
    this.alarm = 0,
    this.alarmBelow = false,
    this.onText = '',
    this.offText = '',
  });

  final String key, label;
  final SourceGroup group;
  final String unit;
  final int decimals;

  /// Khoảng mặc định (thanh giá trị, vector)
  final double min, max;

  /// Nguồn đúng/sai (giá trị 1/0)
  final bool flag;

  /// Ngưỡng bật đèn LED mặc định: sáng khi giá trị > `alarm` (hoặc < nếu `alarmBelow`)
  final double alarm;
  final bool alarmBelow;

  /// Chữ hiện trên ô đồng hồ cho nguồn đúng/sai
  final String onText, offText;

  String format(double v) {
    if (flag) return v >= 0.5 ? onText : offText;
    final s = v.toStringAsFixed(decimals);
    return unit.isEmpty ? s : (unit == '%' ? '$s%' : '$s $unit');
  }
}

abstract final class DataSource {
  static const battery = 'battery', current = 'current', speed = 'speed', ping = 'ping', lq = 'lq', rssi = 'rssi';
  static const arm = 'arm', link = 'link', failsafe = 'failsafe';

  /// Ô theo dõi 10 kênh (chỉ ô đồng hồ)
  static const channels = 'channels';

  static const carKeys = [battery, current, speed, ping, lq, rssi];
  static const stateKeys = [arm, link, failsafe];

  static String ch(int n) => 'ch:$n';
  static String input(String id) => 'in:$id';

  static int? chOf(String? key) => key != null && key.startsWith('ch:') ? int.tryParse(key.substring(3)) : null;
  static String? inputOf(String? key) => key != null && key.startsWith('in:') ? key.substring(3) : null;

  /// Thông tin nguồn; null nếu khoá không hợp lệ (vd Input đã bị xoá)
  static SourceInfo? info(String? key, CarProfile p) {
    switch (key) {
      case battery:
        return SourceInfo(key!, tr('Pin', 'Battery'), SourceGroup.car,
            unit: 'V', decimals: 2, min: 6, max: 8.4, alarm: 7, alarmBelow: true);
      case current:
        return SourceInfo(key!, tr('Dòng', 'Current'), SourceGroup.car, unit: 'A', decimals: 1, min: 0, max: 20, alarm: 10);
      case speed:
        return SourceInfo(key!, tr('Tốc độ', 'Speed'), SourceGroup.car, unit: 'km/h', decimals: 1, min: 0, max: 40, alarm: 20);
      case ping:
        return SourceInfo(key!, 'Ping', SourceGroup.car, unit: 'ms', min: 0, max: 200, alarm: 100);
      case lq:
        return SourceInfo(key!, tr('Chất lượng liên kết (LQ)', 'Link quality (LQ)'), SourceGroup.car,
            unit: '%', min: 0, max: 100, alarm: 70, alarmBelow: true);
      case rssi:
        return SourceInfo(key!, 'RSSI', SourceGroup.car, unit: 'dBm', min: -90, max: -30, alarm: -80, alarmBelow: true);
      case arm:
        return SourceInfo(key!, 'ARM', SourceGroup.state, flag: true, min: 0, max: 1, onText: 'ARMED', offText: 'DISARMED');
      case link:
        return SourceInfo(key!, tr('Kết nối', 'Link'), SourceGroup.state,
            flag: true, min: 0, max: 1, onText: 'OK', offText: tr('MẤT', 'LOST'));
      case failsafe:
        return SourceInfo(key!, 'Failsafe', SourceGroup.state,
            flag: true, min: 0, max: 1, onText: tr('CÓ', 'ON'), offText: tr('KHÔNG', 'OFF'));
      case channels:
        return SourceInfo(key!, tr('Kênh đầu ra', 'Output channels'), SourceGroup.channel);
    }
    final n = chOf(key);
    if (n != null) {
      if (n < 1 || n > p.channels.length) return null;
      return SourceInfo(key!, p.chLabel(n), SourceGroup.channel, unit: '%');
    }
    final d = p.input(inputOf(key));
    if (d != null) {
      return SourceInfo(key!, d.name, SourceGroup.input, unit: '%', min: d.isUnipolar ? 0 : -100);
    }
    return null;
  }

  /// Các nguồn chọn được cho một loại phần tử, theo nhóm
  static List<String> options(CarProfile p, ItemKind kind) => [
        ...carKeys,
        if (kind == ItemKind.gauge || kind == ItemKind.led) ...stateKeys,
        if (kind == ItemKind.gauge) channels,
        for (var i = 1; i <= p.channels.length; i++) ch(i),
        for (final d in p.inputs) input(d.id),
      ];

  /// Nhãn mặc định của phần tử hiển thị: tên nguồn (vector: "X / Y")
  static String labelOf(ControlItem it, CarProfile p) {
    final x = info(it.source, p)?.label ?? it.kind.label;
    if (it.kind != ItemKind.vector) return x;
    return '$x / ${info(it.sourceY, p)?.label ?? '?'}';
  }
}
