import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/fusion/estimators.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/motion_clip.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/core/safety/safety_tuning.dart';

import '../support/ride_simulator.dart';

/// A pipeline that also feeds a [SafetyMonitor] the way SensorFeed does:
/// raw IMU at full rate, processed state at 10 Hz.
class _Monitored extends MotionPipeline {
  _Monitored({this.impactG = SafetyTuning.defaultImpactG});

  final double impactG;
  final hazards = <Hazard>[];
  final clips = <(Hazard, MotionClip)>[];
  late final monitor = SafetyMonitor(
    onHazard: hazards.add,
    onClip: (h, c) => clips.add((h, c)),
    impactG: impactG,
  );
  double _nextUpdate = 0;

  List<HazardKind> get kinds => [for (final h in hazards) h.kind];
  Iterable<Hazard> of(HazardKind kind) => hazards.where((h) => h.kind == kind);

  @override
  void addAccel(Vec3 accel, double t) {
    super.addAccel(accel, t);
    monitor.addAccel(accel, t);
    if (t >= _nextUpdate) {
      _nextUpdate = t + 0.1;
      monitor.update(snapshot(), mount);
    }
  }

  @override
  void addGyro(Vec3 rate, double t, double dt) {
    super.addGyro(rate, t, dt);
    monitor.addGyro(rate, t, dt);
  }
}

final _mounts = {
  'handlebar portrait': Mount.handlebarPortrait,
  'odd holder': Mount.euler(70, 35, -110),
};

/// Parks, calibrates "up" and rides off to [kmh].
(_Monitored, RideSimulator) _rideAt(double kmh, Mount mount) {
  final p = _Monitored();
  final sim = RideSimulator(mount: mount);
  sim.still(p, 5);
  p.captureStillReference();
  sim.accelerateTo(p, kmh);
  sim.cruise(p, 5);
  return (p, sim);
}

