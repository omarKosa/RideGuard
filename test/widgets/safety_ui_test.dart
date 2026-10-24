import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ride_guard/core/analysis/ride_analyzer.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/fusion/mount_orientation.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/safety_baseline.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/core/safety/safety_tuning.dart';
import 'package:ride_guard/data/api_client.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/data/sync_service.dart';
import 'package:ride_guard/models/bike_choice.dart';
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/models/emergency_contact.dart';
import 'package:ride_guard/models/incident.dart';
import 'package:ride_guard/models/ride_summary.dart';
import 'package:ride_guard/screens/ride/ride_screen.dart';
import 'package:ride_guard/screens/ride_summary_screen.dart';
import 'package:ride_guard/screens/settings/settings_screen.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/emergency_platform.dart';
import 'package:ride_guard/services/safety_controller.dart';
import 'package:ride_guard/services/sensor_feed.dart';
import 'package:ride_guard/widgets/safety_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Hazard _hazard(HazardKind kind) => Hazard(
  kind: kind,
  t: 0,
  speedKmh: 95,
  leanDeg: 2,
  wobbleHz: kind == HazardKind.wobble ? 6.5 : null,
);

RideSummary _summary(DateTime start) => RideSummary(
  rideId: 'ride-1',
  kind: RideKind.ride,
  status: RideStatus.completed,
  startedAt: start,
  endedAt: start.add(const Duration(minutes: 20)),
  windowMinutes: 15,
  totals: const RideStats(),
  window: const RideStats(),
  brakeEvents: const [],
  mountRealignments: 0,
  sampleCount: 0,
);

