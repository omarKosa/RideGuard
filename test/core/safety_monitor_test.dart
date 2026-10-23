import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';

import '../support/ride_simulator.dart';

/// A pipeline that also feeds a [SafetyMonitor] the way SensorFeed does:
/// raw IMU at full rate, processed state at 10 Hz.
class _Monitored extends MotionPipeline {
  final hazards = <Hazard>[];
  late final monitor = SafetyMonitor(onHazard: hazards.add);
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
}
