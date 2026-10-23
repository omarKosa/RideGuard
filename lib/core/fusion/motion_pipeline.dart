import 'dart:math' as math;

import '../math/vec3.dart';
import 'estimators.dart';
import 'mount_orientation.dart';

/// Sensor-fusion parameters produced by calibration.
class FusionParams {
  const FusionParams({
    required this.mount,
    this.gyroBias = Vec3.zero,
    this.linearAccelBias = Vec3.zero,
    this.leanGain = 1.0,
  });

  factory FusionParams.fromJson(Map<String, dynamic> json) => FusionParams(
    mount: MountOrientation.fromJson(json['mount'] as Map<String, dynamic>),
    gyroBias: Vec3.fromList(json['gyro_bias'] as List<dynamic>),
    linearAccelBias: Vec3.fromList(json['linear_accel_bias'] as List<dynamic>),
    leanGain: (json['lean_gain'] as num).toDouble(),
  );

  final MountOrientation mount;
  final Vec3 gyroBias;
  final Vec3 linearAccelBias;
  final double leanGain;

  Map<String, dynamic> toJson() => {
    'mount': mount.toJson(),
    'gyro_bias': gyroBias.toList(),
    'linear_accel_bias': linearAccelBias.toList(),
    'lean_gain': leanGain,
  };
}

class GpsFix {
  const GpsFix({
    required this.t,
    required this.speedMps,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.speedAccuracyMps,
  });

  /// Monotonic seconds, same clock as the IMU readings.
  final double t;
  final double speedMps;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final double? speedAccuracyMps;
}

/// Everything the UI, analysis and calibration need from one moment.
class MotionState {
  const MotionState({
    required this.t,
    required this.speedKmh,
    required this.speedSource,
    required this.leanDeg,
    required this.physicsLeanDeg,
    required this.accelLeanDeg,
    required this.rollRate,
    required this.yawRate,
    required this.forwardAccel,
    required this.lateralAccel,
    required this.isStill,
    required this.stillFor,
    required this.mountReady,
    required this.forwardLearned,
    required this.straightOffsetDeg,
    required this.mountRealignments,
    this.lastFix,
  });

  final double t;
  final double speedKmh;
  final SpeedSource speedSource;

  /// Calibrated, normalized lean. Positive = right.
  final double leanDeg;

  /// Lean implied by speed and yaw rate (coordinated turn).
  final double physicsLeanDeg;

  /// Lean implied by gravity alone (valid only when not turning).
  final double accelLeanDeg;

  /// Bias-free roll and yaw rates in the bike frame, rad/s.
  final double rollRate;
  final double yawRate;

  /// Gravity-free acceleration along the bike's forward/right axes, m/s².
  final double forwardAccel;
  final double lateralAccel;

  final bool isStill;
  final double stillFor;
  final bool mountReady;

  /// True once the forward axis comes from real acceleration, not a guess.
  final bool forwardLearned;

  /// How far (deg) the learned "straight" reading has moved from the
  /// calibrated one. Non-zero means the app normalized a tilted mount.
  final double straightOffsetDeg;
  final int mountRealignments;
  final GpsFix? lastFix;

  bool get speedReliable =>
      speedSource == SpeedSource.gps ||
      speedSource == SpeedSource.deadReckoning;
}

/// Turns raw phone-frame IMU and GPS readings into bike-frame motion.
///
/// Without calibration it bootstraps itself: the first still period gives
/// the up axis and gyro bias, acceleration gives the forward axis, and
/// straight riding refines the upright reference. Calibration just makes
/// sure each of those happens under controlled conditions.
class MotionPipeline {
  MotionPipeline({FusionParams? params, this.learningMode = false})
    : _mount = params?.mount,
      _referenceMount = params?.mount,
      _gyroBias = params?.gyroBias ?? Vec3.zero,
      _linearBias = params?.linearAccelBias ?? Vec3.zero,
      _forwardLearned = params != null,
      _lean = LeanEstimator(gain: params?.leanGain ?? 1.0),
      _normalizer = StraightLineNormalizer(
        timeConstant: learningMode ? 3.0 : 20.0,
      );

  /// Calibration mode: learns biases and axes aggressively.
  final bool learningMode;

  final StillnessDetector _still = StillnessDetector();
  final ForwardAxisLearner _forward = ForwardAxisLearner();
  final SpeedEstimator _speed = SpeedEstimator();
  final LeanEstimator _lean;
  final StraightLineNormalizer _normalizer;

  MountOrientation? _mount;
  MountOrientation? _referenceMount;
  Vec3 _gyroBias;
  Vec3 _linearBias;
  bool _forwardLearned;

  Vec3? _gravityLp;
  double? _lastAccelT;
  Vec3 _linearLp = Vec3.zero;
  double? _lastLinearT;
  Vec3 _linearSum = Vec3.zero;
  int _linearCount = 0;
  GpsFix? _lastFix;

