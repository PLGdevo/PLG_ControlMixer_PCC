import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/services/ping_service.dart';

void main() {
  test('RTT min/avg/max và jitter', () {
    final w = PingWindow();
    w.onSent(1, 0);
    w.onPong(1, 10);
    w.onSent(2, 100);
    w.onPong(2, 130);
    w.onSent(3, 200);
    w.onPong(3, 220);
    final s = w.stats();
    expect(s.received, 3);
    expect(s.minMs, 10);
    expect(s.maxMs, 30);
    expect(s.avgMs, 20);
    expect(s.jitterMs, 15); // (|30-10| + |20-30|) / 2
    expect(s.lossPct, 0);
  });

  test('gói mất sau timeout', () {
    final w = PingWindow(timeoutMs: 1000);
    w.onSent(1, 0);
    w.onPong(1, 20);
    w.onSent(2, 100);
    w.tick(1200);
    final s = w.stats();
    expect(s.sent, 2);
    expect(s.lost, 1);
    expect(s.lossPct, 50);
  });

  test('gói về sau khi đã timeout vẫn tính là mất', () {
    final w = PingWindow(timeoutMs: 1000);
    w.onSent(1, 0);
    w.onPong(1, 1500);
    final s = w.stats();
    expect(s.lost, 1);
    expect(s.received, 0);
    expect(s.avgMs, isNull);
  });

  test('gói về sai thứ tự ghép theo seq', () {
    final w = PingWindow();
    w.onSent(1, 0);
    w.onSent(2, 10);
    w.onPong(2, 40); // rtt 30
    w.onPong(1, 50); // rtt 50
    final s = w.stats();
    expect(s.received, 2);
    expect(s.minMs, 30);
    expect(s.maxMs, 50);
  });

  test('cửa sổ trượt 20 gói', () {
    final w = PingWindow(size: 20);
    for (var i = 0; i < 30; i++) {
      w.onSent(i, i * 100.0);
      if (i >= 10) w.onPong(i, i * 100.0 + 5); // 10 gói đầu mất
    }
    w.tick(10000);
    final s = w.stats();
    expect(s.sent, 20);
    expect(s.lost, 0);
  });
}
