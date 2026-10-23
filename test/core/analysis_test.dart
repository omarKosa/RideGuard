import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/brake_detector.dart';
import 'package:ride_guard/core/analysis/ride_analyzer.dart';
import 'package:ride_guard/core/buffer/time_window_buffer.dart';
import 'package:ride_guard/core/fusion/estimators.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/models/brake_event.dart';
import 'package:ride_guard/models/ride_sample.dart';

final t0 = DateTime.utc(2026, 10, 22, 8);

RideSample sample(int i, double speed, {double lean = 0, double hz = 10}) =>
    RideSample(
      seq: i,
      time: t0.add(Duration(microseconds: (i * 1e6 / hz).round())),
      speedKmh: speed,
      speedSource: SpeedSource.gps,
      leanDeg: lean,
      rollRateDps: 0,
      yawRateDps: 0,
      forwardAccel: 0,
      lateralAccel: 0,
    );

/// Speed profile at 10 Hz: [cruise] s at [v], brake at [decel] to 0, then
/// stand for 2 s.
List<double> stopProfile(double v, double decel, {double cruise = 3}) {
  final speeds = <double>[];
  for (var i = 0; i < cruise * 10; i++) {
    speeds.add(v);
  }
  var s = v;
  while (s > 0) {
    s = (s - decel * 3.6 * 0.1).clamp(0, v);
    speeds.add(s);
  }
  for (var i = 0; i < 20; i++) {
    speeds.add(0);
  }
  return speeds;
}

void main() {
  group('Vec3', () {
    test('cross, dot and rotation', () {
      expect(Vec3.unitX.cross(Vec3.unitY), Vec3.unitZ);
      expect(Vec3.unitX.dot(Vec3.unitY), 0);
      final r = Vec3.unitX.rotated(Vec3.unitZ, degToRad(90));
      expect((r - Vec3.unitY).length, lessThan(1e-9));
      expect(Vec3.fromList(const [1, 2, 3]).toList(), [1.0, 2.0, 3.0]);
    });
  });

  group('TimeWindowBuffer', () {
    test('evicts items older than the window', () {
      final b = TimeWindowBuffer<DateTime>(
        window: const Duration(minutes: 12),
        timeOf: (t) => t,
      );
      for (var m = 0; m <= 20; m++) {
        b.add(t0.add(Duration(minutes: m)));
      }
      expect(b.length, 13); // minutes 8..20 inclusive
      expect(b.first, t0.add(const Duration(minutes: 8)));
      b.window = const Duration(minutes: 5);
      expect(b.length, 6);
    });

    test('rejects out-of-order items', () {
      final b = TimeWindowBuffer<DateTime>(
        window: const Duration(minutes: 1),
        timeOf: (t) => t,
      );
      b.add(t0.add(const Duration(seconds: 5)));
      expect(() => b.add(t0), throwsStateError);
    });
  });

  group('BrakeDetector', () {
    test('measures a stop from 80 km/h at 7 m/s²', () {
      final d = BrakeDetector();
      final events = <BrakeEvent>[];
      final speeds = stopProfile(80, 7);
      for (var i = 0; i < speeds.length; i++) {
        final e = d.add(sample(i, speeds[i]).time, speeds[i]);
        if (e != null) events.add(e);
      }
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.startSpeedKmh, closeTo(80, 1));
      expect(e.durationS, closeTo(80 / 3.6 / 7, 0.4));
      expect(e.peakDecelMps2, closeTo(7, 0.5));
      // d = v²/2a
      expect(e.distanceM, closeTo(35.3, 4));
    });

    test('ignores slowing down without stopping and slow stops', () {
      final d = BrakeDetector();
      var i = 0;
      BrakeEvent? got;
      void feed(double v) => got ??= d.add(sample(i++, v).time, v);
      for (var v = 80.0; v > 40; v -= 2) {
        feed(v);
      }
      for (var v = 40.0; v < 70; v += 1) {
        feed(v);
      }
      // Rolling to a stop from walking pace is not a brake event either.
      for (var v = 69.0; v > 15; v -= 0.05) {
        feed(v); // gentle 0.14 m/s² roll-off
      }
      for (final v in stopProfile(15, 3)) {
        feed(v);
      }
      expect(got, isNull);
    });
  });

  group('RideAnalyzer', () {
    test('window stats only cover the last N minutes; totals cover all', () {
      final a = RideAnalyzer(window: const Duration(minutes: 12));
      var i = 0;
      // 5 min at 150 km/h leaning 45° right, then 15 min calmer riding with
      // two stops.
      for (; i < 5 * 60 * 10; i++) {
        a.add(sample(i, 150, lean: 45));
      }
      for (final v in stopProfile(100, 8, cruise: 60)) {
        a.add(sample(i++, v, lean: -20));
      }
      for (final v in stopProfile(60, 4, cruise: 700)) {
        a.add(sample(i++, v, lean: 10));
      }

      final window = a.windowStats();
      final totals = a.totals();
      expect(window.span.inSeconds, closeTo(720, 1));
      expect(window.maxSpeedKmh, closeTo(100, 0.01));
      expect(window.maxLeanRightDeg, 10);
      expect(window.maxLeanLeftDeg, 20);
      expect(totals.maxSpeedKmh, 150);
      expect(totals.maxLeanRightDeg, 45);
      expect(totals.brakeEvents, 2);
      // The 60 km/h stop at 4 m/s² takes longer than the 100 km/h one at 8.
      expect(totals.maxStopTimeS, closeTo(60 / 3.6 / 4, 0.4));
      expect(totals.bestDecelMps2, closeTo(8, 0.6));
    });

    test('lean while crawling or standing does not count', () {
      final a = RideAnalyzer();
      for (var i = 0; i < 50; i++) {
        a.add(sample(i, 4, lean: -40));
      }
      expect(a.totals().maxLeanLeftDeg, 0);
    });
  });
}