void main() {
  for (final MapEntry(key: name, value: mount) in _mounts.entries) {
    group(name, () {
      test('normal riding raises nothing', () {
        final (p, sim) = _rideAt(100, mount);
        sim.turn(p, 40, 8);
        sim.cruise(p, 4);
        sim.turn(p, -42, 8);
        sim.turn(p, 25, 2); // quick swerve
        sim.weave(p, 1, 8, 5); // slalom through traffic
        sim.brakeToStop(p, decel: 9); // emergency stop
        sim.still(p, 10);
        sim.accelerateTo(p, 30);
        sim.brakeToStop(p);
        sim.still(p, 20, leanDeg: 12); // side stand
        expect(p.hazards, isEmpty);
      });

      test('a speed wobble is reported once, with its frequency', () {
        final (p, sim) = _rideAt(110, mount);
        sim.wobble(p, 7, 3, 2);
        sim.cruise(p, 5);
        expect(p.kinds, [HazardKind.wobble]);
        final w = p.hazards.single;
        expect(w.wobbleHz, closeTo(7, 1));
        expect(w.speedKmh, closeTo(110, 5));
      });

      test('a low-side crash is detected once', () {
        final (p, sim) = _rideAt(50, mount);
        sim.turn(p, 30, 3);
        sim.lowside(p);
        sim.still(p, 6, leanDeg: 85);
        final crashes = p.of(HazardKind.crash).toList();
        expect(crashes, hasLength(1));
        expect(crashes.single.speedKmh, greaterThan(20));
        expect(crashes.single.latitude, isNotNull);

        // Still lying there: no repeat alarm.
        sim.still(p, 60, leanDeg: 85);
        expect(p.of(HazardKind.crash), hasLength(1));
      });
    });
  }

  test('an impact the rider rides through is only an anomaly', () {
    final (p, sim) = _rideAt(60, Mount.handlebarPortrait);
    sim.impact(p, g: 5);
    sim.cruise(p, 20);
    expect(p.kinds, [HazardKind.impact]);
    expect(p.hazards.single.peakAccelG, greaterThan(4.5));
  });

  test('an impact followed by a stop is a crash', () {
    final (p, sim) = _rideAt(60, Mount.handlebarPortrait);
    sim.impact(p, g: 8);
    sim.brakeToStop(p, decel: 12);
    sim.still(p, 8);
    expect(p.kinds, [HazardKind.impact, HazardKind.crash]);
    final crash = p.hazards.last;
    expect(crash.peakAccelG, greaterThan(7.5));
    expect(crash.speedKmh, closeTo(60, 5));
  });

  test('crash detection only arms after riding', () {
    final p = _Monitored();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 5);
    p.captureStillReference();
    // Knocked over in the garage, then dropped.
    sim.still(p, 10, leanDeg: 85);
    sim.impact(p, g: 8);
    sim.still(p, 10);
    expect(p.hazards, isEmpty);

    // Parked after a ride, then tipped over minutes later.
    sim.accelerateTo(p, 40);
    sim.brakeToStop(p);
    sim.still(p, 70, leanDeg: 12);
    sim.still(p, 10, leanDeg: 85);
    expect(p.hazards, isEmpty);
  });

  test('extreme lean is an anomaly', () {
    final (p, sim) = _rideAt(80, Mount.handlebarPortrait);
    sim.turn(p, 58, 6);
    sim.cruise(p, 3);
    expect(p.kinds, [HazardKind.extremeLean]);
  });

  test('no wobble below the minimum speed', () {
    final (p, sim) = _rideAt(20, Mount.handlebarPortrait);
    sim.wobble(p, 7, 3, 2);
    expect(p.hazards, isEmpty);
  });

  test('wobble produces a 10 s clip around it', () {
    final (p, sim) = _rideAt(110, Mount.handlebarPortrait);
    sim.wobble(p, 7, 3, 2);
    sim.cruise(p, 10);
    final (hazard, clip) = p.clips.single;
    expect(hazard, same(p.hazards.single));
    expect(clip.startOffsetS, -5);
    expect(clip.rateHz, closeTo(50, 1));
    expect(clip.accel.length, inInclusiveRange(490, 510));
    expect(clip.gyro.length, inInclusiveRange(490, 510));
    expect(clip.accel.first[0], closeTo(-5, 0.05));
    expect(clip.accel.last[0], closeTo(5, 0.05));
    expect(clip.accel.first, hasLength(4));
    // Raw accelerometer: gravity is in there.
    expect(Vec3.fromList(clip.accel.first.sublist(1)).length, closeTo(9.8, 1));

    final body = clip.toApiJson();
    expect(
      body.keys,
      unorderedEquals(['rate_hz', 'start_offset_s', 'accel', 'gyro']),
    );
    expect(body['start_offset_s'], -5);
    expect((body['accel'] as List).length, lessThanOrEqualTo(1500));
  });

  test('ride ending right after a hazard flushes a truncated clip', () {
    final (p, sim) = _rideAt(110, Mount.handlebarPortrait);
    sim.wobble(p, 7, 3, 2);
    sim.cruise(p, 1);
    expect(p.hazards, hasLength(1));
    expect(p.clips, isEmpty);

    p.monitor.takeNoise();
    final (hazard, clip) = p.clips.single;
    expect(hazard, same(p.hazards.single));
    expect(clip.startOffsetS, -5);
    expect(clip.accel.last[0], inExclusiveRange(1, 2.5));
    expect(clip.gyro.last[0], lessThanOrEqualTo(2.5));

    // Delivered once.
    p.monitor.takeNoise();
    expect(p.clips, hasLength(1));
  });

  /// The row of [rows] with the largest magnitude.
  List<double> peak(List<List<double>> rows) => rows.reduce(
    (a, b) =>
        Vec3.fromList(b.sublist(1)).length > Vec3.fromList(a.sublist(1)).length
        ? b
        : a,
  );

  test("an impact crash's clip is centred on the impact", () {
    final (p, sim) = _rideAt(60, Mount.handlebarPortrait);
    sim.impact(p, g: 8);
    sim.brakeToStop(p, decel: 12);
    sim.still(p, 8);
    expect(p.kinds, [HazardKind.impact, HazardKind.crash]);
    final crash = p.hazards.last;
    // Confirmed only once the bike had stayed stopped, seconds later...
    final clip = p.clips.singleWhere((c) => identical(c.$1, crash)).$2;
    // ...but the clip is around the impact itself, and complete.
    expect(peak(clip.accel)[0], closeTo(0, 0.3));
    expect(
      Vec3.fromList(peak(clip.accel).sublist(1)).length / 9.81,
      greaterThan(7),
    );
    expect(clip.startOffsetS, -5);
    expect(clip.accel.first[0], closeTo(-5, 0.05));
    expect(clip.accel.last[0], closeTo(5, 0.05));
    expect(clip.accel.length, inInclusiveRange(490, 510));

    // Warnings keep their clip around the report.
    final impactClip = p.clips
        .singleWhere((c) => c.$1.kind == HazardKind.impact)
        .$2;
    expect(peak(impactClip.accel)[0], inInclusiveRange(-0.5, 0));
  });

  test("a bike-down crash's clip is centred on the bike going down", () {
    // No impact path: only lying on its side makes this a crash.
    final p = _Monitored(impactG: 50);
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 5);
    p.captureStillReference();
    sim.accelerateTo(p, 50);
    sim.cruise(p, 5);
    sim.lowside(p);
    sim.still(p, 6, leanDeg: 85);
    expect(p.kinds, [HazardKind.crash]);
    final (_, clip) = p.clips.single;
    // Confirmed 3 s after it went down; t = 0 is the moment the tilt says
    // "on its side" (a filtered reading, a little after the fall starts).
    final fallStart = clip.gyro.firstWhere(
      (r) => Vec3.fromList(r.sublist(1)).length > 1.5,
    );
    expect(fallStart[0], inInclusiveRange(-1.5, 0));
    expect(peak(clip.accel)[0], inInclusiveRange(-1, 0)); // hits the ground
    expect(clip.startOffsetS, -5);
    expect(clip.accel.last[0], closeTo(5, 0.05));
  });

  test('a crash long after its event is clamped to what the buffer holds', () {
    final rec = ClipRecorder(lookback: 16);
    final done = <(Hazard, MotionClip)>[];
    const h = Hazard(kind: HazardKind.crash, t: 60, speedKmh: 0, leanDeg: 0);
    for (var i = 0; i <= 70 * 50; i++) {
      final t = i / 50;
      rec.addAccel(const Vec3(0, 0, 9.81), t);
      rec.addGyro(Vec3.zero, t);
      if (i == 60 * 50) rec.capture(h, at: 20); // 40 s earlier
      done.addAll(rec.poll(t));
    }
    final clip = done.single.$2;
    expect(clip.startOffsetS, -5);
    expect(clip.accel.first[0], closeTo(-5, 0.03));
    expect(clip.accel.last[0], closeTo(5, 0.03));
  });

  test('a clip early in the ride starts where the data does', () {
    final rec = ClipRecorder();
    for (var i = 0; i <= 100; i++) {
      final t = 10 + i * 0.02;
      rec.addAccel(const Vec3(0, 0, 9.81), t);
      rec.addGyro(const Vec3(0.1, 0, 0), t);
    }
    const h = Hazard(kind: HazardKind.impact, t: 11, speedKmh: 40, leanDeg: 0);
    rec.capture(h);
    expect(rec.poll(12), isEmpty);
    final (hazard, clip) = rec.flush().single;
    expect(hazard, same(h));
    expect(clip.startOffsetS, closeTo(-1, 1e-9));
    expect(clip.accel.first[0], closeTo(-1, 1e-9));
    expect(clip.accel.last[0], closeTo(1, 1e-9));
    expect(rec.flush(), isEmpty);
  });

  test('a fast sensor is thinned to fit the upload limit', () {
    final rec = ClipRecorder();
    const h = Hazard(kind: HazardKind.impact, t: 20, speedKmh: 40, leanDeg: 0);
    var captured = false;
    final done = <(Hazard, MotionClip)>[];
    for (var i = 0; i < 30 * 400; i++) {
      final t = i / 400;
      rec.addAccel(Vec3(0.123456789, 0, 9.81), t);
      rec.addGyro(const Vec3(0, 0, 0.5), t);
      if (!captured && t >= 20) {
        rec.capture(h);
        captured = true;
      }
      done.addAll(rec.poll(t));
    }
    final clip = done.single.$2;
    expect(clip.accel.length, inInclusiveRange(1000, 1500));
    expect(clip.gyro.length, inInclusiveRange(1000, 1500));
    expect(clip.rateHz, closeTo(clip.accel.length / 10, 5));
    expect(clip.accel.first[1], 0.1235);
  });

  test('a sample is checked for hazards before any clip is delivered', () {
    MotionState at(double t, double kmh) => MotionState(
      t: t,
      speedKmh: kmh,
      speedSource: SpeedSource.gps,
      leanDeg: 0,
      physicsLeanDeg: 0,
      accelLeanDeg: 0,
      rollRate: 0,
      yawRate: 0,
      forwardAccel: 0,
      lateralAccel: 0,
      isStill: kmh == 0,
      stillFor: 0,
      mountReady: true,
      forwardLearned: true,
      straightOffsetDeg: 0,
      mountRealignments: 0,
    );
    final hazards = <Hazard>[];
    // A clip handler that fails (or is slow) must not cost detection.
    final m = SafetyMonitor(
      onHazard: hazards.add,
      onClip: (_, _) => throw StateError('upload queue full'),
    );
    const upright = Vec3(0, 0, 9.81);
    var t = 0.0;
    void step(double kmh, {double g = 1}) {
      t = double.parse((t + 0.02).toStringAsFixed(2));
      try {
        m.addAccel(upright * g, t);
      } on StateError {
        // The handler's failure surfaces, after detection.
      }
      if ((t * 100).round() % 10 == 0) m.update(at(t, kmh), null);
    }

    while (t < 1) {
      step(60);
    }
    step(60, g: 5); // pothole: a warning with a clip
    while (t < 6.3) {
      step(60);
    }
    expect([for (final h in hazards) h.kind], [HazardKind.impact]);
    // The pothole's clip completes on this very sample: a crash impact.
    final clipDone = hazards.single.t + 5;
    while (t < clipDone - 0.01) {
      step(60);
    }
    step(60, g: 8);
    while (t < clipDone + 8) {
      step(0);
    }
    expect(
      [for (final h in hazards) h.kind],
      [HazardKind.impact, HazardKind.crash],
    );
    expect(hazards.last.peakAccelG, closeTo(8, 0.01));
  });
}
