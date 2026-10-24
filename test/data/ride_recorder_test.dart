import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/models/ride_summary.dart';
import 'package:ride_guard/services/ride_recorder.dart';

import '../support/fakes.dart';
import '../support/ride_simulator.dart';

void main() {
  test(
    'uploads header, numbered samples in batches, then the summary',
    () async {
      final s = offlineFirstStack();
      final sim = RideSimulator(mount: Mount.euler(25, 120, -40));
      var now = sim.start;
      final recorder = RideRecorder(
        rideId: 'ride-1',
        kind: RideKind.ride,
        bikeId: 'bike-1',
        calibrationId: 'cal-1',
        remote: s.remote,
        clock: () => now,
      );
      await recorder.start();

      final p = MotionPipeline();
      void tick(SimTick t) {
        now = t.time;
        recorder.record(t.state);
      }

      sim.still(p, 5, onTick: tick);
      sim.accelerateTo(p, 80, onTick: tick);
      sim.turn(p, 35, 8, onTick: tick);
      sim.brakeToStop(p, decel: 7, onTick: tick);
      sim.still(p, 2, onTick: tick);
      final summary = await recorder.finish(
        performance: {'sustained_top_speed_kmh': 80.0, 'stops': []},
      );
      await s.sync.flush();

      final header = s.backend.bodiesFor('PUT', RegExp(r'/v1/rides/ride-1$'));
      expect(header.single, containsPair('kind', 'ride'));
      expect(header.single, containsPair('calibration_id', 'cal-1'));
      expect(header.single, containsPair('analysis_window_min', 15));

      final batches = s.backend.bodiesFor('POST', '/samples');
      final samples = [
        for (final b in batches) ...(b['samples'] as List<dynamic>),
      ].cast<Map<String, dynamic>>();
      expect(batches.length, greaterThan(1));
      expect(samples.length, summary.sampleCount);
      expect([
        for (final x in samples) x['seq'],
      ], List.generate(samples.length, (i) => i));

      for (final x in samples) {
        // Matches the backend's validation rules.
        expect(x['speed_kmh'] as num, inInclusiveRange(0, 500));
        expect(x['lean_deg'] as num, inInclusiveRange(-90, 90));
        expect([
          'none',
          'gps',
          'deadReckoning',
          'stale',
        ], contains(x['speed_source']));
        expect(DateTime.parse(x['recorded_at'] as String).isUtc, isTrue);
      }
      final peakLean = samples
          .map((x) => (x['lean_deg'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
      expect(peakLean, closeTo(35, 3.5));

      final posted = s.backend.bodiesFor('PUT', '/summary').single;
      expect(posted['status'], 'completed');
      final totals = posted['totals'] as Map<String, dynamic>;
      expect(totals['max_speed_kmh'] as num, closeTo(80, 3));
      expect(totals['max_lean_right_deg'] as num, closeTo(35, 3.5));
      expect(totals['brake_event_count'], 1);
      expect(
        (posted['brake_events'] as List<dynamic>).single['start_speed_kmh']
            as num,
        closeTo(80, 4),
      );
      expect(posted['performance']['sustained_top_speed_kmh'], 80);

      // Kept with the last ride on the phone.
      final stored = RideSummary.fromJson(
        jsonDecode(jsonEncode(summary.toJson())) as Map<String, dynamic>,
      );
      expect(stored.performance, summary.performance);
    },
  );
}
