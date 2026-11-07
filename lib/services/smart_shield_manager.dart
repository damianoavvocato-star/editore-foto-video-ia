import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

enum SmartShieldMode { balanced, conservative }

/// Pure policy so thresholds can be verified without physical devices.
class SmartShieldPolicy {
  const SmartShieldPolicy();

  SmartShieldMode evaluate({
    required int measuredFrames,
    required int slowFrames,
    required SmartShieldMode current,
  }) {
    if (measuredFrames < 30) return current;
    final ratio = slowFrames / measuredFrames;
    if (ratio >= 0.25) return SmartShieldMode.conservative;
    if (ratio <= 0.08) return SmartShieldMode.balanced;
    return current; // Hysteresis prevents profile oscillation.
  }

  double previewDecodeScale(SmartShieldMode mode) =>
      mode == SmartShieldMode.conservative ? 0.65 : 1.0;
}

/// Lightweight runtime guard based only on signals Flutter actually exposes.
/// It deliberately does not guess free RAM, CPU/GPU clocks, or thermal state.
class SmartShieldManager with WidgetsBindingObserver, ChangeNotifier {
  SmartShieldManager({
    SmartShieldPolicy policy = const SmartShieldPolicy(),
    int maxFrameSamples = 60,
    Duration slowFrameThreshold = const Duration(milliseconds: 17),
  })  : _policy = policy,
        _maxFrameSamples = maxFrameSamples.clamp(30, 240).toInt(),
        _slowFrameThreshold = slowFrameThreshold {
    if (slowFrameThreshold <= Duration.zero) {
      throw ArgumentError.value(
        slowFrameThreshold,
        'slowFrameThreshold',
        'La soglia dei fotogrammi deve essere positiva.',
      );
    }
  }

  final SmartShieldPolicy _policy;
  final int _maxFrameSamples;
  final Duration _slowFrameThreshold;
  final Queue<bool> _frameSamples = Queue<bool>();

  SmartShieldMode _mode = SmartShieldMode.balanced;
  bool _isInBackground = false;
  bool _started = false;
  bool _disposed = false;

  SmartShieldMode get mode => _mode;
  double get previewDecodeScale => _policy.previewDecodeScale(_mode);
  bool get isInBackground => _isInBackground;
  int get maxFrameSamples => _maxFrameSamples;
  int get measuredFrames => _frameSamples.length;
  int get slowFrames => _frameSamples.where((slow) => slow).length;

  void start() {
    if (_disposed) throw StateError('SmartShieldManager è già stato chiuso.');
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void didHaveMemoryPressure() {
    if (_disposed) return;
    // Flutter reports real memory pressure from the platform. Switch to the
    // conservative preview profile immediately and discard stale frame data;
    // recovery requires a fresh window of healthy frame timings.
    _frameSamples.clear();
    if (_mode == SmartShieldMode.conservative) return;
    _mode = SmartShieldMode.conservative;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final next = state != AppLifecycleState.resumed;
    if (_isInBackground == next) return;
    _isInBackground = next;
    notifyListeners();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (_disposed || _isInBackground) return;
    for (final timing in timings) {
      _frameSamples.addLast(timing.totalSpan > _slowFrameThreshold);
      while (_frameSamples.length > _maxFrameSamples) {
        _frameSamples.removeFirst();
      }
    }
    final next = _policy.evaluate(
      measuredFrames: measuredFrames,
      slowFrames: slowFrames,
      current: _mode,
    );
    if (next != _mode) {
      _mode = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      _started = false;
    }
    super.dispose();
  }
}
