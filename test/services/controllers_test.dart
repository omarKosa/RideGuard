import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/calibration/calibration_session.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/calibration_controller.dart';
import 'package:ride_guard/services/ride_controller.dart';
import 'package:ride_guard/services/sensor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/ride_simulator.dart';

/// Forwards what the simulator would feed a pipeline into a fake sensor
/// source instead, so the real SensorFeed/controller path is exercised.
class _SourcePipe extends MotionPipeline {
  _SourcePipe(this.source);

  final FakeSensorSource source;
  final _ts = DateTime.utc(2026);
  double t = 0;

  DateTime get _now => _ts.add(Duration(microseconds: (t * 1e6).round()));

  @override
  void addAccel(accel, double t) {
    this.t = t;
    source.accel.add(ImuEvent(accel, _now));
  }

  @override
  void addLinearAccel(accel, double t) =>
      source.linear.add(ImuEvent(accel, _now));

  @override
  void addGyro(rate, double t, double dt) =>
      source.gyro.add(ImuEvent(rate, _now));

  @override
  void addGps(GpsFix fix) => source.gps.add(
    LocationEvent(
      speedMps: fix.speedMps,
      latitude: 30,
      longitude: 31,
      accuracyM: 4,
      speedAccuracyMps: 0.3,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'init ride then a real ride, end to end through the controllers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final stack = offlineFirstStack();
      final app = AppState(
        store: await LocalStore.open(),
        remote: stack.remote,
      );
      await app.load();
      await app.saveBike(model: 'KTM 390 Duke', ratedTopSpeedKmh: 165);

      final source = FakeSensorSource();
      final mount = Mount.euler(70, 35, -110); // phone in an odd holder
      Future<void> noop(bool _) async {}

      // ---- Calibration ----
      final pipe = _SourcePipe(source);
      // Sensor time follows the simulation, not the wall clock.
      SensorFeed feed() => SensorFeed(source, clock: () => pipe.t);
      final cal = CalibrationController(
        app: app,
        feed: feed(),
        keepAwake: noop,
      );
      await tester.runAsync(cal.start);
      final sim = RideSimulator(mount: mount);

      // Real time must pass for the 10 Hz ticker, so stream in chunks.
      Future<void> drive(void Function() segment) async {
        segment();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
      }

      for (var i = 0; i < 6; i++) {
        await drive(() => sim.still(pipe, 1));
      }
      expect(cal.session!.states[CalibrationTask.holdStill], TaskState.done);

      await tester.runAsync(() async {
        cal.skip(); // straight line (needs many real-time ticks)
        cal.skip(); // top speed
        cal.skip(); // brake
        cal.skip(); // turns
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(cal.phase, CalibrationPhase.finished);
      final result = cal.result!;
      expect(result.skippedTasks, hasLength(4));
      expect(result.quality, lessThan(0.6));
      expect(result.params.mount.up.angleTo(mount.upInPhone), lessThan(0.05));
      await tester.runAsync(cal.accept);
      expect(app.startupStep, StartupStep.ready);
      cal.dispose();

      // ---- Ride ----
      final ride = RideController(app: app, feed: feed(), keepAwake: noop);
      await tester.runAsync(ride.start);
      for (var i = 0; i < 3; i++) {
        await drive(() => sim.still(pipe, 1));
      }
      await drive(() => sim.accelerateTo(pipe, 50));
      for (var i = 0; i < 4; i++) {
        await drive(() => sim.cruise(pipe, 1));
      }
      expect(ride.state!.speedKmh, closeTo(50, 3));
      final summary = (await tester.runAsync(ride.stop))!;
      ride.dispose();

      expect(app.lastRide!.rideId, summary.rideId);
      expect(summary.totals.maxSpeedKmh, closeTo(50, 3));
      expect(summary.sampleCount, greaterThan(5));

      await tester.runAsync(stack.sync.flush);
      final paths = stack.backend.requests.map((r) => r.url.path).toList();
      // Calibration ride, its calibration record, then the real ride.
      expect(paths.where((p) => p.startsWith('/v1/calibrations/')).length, 1);
      expect(paths.where((p) => p.endsWith('/summary')).length, 2);
      final rideHeader = stack.backend
          .bodiesFor('PUT', RegExp('/v1/rides/${summary.rideId}\$'))
          .single;
      expect(rideHeader['calibration_id'], result.id);
    },
  );
}
