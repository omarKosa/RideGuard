import 'dart:math' as math;

import 'package:ride_guard/core/fusion/estimators.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/math/vec3.dart';

/// Rotation matrix (rows) mapping bike-frame vectors (forward, left, up) to
/// phone-frame vectors - i.e. how the phone is mounted.
class Mount {
  const Mount(this.r0, this.r1, this.r2);

  /// Rotation from yaw (about up), pitch (about left), roll (about forward),
  /// all in degrees.
  factory Mount.euler(double yawDeg, double pitchDeg, double rollDeg) {
    final a = degToRad(yawDeg), b = degToRad(pitchDeg), c = degToRad(rollDeg);
    final ca = math.cos(a), sa = math.sin(a);
    final cb = math.cos(b), sb = math.sin(b);
    final cc = math.cos(c), sc = math.sin(c);
    // Rz(a) * Ry(b) * Rx(c)
    return Mount(
      Vec3(ca * cb, ca * sb * sc - sa * cc, ca * sb * cc + sa * sc),
      Vec3(sa * cb, sa * sb * sc + ca * cc, sa * sb * cc - ca * sc),
      Vec3(-sb, cb * sc, cb * cc),
    );
  }

  /// Portrait on the handlebars, screen facing the rider, tilted back 20°
  /// (rotated about the phone's x axis): phone +y is up-ish, phone -z points
  /// forward.
  static final handlebarPortrait = const Mount(
    Vec3(0, -1, 0),
    Vec3(0, 0, 1),
    Vec3(-1, 0, 0),
  ).then(Mount.euler(0, 0, -20));

  final Vec3 r0, r1, r2;

  Vec3 apply(Vec3 v) => Vec3(r0.dot(v), r1.dot(v), r2.dot(v));

  /// This mount followed by an extra phone-frame rotation [m].
  Mount then(Mount m) {
    Vec3 col(int i) => Vec3(
      [r0.x, r0.y, r0.z][i],
      [r1.x, r1.y, r1.z][i],
      [r2.x, r2.y, r2.z][i],
    );
    final c0 = m.apply(col(0)), c1 = m.apply(col(1)), c2 = m.apply(col(2));
    return Mount(
      Vec3(c0.x, c1.x, c2.x),
      Vec3(c0.y, c1.y, c2.y),
      Vec3(c0.z, c1.z, c2.z),
    );
  }

  Vec3 get forwardInPhone => apply(Vec3.unitX);
  Vec3 get upInPhone => apply(Vec3.unitZ);
}

class SimTick {
  SimTick(this.state, this.time, this.trueLeanDeg, this.trueSpeedKmh);
  final MotionState state;
  final DateTime time;
  final double trueLeanDeg;
  final double trueSpeedKmh;
}

/// Generates physically consistent IMU and GPS readings for a scripted
/// ride: coordinated turns, side-stand lean, accelerating and braking.
class RideSimulator {
  RideSimulator({
    required this.mount,
    this.imuHz = 50,
    this.gyroBias = const Vec3(0.012, -0.018, 0.009),
    this.gyroNoise = 0.01,
    this.accelNoise = 0.08,
    int seed = 7,
  }) : _rng = math.Random(seed);

  Mount mount;
  final double imuHz;
  final Vec3 gyroBias;
  final double gyroNoise;
  final double accelNoise;
  final math.Random _rng;

  final DateTime start = DateTime.utc(2026, 10, 22, 9);
  double t = 0;
  double v = 0; // m/s
  double lean = 0; // rad, + right
  double _nextGps = 0;
  double _nextTick = 0;

