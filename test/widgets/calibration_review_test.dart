import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/fusion/mount_orientation.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/models/bike_choice.dart';
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/screens/calibration/calibration_screen.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/calibration_controller.dart';
import 'package:ride_guard/services/safety_controller.dart';
import 'package:ride_guard/services/sensor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// An init ride that has just finished, without riding it.
class _FinishedInitRide extends CalibrationController {
  _FinishedInitRide({required super.app, required super.safety, this.done})
    : super(feed: SensorFeed(FakeSensorSource()));

  final CalibrationProfile? done;

  @override
  CalibrationPhase get phase => CalibrationPhase.finished;

  @override
  CalibrationProfile? get result => done;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FinishedInitRide> pumpFinished(
    WidgetTester tester, {
    required bool alerts,
  }) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final stack = offlineFirstStack();
    final app = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      catalogue: realCatalogue(),
    );
    await app.load();
    final bike = await app.saveBike(
      const OtherChoice(make: 'KTM', model: '390 Duke', topSpeedKmh: 165),
    );
    final safety = SafetyController(app: app, platform: FakeEmergencyPlatform())
      ..begin('cal-ride');
    if (alerts) {
      safety
        ..report(
          const Hazard(
            kind: HazardKind.wobble,
            t: 1,
            speedKmh: 95,
            leanDeg: 2,
            wobbleHz: 8.5,
            wobbleRms: 0.62,
          ),
        )
        ..report(
          const Hazard(
            kind: HazardKind.impact,
            t: 2,
            speedKmh: 62,
            leanDeg: 1,
            peakAccelG: 4.6,
          ),
        );
    }
    safety.end();
    final cal = _FinishedInitRide(
      app: app,
      safety: safety,
      done: CalibrationProfile(
        id: 'cal-1',
        bikeId: bike.id,
        rideId: 'cal-ride',
        calibratedAt: DateTime.utc(2026, 10, 24),
        params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
        forwardFromMotion: true,
        straightOffsetDeg: 0,
        quality: 0.9,
      ),
    );
    addTearDown(safety.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider<SafetyController>.value(value: safety),
          ChangeNotifierProvider<CalibrationController>.value(value: cal),
        ],
        child: const MaterialApp(home: CalibrationView()),
      ),
    );
    await tester.pumpAndSettle();
    return cal;
  }

  testWidgets('init ride alerts are asked about before the result', (
    tester,
  ) async {
    final cal = await pumpFinished(tester, alerts: true);
    expect(find.text('ALERT 1 OF 2'), findsOneWidget);
    expect(find.byKey(const Key('alert-card')), findsOneWidget);
    expect(find.text('CALIBRATED'), findsNothing);

    await tester.tap(find.byKey(const Key('alert-no')));
    await tester.pumpAndSettle();
    expect(find.text('ALERT 2 OF 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('alert-yes')));
    await tester.pumpAndSettle();

    expect(find.text('CALIBRATED'), findsOneWidget);
    expect(cal.alertsReviewed, isTrue);
    expect(cal.incidents.map((i) => i.riderLabel?.name), ['no', 'yes']);
  });

  testWidgets('back on the init ride cards skips to the result', (
    tester,
  ) async {
    final cal = await pumpFinished(tester, alerts: true);
    expect(find.byKey(const Key('alert-card')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('alert-card')), findsNothing);
    expect(find.text('CALIBRATED'), findsOneWidget);
    expect(cal.alertsReviewed, isTrue);
    expect(cal.incidents, hasLength(2));
    expect(cal.incidents.every((i) => i.riderLabel == null), isTrue);
  });

  testWidgets('an init ride without alerts goes straight to the result', (
    tester,
  ) async {
    await pumpFinished(tester, alerts: false);
    expect(find.byKey(const Key('alert-card')), findsNothing);
    expect(find.text('CALIBRATED'), findsOneWidget);
  });
}
