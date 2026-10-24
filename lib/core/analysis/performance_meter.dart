import 'dart:collection';

import '../../models/brake_event.dart';
import '../fusion/estimators.dart';
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

  /// A stop can't start much faster than the bike was ever sustained at;
  /// one that does began at a GPS glitch (one wild fix just before
  /// braking), so its mean deceleration is meaningless.
  static const stopStartFactor = 1.1;
  static const stopStartSlackKmh = 5.0;

  /// Fastest believable start of a stop; null without a sustained top
  /// speed (nothing to compare against).
  double? get maxStopStartKmh {
    final top = sustainedTopSpeedKmh;
    return top == null ? null : top * stopStartFactor + stopStartSlackKmh;
  }

  /// Stops that did not start at a glitch (all of them when there is no
  /// sustained top speed to compare with).
  Iterable<BrakeEvent> get plausibleStops {
    final max = maxStopStartKmh;
    return max == null ? stops : stops.where((s) => s.startSpeedKmh <= max);
  }

  /// Stops whose mean deceleration can be judged against the model: only
  /// with a sustained top speed to rule out glitches.
  Iterable<BrakeEvent> get judgeableStops =>
      maxStopStartKmh == null ? const [] : plausibleStops;

  /// Shape the backend's `measured` block expects. A value outside the
  /// schema would get the whole check rejected (and dropped by the outbox),
  /// so: stops the schema can't hold (rounded duration <= 0 or > 120 s,
  /// mean decel > 100 m/s2, i.e. clock steps or crash-like glitches) and
  /// stops that started at a GPS glitch ([plausibleStops]) are left out
  /// before the 50-stop cap (which keeps the hardest); peaks and top speed are clamped into
  /// range, keeping the direction of an extreme reading (the local check
  /// already judged the raw values). [toJson] keeps everything as measured.
  Map<String, dynamic> toApiJson() => {
    'sustained_top_speed_kmh': _clamped(sustainedTopSpeedKmh, maxApiSpeedKmh),
    'peak_accel_mps2': _clamped(peakAccelMps2, maxApiAccelMps2),
    'peak_decel_mps2': _clamped(peakDecelMps2, maxApiAccelMps2),
    'stops': _apiStops(),
  };

  /// At most [maxApiStops], the hardest by mean deceleration (they are what
  /// the braking check is about), in ride order.
  List<Map<String, dynamic>> _apiStops() {
    final valid = plausibleStops.map(_apiStop).nonNulls.toList();
    if (valid.length <= maxApiStops) return valid;
    final order = List.generate(valid.length, (i) => i)
      ..sort(
        (a, b) => (valid[b]['mean_decel_mps2'] as double).compareTo(
          valid[a]['mean_decel_mps2'] as double,
        ),
      );
    final kept = order.take(maxApiStops).toList()..sort();
    return [for (final i in kept) valid[i]];
  }

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

  /// Distinct GPS fixes needed inside the top-speed window, so one wild
  /// fix carried forward by dead reckoning is never "sustained".
  static const _minTopFixes = 3;
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

  /// Only speed backed by fresh GPS counts (not dead reckoning through a
  /// gap), and the window must hold several distinct fixes.
  void _updateTop(MotionState s) {
    if (s.speedSource != SpeedSource.gps) {
      _speedRun.clear();
      return;
    }
    _speedRun.addLast(s);
    while (_speedRun.length > 1 &&
        _speedRun.first.t < s.t - _topWindowS - _tol) {
      _speedRun.removeFirst();
    }
    if (s.t - _speedRun.first.t < _topWindowS - _tol) return;
    final from = s.t - _topWindowS - _tol;
    var minSpeed = double.infinity;
    final fixes = <double>{};
    for (final x in _speedRun) {
      if (x.t < from) continue;
      if (x.speedKmh < minSpeed) minSpeed = x.speedKmh;
      final fix = x.lastFix;
      if (fix != null && fix.t >= from) fixes.add(fix.t);
    }
    if (fixes.length < _minTopFixes) return;
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
