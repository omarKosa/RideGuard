import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/brake_detector.dart';
import 'package:ride_guard/core/analysis/performance_meter.dart';
import 'package:ride_guard/core/catalogue/spec_check.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/models/brake_event.dart';
import 'package:ride_guard/models/catalogue_model.dart';

import '../support/fakes.dart';
import '../support/ride_simulator.dart';

/// A pipeline whose GPS can be cut off (tunnel, lost fix).
class _GpsGated extends MotionPipeline {
  bool blocked = false;

  @override
  void addGps(GpsFix fix) {
    if (!blocked) super.addGps(fix);
  }
}

/// A single wild fix, as phones sometimes report.
GpsFix _spike(RideSimulator sim) => GpsFix(
  t: sim.t,
  speedMps: 400 / 3.6,
  latitude: 30,
  longitude: 31,
  accuracyM: 4,
);

SpecValue _v(double v) =>
    SpecValue(value: v, source: 'https://x', quality: SpecQuality.official);

final gsx = CatalogueModel(
  id: 'suzuki-gsx-s1000',
  make: 'Suzuki',
  model: 'GSX-S1000',
  yearFrom: 2021,
  yearTo: null,
  markets: {'TR'},
  category: BikeCategory.naked,
  abs: AbsFitment.yes,
  displacementCc: _v(999),
  topSpeedKmh: _v(250),
  zeroTo100S: _v(3.1),
);

final scooter = CatalogueModel(
  id: 'scooter',
  make: 'X',
  model: 'Y',
  yearFrom: 2020,
  yearTo: null,
  markets: {'TR'},
  category: BikeCategory.scooter,
  abs: AbsFitment.no,
  displacementCc: _v(125),
  powerKw: _v(8.5),
  weightKg: _v(130),
);

