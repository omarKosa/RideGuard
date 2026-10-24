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
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/models/emergency_contact.dart';
import 'package:ride_guard/models/incident.dart';
import 'package:ride_guard/models/ride_summary.dart';
import 'package:ride_guard/screens/ride_summary_screen.dart';
import 'package:ride_guard/screens/settings/settings_screen.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/emergency_platform.dart';
import 'package:ride_guard/services/safety_controller.dart';
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

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(AppState, SyncService, FakeEmergencyPlatform)> deps() async {
    final stack = offlineFirstStack();
    final app = AppState(store: await LocalStore.open(), remote: stack.remote);
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

  testWidgets('marking a warning "not real" makes detection less sensitive', (
    tester,
  ) async {
    // The test font draws every glyph as a full square; give the stat
    // tiles room.
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final stack = offlineFirstStack();
    final app = AppState(store: await LocalStore.open(), remote: stack.remote);
    await app.load();
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
    final start = DateTime.utc(2026, 10, 23, 9);
    Incident incident(HazardKind kind, IncidentOutcome outcome) => Incident(
      id: 'i-${kind.name}',
      rideId: 'ride-1',
      kind: kind,
      detectedAt: start.add(const Duration(minutes: 3)),
      speedKmh: 88,
      leanDeg: 1,
      wobbleHz: 8.5,
      wobbleRms: 0.62,
      outcome: outcome,
    );
    final summary = RideSummary(
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
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          home: RideSummaryScreen(
            summary: summary,
            incidents: [
              incident(HazardKind.wobble, IncidentOutcome.warned),
              incident(HazardKind.crash, IncidentOutcome.cancelled),
            ],
          ),
        ),
      ),
    );

    expect(find.text('SAFETY ALERTS (2)'), findsOneWidget);
    expect(
      find.textContaining('Crash at 88 km/h - you cancelled'),
      findsOneWidget,
    );
    // Crashes can't be marked.
    expect(find.byKey(const Key('false-alarm-1')), findsNothing);

    final notReal = find.byKey(const Key('false-alarm-0'));
    await tester.ensureVisible(notReal);
    await tester.tap(notReal);
    await tester.pumpAndSettle();

    expect(notReal, findsNothing);
    expect(app.safetyBaseline!.falseAlarms, 1);
    expect(app.safetyTuning.wobbleMinRms, closeTo(0.62 * 1.15, 1e-9));
    final upload = stack.backend.bodiesFor('PUT', '/incidents/i-wobble').last;
    expect(upload['false_alarm'], isTrue);
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
