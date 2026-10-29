import 'dart:collection';
import 'dart:math' as math;

import '../math/vec3.dart';

const double gravity = 9.80665;

double radToDeg(double rad) => rad * 180 / math.pi;
double degToRad(double deg) => deg * math.pi / 180;

/// First-order low-pass smoothing factor for a sample spaced [dt] apart.
double lowPassAlpha(double dt, double timeConstant) =>
    timeConstant <= 0 ? 1 : dt / (timeConstant + dt);

/// Decides whether the bike is standing still from the last second of IMU
/// data. Tolerates engine vibration: vibration averages out of the mean
/// rotation rate and mean gravity-free acceleration, while pulling away
/// smoothly (no rotation, |accel| barely changes) does not.
class StillnessDetector {
  StillnessDetector({
    this.window = 1.0,
    this.maxMeanGyro = 0.06,
    this.maxAccelStdDev = 0.8,
    this.maxMeanLinear = 0.5,
  });

  final double window;
  final double maxMeanGyro;
  final double maxAccelStdDev;
  final double maxMeanLinear;

  final ListQueue<(double, Vec3)> _gyro = ListQueue();
  final ListQueue<(double, double)> _accel = ListQueue();
  final ListQueue<(double, Vec3)> _linear = ListQueue();
  double? _stillSince;

  void addGyro(Vec3 rate, double t) {
    _gyro.addLast((t, rate));
    while (_gyro.isNotEmpty && _gyro.first.$1 < t - window) {
      _gyro.removeFirst();
    }
    _refresh(t);
  }

  void addAccel(Vec3 accel, double t) {
    _accel.addLast((t, accel.length));
    while (_accel.isNotEmpty && _accel.first.$1 < t - window) {
      _accel.removeFirst();
    }
    _refresh(t);
  }

  void addLinear(Vec3 accel, double t) {
    _linear.addLast((t, accel));
    while (_linear.isNotEmpty && _linear.first.$1 < t - window) {
      _linear.removeFirst();
    }
  }

  bool get isStill => _stillSince != null;

  /// Seconds the bike has been continuously still at time [t].
  double stillFor(double t) => _stillSince == null ? 0 : t - _stillSince!;

  void _refresh(double t) {
    final still = _evaluate();
    if (still) {
      _stillSince ??= t;
    } else {
      _stillSince = null;
    }
  }

  bool _evaluate() {
    // Need most of a window before judging. Phones without a gyroscope are
    // judged on the accelerometer alone.
    if (_accel.length < 10) return false;
    if (_accel.last.$1 - _accel.first.$1 < window * 0.8) return false;
    if (_gyro.isNotEmpty) {
      if (_gyro.length < 10) return false;
      if (_gyro.last.$1 - _gyro.first.$1 < window * 0.8) return false;
      var sum = Vec3.zero;
      for (final (_, g) in _gyro) {
        sum += g;
      }
      if ((sum / _gyro.length.toDouble()).length > maxMeanGyro) return false;
    }

    if (_linear.isNotEmpty) {
      // Short window so a push is noticed within a few hundred ms.
      final since = _linear.last.$1 - 0.3;
      var lin = Vec3.zero;
      var n = 0;
      for (final (t, a) in _linear) {
        if (t < since) continue;
        lin += a;
        n++;
      }
      if ((lin / n.toDouble()).length > maxMeanLinear) return false;
    }

    var mean = 0.0;
    for (final (_, a) in _accel) {
      mean += a;
    }
    mean /= _accel.length;
    var variance = 0.0;
    for (final (_, a) in _accel) {
      variance += (a - mean) * (a - mean);
    }
    variance /= _accel.length;
    return math.sqrt(variance) <= maxAccelStdDev;
  }
}

/// Learns which phone axis points towards the front wheel.
///
/// Over each GPS interval the mean gravity-free acceleration is compared to
/// the GPS speed change: speeding up pushes it forward, braking pushes it
/// backward. Multiplying by the sign of dv/dt makes both point forward.
/// Old evidence decays so a phone that rotates in its mount is re-learned.
class ForwardAxisLearner {
  ForwardAxisLearner({this.decay = 0.97});

  final double decay;