void main() {
  test('gentle init ride is not tested, never mismatch', () {
    const r = PerformanceReadings(
      sustainedTopSpeedKmh: 90,
      peakAccelMps2: 3,
      peakDecelMps2: 4,
    );
    final c = SpecCheck.run(gsx, r);
    expect(c.results.values.every((x) => x == CheckResult.notTested), isTrue);
    expect(c.mismatch, isFalse);
  });

  test('impossible top speed is a mismatch', () {
    expect(
      SpecCheck.run(
        gsx,
        const PerformanceReadings(sustainedTopSpeedKmh: 272),
      ).results[SpecItem.topSpeed],
      CheckResult.mismatch,
    );
    expect(
      SpecCheck.run(
        gsx,
        const PerformanceReadings(sustainedTopSpeedKmh: 270),
      ).results[SpecItem.topSpeed],
      CheckResult.match,
    );
  });

  test('scooter acceleration envelope from power to weight', () {
    final c = SpecCheck.run(
      scooter,
      const PerformanceReadings(peakAccelMps2: 3.5),
    );
    expect(c.envelope!.maxAccelMps2, closeTo(5.0, 1e-9));
    expect(c.results[SpecItem.acceleration], isNot(CheckResult.mismatch));
    expect(c.mismatch, isFalse);
    final hard = SpecCheck.run(
      scooter,
      const PerformanceReadings(peakAccelMps2: 6.5),
    );
    expect(hard.results[SpecItem.acceleration], CheckResult.mismatch);
    expect(hard.mismatch, isTrue);
  });

  test('a 125 commuter launching at 4 m/s2 is never a mismatch', () {
    final commuter = CatalogueModel(
      id: 'commuter-125',
      make: 'X',
      model: 'Z',
      yearFrom: 2020,
      yearTo: null,
      markets: {'TR'},
      category: BikeCategory.commuter,
      abs: AbsFitment.no,
      displacementCc: _v(125),
      powerKw: _v(6.5),
      weightKg: _v(120),
    );
    const launch = PerformanceReadings(peakAccelMps2: 4);
    expect(
      SpecCheck.run(commuter, launch).results[SpecItem.acceleration],
      isNot(CheckResult.mismatch),
    );
    // Nor any small bike in the shipped catalogue.
    final cat = realCatalogue();
    final small = [
      for (final make in cat.makes)
        ...cat.modelsFor(make).where((m) => m.displacementCc.value <= 125),
    ];
    expect(small, isNotEmpty);
    for (final m in small) {
      expect(
        SpecCheck.run(m, launch).results[SpecItem.acceleration],
        isNot(CheckResult.mismatch),
        reason: m.id,
      );
    }
  });

  test('braking beyond tyre grip', () {
    final c = SpecCheck.run(
      gsx,
      const PerformanceReadings(peakDecelMps2: 13.5),
    );
    expect(c.envelope!.maxDecelMps2, closeTo(1.1 * 9.81, 1e-9));
    expect(c.results[SpecItem.braking], CheckResult.mismatch);
    final s = SpecCheck.run(
      scooter,
      const PerformanceReadings(peakDecelMps2: 9.6),
    );
    expect(s.envelope!.maxDecelMps2, closeTo(0.8 * 9.81, 1e-9));
    expect(s.results[SpecItem.braking], CheckResult.mismatch);
  });

  test('a single impossible stop is a mismatch', () {
    final t = DateTime.utc(2026);
    final stop = BrakeEvent(
      startedAt: t,
      endedAt: t.add(const Duration(seconds: 2)),
      startSpeedKmh: 100,
      distanceM: 30,
      peakDecelMps2: 8,
    );
    final c = SpecCheck.run(
      gsx,
      PerformanceReadings(
        sustainedTopSpeedKmh: 110,
        peakDecelMps2: 8,
        stops: [stop],
      ),
    );
    expect(c.results[SpecItem.braking], CheckResult.mismatch);
    // Without a sustained top speed a glitch can't be ruled out: only the
    // peak deceleration is judged.
    expect(
      SpecCheck.run(
        gsx,
        PerformanceReadings(peakDecelMps2: 8, stops: [stop]),
      ).results[SpecItem.braking],
      CheckResult.notTested,
    );
    // A stop starting far above anything sustained began at a glitch.
    expect(
      SpecCheck.run(
        gsx,
        PerformanceReadings(
          sustainedTopSpeedKmh: 60,
          peakDecelMps2: 8,
          stops: [stop],
        ),
      ).results[SpecItem.braking],
      CheckResult.notTested,
    );
  });

  test('gsx acceleration envelope and api json', () {
    final e = ModelEnvelope.of(gsx);
    expect(e.maxAccelMps2, closeTo(1.1 * 9.81, 1e-9));
    expect(e.toApiJson().keys, [
      'top_speed_kmh',
      'max_accel_mps2',
      'max_decel_mps2',
    ]);
  });

  test('other bike has no envelope', () {
    final c = SpecCheck.run(null, const PerformanceReadings(peakDecelMps2: 50));
    expect(c.envelope, isNull);
    expect(c.results.values.every((x) => x == CheckResult.notTested), isTrue);
    expect(c.mismatch, isFalse);
    expect(c.resultsApiJson(), {
      'top_speed': 'not_tested',
      'acceleration': 'not_tested',
      'braking': 'not_tested',
    });
  });

  group('GPS glitches on the init ride', () {
    final gsx2015 = realCatalogue().byId('suzuki-gsx-s1000-2015')!;

    test('a spike then a GPS gap is not a sustained top speed', () {
      final p = _GpsGated();
      final sim = RideSimulator(mount: Mount.handlebarPortrait);
      sim.still(p, 5);
      p.captureStillReference();
      final m = PerformanceMeter();
      void feed(SimTick k) => m.add(k.state);
      sim.accelerateTo(p, 60, onTick: feed);
      sim.cruise(p, 10, onTick: feed);
      p.addGps(_spike(sim));
      p.blocked = true;
      sim.cruise(p, 3.9, onTick: feed);
      p.blocked = false;
      sim.cruise(p, 10, onTick: feed);

      final r = m.readings;
      expect(r.sustainedTopSpeedKmh, inInclusiveRange(55, 65));
      final c = SpecCheck.run(gsx2015, r);
      expect(c.results[SpecItem.topSpeed], isNot(CheckResult.mismatch));
      expect(c.mismatch, isFalse);
    });

    test('a spike just before a stop is not impossible braking', () {
      final p = MotionPipeline();
      final sim = RideSimulator(mount: Mount.handlebarPortrait);
      sim.still(p, 5);
      p.captureStillReference();
      final m = PerformanceMeter();
      final brakes = BrakeDetector();
      void feed(SimTick k) {
        m.add(k.state);
        final e = brakes.add(k.time, k.state.speedKmh);
        if (e != null) m.addStop(e);
      }

      sim.accelerateTo(p, 50, onTick: feed);
      sim.cruise(p, 10.3, onTick: feed);
      p.addGps(_spike(sim));
      sim.brakeToStop(p, decel: 4, onTick: feed);
      sim.still(p, 3, onTick: feed);

      final r = m.readings;
      // The glitch did produce a "stop from 400 km/h"...
      expect(r.stops.map((s) => s.startSpeedKmh), contains(greaterThan(300)));
      final c = SpecCheck.run(gsx2015, r);
      // ...which is not judged, nor uploaded.
      expect(c.results[SpecItem.braking], isNot(CheckResult.mismatch));
      expect(c.mismatch, isFalse);
      final sent = (r.toApiJson()['stops'] as List).cast<Map>();
      expect(sent.every((s) => (s['start_speed_kmh'] as num) < 100), isTrue);
    });
  });
}
