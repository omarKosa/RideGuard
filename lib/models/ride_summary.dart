import '../core/analysis/ride_analyzer.dart';
import 'brake_event.dart';

enum RideKind { calibration, ride }

enum RideStatus { completed, aborted }

class RideSummary {
  const RideSummary({
    required this.rideId,
    required this.kind,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.windowMinutes,
    required this.totals,
    required this.window,
    required this.brakeEvents,
    required this.mountRealignments,
    required this.sampleCount,
    this.safetyStats,
    this.performance,
  });

  factory RideSummary.fromJson(Map<String, dynamic> json) {
    RideStats stats(Map<String, dynamic> j) => RideStats(
      maxSpeedKmh: (j['max_speed_kmh'] as num).toDouble(),
      maxLeanLeftDeg: (j['max_lean_left_deg'] as num).toDouble(),
      maxLeanRightDeg: (j['max_lean_right_deg'] as num).toDouble(),
      maxStopTimeS: (j['max_stop_time_s'] as num).toDouble(),
      bestDecelMps2: (j['best_decel_mps2'] as num).toDouble(),
      brakeEvents: j['brake_event_count'] as int,
      distanceM: (j['distance_m'] as num).toDouble(),
      movingTimeS: (j['moving_time_s'] as num).toDouble(),
      span: Duration(milliseconds: ((j['span_s'] as num) * 1000).round()),
    );
    return RideSummary(
      rideId: json['ride_id'] as String,
      kind: RideKind.values.byName(json['kind'] as String),
      status: RideStatus.values.byName(json['status'] as String),
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.parse(json['ended_at'] as String),
      windowMinutes: json['analysis_window_min'] as int,
      totals: stats(json['totals'] as Map<String, dynamic>),
      window: stats(json['window'] as Map<String, dynamic>),
      brakeEvents: [
        for (final e in json['brake_events'] as List<dynamic>)
          BrakeEvent.fromJson(e as Map<String, dynamic>),
      ],
      mountRealignments: json['mount_realignments'] as int,
      sampleCount: json['sample_count'] as int,
      safetyStats: json['safety_stats'] as Map<String, dynamic>?,
      performance: json['performance'] as Map<String, dynamic>?,
    );
  }

  final String rideId;
  final RideKind kind;
  final RideStatus status;
  final DateTime startedAt;
  final DateTime endedAt;
  final int windowMinutes;

  /// Whole ride.
  final RideStats totals;

  /// The last [windowMinutes] of the ride.
  final RideStats window;
  final List<BrakeEvent> brakeEvents;
  final int mountRealignments;
  final int sampleCount;

  /// Normal-riding statistics and the safety thresholds used on this ride.
  final Map<String, dynamic>? safetyStats;

  /// What the bike did (`PerformanceReadings.toApiJson`): sustained top
  /// speed, peak acceleration and braking, stops.
  final Map<String, dynamic>? performance;

  Duration get duration => endedAt.difference(startedAt);

  static Map<String, dynamic> _statsJson(RideStats s) => {
    'max_speed_kmh': _r(s.maxSpeedKmh),
    'max_lean_left_deg': _r(s.maxLeanLeftDeg),
    'max_lean_right_deg': _r(s.maxLeanRightDeg),
    'max_stop_time_s': _r(s.maxStopTimeS),
    'best_decel_mps2': _r(s.bestDecelMps2),
    'brake_event_count': s.brakeEvents,
    'distance_m': _r(s.distanceM),
    'moving_time_s': _r(s.movingTimeS),
    'avg_moving_speed_kmh': _r(s.avgMovingSpeedKmh),
    'span_s': _r(s.span.inMilliseconds / 1000),
  };

  /// Body of `PUT /v1/rides/{id}/summary`.
  Map<String, dynamic> toApiJson() => {
    'status': status.name,
    'ended_at': endedAt.toUtc().toIso8601String(),
    'analysis_window_min': windowMinutes,
    'mount_realignments': mountRealignments,
    'sample_count': sampleCount,
    'totals': _statsJson(totals),
    'window': _statsJson(window),
    'brake_events': [for (final e in brakeEvents) e.toJson()],
    if (safetyStats != null) 'safety_stats': safetyStats,
    if (performance != null) 'performance': performance,
  };

  Map<String, dynamic> toJson() => {
    ...toApiJson(),
    'ride_id': rideId,
    'kind': kind.name,
    'started_at': startedAt.toUtc().toIso8601String(),
  };
}

double _r(double v) => double.parse(v.toStringAsFixed(2));