  Vec3 _sum = Vec3.zero;
  double _weight = 0;
  int _samples = 0;

  int get samples => _samples;

  /// 1.0 when every sample agreed on the direction.
  double get consistency => _weight == 0 ? 0 : _sum.length / _weight;

  bool get isConfident => _samples >= 4 && consistency > 0.7;

  Vec3? get forward => isConfident ? _sum.normalized() : null;

  /// [meanLinearAccel] is in the phone frame (gravity removed), [dvdt] in
  /// m/s² from GPS, [up] the current mount up axis.
  bool add(Vec3 meanLinearAccel, double dvdt, Vec3 up) {
    if (dvdt.abs() < 0.8) return false;
    final horizontal = meanLinearAccel.rejectFrom(up);
    if (horizontal.length < 0.4) return false;
    // Reject intervals where the IMU and GPS disagree badly on magnitude
    // (bumps, GPS glitches).
    final ratio = horizontal.length / dvdt.abs();
    if (ratio < 0.4 || ratio > 2.5) return false;

    final w = math.min(dvdt.abs(), 4.0);
    _sum = _sum * decay + horizontal.normalized() * (dvdt.sign * w);
    _weight = _weight * decay + w;
    _samples++;
    return true;
  }

  void reset() {
    _sum = Vec3.zero;
    _weight = 0;
    _samples = 0;
  }
}

/// Lean angle from a complementary filter: the gyro roll rate is integrated
/// for fast response and pulled towards a slow but drift-free reference.
class LeanEstimator {
  LeanEstimator({this.gain = 1.0});

  /// Gyro scale correction learned during calibration.
  double gain;

  /// Radians, positive = leaning right.
  double lean = 0;

  void predict(double rollRate, double dt) {
    lean += gain * rollRate * dt;
  }

  void correct(double reference, double dt, double timeConstant) {
    lean += (reference - lean) * lowPassAlpha(dt, timeConstant);
  }

  void reset([double value = 0]) => lean = value;

  /// Lean of a coordinated turn: tan(lean) = v·ω / g, where ω is the yaw rate
  /// about the world vertical. The phone measures yaw about the bike's tilted
  /// up axis, which is ω·cos(lean), so that is undone with [currentLean].
  /// Positive yaw is a left turn, which needs a left (negative) lean.
  static double physicsLean(
    double speedMps,
    double yawRateUp,
    double currentLean,
  ) {
    final c = math.cos(currentLean).clamp(0.5, 1.0);
    return math.atan(-speedMps * (yawRateUp / c) / gravity);
  }
}

enum SpeedSource { none, gps, deadReckoning, stale }

/// GPS Doppler speed, filled in between ~1 Hz fixes by integrating the
/// calibrated forward acceleration.
class SpeedEstimator {
  SpeedEstimator({this.maxDeadReckoning = 4.0});

  /// Seconds after the last fix during which acceleration integration is
  /// trusted.
  final double maxDeadReckoning;

  double speedMps = 0;
  double? _lastFixT;

  SpeedSource sourceAt(double t) {
    final last = _lastFixT;
    if (last == null) return SpeedSource.none;
    final age = t - last;
    if (age <= 1.5) return SpeedSource.gps;
    if (age <= maxDeadReckoning) return SpeedSource.deadReckoning;
    return SpeedSource.stale;
  }

  bool isReliable(double t) {
    final s = sourceAt(t);
    return s == SpeedSource.gps || s == SpeedSource.deadReckoning;
  }

  /// Below this a GPS speed can be position noise on a parked phone.
  static const double noiseCeilingMps = 4.0;

  /// GPS accuracy (m) worse than this makes low speeds untrustworthy.
  static const double poorAccuracyM = 10;

  void onGps(
    double gpsSpeedMps,
    double t, {
    double? speedAccuracyMps,
    double? accuracyM,
    bool phoneStill = false,
  }) {
    if (!gpsSpeedMps.isFinite || gpsSpeedMps < 0) return;
    speedMps = _isNoise(gpsSpeedMps, speedAccuracyMps, accuracyM, phoneStill)
        ? 0
        : gpsSpeedMps;
    _lastFixT = t;
  }

