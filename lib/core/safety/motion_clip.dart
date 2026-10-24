import 'dart:collection';
import 'dart:math' as math;

import '../math/vec3.dart';
import 'safety_monitor.dart';

/// The raw IMU signal around one hazard: data for analysing alerts later,
/// never used for detection.
class MotionClip {
  const MotionClip({
    required this.rateHz,
    required this.startOffsetS,
    required this.accel,
    required this.gyro,
  });

  /// Samples per second of [accel] (after any thinning).
  final double rateHz;

  /// Where recording starts relative to the hazard: -5, or later when the
  /// ride had only just started.
  final double startOffsetS;

  /// Raw accelerometer including gravity, phone frame: `[t, x, y, z]` with
  /// t in seconds relative to the hazard, m/s².
  final List<List<double>> accel;

  /// Gyroscope, phone frame: `[t, x, y, z]`, rad/s.
  final List<List<double>> gyro;

  /// Body of `PUT /v1/rides/{ride}/incidents/{id}/clip`.
  Map<String, dynamic> toApiJson() => {
    'rate_hz': rateHz,
    'start_offset_s': startOffsetS,
    'accel': accel,
    'gyro': gyro,
  };
}

/// Keeps the last few seconds of raw IMU and cuts a [MotionClip] from
/// [before] seconds ahead of each captured event to [after] seconds past
/// it.
class ClipRecorder {
  ClipRecorder({this.before = 5, this.after = 5, this.lookback = 0});

  final double before;
  final double after;

  /// How long before a hazard is reported its event may have happened (a
  /// crash is confirmed seconds after the impact). The buffer keeps
  /// [lookback] + [before] seconds; an older event is clamped to
  /// [lookback] before the report.
  final double lookback;

  /// Rows per stream the backend accepts; faster sensors are thinned.
  static const maxRows = 1500;

  // Backend limits on the clip header.
  static const _maxRateHz = 1000.0;
  static const _minStartOffsetS = -10.0;

  final ListQueue<(double, Vec3)> _accel = ListQueue();
  final ListQueue<(double, Vec3)> _gyro = ListQueue();
  final List<(Hazard, double)> _pending = [];
  double? _firstT;

  /// Raw accelerometer including gravity, phone frame, m/s².
  void addAccel(Vec3 accel, double t) => _add(_accel, accel, t);

  /// Gyroscope, phone frame, rad/s.
  void addGyro(Vec3 rate, double t) => _add(_gyro, rate, t);

  /// Starts a clip around [h], centred on the event time [at] (default:
  /// when it was reported), same clock as the samples. Row times are
  /// relative to [at].
  void capture(Hazard h, {double? at}) {
    if (!h.t.isFinite) return;
    final event = at != null && at.isFinite ? at : h.t;
    _pending.add((h, math.min(h.t, math.max(event, h.t - lookback))));
  }

  /// Clips whose [after] seconds have passed by [t].
  List<(Hazard, MotionClip)> poll(double t) {
    if (_pending.isEmpty) return const [];
    final done = [
      for (final p in _pending)
        if (t > p.$2 + after) p,
    ];
    if (done.isEmpty) return const [];
    _pending.removeWhere(done.contains);
    final clips = _cut(done);
    _trim();
    return clips;
  }

  /// Every pending clip, cut short where the data ends (the ride stopped).
  List<(Hazard, MotionClip)> flush() {
    final clips = _cut(_pending);
    _pending.clear();
    _trim();
    return clips;
  }

  void _add(ListQueue<(double, Vec3)> q, Vec3 v, double t) {
    if (!v.isFinite || !t.isFinite) return;
    // Keep each stream ordered; a sample from the past is dropped.
    if (q.isNotEmpty && t < q.last.$1) return;
    _firstT ??= t;
    q.addLast((t, v));
    _trim();
  }

  /// Drops samples no current or future clip can need.
  void _trim() {
    var from = math.max(
      _accel.isEmpty ? double.negativeInfinity : _accel.last.$1,
      _gyro.isEmpty ? double.negativeInfinity : _gyro.last.$1,
    );
    from -= lookback;
    for (final (_, at) in _pending) {
      from = math.min(from, at);
    }
    from -= before;
    for (final q in [_accel, _gyro]) {
      while (q.isNotEmpty && q.first.$1 < from) {
        q.removeFirst();
      }
    }
  }

  List<(Hazard, MotionClip)> _cut(List<(Hazard, double)> pending) => [
    for (final (h, at) in pending)
      if (_clip(at) case final clip?) (h, clip),
  ];

  MotionClip? _clip(double at) {
    final accel = _rows(_accel, at);
    final gyro = _rows(_gyro, at);
    final rate = _rate(accel) ?? _rate(gyro);
    if (rate == null) return null;
    final firstT = _firstT ?? at;
    final start = (firstT - at)
        .clamp(math.max(-before, _minStartOffsetS), 0.0)
        .toDouble();
    return MotionClip(
      rateHz: _round(math.min(rate, _maxRateHz), 100),
      startOffsetS: _round(start, 1e4),
      accel: accel,
      gyro: gyro,
    );
  }

  List<List<double>> _rows(ListQueue<(double, Vec3)> q, double at) {
    final from = at - before, to = at + after;
    final window = [
      for (final s in q)
        if (s.$1 >= from && s.$1 <= to) s,
    ];
    final step = (window.length / maxRows).ceil();
    return [
      for (var i = 0; i < window.length; i += math.max(step, 1))
        [
          _round(window[i].$1 - at, 1e4),
          _round(window[i].$2.x, 1e4),
          _round(window[i].$2.y, 1e4),
          _round(window[i].$2.z, 1e4),
        ],
    ];
  }

  static double? _rate(List<List<double>> rows) {
    if (rows.length < 2) return null;
    final span = rows.last[0] - rows.first[0];
    return span > 0 ? (rows.length - 1) / span : null;
  }

  static double _round(double v, double scale) =>
      (v * scale).roundToDouble() / scale;
}
