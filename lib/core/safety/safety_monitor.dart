import 'dart:math' as math;

import '../fusion/estimators.dart';
import '../fusion/motion_pipeline.dart';
import '../fusion/mount_orientation.dart';
import '../math/vec3.dart';
import 'safety_baseline.dart';
import 'safety_tuning.dart';
import 'wobble_detector.dart';

enum HazardKind {
  /// Crash or bike down. The only kind that escalates to a call.
  crash,

  /// Speed wobble / tank slapper.
  wobble,

  /// Hard jolt while riding (pothole, kerb, object) that did not end the
  /// ride.
  impact,

  /// Lean beyond what a road tyre can normally hold.
  extremeLean;

  bool get critical => this == HazardKind.crash;
}

/// Something the rider should know about, with the riding context at the
/// moment it was detected.
class Hazard {
  const Hazard({
    required this.kind,
    required this.t,
    required this.speedKmh,
    required this.leanDeg,
    this.peakAccelG,
    this.wobbleHz,
    this.wobbleRms,
    this.latitude,
    this.longitude,
  });

  final HazardKind kind;

  /// Monotonic seconds, same clock as the sensor readings.
  final double t;

  /// Speed shortly before the event (for a crash: before the impact).
  final double speedKmh;
  final double leanDeg;
  final double? peakAccelG;
  final double? wobbleHz;

  /// Strength of the oscillation, rad/s RMS.
  final double? wobbleRms;
  final double? latitude;
  final double? longitude;
}

/// Watches the raw IMU stream and the processed motion state for crashes,
/// speed wobbles and other anomalies.
///
/// A crash is either
/// * a hard **impact** while riding, after which the bike (or the phone that
///   flew off it) stays stopped, or
/// * the **bike down**: lying on its side shortly after riding, with or
///   without a big impact (a low-side slide often has none).
///
/// Crash detection only arms once the bike has moved at speed, and disarms
/// after firing until it moves again, so a bike tipping over in the garage
/// or one that is still lying down never re-triggers.
///
/// It also records what normal riding looks like ([takeNoise]) so the
/// thresholds can be learned per bike and mount (see [SafetyBaseline]).
class SafetyMonitor {
  SafetyMonitor({
    required this.onHazard,
    this.impactG = SafetyTuning.defaultImpactG,
    this.armSpeedKmh = 15,
    this.ridingSpeedKmh = 10,
    this.stopSpeedKmh = 5,
    this.downTiltDeg = 60,
    this.downFor = 3.0,
    this.stoppedFor = 5.0,
    this.confirmWithin = 15.0,
    this.recentMotion = 60.0,
    this.wobbleMinSpeedKmh = 30,
    this.wobbleFor = 0.6,
    this.extremeLeanDeg = SafetyTuning.defaultExtremeLeanDeg,
    this.extremeLeanFor = 0.5,
    this.leanMinSpeedKmh = 20,
    this.warningCooldown = 10.0,
    this.noiseMinSpeedKmh = 20,
    WobbleDetector? wobble,
  }) : _wobble = wobble ?? WobbleDetector();

  /// A monitor using thresholds learned for this bike and mount.
  factory SafetyMonitor.tuned(
    SafetyTuning tuning, {
    required void Function(Hazard hazard) onHazard,
  }) => SafetyMonitor(
    onHazard: onHazard,
    impactG: tuning.impactG,
    extremeLeanDeg: tuning.extremeLeanDeg,
    wobble: WobbleDetector(
      minRms: tuning.wobbleMinRms,
      maxHz: tuning.wobbleMaxHz,
    ),
  );

  final void Function(Hazard hazard) onHazard;

  /// Total acceleration (g) that counts as an impact.
  final double impactG;

  /// Speed that arms crash detection.
  final double armSpeedKmh;

  /// Above this speed after an impact, the ride is going on.
  final double ridingSpeedKmh;
  final double stopSpeedKmh;

  /// Angle between gravity and the bike's up axis that means "on its side".
  /// Hard braking tilts the reading forward by at most ~45°.
  final double downTiltDeg;

  /// Seconds lying down before it counts as a crash.
  final double downFor;

  /// Seconds stopped after an impact before it counts as a crash.
  final double stoppedFor;

  /// Seconds after an impact within which the stop must happen.
  final double confirmWithin;

  /// The bike must have been moving this recently for "bike down".
  final double recentMotion;

  final double wobbleMinSpeedKmh;
  final double wobbleFor;
  final double extremeLeanDeg;
  final double extremeLeanFor;
  final double leanMinSpeedKmh;

