import 'dart:collection';

import '../../models/brake_event.dart';
import '../fusion/motion_pipeline.dart';

double _r2(double v) => double.parse(v.toStringAsFixed(2));

/// What the bike actually did: sustained top speed, peak acceleration and
/// braking, and the stops. Pure measurement, no judgement.
class PerformanceReadings {
  const PerformanceReadings({
    this.sustainedTopSpeedKmh,
    this.peakAccelMps2,
    this.peakDecelMps2,
    this.stops = const [],
  });

  factory PerformanceReadings.fromJson(Map<String, dynamic> json) =>
      PerformanceReadings(
        sustainedTopSpeedKmh: (json['sustained_top_speed_kmh'] as num?)
            ?.toDouble(),
        peakAccelMps2: (json['peak_accel_mps2'] as num?)?.toDouble(),
        peakDecelMps2: (json['peak_decel_mps2'] as num?)?.toDouble(),
        stops: [
          for (final s in (json['stops'] as List? ?? const []))
            BrakeEvent.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
      );

  static const maxApiStops = 50;

  // Backend ModelCheckIn limits (backend/app/schemas/model_checks.py).
  static const maxApiSpeedKmh = 500.0;
  static const maxApiAccelMps2 = 100.0;
  static const maxApiStopS = 120.0;

  final double? sustainedTopSpeedKmh;
  final double? peakAccelMps2;
  final double? peakDecelMps2;
  final List<BrakeEvent> stops;

  /// Shape the backend's `measured` block expects. A value outside the
  /// schema would get the whole check rejected (and dropped by the outbox),
  /// so: stops the schema can't hold (rounded duration <= 0 or > 120 s,
  /// mean decel > 100 m/s2, i.e. clock steps or crash-like glitches) are
  /// left out before the 50-stop cap; peaks and top speed are clamped into
  /// range, keeping the direction of an extreme reading (the local check
  /// already judged the raw values). [toJson] keeps everything as measured.
  Map<String, dynamic> toApiJson() => {
    'sustained_top_speed_kmh': _clamped(sustainedTopSpeedKmh, maxApiSpeedKmh),
    'peak_accel_mps2': _clamped(peakAccelMps2, maxApiAccelMps2),
    'peak_decel_mps2': _clamped(peakDecelMps2, maxApiAccelMps2),
    'stops': stops.map(_apiStop).nonNulls.take(maxApiStops).toList(),
  };

  static Map<String, dynamic>? _apiStop(BrakeEvent s) {
    final duration = _r2(s.durationS);
    final speed = _r2(s.startSpeedKmh);
    final decel = _r2(s.meanDecelMps2);
    if (duration <= 0 || duration > maxApiStopS) return null;
    if (speed < 0 || speed > maxApiSpeedKmh) return null;
    if (decel < 0 || decel > maxApiAccelMps2) return null;
    return {
      'start_speed_kmh': speed,
      'duration_s': duration,
      'mean_decel_mps2': decel,
    };
  }

  static double? _clamped(double? v, double max) =>
      v == null ? null : _r2(v.clamp(0, max).toDouble());

  /// Local storage form (full brake events).
  Map<String, dynamic> toJson() => {
    'sustained_top_speed_kmh': _opt(sustainedTopSpeedKmh),
    'peak_accel_mps2': _opt(peakAccelMps2),
    'peak_decel_mps2': _opt(peakDecelMps2),
    'stops': [for (final s in stops) s.toJson()],
  };

  static double? _opt(double? v) => v == null ? null : _r2(v);
}

class PerformanceMeter {
  static const _topWindowS = 3.0;
  static const _accelWindowS = 1.0;
  static const _decelWindowS = 0.5;
  static const _minMovingKmh = 5.0;
  static const _tol = 0.05; // sample-timing slack at ~10 Hz

  final _speedRun = Queue<MotionState>();
  final _accelRun = Queue<MotionState>();
  final List<BrakeEvent> _stops = [];

  double? _top;
  double? _accel;
  double? _decel;

  void add(MotionState s) {
    _updateTop(s);
    _updateAccel(s);
  }

  void addStop(BrakeEvent e) => _stops.add(e);

  PerformanceReadings get readings => PerformanceReadings(
    sustainedTopSpeedKmh: _top,
    peakAccelMps2: _accel,
    peakDecelMps2: _decel,
    stops: List.unmodifiable(_stops),
  );

  void _updateTop(MotionState s) {
    if (!s.speedReliable) {
      _speedRun.clear();
      return;
    }
    _speedRun.addLast(s);
    while (_speedRun.length > 1 &&
        _speedRun.first.t < s.t - _topWindowS - _tol) {
      _speedRun.removeFirst();
    }
    if (s.t - _speedRun.first.t < _topWindowS - _tol) return;
    var minSpeed = double.infinity;
    for (final x in _speedRun) {
      if (x.t >= s.t - _topWindowS - _tol && x.speedKmh < minSpeed) {
        minSpeed = x.speedKmh;
      }
    }
    if (_top == null || minSpeed > _top!) _top = minSpeed;
  }

  void _updateAccel(MotionState s) {
    if (s.speedKmh < _minMovingKmh) {
      _accelRun.clear();
      return;
    }
    _accelRun.addLast(s);
    while (_accelRun.length > 1 &&
        _accelRun.first.t < s.t - _accelWindowS - _tol) {
      _accelRun.removeFirst();
    }
    final span = s.t - _accelRun.first.t;
    if (span >= _accelWindowS - _tol) {
      final m = _mean(s.t, _accelWindowS, 1);
      if (_accel == null || m > _accel!) _accel = m;
    }
    if (span >= _decelWindowS - _tol) {
      final m = _mean(s.t, _decelWindowS, -1);
      if (_decel == null || m > _decel!) _decel = m;
    }
  }

  double _mean(double now, double window, double sign) {
    var sum = 0.0;
    var n = 0;
    for (final x in _accelRun) {
      if (x.t >= now - window - _tol) {
        sum += sign * x.forwardAccel;
        n++;
      }
    }
    return sum / n;
  }
}