  /// A parked phone's GPS still reports speed: ~0.1-0.3 m/s with a good fix,
  /// and walking pace or more indoors, where the position wanders.
  static bool _isNoise(
    double v,
    double? speedAccuracy,
    double? accuracy,
    bool phoneStill,
  ) {
    if (v < 0.4) return true;
    // Not distinguishable from zero by the receiver's own estimate.
    if (speedAccuracy != null && speedAccuracy > 0 && v <= speedAccuracy) {
      return true;
    }
    // The phone isn't moving at all and the fix is too poor to argue.
    final poorFix = accuracy == null || accuracy > poorAccuracyM;
    return phoneStill && poorFix && v < noiseCeilingMps;
  }

  void onForwardAccel(double accel, double t, double dt) {
    final last = _lastFixT;
    if (last == null || t - last > maxDeadReckoning) return;
    speedMps = math.max(0, speedMps + accel * dt);
  }
}

/// Keeps re-learning what "riding straight" reads as.
///
/// A motorcycle going straight at steady speed is upright relative to
/// gravity (even on cambered roads), so the gravity reading at those moments
/// is the true bike-up axis in the phone frame. This corrects a calibration
/// done on the side stand, a phone mounted at an odd angle, and a phone that
/// slips in its mount mid-ride.
class StraightLineNormalizer {
  StraightLineNormalizer({required this.timeConstant});

  /// How quickly the up axis follows the straight-line reading (seconds).
  double timeConstant;

  /// Roll error beyond which the mount is assumed to have moved and is
  /// snapped instead of slowly corrected.
  static const double shiftRoll = 0.17; // ~10°
  static const double shiftPitch = 0.26; // ~15°

  Vec3? _mean;
  double _qualified = 0;
  int realignments = 0;

  // A suspected mount shift: the reading has been far off for a while.
  Vec3 _shiftSum = Vec3.zero;
  int _shiftN = 0;
  double _shiftTime = 0;

  /// Feeds one IMU step. Returns the corrected up axis, or null when the
  /// conditions for "straight and steady" are not met.
  Vec3? update({
    required Vec3 gravityReading,
    required Vec3 up,
    required Vec3 forward,
    required double dt,
    required bool qualifies,
  }) {
    if (!qualifies) {
      _qualified = 0;
      _mean = null;
      _resetShift();
      return null;
    }

    final right = forward.cross(up);
    final roll = math.atan2(-gravityReading.dot(right), gravityReading.dot(up));
    final pitch = math.atan2(
      gravityReading.dot(forward),
      gravityReading.dot(up),
    );

    if (roll.abs() > shiftRoll || pitch.abs() > shiftPitch) {
      // Way off: the phone moved. Collect a clean average of the new pose
      // (skipping the transition) and snap to it.
      _mean = null;
      _qualified = 0;
      _shiftTime += dt;
      if (_shiftTime > 0.5) {
        _shiftSum += gravityReading;
        _shiftN++;
      }
      if (_shiftTime < 2.5 || _shiftN == 0) return null;
      final g = _shiftSum / _shiftN.toDouble();
      _resetShift();
      realignments++;
      return pitch.abs() > shiftPitch
          ? g.normalized()
          : g.rejectFrom(forward).normalized();
    }
    _resetShift();

    _mean = _mean == null
        ? gravityReading
        : _mean!.lerp(gravityReading, lowPassAlpha(dt, 2.0));
    _qualified += dt;
    if (_qualified < 2.0) return null;

    // Only the roll part is corrected: pitch legitimately changes on hills,
    // while a bike riding straight is never rolled.
    final mean = _mean!;
    final meanRoll = math.atan2(-mean.dot(right), mean.dot(up));
    final target = mean.rejectFrom(forward).normalized();
    // Large, consistent offsets (side stand, crooked holder) converge fast;
    // the slow constant only filters small noise once close.
    final tau = meanRoll.abs() > 0.05
        ? math.min(timeConstant, 3.0)
        : timeConstant;
    return up.lerp(target, lowPassAlpha(dt, tau)).normalized();
  }

  void _resetShift() {
    _shiftSum = Vec3.zero;
    _shiftN = 0;
    _shiftTime = 0;
  }
}
