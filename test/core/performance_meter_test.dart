import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/performance_meter.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/models/brake_event.dart';

import '../support/ride_simulator.dart';

MotionState _copy(MotionState s, {double? t, double? speedKmh}) => MotionState(
  t: t ?? s.t,
  speedKmh: speedKmh ?? s.speedKmh,
  speedSource: s.speedSource,
  leanDeg: s.leanDeg,
  physicsLeanDeg: s.physicsLeanDeg,
  accelLeanDeg: s.accelLeanDeg,
  rollRate: s.rollRate,
  yawRate: s.yawRate,
  forwardAccel: s.forwardAccel,
  lateralAccel: s.lateralAccel,
  isStill: s.isStill,
  stillFor: s.stillFor,
  mountReady: s.mountReady,
  forwardLearned: s.forwardLearned,
  straightOffsetDeg: s.straightOffsetDeg,
  mountRealignments: s.mountRealignments,
);

(MotionPipeline, RideSimulator) _start() {
  final p = MotionPipeline();
  final sim = RideSimulator(mount: Mount.handlebarPortrait);
  sim.still(p, 5);
  p.captureStillReference();
  return (p, sim);
}

void main() {
  test('sustained top speed ignores a one-sample GPS spike', () {
    final (p, sim) = _start();
    final m = PerformanceMeter();
    var n = 0;
    void feed(SimTick k) {
      n++;
      m.add(n == 100 ? _copy(k.state, speedKmh: 400) : k.state);
    }

    sim.accelerateTo(p, 120, onTick: feed);
    sim.cruise(p, 15, onTick: feed);
    expect(m.readings.sustainedTopSpeedKmh, inInclusiveRange(115, 125));
  });

  test('peak accel of a launch and peak decel of a hard stop', () {
    final (p, sim) = _start();
    final m = PerformanceMeter();
    sim.accelerateTo(
      p,
      100,
      accel: 100 / 3.6 / 4,
      onTick: (k) => m.add(k.state),
    );
    sim.cruise(p, 3, onTick: (k) => m.add(k.state));
    sim.brakeToStop(p, decel: 8, onTick: (k) => m.add(k.state));
    expect(m.readings.peakAccelMps2, inInclusiveRange(6, 9));
    expect(m.readings.peakDecelMps2, inInclusiveRange(6.5, 9.5));
  });

  test('gentle ride gives low readings and json round-trips', () {
    final (p, sim) = _start();
    final m = PerformanceMeter();
    sim.accelerateTo(p, 50, accel: 1.5, onTick: (k) => m.add(k.state));
    sim.cruise(p, 6, onTick: (k) => m.add(k.state));
    sim.brakeToStop(p, decel: 2, onTick: (k) => m.add(k.state));
    final t0 = DateTime.utc(2026, 10, 22, 9);
    m.addStop(
      BrakeEvent(
        startedAt: t0,
        endedAt: t0.add(const Duration(seconds: 7)),
        startSpeedKmh: 50,
        distanceM: 50,
        peakDecelMps2: 2.2,
      ),
    );
    final r = m.readings;
    expect(r.sustainedTopSpeedKmh, inInclusiveRange(40, 55));
    expect(r.peakAccelMps2, lessThan(3));
    expect(r.peakDecelMps2, lessThan(3.5));

    final api = r.toApiJson();
    expect((api['stops'] as List).single, {
      'start_speed_kmh': 50.0,
      'duration_s': 7.0,
      'mean_decel_mps2': 1.98,
    });
    final back = PerformanceReadings.fromJson(r.toJson());
    expect(back.toJson(), r.toJson());
    expect(back.stops.single.startSpeedKmh, 50);
  });

  test('empty meter gives nulls and caps stops at 50', () {
    final m = PerformanceMeter();
    expect(m.readings.sustainedTopSpeedKmh, isNull);
    expect(m.readings.toApiJson()['peak_accel_mps2'], isNull);
    final t0 = DateTime.utc(2026);
    for (var i = 0; i < 60; i++) {
      m.addStop(
        BrakeEvent(
          startedAt: t0,
          endedAt: t0.add(const Duration(seconds: 3)),
          startSpeedKmh: 40,
          distanceM: 20,
          peakDecelMps2: 4,
        ),
      );
    }
    expect((m.readings.toApiJson()['stops'] as List).length, 50);
  });

  test('api json only carries stops and peaks the backend accepts', () {
    final t0 = DateTime.utc(2026);
    BrakeEvent stop(Duration d, double fromKmh) => BrakeEvent(
      startedAt: t0,
      endedAt: t0.add(d),
      startSpeedKmh: fromKmh,
      distanceM: 1,
      peakDecelMps2: 9,
    );
    final readings = PerformanceReadings(
      sustainedTopSpeedKmh: 612,
      peakAccelMps2: -0.4,
      peakDecelMps2: 140,
      stops: [
        stop(Duration.zero, 30), // clock stepped back
        stop(const Duration(milliseconds: 13), 60), // ~1280 m/s2
        stop(const Duration(seconds: 200), 50), // longer than 120 s
        stop(const Duration(seconds: 4), 60), // a real stop
      ],
    );
    final api = readings.toApiJson();
    final stops = (api['stops'] as List).cast<Map<String, dynamic>>();
    expect(stops, hasLength(1));
    expect(stops.single['duration_s'], 4);
    for (final s in stops) {
      expect(s['duration_s'], allOf(greaterThan(0), lessThanOrEqualTo(120)));
      expect(s['mean_decel_mps2'], inInclusiveRange(0, 100));
      expect(s['start_speed_kmh'], inInclusiveRange(0, 500));
    }
    expect(api['sustained_top_speed_kmh'], 500);
    expect(api['peak_accel_mps2'], 0);
    expect(api['peak_decel_mps2'], 100);
    // Local storage keeps everything as measured.
    final local = readings.toJson();
    expect((local['stops'] as List), hasLength(4));
    expect(local['sustained_top_speed_kmh'], 612);
    expect(local['peak_decel_mps2'], 140);
  });

  test('dropped stops are not sent and do not count', () {
    final t0 = DateTime.utc(2026);
    final readings = PerformanceReadings(
      stops: [
        for (var i = 0; i < 10; i++)
          BrakeEvent(
            startedAt: t0,
            endedAt: t0,
            startSpeedKmh: 40,
            distanceM: 0,
            peakDecelMps2: 4,
          ),
        for (var i = 0; i < 45; i++)
          BrakeEvent(
            startedAt: t0,
            endedAt: t0.add(const Duration(seconds: 3)),
            startSpeedKmh: 40,
            distanceM: 20,
            peakDecelMps2: 4,
          ),
      ],
    );
    expect((readings.toApiJson()['stops'] as List).length, 45);
  });
}
