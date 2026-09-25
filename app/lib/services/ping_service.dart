// Đo ping (F3): RTT min/avg/max, jitter, % mất gói trên cửa sổ trượt 20 gói.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/protocol.dart';
import '../transport/transport.dart';

class PingStats {
  final int sent, received, lost;
  final double? minMs, avgMs, maxMs, jitterMs, lastMs;

  const PingStats({
    this.sent = 0,
    this.received = 0,
    this.lost = 0,
    this.minMs,
    this.avgMs,
    this.maxMs,
    this.jitterMs,
    this.lastMs,
  });

  double get lossPct => sent == 0 ? 0 : lost / sent * 100;
  bool get hasData => received > 0;

  @override
  String toString() => 'PingStats(sent $sent, recv $received, lost $lost, avg $avgMs, jitter $jitterMs)';
}

class _Rec {
  _Rec(this.seq, this.sentAtMs);
  final int seq;
  final double sentAtMs;
  double? rttMs;
  bool lost = false;
  bool get done => rttMs != null || lost;
}

/// Phần thống kê thuần (không I/O), để test riêng
class PingWindow {
  PingWindow({this.size = 20, this.timeoutMs = 1000});

  final int size;
  final int timeoutMs;
  final List<_Rec> _recs = [];

  void onSent(int seq, double nowMs) {
    _recs.add(_Rec(seq, nowMs));
    // Giữ lại gói chưa xong để còn ghép, nhưng cửa sổ chỉ tính `size` gói gần nhất
    while (_recs.length > size * 2) {
      _recs.removeAt(0);
    }
  }

  /// Ghép theo seq (gói về sai thứ tự vẫn đúng). Về sau timeout → vẫn tính là mất.
  void onPong(int seq, double nowMs) {
    for (final r in _recs.reversed) {
      if (r.seq != seq) continue;
      if (r.done) return;
      final rtt = nowMs - r.sentAtMs;
      if (rtt > timeoutMs) {
        r.lost = true;
      } else {
        r.rttMs = rtt;
      }
      return;
    }
  }

  /// Đánh dấu mất các gói quá hạn
  void tick(double nowMs) {
    for (final r in _recs) {
      if (!r.done && nowMs - r.sentAtMs > timeoutMs) r.lost = true;
    }
  }

  bool get allDone => _recs.every((r) => r.done);

  PingStats stats() {
    final done = _recs.where((r) => r.done).toList();
    final win = done.length > size ? done.sublist(done.length - size) : done;
    final got = win.where((r) => r.rttMs != null).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final rtts = got.map((r) => r.rttMs!).toList();
    double? jitter;
    if (rtts.length >= 2) {
      var s = 0.0;
      for (var i = 1; i < rtts.length; i++) {
        s += (rtts[i] - rtts[i - 1]).abs();
      }
      jitter = s / (rtts.length - 1);
    }
    final last = win.lastWhere((r) => r.rttMs != null, orElse: () => _Rec(-1, 0)).rttMs;
    return PingStats(
      sent: win.length,
      received: rtts.length,
      lost: win.length - rtts.length,
      minMs: rtts.isEmpty ? null : rtts.reduce((a, b) => a < b ? a : b),
      maxMs: rtts.isEmpty ? null : rtts.reduce((a, b) => a > b ? a : b),
      avgMs: rtts.isEmpty ? null : rtts.reduce((a, b) => a + b) / rtts.length,
      jitterMs: jitter,
      lastMs: last,
    );
  }

  void clear() => _recs.clear();
}

/// Gửi PING qua một kết nối đang mở và nghe PONG
class PingService extends ChangeNotifier {
  PingService(this.transport, {this.timeoutMs = 1000}) : window = PingWindow(timeoutMs: timeoutMs) {
    _clock.start();
    _sub = transport.incoming.listen(_onData);
  }

  final CarTransport transport;
  final int timeoutMs;
  final PingWindow window;
  final _clock = Stopwatch();
  StreamSubscription? _sub;
  Timer? _timer;
  int _seq = 0;
  int? _remaining;

  PingStats get stats => window.stats();
  bool get running => _timer != null;

  double get _now => _clock.elapsedMicroseconds / 1000;

  void _onData(Uint8List data) {
    final f = decodeFrame(data);
    if (f == null || f.type != PacketType.pong) return;
    final p = Pong.parse(f.payload);
    if (p == null) return;
    window.onPong(p.seq, _now);
    notifyListeners();
  }

  Future<void> _sendOne() async {
    _seq = (_seq + 1) & 0xFFFF;
    window.onSent(_seq, _now);
    try {
      await transport.send(encodePing(_seq, _now.round()));
    } catch (_) {
      // Gửi lỗi sẽ được tính là mất khi quá hạn
    }
  }

  /// Chạy liên tục (`count` = null) hoặc `count` gói, cách nhau `intervalMs`
  void start({int intervalMs = 1000, int? count}) {
    stop();
    _remaining = count;
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => _tick());
    _tick();
  }

  void _tick() {
    window.tick(_now);
    if (_remaining != null) {
      if (_remaining! <= 0) {
        if (window.allDone) stop();
        notifyListeners();
        return;
      }
      _remaining = _remaining! - 1;
    }
    _sendOne();
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Gửi `count` gói rồi chờ tới khi có đủ phản hồi hoặc hết hạn
  Future<PingStats> burst({int count = 3, int intervalMs = 200}) async {
    for (var i = 0; i < count; i++) {
      await _sendOne();
      if (i < count - 1) await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
    final deadline = _now + timeoutMs + 50;
    while (_now < deadline) {
      window.tick(_now);
      if (window.allDone) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    window.tick(_now + timeoutMs + 1);
    return window.stats();
  }

  @override
  void dispose() {
    stop();
    _sub?.cancel();
    super.dispose();
  }
}