CalibrationProfile _calibration(String bikeId) => CalibrationProfile(
  id: 'cal-1',
  bikeId: bikeId,
  rideId: 'cal-ride',
  calibratedAt: DateTime.utc(2026, 10, 22),
  params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
  forwardFromMotion: true,
  straightOffsetDeg: 0,
  quality: 0.9,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(AppState, SyncService, FakeEmergencyPlatform)> deps() async {
    final stack = offlineFirstStack();
    final app = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      catalogue: realCatalogue(),
    );
    await app.load();
    return (app, stack.sync, FakeEmergencyPlatform());
  }

  testWidgets('crash alert counts down and holds to cancel', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (app, _, platform) = await deps();
    await app.setEmergencyContact(
      const EmergencyContact(name: 'Mona', phone: '+201001234567'),
    );
    final safety = SafetyController(app: app, platform: platform)
      ..begin('ride');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: safety,
        child: const MaterialApp(
          home: SafetyLayer(child: Scaffold(body: Text('riding'))),
        ),
      ),
    );

    safety.report(_hazard(HazardKind.wobble));
    await tester.pump();
    expect(find.byKey(const Key('hazard-warning')), findsOneWidget);
    expect(find.textContaining('Speed wobble at 95 km/h'), findsOneWidget);

    safety.report(_hazard(HazardKind.crash));
    await tester.pump();
    expect(find.text('CRASH DETECTED'), findsOneWidget);
    expect(find.text('Calling Mona in 30 s'), findsOneWidget);
    // The warning banner gives way to the crash alert.
    expect(find.byKey(const Key('hazard-warning')), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Calling Mona in 25 s'), findsOneWidget);

    // A tap (rain, debris) is not enough.
    await tester.tap(find.byKey(const Key('dismiss-crash')));
    await tester.pump();
    expect(safety.phase, SafetyPhase.countdown);

    await tester.longPress(find.byKey(const Key('dismiss-crash')));
    await tester.pump();
    expect(safety.phase, SafetyPhase.idle);
    expect(find.byKey(const Key('crash-alert')), findsNothing);
    expect(platform.events, isNot(contains(startsWith('call'))));

    safety.dispose();
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('settings saves a validated emergency contact', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (app, sync, platform) = await deps();
    platform.permission = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: sync),
          Provider.value(value: ApiClient(baseUrl: () => 'http://x')),
          Provider<EmergencyPlatform>.value(value: platform),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final save = find.byKey(const Key('save-contact'));
    await tester.enterText(find.byKey(const Key('contact-name')), 'Mona');
    await tester.enterText(find.byKey(const Key('contact-phone')), '12');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid phone number'), findsOneWidget);
    expect(app.emergencyContact, isNull);

    await tester.enterText(
      find.byKey(const Key('contact-phone')),
      '+20 100 123 4567',
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(app.emergencyContact!.phone, '+201001234567');
    expect(app.emergencyContact!.name, 'Mona');
    // Without call permission the rider is told what will happen instead.
    expect(find.textContaining('the dialer will only open'), findsOneWidget);

    // Survives a restart.
    expect((await LocalStore.open()).emergencyContact!.phone, '+201001234567');
  });

  testWidgets('the summary shows what the rider answered', (tester) async {
    // The test font draws every glyph as a full square; give the stat
    // tiles room.
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (app, _, _) = await deps();
    final start = DateTime.utc(2026, 10, 23, 9);
    final at = start.add(const Duration(minutes: 30));
    Incident incident(String id, HazardKind kind, IncidentOutcome outcome) =>
        Incident(
          id: id,
          rideId: 'ride-1',
          kind: kind,
          detectedAt: start.add(const Duration(minutes: 3)),
          speedKmh: 88,
          leanDeg: 1,
          wobbleHz: 8.5,
          wobbleRms: 0.62,
          peakAccelG: 4.6,
          outcome: outcome,
        );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          home: RideSummaryScreen(
            summary: _summary(start),
            incidents: [
              incident(
                'w',
                HazardKind.wobble,
                IncidentOutcome.warned,
              ).labelled(RiderLabel.no, at),
              incident(
                'c',
                HazardKind.crash,
                IncidentOutcome.cancelled,
              ).labelled(RiderLabel.yes, at),
              incident('i', HazardKind.impact, IncidentOutcome.warned),
            ],
          ),
        ),
      ),
    );

    expect(find.text('SAFETY ALERTS (3)'), findsOneWidget);
    expect(
      find.textContaining('Crash at 88 km/h - you cancelled'),
      findsOneWidget,
    );
    expect(find.text('You said: not real'), findsOneWidget);
    expect(find.text('You said: it happened'), findsOneWidget);
    expect(find.text('No answer'), findsOneWidget);
    // Labelling happens on the cards now.
    expect(find.text('NOT REAL'), findsNothing);
    expect(find.byKey(const Key('false-alarm-0')), findsNothing);
  });

  group('after a ride', () {
    Future<(AppState, SyncService, RecordingBackend)> pumpRide(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 6000);
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
      await app.saveCalibration(_calibration(bike.id));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider.value(value: stack.sync),
            Provider<SensorSource>.value(value: FakeSensorSource()),
            Provider<EmergencyPlatform>.value(value: FakeEmergencyPlatform()),
          ],
          child: const MaterialApp(home: RideScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return (app, stack.sync, stack.backend);
    }

    SafetyController safetyOf(WidgetTester tester) =>
        Provider.of<SafetyController>(
          tester.element(find.byKey(const Key('stop-ride'))),
          listen: false,
        );

    void warn(WidgetTester tester) {
      final safety = safetyOf(tester);
      safety.report(
        const Hazard(
          kind: HazardKind.wobble,
          t: 1,
          speedKmh: 95,
          leanDeg: 2,
          wobbleHz: 8.5,
          wobbleRms: 0.62,
        ),
      );
      safety.report(
        const Hazard(
          kind: HazardKind.impact,
          t: 2,
          speedKmh: 62,
          leanDeg: 1,
          peakAccelG: 4.6,
        ),
      );
    }

    Future<void> stopRide(WidgetTester tester) async {
      await tester.longPress(find.byKey(const Key('stop-ride')));
      // Finishing the ride does real I/O.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('alert cards come before the summary', (tester) async {
      final (app, sync, backend) = await pumpRide(tester);
      warn(tester);
      await tester.pump();
      await stopRide(tester);

      expect(find.text('RIDE SUMMARY'), findsNothing);
      expect(find.text('ALERT 1 OF 2'), findsOneWidget);
      expect(find.text('SPEED WOBBLE'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('alert-card')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('ALERT 2 OF 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('alert-yes')));
      await tester.pumpAndSettle();

      expect(find.text('RIDE SUMMARY'), findsOneWidget);
      expect(find.text('You said: not real'), findsOneWidget);
      expect(find.text('You said: it happened'), findsOneWidget);
      // NO on the wobble makes wobble alerts just less sensitive.
      expect(app.safetyBaseline!.falseAlarms, 1);
      expect(app.safetyTuning.wobbleMinRms, closeTo(0.62 * 1.15, 1e-9));
      expect(app.safetyTuning.impactG, SafetyTuning.defaultImpactG);

      await sync.flush();
      final uploads = backend.bodiesFor('PUT', '/incidents/');
      final last = {for (final u in uploads) u['kind']: u};
      expect(last['wobble']!['rider_label'], 'no');
      expect(last['wobble']!['labelled_at'], isNotNull);
      expect(last['impact']!['rider_label'], 'yes');
      expect(uploads.every((u) => !u.containsKey('false_alarm')), isTrue);
    });

    testWidgets('system back on the cards skips to the summary', (
      tester,
    ) async {
      final (app, sync, backend) = await pumpRide(tester);
      warn(tester);
      await tester.pump();
      await stopRide(tester);
      expect(find.byKey(const Key('alert-card')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alert-card')), findsNothing);
      expect(find.text('RIDE SUMMARY'), findsOneWidget);
      expect(find.text('No answer'), findsNWidgets(2));
      expect(app.safetyBaseline!.falseAlarms, 0);
      await sync.flush();
      final uploads = backend.bodiesFor('PUT', '/incidents/');
      expect(uploads, isNotEmpty);
      expect(uploads.every((u) => u['rider_label'] == null), isTrue);
    });

    testWidgets('no alerts, no cards', (tester) async {
      await pumpRide(tester);
      await stopRide(tester);
      expect(find.byKey(const Key('alert-card')), findsNothing);
      expect(find.text('RIDE SUMMARY'), findsOneWidget);
    });
  });

  testWidgets('settings shows what was learned and can reset it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2600);
    addTearDown(tester.view.reset);
    final (app, sync, platform) = await deps();
    await app.saveCalibration(
      CalibrationProfile(
        id: 'cal-1',
        bikeId: 'bike',
        rideId: 'cal-ride',
        calibratedAt: DateTime.utc(2026, 10, 22),
        params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
        forwardFromMotion: true,
        straightOffsetDeg: 0,
        quality: 0.9,
      ),
    );
    final noise = RideNoise(imuHz: 50);
    for (var i = 0; i < 1200; i++) {
      noise.wobbleRms.add(0.3); // a buzzing mount
      noise.peakG.add(1.5);
    }
    await app.learnFromRide(noise, incidents: const []);
    expect(app.safetyTuning.wobbleMinRms, greaterThan(0.85));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: sync),
          Provider.value(value: ApiClient(baseUrl: () => 'http://x')),
          Provider<EmergencyPlatform>.value(value: platform),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    expect(find.text('SAFETY LEARNING'), findsOneWidget);
    expect(find.text('20 min of riding'), findsOneWidget);
    expect(find.textContaining('rad/s (+'), findsOneWidget);

    final reset = find.byKey(const Key('reset-safety-learning'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESET'));
    await tester.pumpAndSettle();

    expect(app.safetyTuning.wobbleMinRms, SafetyTuning.defaultWobbleRms);
    expect(app.safetyBaseline!.ridingSeconds, 0);
    expect(find.text('not enough riding yet'), findsOneWidget);
  });
}
