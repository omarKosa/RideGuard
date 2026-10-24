// End-to-end check against the real backend + Postgres:
//
//   docker compose up -d
//   RIDEGUARD_LIVE_API=http://localhost:8000 flutter test test/integration
//
// A simulated init ride and a regular ride (phone in an awkward mount) go
// through the app's real pipeline, recorder, outbox and HTTP client; the test
// then reads them back from the API and checks what Postgres stored.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ride_guard/core/calibration/calibration_session.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/core/safety/safety_tuning.dart';
import 'package:ride_guard/data/api_client.dart';
import 'package:ride_guard/data/outbox.dart';
import 'package:ride_guard/data/remote_repository.dart';
import 'package:ride_guard/data/sync_service.dart';
import 'package:ride_guard/models/bike_profile.dart';
import 'package:ride_guard/models/incident.dart';
import 'package:ride_guard/models/ride_summary.dart';
import 'package:ride_guard/services/calibration_profile_builder.dart';
import 'package:ride_guard/services/phone_info.dart';
import 'package:ride_guard/services/ride_recorder.dart';
import 'package:uuid/uuid.dart';

import '../support/ride_simulator.dart';

final _api = Platform.environment['RIDEGUARD_LIVE_API'];

void main() {
  const uuid = Uuid();

  Future<Map<String, dynamic>> get(String path) async {
    final r = await http.get(Uri.parse('$_api$path'));
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  test('init ride + ride are stored correctly in Postgres', () async {
    final client = ApiClient(baseUrl: () => _api!);
    expect(await client.isHealthy(), isTrue, reason: 'backend at $_api');
    final sync = SyncService(api: client, store: MemoryOutboxStore());
    final remote = RemoteRepository(sync);

    final riderId = uuid.v4();
    final bike = BikeProfile(
      id: uuid.v4(),
      model: 'Live Test MT-09',
      ratedTopSpeedKmh: 225,
      createdAt: DateTime.now(),
    );
    await remote.upsertRider(riderId, PhoneInfo.unknown);
    await remote.upsertBike(riderId, bike);

    // Sensor time is simulated, but timestamps must be "now" for the
    // server's clock checks.
    final mount = Mount.euler(-30, 140, 65); // upside-down-ish, twisted
    final sim = RideSimulator(mount: mount);
    final wallStart = DateTime.now().toUtc().subtract(
      const Duration(minutes: 10),
    );
    DateTime wall(SimTick t) => wallStart.add(t.time.difference(sim.start));
    var now = wallStart;

    // ---------------- Init ride ----------------
    final calPipeline = MotionPipeline(learningMode: true);
    final session = CalibrationSession(
      pipeline: calPipeline,
      ratedTopSpeedKmh: bike.ratedTopSpeedKmh,
    );
    final calRecorder = RideRecorder(
      rideId: uuid.v4(),
      kind: RideKind.calibration,
      bikeId: bike.id,
      remote: remote,
      clock: () => now,
    );
    await calRecorder.start();
    void calTick(SimTick t) {
      now = wall(t);
      calRecorder.record(t.state);
      session.update(t.state, now);
    }

    final p = calPipeline;
    sim.still(p, 6, leanDeg: -7, onTick: calTick); // left on the side stand
    sim.accelerateTo(p, 45, onTick: calTick);
    sim.cruise(p, 12, onTick: calTick);
    sim.accelerateTo(p, 168, accel: 3.2, onTick: calTick);
    sim.accelerateTo(p, 60, accel: 1.0, onTick: calTick);
    sim.cruise(p, 3, onTick: calTick);
    sim.brakeToStop(p, decel: 7, onTick: calTick);
    sim.still(p, 1, onTick: calTick);
    sim.accelerateTo(p, 40, onTick: calTick);
    sim.turn(p, -22, 6, onTick: calTick);
    sim.cruise(p, 3, onTick: calTick);
    sim.turn(p, 24, 6, onTick: calTick);
    sim.cruise(p, 2, onTick: calTick);
    expect(session.isFinished, isTrue);
    expect(session.skippedTasks, isEmpty);

    final calSummary = await calRecorder.finish();
    final profile = buildCalibrationProfile(
      id: uuid.v4(),
      bikeId: bike.id,
      summary: calSummary,
      session: session,
      pipeline: calPipeline,
      calibratedAt: now,
    )!;
    expect(profile.quality, greaterThan(0.9));
    await remote.saveCalibration(profile);

    // ---------------- Regular ride ----------------
    final ride = MotionPipeline(params: profile.params);
    final rideRecorder = RideRecorder(
      rideId: uuid.v4(),
      kind: RideKind.ride,
      bikeId: bike.id,
      calibrationId: profile.id,
      remote: remote,
      clock: () => now,
    );
    await rideRecorder.start();
    void rideTick(SimTick t) {
      now = wall(t);
      rideRecorder.record(t.state);
    }

    sim.still(ride, 3, onTick: rideTick);
    sim.accelerateTo(ride, 110, onTick: rideTick);
    sim.cruise(ride, 10, onTick: rideTick);
    sim.turn(ride, 42, 8, onTick: rideTick);
    sim.cruise(ride, 5, onTick: rideTick);
    sim.turn(ride, -36, 8, onTick: rideTick);
    sim.brakeToStop(ride, decel: 8, onTick: rideTick);
    sim.still(ride, 2, onTick: rideTick);
    final rideSummary = await rideRecorder.finish();

    // ---------------- Deliver and verify ----------------
    await sync.flush();
    expect(sync.pending, 0, reason: sync.lastError);
    expect(sync.dropped, 0, reason: sync.lastError);

    final stored = await get('/v1/rides/${rideSummary.rideId}');
    expect(stored['status'], 'completed');
    expect(stored['calibration_id'], profile.id);
    expect(stored['stored_sample_count'], rideSummary.sampleCount);
    expect(stored['reported_sample_count'], rideSummary.sampleCount);
    expect(stored['max_lean_right_deg'] as num, closeTo(42, 3.5));
    expect(stored['max_lean_left_deg'] as num, closeTo(36, 3.5));
    expect(stored['max_speed_kmh'] as num, closeTo(110, 3));
    expect((stored['brake_events'] as List).length, 1);

    // Server recomputes the window from the raw rows and agrees.
    final analysis = await get(
      '/v1/rides/${rideSummary.rideId}/analysis?window_min=15',
    );
    expect(
      analysis['max_speed_kmh'] as num,
      closeTo(rideSummary.window.maxSpeedKmh, 0.05),
    );
    expect(
      analysis['max_lean_right_deg'] as num,
      closeTo(rideSummary.window.maxLeanRightDeg, 0.05),
    );
    expect(
      analysis['max_lean_left_deg'] as num,
      closeTo(rideSummary.window.maxLeanLeftDeg, 0.05),
    );

    final cal = await get('/v1/calibrations/${profile.id}');
    expect(cal['achieved_top_speed_kmh'] as num, closeTo(168, 3));
    expect(cal['stop_time_s'] as num, closeTo(60 / 3.6 / 7, 1.0));
    expect(cal['forward_from_motion'], isTrue);
    // The side-stand offset was learned and normalized.
    expect((cal['straight_offset_deg'] as num).abs(), closeTo(7, 1.5));

    final stats = await get('/v1/bikes/${bike.id}/stats');
    expect(stats['ride_count'], 1);
    expect((stats['latest_calibration'] as Map)['id'], profile.id);

    // ignore: avoid_print
    print(
      'LIVE OK bike=${bike.id} ride=${rideSummary.rideId} '
      'cal=${profile.id} samples=${rideSummary.sampleCount}',
    );
  }, skip: _api == null ? 'set RIDEGUARD_LIVE_API to run' : false);

  test('detected hazards are stored as incidents', () async {
    final client = ApiClient(baseUrl: () => _api!);
    final sync = SyncService(api: client, store: MemoryOutboxStore());
    final remote = RemoteRepository(sync);
    final riderId = uuid.v4();
    final bike = BikeProfile(
      id: uuid.v4(),
      model: 'Live Test Crash',
      ratedTopSpeedKmh: 200,
      createdAt: DateTime.now(),
    );
    await remote.upsertRider(riderId, PhoneInfo.unknown);
    await remote.upsertBike(riderId, bike);

    final sim = RideSimulator(mount: Mount.handlebarPortrait);
    final wallStart = DateTime.now().toUtc().subtract(
      const Duration(minutes: 5),
    );
    var now = wallStart;
    final recorder = RideRecorder(
      rideId: uuid.v4(),
      kind: RideKind.ride,
      bikeId: bike.id,
      remote: remote,
      clock: () => now,
    );
    await recorder.start();

    final p = MotionPipeline();
    final incidents = <Incident>[];
    final monitor = SafetyMonitor(
      onHazard: (h) => incidents.add(
        Incident.fromHazard(
          id: uuid.v4(),
          rideId: recorder.rideId,
          hazard: h,
          detectedAt: now,
        ),
      ),
    );
    // Raw IMU straight to the monitor, like SensorFeed does.
    final feed = _MonitoredPipeline(p, monitor);
    void tick(SimTick t) {
      now = wallStart.add(t.time.difference(sim.start));
      recorder.record(t.state);
      monitor.update(t.state, p.mount);
    }

    sim.still(feed, 5, onTick: tick);
    p.captureStillReference();
    sim.accelerateTo(feed, 110, onTick: tick);
    sim.cruise(feed, 5, onTick: tick);
    sim.wobble(feed, 7, 3, 2, onTick: tick);
    sim.accelerateTo(feed, 50, accel: 2, onTick: tick);
    sim.cruise(feed, 3, onTick: tick);
    sim.lowside(feed, onTick: tick);
    sim.still(feed, 6, leanDeg: 85, onTick: tick);
    expect(incidents.map((i) => i.kind), [
      HazardKind.wobble,
      HazardKind.impact,
      HazardKind.crash,
    ]);

    for (final i in incidents) {
      await remote.saveIncident(i);
    }
    final crash = incidents.last;
    now = now.add(const Duration(seconds: 30));
    await remote.saveIncident(crash.resolve(IncidentOutcome.called, now));
    // The rider says the wobble was road buzz.
    await remote.saveIncident(incidents.first.markedFalseAlarm());
    final noise = monitor.takeNoise();
    await recorder.finish(safetyStats: noise.toApiJson(SafetyTuning.defaults));

    await sync.flush();
    expect(sync.pending, 0, reason: sync.lastError);
    expect(sync.dropped, 0, reason: sync.lastError);

    final r = await http.get(
      Uri.parse('$_api/v1/rides/${recorder.rideId}/incidents'),
    );
    expect(r.statusCode, 200, reason: r.body);
    final stored = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    expect(stored.map((i) => i['kind']), ['wobble', 'impact', 'crash']);
    expect(stored[0]['wobble_hz'] as num, closeTo(7, 1));
    expect(stored[0]['outcome'], 'warned');
    expect(stored[0]['false_alarm'], isTrue);
    expect(stored[0]['wobble_rms'] as num, greaterThan(1));
    expect(stored[2]['outcome'], 'called');
    expect(stored[2]['speed_kmh'] as num, greaterThan(20));
    expect(stored[2]['false_alarm'], isFalse);

    final ride = await get('/v1/rides/${recorder.rideId}');
    final stats = ride['safety_stats'] as Map<String, dynamic>;
    expect(stats['riding_s'], noise.ridingSeconds.round());
    expect(stats['imu_hz'], 50);
    expect(stats['wobble_threshold_rms'], SafetyTuning.defaultWobbleRms);
  }, skip: _api == null ? 'set RIDEGUARD_LIVE_API to run' : false);
}

/// Forwards raw IMU readings to both the pipeline and the monitor.
class _MonitoredPipeline extends MotionPipeline {
  _MonitoredPipeline(this.inner, this.monitor);

  final MotionPipeline inner;
  final SafetyMonitor monitor;

  @override
  void addAccel(accel, double t) {
    inner.addAccel(accel, t);
    monitor.addAccel(accel, t);
  }

  @override
  void addLinearAccel(accel, double t) => inner.addLinearAccel(accel, t);

  @override
  void addGyro(rate, double t, double dt) {
    inner.addGyro(rate, t, dt);
    monitor.addGyro(rate, t, dt);
  }

  @override
  void addGps(GpsFix fix) => inner.addGps(fix);

  @override
  MotionState snapshot() => inner.snapshot();
}