  /// Runs [seconds] of simulated time. [accel] gives forward acceleration
  /// and [leanAt] the desired lean (deg), both as a function of local time.
  void run(
    MotionPipeline p,
    double seconds, {
    double Function(double tLocal)? accel,
    double Function(double tLocal)? leanAt,
    void Function(SimTick tick)? onTick,
  }) {
    final dt = 1 / imuHz;
    final steps = (seconds * imuHz).round();
    for (var i = 0; i < steps; i++) {
      final local = i * dt;
      final a = accel?.call(local) ?? 0;
      final targetLean = degToRad(leanAt?.call(local) ?? radToDeg(lean));
      final rollRate = (targetLean - lean) / dt;
      lean = targetLean;
      final newV = math.max(0.0, v + a * dt);
      final effectiveA = (newV - v) / dt;
      v = newV;
      t += dt;

      // Coordinated turn when moving; plain tilt (stand) when stopped.
      final moving = v > 0.5;
      final ac = moving ? gravity * math.tan(lean) : 0.0; // + towards right
      final omega = moving ? -ac / v : 0.0; // about world up, + = left
      final c = math.cos(lean), s = math.sin(lean);

      final specific = Vec3(
        effectiveA,
        -(ac * c - gravity * s),
        ac * s + gravity * c,
      );
      final reaction = Vec3(0, gravity * s, gravity * c);
      final rate = Vec3(rollRate, omega * s, omega * c);

      p.addAccel(mount.apply(specific) + _noise(accelNoise), t);
      p.addLinearAccel(
        mount.apply(specific - reaction) + _noise(accelNoise),
        t,
      );
      p.addGyro(mount.apply(rate) + gyroBias + _noise(gyroNoise), t, dt);

      if (t >= _nextGps) {
        _nextGps += 1.0;
        p.addGps(
          GpsFix(
            t: t,
            speedMps: math.max(0, v + (_rng.nextDouble() - 0.5) * 0.2),
            latitude: 30.0,
            longitude: 31.0,
            accuracyM: 4,
          ),
        );
      }
      if (t >= _nextTick) {
        _nextTick += 0.1;
        onTick?.call(
          SimTick(
            p.snapshot(),
            start.add(Duration(microseconds: (t * 1e6).round())),
            radToDeg(lean),
            v * 3.6,
          ),
        );
      }
    }
  }

  // Convenience segments ----------------------------------------------------

  void still(
    MotionPipeline p,
    double seconds, {
    double leanDeg = 0,
    void Function(SimTick)? onTick,
  }) => run(p, seconds, leanAt: (_) => leanDeg, onTick: onTick);

  void accelerateTo(
    MotionPipeline p,
    double kmh, {
    double accel = 2.5,
    void Function(SimTick)? onTick,
  }) {
    final secs = (kmh / 3.6 - v).abs() / accel;
    final sign = kmh / 3.6 >= v ? 1.0 : -1.0;
    run(p, secs, accel: (_) => accel * sign, leanAt: (_) => 0, onTick: onTick);
  }

  void cruise(
    MotionPipeline p,
    double seconds, {
    void Function(SimTick)? onTick,
  }) => run(p, seconds, leanAt: (_) => 0, onTick: onTick);

  /// Rolls into [leanDeg], holds it, and rolls back out over [seconds].
  void turn(
    MotionPipeline p,
    double leanDeg,
    double seconds, {
    void Function(SimTick)? onTick,
  }) {
    const ramp = 1.0;
    run(
      p,
      seconds,
      onTick: onTick,
      leanAt: (tl) {
        if (tl < ramp) return leanDeg * tl / ramp;
        if (tl > seconds - ramp) return leanDeg * (seconds - tl) / ramp;
        return leanDeg;
      },
    );
  }

  void brakeToStop(
    MotionPipeline p, {
    double decel = 6,
    void Function(SimTick)? onTick,
  }) {
    final secs = v / decel + 0.5;
    run(p, secs, accel: (_) => -decel, leanAt: (_) => 0, onTick: onTick);
  }

  Vec3 _noise(double sigma) => Vec3(_gauss(), _gauss(), _gauss()) * sigma;

  double _gauss() {
    final u1 = math.max(_rng.nextDouble(), 1e-12);
    final u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
