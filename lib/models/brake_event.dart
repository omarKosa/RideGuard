/// A stop from speed: brake onset until the bike is (nearly) standing.
class BrakeEvent {
  const BrakeEvent({
    required this.startedAt,
    required this.endedAt,
    required this.startSpeedKmh,
    required this.distanceM,
    required this.peakDecelMps2,
  });

  factory BrakeEvent.fromJson(Map<String, dynamic> json) => BrakeEvent(
    startedAt: DateTime.parse(json['started_at'] as String),
    endedAt: DateTime.parse(json['ended_at'] as String),
    startSpeedKmh: (json['start_speed_kmh'] as num).toDouble(),
    distanceM: (json['distance_m'] as num).toDouble(),
    peakDecelMps2: (json['peak_decel_mps2'] as num).toDouble(),
  );

  final DateTime startedAt;
  final DateTime endedAt;
  final double startSpeedKmh;
  final double distanceM;
  final double peakDecelMps2;

  double get durationS => endedAt.difference(startedAt).inMilliseconds / 1000;

  /// Average deceleration over the whole stop.
  double get meanDecelMps2 =>
      durationS <= 0 ? 0 : (startSpeedKmh / 3.6) / durationS;

  Map<String, dynamic> toJson() => {
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'start_speed_kmh': double.parse(startSpeedKmh.toStringAsFixed(2)),
    'duration_s': double.parse(durationS.toStringAsFixed(2)),
    'distance_m': double.parse(distanceM.toStringAsFixed(1)),
    'peak_decel_mps2': double.parse(peakDecelMps2.toStringAsFixed(2)),
  };
}
