import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/safety_baseline.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/core/safety/safety_tuning.dart';
import 'package:ride_guard/models/incident.dart';

import '../support/ride_simulator.dart';

class _Monitored extends MotionPipeline {
  _Monitored([SafetyTuning tuning = SafetyTuning.defaults]) {
    monitor = SafetyMonitor.tuned(tuning, onHazard: hazards.add);
  }

  final hazards = <Hazard>[];
  late final SafetyMonitor monitor;
  double _nextUpdate = 0;

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

/// Engine/road vibration reaching the phone: 9 Hz, ~0.7·[peak] rad/s RMS.
Vec3 Function(double) _vibration(double peak) {
  const w = 2 * math.pi * 9;
  return (t) => Vec3(peak * math.sin(w * t), 0.5 * peak * math.cos(w * t), 0);
}

/// [n] seconds of riding at a constant per-second [wobble] and [g].
RideNoise _noise(int n, {double wobble = 0.05, double g = 1.3, double? hz}) {
  final noise = RideNoise(imuHz: hz);
  for (var i = 0; i < n; i++) {
    noise.wobbleRms.add(wobble);
    noise.peakG.add(g);
  }
  return noise;
}

(_Monitored, RideSimulator) _rideOff([
  SafetyTuning tuning = SafetyTuning.defaults,
]) {
  final p = _Monitored(tuning);
  final sim = RideSimulator(mount: Mount.handlebarPortrait);
  sim.still(p, 5);
  p.captureStillReference();
  sim.accelerateTo(p, 90);
  return (p, sim);
}

void main() {
  group('Histogram', () {
    test('quantiles round up to the bin edge', () {
      final h = Histogram.wobble();
      for (var i = 1; i <= 100; i++) {
        h.add(i / 100);
      }
      expect(h.quantile(0.5), inInclusiveRange(0.5, 0.5 * 1.18));
      expect(h.quantile(0.99), inInclusiveRange(0.99, 0.99 * 1.18));
      expect(Histogram.wobble().quantile(0.99), isNull);
    });

    test('histograms add up', () {
      final a = Histogram.wobble()..add(0.1);
      final b = Histogram.wobble()
        ..add(0.1)
        ..add(2);
      expect((a + b).total, 3);
      expect((a + b).quantile(1), greaterThanOrEqualTo(2));
    });
  });

  group('SafetyBaseline', () {
    test('stays at defaults until there is enough riding', () {
      final b = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(30, wobble: 0.3, g: 3.8));
      final t = b.tuning;
      expect(t.wobbleMinRms, SafetyTuning.defaultWobbleRms);
      expect(t.impactG, SafetyTuning.defaultImpactG);
      expect(t.warnings, isEmpty);
    });

    test('a smooth mount keeps default sensitivity', () {
      final t = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(600, hz: 50)).tuning;
      expect(t.wobbleMinRms, SafetyTuning.defaultWobbleRms);
      expect(t.impactG, SafetyTuning.defaultImpactG);
      expect(t.wobbleMaxHz, SafetyTuning.defaultWobbleMaxHz);
      expect(t.warnings, isEmpty);
    });

    test('vibration raises thresholds, never past the caps', () {
      final some = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(600, wobble: 0.22, g: 3.6)).tuning;
      expect(some.wobbleMinRms, inInclusiveRange(0.66, 0.78));
      expect(some.impactG, inInclusiveRange(4.5, 5.3));
      expect(some.warnings, isEmpty);

      final lots = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(600, wobble: 0.6, g: 9)).tuning;
      expect(lots.wobbleMinRms, SafetyTuning.maxWobbleRms);
      expect(lots.impactG, SafetyTuning.maxImpactG);
      expect(lots.warnings, hasLength(2));
      expect(lots.warnings.first, contains('Strong vibration'));
    });

    test('a single pothole does not move the floor', () {
      final noise = _noise(600, g: 1.4)..peakG.add(7);
      final t = SafetyBaseline(calibrationId: 'c').withRide(noise).tuning;
      expect(t.impactG, SafetyTuning.defaultImpactG);
    });

    test('it forgets: a fixed mount brings sensitivity back', () {
      var b = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(1800, wobble: 0.3));
      expect(b.tuning.wobbleMinRms, greaterThan(0.85));
      for (var i = 0; i < 4; i++) {
        b = b.withRide(_noise(3600)); // four hours on a damped mount
      }
      expect(b.tuning.wobbleMinRms, SafetyTuning.defaultWobbleRms);
      expect(b.rides, 5);
      expect(b.ridingSeconds, SafetyBaseline.windowSeconds);
      expect(b.recentRides, hasLength(3));
    });

    test('false alarms raise just that threshold, within its cap', () {
      final base = SafetyBaseline(calibrationId: 'c').withRide(_noise(600));
      final w = base.withFalseWobble(0.62).tuning;
      expect(w.wobbleMinRms, closeTo(0.62 * 1.15, 1e-9));
      expect(w.impactG, SafetyTuning.defaultImpactG);

      final i = base.withFalseImpact(4.3).withFalseImpact(4.1).tuning;
      expect(i.impactG, closeTo(4.3 * 1.1, 1e-9));

      final l = base.withFalseLean(-58).tuning;
      expect(l.extremeLeanDeg, 61);
      expect(base.withFalseLean(80).tuning.extremeLeanDeg, 65);
      expect(base.withFalseWobble(3).tuning.wobbleMinRms, 1.0);
      expect(base.withFalseWobble(0.6).withFalseImpact(5).falseAlarms, 2);
    });

    Incident labelled(HazardKind kind, RiderLabel label) => Incident(
      id: 'i',
      rideId: 'r',
      kind: kind,
      detectedAt: DateTime.utc(2026, 10, 24, 9),
      speedKmh: 90,
      leanDeg: -58,
      peakAccelG: 4.6,
      wobbleHz: 8,
      wobbleRms: 0.62,
      outcome: kind.critical
          ? IncidentOutcome.cancelled
          : IncidentOutcome.warned,
    ).labelled(label, DateTime.utc(2026, 10, 24, 10));

    test('no on a crash never loosens anything', () {
      final base = SafetyBaseline(calibrationId: 'c').withRide(_noise(600));
      final after = base.withLabel(labelled(HazardKind.crash, RiderLabel.no));
      expect(after, same(base));
      expect(after.falseAlarms, 0);
      expect(after.tuning.impactG, SafetyTuning.defaultImpactG);
      expect(after.tuning.wobbleMinRms, SafetyTuning.defaultWobbleRms);
      expect(after.tuning.extremeLeanDeg, SafetyTuning.defaultExtremeLeanDeg);
    });

    test('no on a wobble raises the wobble threshold ×1.15', () {
      final base = SafetyBaseline(calibrationId: 'c').withRide(_noise(600));
      final w = base.withLabel(labelled(HazardKind.wobble, RiderLabel.no));
      expect(w.tuning.wobbleMinRms, closeTo(0.62 * 1.15, 1e-9));
      expect(w.tuning.impactG, SafetyTuning.defaultImpactG);
      expect(w.falseAlarms, 1);
      final i = base.withLabel(labelled(HazardKind.impact, RiderLabel.no));
      expect(i.tuning.impactG, closeTo(4.6 * 1.1, 1e-9));
      final l = base.withLabel(labelled(HazardKind.extremeLean, RiderLabel.no));
      expect(l.tuning.extremeLeanDeg, 61);
      // "It happened" teaches nothing about thresholds.
      for (final kind in HazardKind.values) {
        expect(base.withLabel(labelled(kind, RiderLabel.yes)), same(base));
      }
    });

    test('a slow sensor limits the wobble band and says so', () {
      final b = SafetyBaseline(calibrationId: 'c');
      final slow = b.withRide(_noise(600, hz: 25)).tuning;
      expect(slow.wobbleMaxHz, 6.25);
      expect(slow.wobbleDetectable, isTrue);
      expect(slow.warnings.single, contains('25 Hz'));

      final tooSlow = b.withRide(_noise(600, hz: 10)).tuning;
      expect(tooSlow.wobbleDetectable, isFalse);
      expect(tooSlow.warnings.single, contains('too slow'));
    });

    test('cancelled crashes are counted but never loosen anything', () {
      final b = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(_noise(600), cancelledCrashes: 2);
      expect(b.cancelledCrashes, 2);
      expect(b.tuning.impactG, SafetyTuning.defaultImpactG);
    });

    test('survives storage', () {
      final b = SafetyBaseline(
        calibrationId: 'cal-1',
      ).withRide(_noise(400, wobble: 0.2, g: 2, hz: 48)).withFalseWobble(0.7);
      final back = SafetyBaseline.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
      );
      expect(back.calibrationId, 'cal-1');
      expect(back.ridingSeconds, closeTo(400, 0.01));
      expect(back.imuHz, 48);
      expect(back.tuning.wobbleMinRms, closeTo(b.tuning.wobbleMinRms, 1e-9));
      expect(back.tuning.impactG, closeTo(b.tuning.impactG, 1e-9));
    });
  });

  group('learning from simulated rides', () {
    test('no on an impact never makes crash detection less sensitive', () {
      final base = SafetyBaseline(calibrationId: 'c').withRide(_noise(600));
      final tuning = base.withFalseImpact(5.5).tuning;
      expect(tuning.impactG, SafetyTuning.maxImpactG);
      expect(tuning.crashImpactG, SafetyTuning.defaultImpactG);
      expect(base.tuning.crashImpactG, base.tuning.impactG);

      // A 5 g jolt the rider rides through: no warning any more.
      final (p, sim) = _rideOff(tuning);
      sim.cruise(p, 5);
      sim.impact(p, g: 4);
      sim.cruise(p, 20);
      expect(p.hazards, isEmpty);

      // The same jolt followed by stopping is still a crash.
      sim.impact(p, g: 4);
      sim.brakeToStop(p, decel: 12);
      sim.still(p, 8);
      expect([for (final h in p.hazards) h.kind], [HazardKind.crash]);
      expect(p.hazards.single.peakAccelG, inInclusiveRange(4.5, 5.5));
    });

    test('only steady riding away from hazards is learned', () {
      final (p, sim) = _rideOff();
      sim.cruise(p, 60);
      sim.wobble(p, 7, 3, 2);
      sim.cruise(p, 30);
      sim.brakeToStop(p);
      sim.still(p, 20);
      expect(p.hazards.single.kind, HazardKind.wobble);

      final noise = p.monitor.takeNoise();
      expect(noise.imuHz, 50);
      // ~95 s at 20+ km/h minus ~12 s around the wobble.
      expect(noise.ridingSeconds, inInclusiveRange(75, 90));
      // The wobble itself (1.5 rad/s) never became "normal".
      expect(noise.wobbleRms.quantile(1)!, lessThan(0.1));

      // takeNoise starts over.
      expect(p.monitor.takeNoise().ridingSeconds, 0);
    });

    test('a vibrating mount stops false wobble alarms, real ones still '
        'fire', () {
      // First ride: a mount that buzzes steadily at ~0.25 rad/s.
      final (p, sim) = _rideOff();
      sim.run(p, 120, leanAt: (_) => 0, extraRate: _vibration(0.35));
      sim.brakeToStop(p);
      expect(p.hazards, isEmpty);
      final tuning = SafetyBaseline(
        calibrationId: 'c',
      ).withRide(p.monitor.takeNoise()).tuning;
      expect(tuning.wobbleMinRms, greaterThan(0.7));

      // Next ride: a rough patch buzzes harder, then a real wobble.
      List<HazardKind> rideWith(SafetyTuning t) {
        final (q, s) = _rideOff(t);
        s.cruise(q, 3);
        s.run(q, 5, leanAt: (_) => 0, extraRate: _vibration(0.9));
        s.cruise(q, 12);
        s.wobble(q, 7, 3, 2);
        return [for (final h in q.hazards) h.kind];
      }

      expect(rideWith(SafetyTuning.defaults), [
        HazardKind.wobble,
        HazardKind.wobble,
      ], reason: 'defaults: the rough patch is a false alarm');
      expect(rideWith(tuning), [HazardKind.wobble]);
    });

    test('bands split normal riding by speed', () {
      final p = _Monitored();
      final sim = RideSimulator(mount: Mount.handlebarPortrait);
      sim.still(p, 5);
      p.captureStillReference();
      sim.accelerateTo(p, 50);
      sim.cruise(p, 60);
      sim.accelerateTo(p, 100);
      sim.cruise(p, 60);
      sim.brakeToStop(p);
      expect(p.hazards, isEmpty);

      final noise = p.monitor.takeNoise();
      final slow = noise.bands[SpeedBand.b40to60]!;
      final fast = noise.bands[SpeedBand.b90to120]!;
      // 60 s cruising plus the ~2 s of accelerating through each band.
      expect(slow.wobbleRms.total, inInclusiveRange(50, 65));
      expect(fast.wobbleRms.total, inInclusiveRange(50, 65));
      expect(slow.peakG.total, slow.wobbleRms.total);
      expect(slow.wobbleHz.total, lessThanOrEqualTo(slow.wobbleRms.total));
      expect(noise.bands[SpeedBand.b120plus], isNull);
      // Every band second is also in the ride-wide histograms.
      final inBands = noise.bands.values.fold(
        0.0,
        (s, b) => s + b.wobbleRms.total,
      );
      expect(inBands, noise.ridingSeconds);

      final api = noise.toApiJson(SafetyTuning.defaults);
      final bands = (api['bands'] as List).cast<Map<String, dynamic>>();
      expect(bands.length, lessThanOrEqualTo(5));
      final b = bands.firstWhere((b) => b['band'] == '40-60');
      expect(b['seconds'], slow.wobbleRms.total.round());
      expect(b['wobble_hz']['min'], 0.5);
      expect(b['wobble_hz']['max'], 25);
      for (final key in ['wobble_rms', 'wobble_hz', 'peak_g']) {
        final h = b[key] as Map<String, dynamic>;
        expect(h['min'], greaterThan(0));
        expect(h['max'], greaterThan(h['min'] as num));
        expect((h['counts'] as List).length, lessThanOrEqualTo(100));
      }
      // Upload-only: the stored baseline is unchanged.
      expect(noise.toJson().keys, ['wobble_rms', 'peak_g', 'imu_hz']);
      // Valid JSON.
      jsonEncode(api);
    });

    test('wobble_hz is the frequency of the wobble-band shake only', () {
      RideNoise ride(Vec3 Function(double) extraRate) {
        final p = _Monitored();
        final sim = RideSimulator(mount: Mount.handlebarPortrait);
        sim.still(p, 5);
        p.captureStillReference();
        sim.accelerateTo(p, 50);
        sim.run(p, 60, leanAt: (_) => 0, extraRate: extraRate);
        expect(p.hazards, isEmpty);
        return p.monitor.takeNoise();
      }

      // 20 Hz buzz, above the wobble band: dominates every second.
      const w20 = 2 * math.pi * 20;
      final buzz = ride(
        (t) => Vec3(0, 0.6 * math.sin(w20 * t), 0),
      ).bands[SpeedBand.b40to60]!;
      expect(buzz.wobbleRms.total, greaterThan(55));
      expect(buzz.wobbleHz.total, lessThan(buzz.wobbleRms.total * 0.2));
      expect(buzz.wobbleHz.quantile(1)!, lessThanOrEqualTo(13));

      // 9 Hz shake, inside the band: every second has its frequency.
      final shake = ride(_vibration(0.35)).bands[SpeedBand.b40to60]!;
      expect(shake.wobbleHz.total, shake.wobbleRms.total);
      expect(shake.wobbleHz.quantile(0.5)!, closeTo(9, 1));
    });

    test('speed bands', () {
      expect(SpeedBand.of(19.9), isNull);
      expect(SpeedBand.of(20), SpeedBand.b20to40);
      expect(SpeedBand.of(40), SpeedBand.b40to60);
      expect(SpeedBand.of(89.9), SpeedBand.b60to90);
      expect(SpeedBand.of(119), SpeedBand.b90to120);
      expect(SpeedBand.of(300), SpeedBand.b120plus);
      expect(SpeedBand.of(double.nan), isNull);
      expect(
        [for (final b in SpeedBand.values) b.apiName],
        ['20-40', '40-60', '60-90', '90-120', '120+'],
      );
    });
  });
}
