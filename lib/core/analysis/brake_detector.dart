import 'dart:collection';
import 'dart:math' as math;

import '../../models/brake_event.dart';

/// Streams speed samples and emits a [BrakeEvent] each time the bike is
/// braked from speed to a standstill.
///
/// Braking starts when speed drops faster than [onsetDecel] over one second
/// and ends when speed falls below [stopSpeedKmh]. Re-accelerating or
/// coasting without stopping cancels the event.
class BrakeDetector {
  BrakeDetector({
    this.minStartSpeedKmh = 20,
    this.stopSpeedKmh = 3,
    this.onsetDecel = 1.5,
    this.maxDuration = const Duration(seconds: 30),
  });

  final double minStartSpeedKmh;
  final double stopSpeedKmh;
  final double onsetDecel;
  final Duration maxDuration;

  final ListQueue<(DateTime, double)> _recent = ListQueue();
  _Braking? _active;
  DateTime? _lastTime;
  double _lastSpeed = 0;

  bool get isBraking => _active != null;

  BrakeEvent? add(DateTime time, double speedKmh) {
    final dt = _lastTime == null
        ? 0.0
        : time.difference(_lastTime!).inMicroseconds / 1e6;
    final prevSpeed = _lastSpeed;
    _lastTime = time;
    _lastSpeed = speedKmh;

    _recent.addLast((time, speedKmh));
    while (_recent.isNotEmpty &&
        time.difference(_recent.first.$1) >
            const Duration(milliseconds: 1500)) {
      _recent.removeFirst();
    }

    final decel1s = _decelOverLastSecond(time, speedKmh);
    final active = _active;

    if (active == null) {
      if (speedKmh > stopSpeedKmh && decel1s >= onsetDecel) {
        // Start at the fastest point in the recent window (brake onset).
        var start = _recent.first;
        for (final s in _recent) {
          if (s.$2 >= start.$2) start = s;
        }
        if (start.$2 >= minStartSpeedKmh) {
          final b = _Braking(start.$1, start.$2);
          // Distance already covered between onset and now.
          var prev = start;
          for (final s in _recent.where((s) => !s.$1.isBefore(start.$1))) {
            b.distance += _segmentDistance(prev, s);
            prev = s;
          }
          b.minSpeed = speedKmh;
          b.peakDecel = decel1s;
          _active = b;
        }
      }
      return null;
    }

    active.distance += (prevSpeed + speedKmh) / 2 / 3.6 * dt;
    active.peakDecel = math.max(active.peakDecel, decel1s);
    active.minSpeed = math.min(active.minSpeed, speedKmh);
    active.slowDecelFor = decel1s < 0.3 ? active.slowDecelFor + dt : 0;

    if (speedKmh <= stopSpeedKmh) {
      _active = null;
      return BrakeEvent(
        startedAt: active.startTime,
        endedAt: time,
        startSpeedKmh: active.startSpeed,
        distanceM: active.distance,
        peakDecelMps2: active.peakDecel,
      );
    }

    final reaccelerated = speedKmh > active.minSpeed + 3;
    final coasting = active.slowDecelFor > 3 && speedKmh > 10;
    final tooLong = time.difference(active.startTime) > maxDuration;
    if (reaccelerated || coasting || tooLong) _active = null;
    return null;
  }

  void reset() {
    _recent.clear();
    _active = null;
    _lastTime = null;
    _lastSpeed = 0;
  }

  double _decelOverLastSecond(DateTime now, double speedKmh) {
    (DateTime, double)? ref;
    for (final s in _recent) {
      if (now.difference(s.$1) <= const Duration(seconds: 1)) break;
      ref = s;
    }
    ref ??= _recent.first;
    final dt = now.difference(ref.$1).inMicroseconds / 1e6;
    if (dt < 0.5) return 0;
    return (ref.$2 - speedKmh) / 3.6 / dt;
  }

  static double _segmentDistance((DateTime, double) a, (DateTime, double) b) {
    final dt = b.$1.difference(a.$1).inMicroseconds / 1e6;
    return (a.$2 + b.$2) / 2 / 3.6 * dt;
  }
}

class _Braking {
  _Braking(this.startTime, this.startSpeed);

  final DateTime startTime;
  final double startSpeed;
  double distance = 0;
  double peakDecel = 0;
  double minSpeed = double.infinity;
  double slowDecelFor = 0;
}