  double _rollRate = 0;
  double _yawRate = 0;
  double _physicsLean = 0;
  double _accelLean = 0;
  double _t = 0;

  // Still-period accumulators for calibration capture.
  Vec3 _stillGravitySum = Vec3.zero;
  Vec3 _stillGyroSum = Vec3.zero;
  Vec3 _stillLinearSum = Vec3.zero;
  int _stillGravityN = 0;
  int _stillGyroN = 0;
  int _stillLinearN = 0;

  MountOrientation? get mount => _mount;
  Vec3 get gyroBias => _gyroBias;
  Vec3 get linearAccelBias => _linearBias;
  double get leanGain => _lean.gain;
  bool get forwardLearned => _forwardLearned;
  ForwardAxisLearner get forwardLearner => _forward;

  FusionParams? get params => _mount == null
      ? null
      : FusionParams(
          mount: _mount!,
          gyroBias: _gyroBias,
          linearAccelBias: _linearBias,
          leanGain: _lean.gain,
        );

  // ---------------------------------------------------------------- inputs

  /// Raw accelerometer including gravity, phone frame, m/s².
  void addAccel(Vec3 accel, double t) {
    if (!accel.isFinite) return;
    _t = math.max(_t, t);
    _still.addAccel(accel, t);
    final dt = _lastAccelT == null
        ? 0.02
        : (t - _lastAccelT!).clamp(0.001, 0.2).toDouble();
    _lastAccelT = t;
    _gravityLp = _gravityLp == null
        ? accel
        : _gravityLp!.lerp(accel, lowPassAlpha(dt, 0.3));

    if (_isStill(t)) {
      _stillGravitySum += accel;
      _stillGravityN++;
      // Bootstrap: without calibration take the first steady second as up.
      if (_mount == null && _stillFor(t) >= 1.0) {
        _mount = MountOrientation.provisional(_gravityLp!);
        _referenceMount = _mount;
      }
    } else {
      _resetStillAccumulators();
    }
  }

  /// Gravity-free acceleration, phone frame, m/s².
  void addLinearAccel(Vec3 accel, double t) {
    if (!accel.isFinite) return;
    _t = math.max(_t, t);
    final dt = _lastLinearT == null
        ? 0.02
        : (t - _lastLinearT!).clamp(0.001, 0.2).toDouble();
    _lastLinearT = t;

    _still.addLinear(accel - _linearBias, t);
    if (_isStill(t)) {
      _stillLinearSum += accel;
      _stillLinearN++;
    }

    final corrected = accel - _linearBias;
    _linearLp = _linearLp.lerp(corrected, lowPassAlpha(dt, 0.15));
    _linearSum += corrected;
    _linearCount++;

    final mount = _mount;
    if (mount != null && _forwardLearned) {
      _speed.onForwardAccel(mount.forwardOf(_linearLp), t, dt);
    }
  }

  /// Gyroscope, phone frame, rad/s. [dt] is the time since the previous
  /// gyro sample.
  void addGyro(Vec3 rate, double t, double dt) {
    if (!rate.isFinite) return;
    _t = math.max(_t, t);
    dt = dt.clamp(0.001, 0.1).toDouble();
    _still.addGyro(rate, t);

    final parked = _speed.speedMps < 0.5 || !_speed.isReliable(t);
    if (_isStill(t) && parked) {
      _stillGyroSum += rate;
      _stillGyroN++;
      // Slowly track gyro bias whenever parked (it drifts with temperature).
      _gyroBias = _gyroBias.lerp(
        rate,
        lowPassAlpha(dt, learningMode ? 1.0 : 10.0),
      );
    }

    final mount = _mount;
    if (mount == null) return;

    final w = rate - _gyroBias;
    _rollRate = mount.forwardOf(w);
    _yawRate = mount.upOf(w);
    _lean.predict(_rollRate, dt);

    final gravityLp = _gravityLp;
    _accelLean = gravityLp == null ? 0 : mount.rollOf(gravityLp);
    final v = _speed.speedMps;
    final reliable = _speed.isReliable(t);
    _physicsLean = LeanEstimator.physicsLean(v, _yawRate, _lean.lean);

    if (reliable && v > 4.0) {
      _lean.correct(_physicsLean, dt, 1.5);
    } else if (_isStill(t) || (reliable && _linearLp.length < 1.0)) {
      // Slow or stopped: no centripetal force, gravity tells the truth -
      // unless we are pulling away or braking, which tilts the reading.
      _lean.correct(_accelLean, dt, _isStill(t) ? 0.5 : 1.0);
    } else if (reliable) {
      // Accelerating at low speed: trust the gyro for these few seconds.
    } else {
      // Moving without speed: only drift-correct towards upright.
      _lean.correct(0, dt, 8.0);
    }

    _normalize(mount, dt, t);
  }

