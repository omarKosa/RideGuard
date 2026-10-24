import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/models/emergency_contact.dart';
import 'package:ride_guard/models/incident.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/emergency_platform.dart';
import 'package:ride_guard/services/safety_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

const _contact = EmergencyContact(name: 'Mona', phone: '+201001234567');

Hazard _hazard(HazardKind kind) => Hazard(
  kind: kind,
  t: 100,
  speedKmh: 62,
  leanDeg: 4,
  peakAccelG: kind == HazardKind.crash ? 7.5 : null,
  wobbleHz: kind == HazardKind.wobble ? 6.8 : null,
  latitude: 30.05,
  longitude: 31.24,
);

typedef _Rig = ({
  SafetyController safety,
  FakeEmergencyPlatform platform,
  RecordingBackend backend,
});

Future<_Rig> _rig({EmergencyContact? contact = _contact}) async {
  SharedPreferences.setMockInitialValues({});
  final stack = offlineFirstStack();
  final app = AppState(
    store: await LocalStore.open(),
    remote: stack.remote,
    catalogue: realCatalogue(),
  );
  await app.load();
  await app.setEmergencyContact(contact);
  final platform = FakeEmergencyPlatform();
  final safety = SafetyController(app: app, platform: platform)
    ..begin('8f4c6c36-1f0c-4a8e-9a43-1f6f0e0c7a11');
  return (safety: safety, platform: platform, backend: stack.backend);
}

/// Outcomes uploaded for incidents, in order.
List<String> _uploaded(RecordingBackend backend) => [
  for (final b in backend.bodiesFor('PUT', '/incidents/'))
    b['outcome'] as String,
];

void main() {
  testWidgets('a crash counts down, then calls the contact', (tester) async {
    final r = await _rig();
    r.safety.report(_hazard(HazardKind.crash));

    expect(r.safety.phase, SafetyPhase.countdown);
    expect(r.safety.secondsLeft, 30);
    expect(r.platform.alarmUrgent, isTrue);

    await tester.pump(const Duration(seconds: 29));
    expect(r.safety.secondsLeft, 1);
    expect(r.platform.events, ['alarm']);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(r.safety.phase, SafetyPhase.called);
    // Alarm off first so the call can be heard.
    expect(r.platform.events, ['alarm', 'stop', 'call +201001234567']);
    expect(r.safety.crash!.outcome, IncidentOutcome.called);
    expect(_uploaded(r.backend), ['pending', 'called']);

    final body = r.backend.bodiesFor('PUT', '/incidents/').last;
    expect(body['kind'], 'crash');
    expect(body['peak_accel_g'], 7.5);
    expect(body['latitude'], 30.05);
    expect(body['resolved_at'], isNotNull);

    r.safety.dismiss();
    expect(r.safety.phase, SafetyPhase.idle);
    r.safety.dispose();
  });

  testWidgets("I'm OK cancels the call", (tester) async {
    final r = await _rig();
    r.safety.report(_hazard(HazardKind.crash));
    await tester.pump(const Duration(seconds: 10));

    r.safety.dismiss();
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(r.safety.phase, SafetyPhase.idle);
    expect(r.platform.events, ['alarm', 'stop']);
    expect(r.safety.incidents.single.outcome, IncidentOutcome.cancelled);
    expect(_uploaded(r.backend), ['pending', 'cancelled']);
    r.safety.dispose();
  });

  testWidgets('without a contact the alarm keeps sounding', (tester) async {
    final r = await _rig(contact: null);
    r.safety.report(_hazard(HazardKind.crash));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(r.safety.phase, SafetyPhase.alarming);
    expect(r.platform.alarmUrgent, isTrue);
    expect(r.platform.events, ['alarm']);
    expect(_uploaded(r.backend), ['pending', 'no_contact']);

    r.safety.dismiss();
    expect(r.platform.alarmUrgent, isNull);
    r.safety.dispose();
  });

  testWidgets('a failed call brings the alarm back', (tester) async {
    final r = await _rig();
    r.platform.callResult = CallResult.failed;
    r.safety.report(_hazard(HazardKind.crash));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(r.safety.phase, SafetyPhase.alarming);
    expect(r.platform.alarmUrgent, isTrue);
    expect(r.safety.crash!.outcome, IncidentOutcome.callFailed);
    r.safety.dispose();
  });

  testWidgets('warnings alert briefly and never call', (tester) async {
    final r = await _rig();
    r.safety.report(_hazard(HazardKind.wobble));

    expect(r.safety.phase, SafetyPhase.idle);
    expect(r.safety.warning!.kind, HazardKind.wobble);
    expect(r.platform.alarmUrgent, isFalse);

    await tester.pump(const Duration(seconds: 3));
    expect(r.platform.alarmUrgent, isNull); // alert over
    expect(r.safety.warning, isNotNull); // banner still up

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(r.safety.warning, isNull);
    expect(r.platform.events, ['alert', 'stop']);
    expect(_uploaded(r.backend), ['warned']);
    r.safety.dispose();
  });

  testWidgets('a crash takes over from a warning and is not interrupted', (
    tester,
  ) async {
    final r = await _rig();
    r.safety.report(_hazard(HazardKind.impact));
    r.safety.report(_hazard(HazardKind.crash));
    // A second crash report and a late warning change nothing.
    r.safety.report(_hazard(HazardKind.crash));
    r.safety.report(_hazard(HazardKind.extremeLean));
    await tester.pump(const Duration(seconds: 10));

    expect(r.safety.phase, SafetyPhase.countdown);
    expect(r.platform.alarmUrgent, isTrue);
    expect(r.platform.events, ['alert', 'alarm']);
    expect(r.safety.incidents.map((i) => i.kind), [
      HazardKind.impact,
      HazardKind.crash,
      HazardKind.extremeLean,
    ]);
    r.safety.dispose();
  });

  testWidgets('stopping the ride cancels the countdown', (tester) async {
    final r = await _rig();
    r.safety.report(_hazard(HazardKind.crash));
    r.safety.end();
    await tester.pump(const Duration(seconds: 60));

    expect(r.platform.events, ['alarm', 'stop']);
    expect(r.safety.incidents.single.outcome, IncidentOutcome.cancelled);

    // Hazards after the ride are ignored.
    r.safety.report(_hazard(HazardKind.crash));
    expect(r.safety.phase, SafetyPhase.idle);
    r.safety.dispose();
  });

  test('phone numbers are normalized and validated', () {
    expect(
      EmergencyContact.normalizePhone(' +20 (100) 123-4567 '),
      '+201001234567',
    );
    expect(EmergencyContact.normalizePhone('0100.123.4567'), '01001234567');
    expect(EmergencyContact.normalizePhone('12'), isNull);
    expect(EmergencyContact.normalizePhone('call me'), isNull);
    expect(EmergencyContact.normalizePhone('++20100'), isNull);
  });
}
