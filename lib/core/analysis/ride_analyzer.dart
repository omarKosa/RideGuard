import 'dart:math' as math;

import '../../models/brake_event.dart';
import '../../models/ride_sample.dart';
import '../buffer/time_window_buffer.dart';
import 'brake_detector.dart';

/// Peak values over a span of riding.
class RideStats {
  const RideStats({
    this.maxSpeedKmh = 0,
    this.maxLeanLeftDeg = 0,
    this.maxLeanRightDeg = 0,
    this.maxStopTimeS = 0,
    this.bestDecelMps2 = 0,
    this.brakeEvents = 0,
    this.distanceM = 0,
    this.movingTimeS = 0,
    this.span = Duration.zero,
  });

  final double maxSpeedKmh;

  /// Positive magnitudes.
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;

  /// Longest brake-to-standstill time seen.
  final double maxStopTimeS;
  final double bestDecelMps2;
  final int brakeEvents;
  final double distanceM;
  final double movingTimeS;
  final Duration span;

  double get maxLeanDeg => math.max(maxLeanLeftDeg, maxLeanRightDeg);

  double get avgMovingSpeedKmh =>
      movingTimeS <= 0 ? 0 : distanceM / movingTimeS * 3.6;
}

/// Keeps the last [window] of samples (the "buffer load") and analyses it,
/// while also tracking whole-ride totals that survive eviction.
class RideAnalyzer {
  RideAnalyzer({Duration window = const Duration(minutes: 15)})
    : buffer = TimeWindowBuffer<RideSample>(
        window: window,
        timeOf: (s) => s.time,
      );

  /// Below this speed lean readings are ignored (foot down, stand).
  static const double minLeanSpeedKmh = 10;
  static const double movingSpeedKmh = 3;

  final TimeWindowBuffer<RideSample> buffer;
  final BrakeDetector _brakes = BrakeDetector();
  final List<BrakeEvent> events = [];

  RideSample? _prev;
  double _maxSpeed = 0;
  double _maxLeft = 0;
  double _maxRight = 0;
  double _distance = 0;
  double _moving = 0;
  DateTime? _start;

  Duration get window => buffer.window;
  set window(Duration value) => buffer.window = value;

  /// Adds a sample. Returns a brake event if this sample completed one.
  BrakeEvent? add(RideSample s) {
    _start ??= s.time;
    final prev = _prev;
    _prev = s;
    buffer.add(s);

    if (s.speedReliable) _maxSpeed = math.max(_maxSpeed, s.speedKmh);
    if (s.speedKmh >= minLeanSpeedKmh) {
      if (s.leanDeg < 0) _maxLeft = math.max(_maxLeft, -s.leanDeg);
      if (s.leanDeg > 0) _maxRight = math.max(_maxRight, s.leanDeg);
    }
    if (prev != null) {
      final dt = s.time.difference(prev.time).inMicroseconds / 1e6;
      // A held (stale) speed after GPS dropped out is not movement.
      if (dt > 0 && dt < 5 && prev.speedReliable && s.speedReliable) {
        _distance += (prev.speedKmh + s.speedKmh) / 2 / 3.6 * dt;
        if (s.speedKmh >= movingSpeedKmh) _moving += dt;
      }
    }

    final event = _brakes.add(s.time, s.speedKmh);
    if (event != null) events.add(event);
    return event;
  }

  RideStats totals() => _statsFor(
    maxSpeed: _maxSpeed,
    maxLeft: _maxLeft,
    maxRight: _maxRight,
    distance: _distance,
    moving: _moving,
    brakeEvents: events,
    span: _prev == null || _start == null
        ? Duration.zero
        : _prev!.time.difference(_start!),
  );

  /// Analysis over the buffered window only.
  RideStats windowStats() {
    final first = buffer.first;
    if (first == null) return const RideStats();
    var maxSpeed = 0.0, maxLeft = 0.0, maxRight = 0.0;
    var distance = 0.0, moving = 0.0;
    RideSample? prev;
    for (final s in buffer.items) {
      if (s.speedReliable) maxSpeed = math.max(maxSpeed, s.speedKmh);
      if (s.speedKmh >= minLeanSpeedKmh) {
        if (s.leanDeg < 0) maxLeft = math.max(maxLeft, -s.leanDeg);
        if (s.leanDeg > 0) maxRight = math.max(maxRight, s.leanDeg);
      }
      if (prev != null) {
        final dt = s.time.difference(prev.time).inMicroseconds / 1e6;
        if (dt > 0 && dt < 5 && prev.speedReliable && s.speedReliable) {
          distance += (prev.speedKmh + s.speedKmh) / 2 / 3.6 * dt;
          if (s.speedKmh >= movingSpeedKmh) moving += dt;
        }
      }
      prev = s;
    }
    final inWindow = events
        .where((e) => !e.startedAt.isBefore(first.time))
        .toList();
    return _statsFor(
      maxSpeed: maxSpeed,
      maxLeft: maxLeft,
      maxRight: maxRight,
      distance: distance,
      moving: moving,
      brakeEvents: inWindow,
      span: buffer.span,
    );
  }

  /// Most recent samples, oldest first, for charts.
  List<RideSample> recent(Duration span) {
    final last = buffer.last;
    if (last == null) return const [];
    final cutoff = last.time.subtract(span);
    return buffer.items.where((s) => !s.time.isBefore(cutoff)).toList();
  }

  static RideStats _statsFor({
    required double maxSpeed,
    required double maxLeft,
    required double maxRight,
    required double distance,
    required double moving,
    required List<BrakeEvent> brakeEvents,
    required Duration span,
  }) {
    var maxStop = 0.0, bestDecel = 0.0;
    for (final e in brakeEvents) {
      maxStop = math.max(maxStop, e.durationS);
      bestDecel = math.max(bestDecel, e.peakDecelMps2);
    }
    return RideStats(
      maxSpeedKmh: maxSpeed,
      maxLeanLeftDeg: maxLeft,
      maxLeanRightDeg: maxRight,
      maxStopTimeS: maxStop,
      bestDecelMps2: bestDecel,
      brakeEvents: brakeEvents.length,
      distanceM: distance,
      movingTimeS: moving,
      span: span,
    );
  }
}
