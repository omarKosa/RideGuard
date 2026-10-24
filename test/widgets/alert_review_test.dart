import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ride_guard/core/safety/safety_monitor.dart';
import 'package:ride_guard/models/incident.dart';
import 'package:ride_guard/widgets/alert_card.dart';
import 'package:ride_guard/widgets/alert_review.dart';

Incident _incident(String id, HazardKind kind) => Incident(
  id: id,
  rideId: 'ride-1',
  kind: kind,
  detectedAt: DateTime(2026, 10, 24, 9, 14),
  speedKmh: 95,
  leanDeg: 2,
  peakAccelG: kind == HazardKind.impact ? 4.6 : null,
  wobbleHz: kind == HazardKind.wobble ? 8.5 : null,
  wobbleRms: kind == HazardKind.wobble ? 0.62 : null,
  outcome: kind.critical ? IncidentOutcome.cancelled : IncidentOutcome.warned,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final incidents = [
    _incident('a', HazardKind.wobble),
    _incident('b', HazardKind.impact),
    _incident('c', HazardKind.extremeLean),
  ];

  /// Returns what onDone received so far.
  Future<List<Incident>? Function()> pumpReview(
    WidgetTester tester,
    List<Incident> incidents,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    List<Incident>? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertReview(
            incidents: incidents,
            onLabel: (i, l) async => i.labelled(l, DateTime(2026, 10, 24, 10)),
            onDone: (list) => done = list,
          ),
        ),
      ),
    );
    return () => done;
  }

  testWidgets('answers every alert then finishes', (tester) async {
    final done = await pumpReview(tester, incidents);
    await tester.pumpAndSettle();
    expect(find.text('ALERT 1 OF 3'), findsOneWidget);
    expect(find.text('SPEED WOBBLE'), findsOneWidget);
    expect(find.textContaining('8.5 Hz · 95 km/h'), findsOneWidget);
    expect(find.text('Did this really happen?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('alert-yes')));
    await tester.pumpAndSettle();
    expect(find.text('ALERT 2 OF 3'), findsOneWidget);
    expect(find.text('HARD IMPACT'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('alert-card')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('ALERT 3 OF 3'), findsOneWidget);
    expect(find.text('EXTREME LEAN'), findsOneWidget);
    expect(done(), isNull);

    await tester.tap(find.byKey(const Key('alert-no')));
    await tester.pumpAndSettle();
    final labelled = (done())!;
    expect(labelled.map((i) => i.id), ['a', 'b', 'c']);
    expect(labelled.map((i) => i.riderLabel), [
      RiderLabel.yes,
      RiderLabel.no,
      RiderLabel.no,
    ]);
    expect(labelled.first.labelledAt, DateTime(2026, 10, 24, 10));
  });

  testWidgets('swiping right says it happened', (tester) async {
    final done = await pumpReview(tester, incidents.take(1).toList());
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('alert-card')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    expect((done())!.single.riderLabel, RiderLabel.yes);
  });

  testWidgets('a tap throws the card off with its stamp, once', (tester) async {
    final done = await pumpReview(tester, incidents);
    await tester.pumpAndSettle();
    final start = tester.getCenter(find.byKey(const Key('alert-card')));

    await tester.tap(find.byKey(const Key('alert-yes')));
    await tester.pump(); // the animation starts
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-flight: still the first card, tilted, stamped, moving right.
    expect(find.text('ALERT 1 OF 3'), findsOneWidget);
    expect(find.text('IT HAPPENED'), findsOneWidget);
    expect(find.byType(AlertCard), findsOneWidget);
    final card = tester.getCenter(find.byType(AlertCard));
    expect(card.dx, greaterThan(start.dx + 50));
    // Taps during the flight are ignored.
    await tester.tap(find.byKey(const Key('alert-no')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('alert-yes')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('ALERT 2 OF 3'), findsOneWidget);
    expect(find.text('HARD IMPACT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('alert-skip')));
    await tester.pumpAndSettle();
    expect(done()!.map((i) => i.riderLabel), [RiderLabel.yes, null, null]);
  });

  testWidgets('NO flies left with the NOT REAL stamp', (tester) async {
    final done = await pumpReview(tester, incidents.take(1).toList());
    await tester.pumpAndSettle();
    final start = tester.getCenter(find.byKey(const Key('alert-card')));
    await tester.tap(find.byKey(const Key('alert-no')));
    await tester.pump(); // the animation starts
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('NOT REAL'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(AlertCard)).dx,
      lessThan(start.dx - 50),
    );
    await tester.pumpAndSettle();
    expect(done()!.single.riderLabel, RiderLabel.no);
  });

  testWidgets('skip mid-flight keeps the answer being thrown', (tester) async {
    final done = await pumpReview(tester, incidents);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alert-no')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('alert-skip')));
    await tester.pumpAndSettle();
    expect(done()!.map((i) => i.riderLabel), [RiderLabel.no, null, null]);
  });

  testWidgets('skip leaves the rest unlabelled', (tester) async {
    final done = await pumpReview(tester, incidents);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alert-yes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alert-skip')));
    await tester.pumpAndSettle();
    final labelled = (done())!;
    expect(labelled.map((i) => i.id), ['a', 'b', 'c']);
    expect(labelled.map((i) => i.riderLabel), [RiderLabel.yes, null, null]);
    expect(labelled[1].labelledAt, isNull);
  });

  testWidgets('crash card asks about a real crash', (tester) async {
    await pumpReview(tester, [_incident('x', HazardKind.crash)]);
    await tester.pumpAndSettle();
    expect(find.text('ALERT 1 OF 1'), findsOneWidget);
    expect(find.text('CRASH'), findsOneWidget);
    expect(find.text('Was this a real crash or fall?'), findsOneWidget);
    expect(find.textContaining('you cancelled'), findsOneWidget);
    expect(find.text('Did this really happen?'), findsNothing);
  });

  testWidgets('no alerts finishes at once', (tester) async {
    final done = await pumpReview(tester, const []);
    await tester.pumpAndSettle();
    expect(done(), isEmpty);
    expect(find.byKey(const Key('alert-card')), findsNothing);
  });
}
