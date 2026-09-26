// Nhấn giữ để lặp: bọc quanh nút −/+ (nút bên trong vẫn lo lần bấm thường).
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class HoldRepeat extends StatefulWidget {
  const HoldRepeat({
    super.key,
    required this.onStep,
    required this.child,
    this.accelerate = true,
    this.fastTimes = 1,
  });

  /// Một lần lặp; `times` = số bước gộp lại (giữ lâu thì bằng [fastTimes]). null = không lặp.
  final void Function(int times)? onStep;
  final Widget child;

  /// Càng giữ càng nhanh; false = nhịp đều, chậm (vd đổi số hộp số)
  final bool accelerate;

  /// Số bước mỗi lần lặp sau khi giữ lâu (chỉnh số có dải rộng như µs)
  final int fastTimes;

  @override
  State<HoldRepeat> createState() => _HoldRepeatState();
}

class _HoldRepeatState extends State<HoldRepeat> {
  static const _holdDelay = Duration(milliseconds: 350);
  Timer? _timer;
  int _n = 0;

  void _start() {
    _n = 0;
    _tick();
  }

  void _tick() {
    final f = widget.onStep;
    if (f == null) return _stop();
    _n++;
    f(widget.accelerate && _n > 15 ? widget.fastTimes : 1);
    HapticFeedback.selectionClick();
    final ms = !widget.accelerate ? 350 : (_n < 3 ? 250 : (_n < 10 ? 110 : 55));
    _timer = Timer(Duration(milliseconds: ms), _tick);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(HoldRepeat old) {
    super.didUpdateWidget(old);
    if (widget.onStep == null) _stop(); // chạm giới hạn → dừng
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        gestures: widget.onStep == null
            ? const {}
            : {
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(duration: _holdDelay, debugOwner: this),
                  (r) {
                    r.onLongPressStart = (_) => _start();
                    r.onLongPressEnd = (_) => _stop();
                    r.onLongPressCancel = _stop;
                  },
                ),
              },
        child: widget.child,
      );
}
