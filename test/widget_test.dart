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
import 'package:ride_guard/services/google_auth.dart';
import 'package:ride_guard/widgets/init_ride_warning_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<(AppState, Widget, RecordingBackend)> buildApp({
  bool signedIn = true,
  FakeGoogleAuth? googleAuth,
}) async {
  final stack = offlineFirstStack();
  final store = await LocalStore.open();
  if (signedIn && store.account == null) await store.setAccount(testAccount);
  final app = AppState(
    store: store,
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
    googleAuth: googleAuth ?? FakeGoogleAuth(),
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
    expect(find.text('Choose your make'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('other-bike')));
    await tester.tap(find.byKey(const Key('other-bike')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-bike')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the model'), findsOneWidget);
    expect(find.text('Enter a speed in km/h'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('other-make')), 'Yamaha');
    await tester.enterText(find.byKey(const Key('other-model')), 'MT-07');
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

    // The risks are only shown in a popup when the rider taps start, and
    // the init ride can't begin until every one is acknowledged.
    expect(find.byKey(const Key('ack-0')), findsNothing);
    final start = find.byKey(const Key('start-calibration'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('init-ride-warning')), findsOneWidget);
    final confirm = find.byKey(const Key('confirm-init-ride'));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('init-ride-warning')), findsOneWidget);

    for (var i = 0; i < InitRideWarningDialog.acknowledgements.length; i++) {
      final box = find.byKey(Key('ack-$i'));
      await tester.ensureVisible(box);
      await tester.tap(box);
    }
    await tester.pumpAndSettle();
    await tester.tap(confirm);
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

  testWidgets('a new rider signs in with Google first', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final google = FakeGoogleAuth();
    final (app, widget, backend) = await buildApp(
      signedIn: false,
      googleAuth: google,
    );
    expect(app.startupStep, StartupStep.signIn);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('google-sign-in')), findsOneWidget);

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('SET UP YOUR BIKE'), findsOneWidget);
    expect(app.account!.email, 'mona@example.com');
    // The rider exists on the server before the account is linked to it.
    final paths = backend.requests.map((r) => r.url.path).toList();
    expect(
      paths,
      containsAllInOrder([
        '/v1/riders/${app.riderId}',
        '/v1/riders/${app.riderId}/google',
      ]),
    );
    final link = backend.bodiesFor('PUT', '/v1/riders/${app.riderId}/google');
    expect(link.single['id_token'], google.result.idToken);

    // Signed in for good: the next launch skips the login screen.
    final (reloaded, _, _) = await buildApp(signedIn: false);
    expect(reloaded.startupStep, StartupStep.bikeSetup);
  });

  testWidgets('a failed sign-in explains itself; a cancelled one does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final google = FakeGoogleAuth()
      ..error = const GoogleAuthException('Google sign-in failed.');
    final (app, widget, _) = await buildApp(
      signedIn: false,
      googleAuth: google,
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-error')), findsOneWidget);
    expect(app.account, isNull);

    google.error = const GoogleAuthException('cancelled', cancelled: true);
    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-error')), findsNothing);
    expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
  });

  testWidgets('debug builds can skip sign-in', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (app, widget, _) = await buildApp(signedIn: false);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skip-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('SET UP YOUR BIKE'), findsOneWidget);
    expect(app.account, isNull);
    expect(app.startupStep, StartupStep.bikeSetup);
  });

  testWidgets('the init ride can be skipped and done later from home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (seed, _, _) = await buildApp();
    await seed.saveBike(
      const OtherChoice(make: 'Honda', model: 'PCX 125', topSpeedKmh: 105),
    );
    final (app, widget, _) = await buildApp();
    expect(app.startupStep, StartupStep.calibration);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Cancelling the warning popup stays on the page.
    await tester.ensureVisible(find.byKey(const Key('start-calibration')));
    await tester.tap(find.byKey(const Key('start-calibration')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-init-ride')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('init-ride-warning')), findsNothing);
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('skip-init-ride')));
    await tester.tap(find.byKey(const Key('skip-init-ride')));
    // Home's start button pulses forever, so pump instead of settling.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('START RIDE'), findsOneWidget);
    expect(find.byKey(const Key('init-ride-pending')), findsOneWidget);
    expect(app.initRideSkipped, isTrue);
    final (reloaded, _, _) = await buildApp();
    expect(reloaded.startupStep, StartupStep.ready);

    // From home the init ride is one tap away.
    await tester.ensureVisible(find.byKey(const Key('do-init-ride')));
    await tester.tap(find.byKey(const Key('do-init-ride')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
  });

  testWidgets('skipping the init ride does not carry over to a new bike', (
    tester,
  ) async {
    final (app, _, _) = await buildApp();
    await app.saveBike(
      const OtherChoice(make: 'Honda', model: 'PCX 125', topSpeedKmh: 105),
    );
    await app.skipInitRide();
    expect(app.startupStep, StartupStep.ready);
    await app.saveBike(
      const OtherChoice(make: 'Yamaha', model: 'NMAX', topSpeedKmh: 110),
      differentBike: true,
    );
    expect(app.initRideSkipped, isFalse);
    expect(app.startupStep, StartupStep.calibration);
  });

  testWidgets('signing out returns to the login screen and keeps the bike', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (seed, _, _) = await buildApp();
    await seed.saveBike(
      const OtherChoice(make: 'Honda', model: 'PCX 125', topSpeedKmh: 105),
    );
    await seed.skipInitRide();
    final google = FakeGoogleAuth();
    final (app, widget, _) = await buildApp(googleAuth: google);
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle();
    await tester.tap(find.text('Settings'));
    await settle();
    final signOut = find.byKey(const Key('sign-out'));
    await tester.scrollUntilVisible(
      signOut,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('account-label')), findsOneWidget);
    await tester.ensureVisible(signOut);
    await settle();
    await tester.tap(signOut);
    await settle();

    expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
    expect(google.signOuts, 1);
    expect(app.account, isNull);
    expect(app.bike!.model, 'Honda PCX 125');
    final (reloaded, _, _) = await buildApp(signedIn: false);
    expect(reloaded.startupStep, StartupStep.signIn);
  });
}
