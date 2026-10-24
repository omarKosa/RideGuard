import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/performance_meter.dart';
import 'package:ride_guard/core/catalogue/spec_check.dart';
import 'package:ride_guard/models/brake_event.dart';
import 'package:ride_guard/models/catalogue_model.dart';

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
    expect(c.envelope!.maxAccelMps2, closeTo(2.5, 1e-9));
    expect(c.results[SpecItem.acceleration], CheckResult.mismatch);
    expect(c.mismatch, isTrue);
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
      PerformanceReadings(peakDecelMps2: 8, stops: [stop]),
    );
    expect(c.results[SpecItem.braking], CheckResult.mismatch);
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
}