  /// Minimum seconds between two warnings of the same kind.
  final double warningCooldown;

  /// Riding faster than this counts towards the normal-riding statistics.
  final double noiseMinSpeedKmh;

  final WobbleDetector _wobble;

  /// Seconds around a hazard that are left out of the statistics, so a
  /// real wobble never teaches the app that wobbles are normal.
  static const _quietMargin = 5.0;
  RideNoise _noise = RideNoise();
  final List<(int, double, double)> _pendingSeconds = [];
  final List<int> _gyroPerSecond = [];
  int? _second;
  double _secWobble = 0;
  double _secPeakG = 0;
  int _secGyro = 0;
  bool _secRiding = false;
  bool _secExcluded = false;
  double _lastHazardT = double.negativeInfinity;

  MotionState? _state;
  Vec3? _gravityLp;
  double? _lastAccelT;
  double _lastMovingT = double.negativeInfinity;
  double _crashFiredAt = double.negativeInfinity;
  final Map<HazardKind, double> _lastEmitted = {};

  double? _impactT;
  double _impactPeakG = 0;
  double _impactSpeedKmh = 0;
  bool _impactReported = false;

  double? _stoppedSince;
  double? _downSince;
  double _downSpeedKmh = 0;
  double? _wobbleSince;
  double? _leanSince;

  /// Angle between gravity and the bike's up axis, degrees.
  double tiltDeg = 0;

  WobbleDetector get wobble => _wobble;

  /// Raw accelerometer including gravity, phone frame, m/s².
  void addAccel(Vec3 accel, double t) {
    if (!accel.isFinite) return;
    _rollSecond(t);
    final dt = _lastAccelT == null
        ? 0.02
        : (t - _lastAccelT!).clamp(0.001, 0.2).toDouble();
    _lastAccelT = t;
    _gravityLp = _gravityLp == null
        ? accel
        : _gravityLp!.lerp(accel, lowPassAlpha(dt, 0.5));

    final g = accel.length / gravity;
    _secPeakG = math.max(_secPeakG, g);
    if (g < impactG || t - _lastMovingT > 3) return;
    final impactT = _impactT;
    if (impactT != null && t - impactT < 1.0) {
      _impactPeakG = math.max(_impactPeakG, g);
      return;
    }
    _impactT = t;
    _impactPeakG = g;
    _impactSpeedKmh = _state?.speedKmh ?? 0;
    _impactReported = false;
  }

  /// Gyroscope, phone frame, rad/s.
  void addGyro(Vec3 rate, double t, double dt) {
    if (!rate.isFinite) return;
    _rollSecond(t);
    _secGyro++;
    final wobbling = _wobble.add(rate, t, dt);
    if (_wobble.frequencyHz >= _wobble.minHz &&
        _wobble.frequencyHz <= _wobble.maxHz) {
      _secWobble = math.max(_secWobble, _wobble.rms);
    }
    if (!wobbling) {
      _wobbleSince = null;
      return;
    }
    _secExcluded = true;
    _wobbleSince ??= t;
    final s = _state;
    if (s != null &&
        t - _wobbleSince! >= wobbleFor &&
        s.speedReliable &&
        s.speedKmh >= wobbleMinSpeedKmh) {
      _emit(
        HazardKind.wobble,
        t,
        wobbleHz: _wobble.frequencyHz,
        wobbleRms: _wobble.rms,
      );
    }
  }

