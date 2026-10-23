import 'dart:collection';
import 'dart:math' as math;

import '../math/vec3.dart';
import 'safety_tuning.dart';

/// Recognises a speed wobble ("death wobble", tank slapper) in the raw
/// gyroscope signal: a strong rotation that keeps reversing several times a
/// second.
///
/// Turning, lane changes and weaving are slow (below ~2 Hz) and are removed
/// by a high-pass filter; road buzz and engine vibration are weak or too
/// fast. Amplitude is measured on all axes and the reversal rate on the
/// dominant one, so the phone's mount orientation does not matter.
///
/// Needs the raw IMU rate (~50 Hz): the 10 Hz processed stream cannot
/// represent a 4-10 Hz oscillation.
class WobbleDetector {
  WobbleDetector({
    this.minHz = SafetyTuning.wobbleMinHz,
    this.maxHz = SafetyTuning.defaultWobbleMaxHz,
    this.minRms = SafetyTuning.defaultWobbleRms,
    this.window = 1.0,
    this.highPassHz = 1.5,
  });

  /// Oscillation frequency band that counts as a wobble.
  final double minHz;
  final double maxHz;

  /// Minimum oscillating rotation, rad/s RMS (0.5 ≈ 29°/s by default).
  final double minRms;

  /// Seconds of signal analysed.
  final double window;
  final double highPassHz;

  final ListQueue<(double, Vec3)> _samples = ListQueue();
  Vec3? _lastRaw;
  Vec3 _filtered = Vec3.zero;

  /// Reversal rate on the dominant axis over the last [window], Hz.
  double frequencyHz = 0;

  /// Oscillating rotation over the last [window], rad/s RMS.
  double rms = 0;

  /// Feeds one gyro sample (phone frame, rad/s). Returns true while the
  /// last [window] looks like a wobble.
  bool add(Vec3 rate, double t, double dt) {
    final last = _lastRaw;
    _lastRaw = rate;
    if (last != null) {
      // First-order high-pass: keeps the oscillation, drops turns and bias.
      final rc = 1 / (2 * math.pi * highPassHz);
      _filtered = (_filtered + rate - last) * (rc / (rc + dt));
    }
    _samples.addLast((t, _filtered));
    while (_samples.first.$1 < t - window) {
      _samples.removeFirst();
    }

    final span = t - _samples.first.$1;
    if (span < window * 0.8) {
      frequencyHz = 0;
      rms = 0;
      return false;
    }

    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final (_, v) in _samples) {
      sx += v.x * v.x;
      sy += v.y * v.y;
      sz += v.z * v.z;
    }
    final n = _samples.length.toDouble();
    rms = math.sqrt((sx + sy + sz) / n);
    final axis = sx >= sy && sx >= sz ? 0 : (sy >= sz ? 1 : 2);
    double along(Vec3 v) => switch (axis) {
      0 => v.x,
      1 => v.y,
      _ => v.z,
    };

    // Count reversals with hysteresis so noise around zero is ignored.
    final h = 0.5 * math.sqrt([sx, sy, sz][axis] / n);
    var sign = 0;
    var reversals = 0;
    for (final (_, v) in _samples) {
      final c = along(v);
      if (c > h && sign <= 0) {
        if (sign < 0) reversals++;
        sign = 1;
      } else if (c < -h && sign >= 0) {
        if (sign > 0) reversals++;
        sign = -1;
      }
    }
    frequencyHz = reversals / 2 / span;
    return rms >= minRms && frequencyHz >= minHz && frequencyHz <= maxHz;
  }

  void reset() {
    _samples.clear();
    _lastRaw = null;
    _filtered = Vec3.zero;
    frequencyHz = 0;
    rms = 0;
  }
}