  void addGps(GpsFix fix) {
    _t = math.max(_t, fix.t);
    final prev = _lastFix;
    _speed.onGps(fix.speedMps, fix.t);
    _lastFix = fix;

    final mount = _mount;
    if (prev != null && mount != null && _linearCount > 0) {
      final interval = fix.t - prev.t;
      if (interval > 0.3 && interval < 3.0 && _yawRate.abs() < 0.15) {
        final dvdt = (fix.speedMps - prev.speedMps) / interval;
        final meanAccel = _linearSum / _linearCount.toDouble();
        if (_forward.add(meanAccel, dvdt, mount.up)) _applyLearnedForward();
      }
    }
    _linearSum = Vec3.zero;
    _linearCount = 0;
  }

  // ------------------------------------------------------------ calibration

  /// Locks in up axis, gyro bias and accelerometer bias from the current
  /// still period. Returns false if there is not enough still data.
  bool captureStillReference() {
    if (_stillGravityN < 20 || _stillGyroN < 20) return false;
    final up = _stillGravitySum / _stillGravityN.toDouble();
    _gyroBias = _stillGyroSum / _stillGyroN.toDouble();
    if (_stillLinearN >= 20) {
      _linearBias = _stillLinearSum / _stillLinearN.toDouble();
    }
    _mount = _mount == null
        ? MountOrientation.provisional(up)
        : _mount!.withUp(up);
    _referenceMount = _mount;
    _lean.reset();
    return true;
  }

  void setLeanGain(double gain) => _lean.gain = gain;

  /// Reverses the forward axis (and with it the sign of lean).
  void flipForward() {
    _mount = _mount?.flipped();
    _referenceMount = _referenceMount?.flipped();
    _lean.reset(-_lean.lean);
  }

  // ----------------------------------------------------------------- output

  MotionState snapshot() {
    final mount = _mount;
    final reference = _referenceMount;
    var offset = 0.0;
    if (mount != null && reference != null) {
      offset = radToDeg(reference.rollOf(mount.up));
    }
    return MotionState(
      t: _t,
      speedKmh: _speed.speedMps * 3.6,
      speedSource: _speed.sourceAt(_t),
      leanDeg: mount == null ? 0 : radToDeg(_lean.lean),
      physicsLeanDeg: radToDeg(_physicsLean),
      accelLeanDeg: radToDeg(_accelLean),
      rollRate: _rollRate,
      yawRate: _yawRate,
      forwardAccel: mount?.forwardOf(_linearLp) ?? 0,
      lateralAccel: mount?.rightOf(_linearLp) ?? 0,
      isStill: _isStill(_t),
      stillFor: _stillFor(_t),
      mountReady: mount != null,
      forwardLearned: _forwardLearned,
      straightOffsetDeg: offset,
      mountRealignments: _normalizer.realignments,
      lastFix: _lastFix,
    );
  }

  // --------------------------------------------------------------- internal

  void _applyLearnedForward() {
    final learned = _forward.forward;
    final mount = _mount;
    if (learned == null || mount == null) return;
    final candidate = mount.withForward(learned);
    if (!_forwardLearned ||
        candidate.forward.angleTo(mount.forward) > degToRad(3)) {
      _mount = candidate;
      _referenceMount = _referenceMount?.withForward(learned);
      _forwardLearned = true;
    }
  }

  void _normalize(MountOrientation mount, double dt, double t) {
    final gravityLp = _gravityLp;
    if (gravityLp == null) return;
    final qualifies =
        _speed.isReliable(t) &&
        _speed.speedMps >= 5.5 &&
        _yawRate.abs() < 0.04 &&
        _rollRate.abs() < 0.06 &&
        // Total, not just forward: the forward axis may still be a guess.
        _linearLp.length < 0.7 &&
        _lean.lean.abs() < degToRad(6);
    final before = _normalizer.realignments;
    final newUp = _normalizer.update(
      gravityReading: gravityLp,
      up: mount.up,
      forward: mount.forward,
      dt: dt,
      qualifies: qualifies,
    );
    if (newUp == null) return;
    _mount = mount.withUp(newUp);
    if (_normalizer.realignments != before) {
      // The phone moved in its mount; history is meaningless now.
      _lean.reset();
      _forward.reset();
    }
  }

  /// IMU says still and GPS (when available) does not contradict it.
  bool _isStill(double t) =>
      _still.isStill && !(_speed.isReliable(t) && _speed.speedMps > 1.0);

  double _stillFor(double t) => _isStill(t) ? _still.stillFor(t) : 0;

  void _resetStillAccumulators() {
    _stillGravitySum = Vec3.zero;
    _stillGyroSum = Vec3.zero;
    _stillLinearSum = Vec3.zero;
    _stillGravityN = 0;
    _stillGyroN = 0;
    _stillLinearN = 0;
  }
}