  /// Processed state (10 Hz) and the current mount, for speed, lean and the
  /// bike's up axis.
  void update(MotionState s, MountOrientation? mount) {
    _state = s;
    final t = s.t;
    if (s.speedReliable && s.speedKmh >= noiseMinSpeedKmh) {
      _secRiding = true;
    } else {
      _secExcluded = true;
    }
    final riding = s.speedReliable && s.speedKmh >= ridingSpeedKmh;
    if (s.speedReliable && s.speedKmh >= armSpeedKmh) _lastMovingT = t;
    final armed = _lastMovingT > _crashFiredAt;

    final gravityLp = _gravityLp;
    tiltDeg = mount == null || gravityLp == null
        ? 0
        : radToDeg(gravityLp.angleTo(mount.up));
    final down = mount != null && tiltDeg >= downTiltDeg;
    if (down && _downSince == null) _downSpeedKmh = s.speedKmh;
    _downSince = down ? (_downSince ?? t) : null;
    // Lost GPS after a fall is common; stillness or lying down count too.
    final stopped =
        s.isStill || (s.speedReliable && s.speedKmh < stopSpeedKmh) || down;
    _stoppedSince = stopped ? (_stoppedSince ?? t) : null;

    final impactT = _impactT;
    if (impactT != null) {
      if (!_impactReported && t - impactT >= 0.2) {
        _impactReported = true;
        _emit(
          HazardKind.impact,
          t,
          speedKmh: _impactSpeedKmh,
          peakAccelG: _impactPeakG,
        );
      }
      final stoppedSince = _stoppedSince;
      if (riding && t - impactT > 3) {
        _impactT = null; // Rode on: it was a pothole, not a crash.
      } else if (armed &&
          stoppedSince != null &&
          t - math.max(stoppedSince, impactT) >= stoppedFor) {
        _crash(t, _impactSpeedKmh, _impactPeakG);
        return;
      } else if (t - impactT > confirmWithin) {
        _impactT = null;
      }
    }

    final downSince = _downSince;
    if (armed &&
        downSince != null &&
        t - downSince >= downFor &&
        !riding &&
        t - _lastMovingT <= recentMotion) {
      _crash(t, _downSpeedKmh, null);
      return;
    }

    if (s.speedReliable &&
        s.speedKmh >= leanMinSpeedKmh &&
        s.leanDeg.abs() >= extremeLeanDeg) {
      _leanSince ??= t;
      if (t - _leanSince! >= extremeLeanFor) _emit(HazardKind.extremeLean, t);
    } else {
      _leanSince = null;
    }
  }

  void _crash(double t, double speedKmh, double? peakG) {
    _crashFiredAt = t;
    _impactT = null;
    _emit(HazardKind.crash, t, speedKmh: speedKmh, peakAccelG: peakG);
  }

  void _emit(
    HazardKind kind,
    double t, {
    double? speedKmh,
    double? peakAccelG,
    double? wobbleHz,
    double? wobbleRms,
  }) {
    _excludeAround(t);
    final last = _lastEmitted[kind];
    if (!kind.critical && last != null && t - last < warningCooldown) return;
    _lastEmitted[kind] = t;
    final s = _state;
    onHazard(
      Hazard(
        kind: kind,
        t: t,
        speedKmh: speedKmh ?? s?.speedKmh ?? 0,
        leanDeg: s?.leanDeg ?? 0,
        peakAccelG: peakAccelG,
        wobbleHz: wobbleHz,
        wobbleRms: wobbleRms,
        latitude: s?.lastFix?.latitude,
        longitude: s?.lastFix?.longitude,
      ),
    );
  }

  // ------------------------------------------------- normal-riding statistics

  /// Normal-riding statistics gathered since the last call. Call when the
  /// ride ends.
  RideNoise takeNoise() {
    _rollSecond(double.infinity);
    for (final second in _pendingSeconds) {
      _noise.wobbleRms.add(second.$2);
      _noise.peakG.add(second.$3);
    }
    _pendingSeconds.clear();
    final counts = List.of(_gyroPerSecond)..sort();
    final noise = RideNoise(
      wobbleRms: _noise.wobbleRms,
      peakG: _noise.peakG,
      // Median: the first and last seconds are partial.
      imuHz: counts.length < 5 ? null : counts[counts.length ~/ 2].toDouble(),
    );
    _noise = RideNoise();
    _gyroPerSecond.clear();
    return noise;
  }

  /// Closes the current second when [t] is in a new one.
  void _rollSecond(double t) {
    final second = t.isFinite ? t.floor() : null;
    final current = _second;
    if (current != null && second == current) return;
    if (current != null) {
      if (_secGyro > 0) _gyroPerSecond.add(_secGyro);
      final usable =
          _secRiding && !_secExcluded && current >= _lastHazardT + _quietMargin;
      if (usable) _pendingSeconds.add((current, _secWobble, _secPeakG));
    }
    _second = second;
    _secWobble = 0;
    _secPeakG = 0;
    _secGyro = 0;
    _secRiding = false;
    _secExcluded = false;
    if (second == null) return;
    // Seconds far enough back can no longer be near a hazard.
    while (_pendingSeconds.isNotEmpty &&
        _pendingSeconds.first.$1 + 1 <= second - _quietMargin) {
      final s = _pendingSeconds.removeAt(0);
      _noise.wobbleRms.add(s.$2);
      _noise.peakG.add(s.$3);
    }
  }

  void _excludeAround(double t) {
    _lastHazardT = math.max(_lastHazardT, t);
    _secExcluded = true;
    _pendingSeconds.removeWhere((s) => s.$1 + 1 >= t - _quietMargin);
  }
}
