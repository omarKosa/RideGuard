import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ride_guard/app.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/fusion/mount_orientation.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/data/api_client.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/models/bike_choice.dart';
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/screens/safety_briefing_screen.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<(AppState, Widget, RecordingBackend)> buildApp() async {
  final stack = offlineFirstStack();
  final app = AppState(
    store: await LocalStore.open(),
    remote: stack.remote,
    catalogue: realCatalogue(),
  );
  await app.load();
  final widget = RideGuardApp(
    appState: app,
    sync: stack.sync,
    api: ApiClient(baseUrl: () => 'http://x', client: stack.backend.client),
    sensors: FakeSensorSource(),
    emergency: FakeEmergencyPlatform(),
  );
  return (app, widget, stack.backend);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch asks for the bike, validates, then briefs safety', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (app, widget, backend) = await buildApp();
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('SET UP YOUR BIKE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-bike')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your motorcycle model'), findsOneWidget);
    expect(find.text('Enter a speed in km/h'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('model-field')),
      'Yamaha MT-07',
    );
    await tester.enterText(find.byKey(const Key('top-speed-field')), '900');
    await tester.tap(find.byKey(const Key('save-bike')));
    await tester.pumpAndSettle();
    expect(find.text('Between 40 and 420 km/h'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('top-speed-field')), '214');
    await tester.tap(find.byKey(const Key('save-bike')));
    await tester.pumpAndSettle();

    expect(app.bike!.model, 'Yamaha MT-07');
    expect(app.bike!.ratedTopSpeedKmh, 214);
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
    // Rider and bike were sent to the backend.
    expect(
      backend.requests.map((r) => r.url.path),
      containsAllInOrder([
        '/v1/riders/${app.riderId}',
        '/v1/bikes/${app.bike!.id}',
      ]),
    );

    // The init ride can't start until every risk is acknowledged.
    final start = find.byKey(const Key('start-calibration'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);

    for (var i = 0; i < SafetyBriefingScreen.acknowledgements.length; i++) {
      final box = find.byKey(Key('ack-$i'));
      await tester.ensureVisible(box);
      await tester.tap(box);
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(start);
    await tester.tap(start);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('HOLD STILL'), findsOneWidget);
    expect(find.text('TASK 1 OF 5'), findsOneWidget);
  });

  testWidgets('a calibrated rider lands on the home screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (app, _, _) = await buildApp();
    final bike = await app.saveBike(
      const OtherChoice(make: 'Ducati', model: 'Monster', topSpeedKmh: 230),
    );
    await app.saveCalibration(
      CalibrationProfile(
        id: 'cal',
        bikeId: bike.id,
        rideId: 'ride',
        calibratedAt: DateTime.utc(2026, 10, 22),
        params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
        forwardFromMotion: true,
        straightOffsetDeg: 2,
        quality: 0.9,
        achievedTopSpeedKmh: 180,
      ),
    );

    // Fresh process: state comes back from storage.
    final (reloaded, widget, _) = await buildApp();
    expect(reloaded.startupStep, StartupStep.ready);
    await tester.pumpWidget(widget);
    // The start button pulses forever, so pump instead of settling.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('START RIDE'), findsOneWidget);
    expect(find.textContaining('Ducati Monster'), findsOneWidget);
    expect(find.text('180'), findsOneWidget);
  });

  testWidgets('a legacy stored bike still opens on the home screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cal = CalibrationProfile(
      id: 'cal',
      bikeId: 'legacy',
      rideId: 'ride',
      calibratedAt: DateTime.utc(2026, 10, 22),
      params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
      forwardFromMotion: true,
      straightOffsetDeg: 2,
      quality: 0.9,
      achievedTopSpeedKmh: 180,
    );
    SharedPreferences.setMockInitialValues({
      'bike': jsonEncode({
        'id': 'legacy',
        'model': 'Yamaha MT-07',
        'rated_top_speed_kmh': 214,
        'created_at': '2026-10-01T00:00:00Z',
      }),
    });
    final (seed, _, _) = await buildApp();
    await seed.saveCalibration(cal);

    final (app, widget, _) = await buildApp();
    expect(app.bike!.isOther, isTrue);
    expect(app.bike!.otherModel, 'Yamaha MT-07');
    expect(app.startupStep, StartupStep.ready);
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('START RIDE'), findsOneWidget);
    expect(find.textContaining('Yamaha MT-07'), findsOneWidget);
  });
}
