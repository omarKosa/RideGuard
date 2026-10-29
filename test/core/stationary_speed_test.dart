import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/ride_analyzer.dart';
import 'package:ride_guard/core/fusion/estimators.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/models/ride_sample.dart';

import '../support/ride_simulator.dart';

/// A parked phone indoors: GPS reports a walking-pace speed out of position
/// noise, with poor accuracy.
class _IndoorGps extends MotionPipeline {
  _IndoorGps({this.accuracyM = 30, this.speedAccuracyMps});

  final double accuracyM;
  final double? speedAccuracyMps;

  @override
  void addGps(GpsFix fix) => super.addGps(
    GpsFix(
      t: fix.t,
      speedMps: 1.9, // 6.8 km/h of pure jitter
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyM: accuracyM,
      speedAccuracyMps: speedAccuracyMps,
    ),
  );
}

/// A phone without a gyroscope (e.g. Galaxy A05).
class _NoGyro extends MotionPipeline {
  @override
  void addGyro(Vec3 rate, double t, double dt) {}
}

RideSample _sample(int i, double kmh, SpeedSource source) => RideSample(
  seq: i,
  time: DateTime.utc(2026).add(Duration(milliseconds: i * 100)),
  speedKmh: kmh,
  speedSource: source,
  leanDeg: 0,
  rollRateDps: 0,
  yawRateDps: 0,
  forwardAccel: 0,
  lateralAccel: 0,
);

void main() {
  test('a phone without a gyroscope can still capture the still reference', () {
    final p = _NoGyro();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 6);
    expect(p.captureStillReference(), isTrue);
  });

  test('a parked phone with jittery indoor GPS reads 0 km/h', () {
    final p = _IndoorGps();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 30);
    expect(p.snapshot().speedKmh, 0);
  });

  test('GPS speed within its own uncertainty is treated as standing', () {
    final p = _IndoorGps(accuracyM: 6, speedAccuracyMps: 2.5);
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 10);
    expect(p.snapshot().speedKmh, 0);
  });

  test('slow real riding still shows its speed', () {
    final p = MotionPipeline();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 3);
    sim.accelerateTo(p, 12);
    sim.cruise(p, 10);
    expect(p.snapshot().speedKmh, closeTo(12, 1.5));
  });

  test('a stale speed adds no distance, top speed or moving time', () {
    final a = RideAnalyzer();
    // 1 s of real GPS at 7 km/h, then 60 s where the last value is held
    // after the fixes stopped.
    for (var i = 0; i < 10; i++) {
      a.add(_sample(i, 0, SpeedSource.gps));
    }
    for (var i = 10; i < 610; i++) {
      a.add(_sample(i, 7, SpeedSource.stale));
    }
    final t = a.totals();
    expect(t.distanceM, 0);
    expect(t.maxSpeedKmh, 0);
    expect(t.movingTimeS, 0);
    expect(a.windowStats().distanceM, 0);
  });

  test('reliable speed still adds distance', () {
    final a = RideAnalyzer();
    for (var i = 0; i < 101; i++) {
      a.add(_sample(i, 36, SpeedSource.gps)); // 10 m/s for 10 s
    }
    expect(a.totals().distanceM, closeTo(100, 1));
  });

  test('without a gyroscope the phone is still detected and the mount '
      'learned', () {
    final p = _NoGyro();
    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    sim.still(p, 3);
    expect(p.snapshot().isStill, isTrue);
    expect(p.mount, isNotNull);
  });
}
