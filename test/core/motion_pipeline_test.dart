import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';

import '../support/ride_simulator.dart';

/// Runs a standard ride and records the estimated lean at the middle of the
/// straight, right-turn and left-turn segments.
({
  double straight,
  double right,
  double left,
  double pullAwayError,
  MotionPipeline p,
})
standardRide(Mount mount, {double standLeanDeg = 0, MotionPipeline? pipeline}) {
  final p = pipeline ?? MotionPipeline();
  final sim = RideSimulator(mount: mount);
  late double straight, right, left;
  var maxAccelLeanError = 0.0;
  SimTick? lastTick;
  void keep(SimTick t) => lastTick = t;

  sim.still(p, 5, leanDeg: standLeanDeg);
  if (pipeline != null || standLeanDeg != 0) p.captureStillReference();
  sim.accelerateTo(
    p,
    60,
    onTick: (t) {
      keep(t);
      maxAccelLeanError = math.max(
        maxAccelLeanError,
        (t.state.leanDeg - t.trueLeanDeg).abs(),
      );
    },
  );
  sim.cruise(p, 20, onTick: keep);
  straight = lastTick!.state.leanDeg;
  sim.turn(
    p,
    30,
    8,
    onTick: (t) {
      if ((t.trueLeanDeg - 30).abs() < 1e-6) lastTick = t;
    },
  );
  right = lastTick!.state.leanDeg;
  sim.cruise(p, 6);
  sim.turn(
    p,
    -25,
    8,
    onTick: (t) {
      if ((t.trueLeanDeg + 25).abs() < 1e-6) lastTick = t;
    },
  );
  left = lastTick!.state.leanDeg;
  sim.brakeToStop(p);
  return (
    straight: straight,
    right: right,
    left: left,
    pullAwayError: maxAccelLeanError,
    p: p,
  );
}

void main() {
  final mounts = <String, Mount>{
    'handlebar portrait': Mount.handlebarPortrait,
    'flat on tank': Mount.euler(0, 0, 0),
    'landscape, rotated 90° on the bars': Mount.handlebarPortrait.then(
      Mount.euler(90, 0, 0),
    ),
    'upside down and twisted': Mount.euler(37, 160, -25),
    'crooked 15° roll in the holder': Mount.handlebarPortrait.then(
      Mount.euler(15, 0, 0),
    ),
    'holder twisted 20° sideways on the bars': Mount.handlebarPortrait.then(
      Mount.euler(0, 20, 0),
    ),
  };

  group('lean is mount independent', () {
    mounts.forEach((name, mount) {
      test(name, () {
        final r = standardRide(mount);
        expect(r.p.forwardLearned, isTrue, reason: 'forward axis learned');
        expect(r.straight, closeTo(0, 2));
        expect(r.right, closeTo(30, 3));
        expect(r.left, closeTo(-25, 3));
        expect(
          r.pullAwayError,
          lessThan(3),
          reason: 'pulling away must not fake a lean',
        );
      });
    });
  });

  test('side-stand calibration is normalized while riding straight', () {
    // Calibrated with the bike leaning 9° left on its stand.
    final r = standardRide(Mount.handlebarPortrait, standLeanDeg: -9);
    final s = r.p.snapshot();
    expect(s.straightOffsetDeg.abs(), closeTo(9, 1.5));
    expect(r.straight, closeTo(0, 2));
    expect(r.right, closeTo(30, 3));
    expect(r.left, closeTo(-25, 3));
    // Standing still upright after the ride must read ~0, not the 9° offset.
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(r.p, 3);
    expect(r.p.snapshot().accelLeanDeg, closeTo(0, 2));
  });

  test('phone slipping in its mount mid-ride is re-aligned', () {
    final p = MotionPipeline();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 5);
    sim.accelerateTo(p, 70);
    sim.cruise(p, 10);
    // The holder rotates 20° about the forward axis.
    sim.mount = Mount.handlebarPortrait.then(Mount.euler(0, 0, 20));
    sim.cruise(p, 15);
    expect(p.snapshot().mountRealignments, greaterThanOrEqualTo(1));
    double? mid;
    sim.turn(
      p,
      35,
      8,
      onTick: (t) {
        if ((t.trueLeanDeg - 35).abs() < 1e-6) mid = t.state.leanDeg;
      },
    );
    expect(mid, closeTo(35, 3.5));
    sim.cruise(p, 5);
    expect(p.snapshot().leanDeg, closeTo(0, 2));
  });

  test('gyro bias is learned while parked', () {
    final p = MotionPipeline(learningMode: true);
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 6);
    expect(p.captureStillReference(), isTrue);
    expect((p.gyroBias - sim.gyroBias).length, lessThan(0.005));
    expect(p.snapshot().leanDeg, closeTo(0, 1));
  });

  test('speed is GPS-backed and reports its source', () {
    final p = MotionPipeline();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 3);
    sim.accelerateTo(p, 90);
    sim.cruise(p, 5);
    final s = p.snapshot();
    expect(s.speedKmh, closeTo(90, 2));
    expect(s.speedReliable, isTrue);
  });
}
