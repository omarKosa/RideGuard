import '../core/fusion/motion_pipeline.dart';
import 'brake_event.dart';

/// Result of the init ride: how the phone sits on this bike plus the
/// rider's measured limits.
class CalibrationProfile {
  const CalibrationProfile({
    required this.id,
    required this.bikeId,
    required this.rideId,
    required this.calibratedAt,
    required this.params,
    required this.forwardFromMotion,
    required this.straightOffsetDeg,
    required this.quality,
    this.achievedTopSpeedKmh,
    this.brakeEvent,
    this.skippedTasks = const [],
    this.warnings = const [],
  });

  factory CalibrationProfile.fromJson(Map<String, dynamic> json) =>
      CalibrationProfile(
        id: json['id'] as String,
        bikeId: json['bike_id'] as String,
        rideId: json['ride_id'] as String,
        calibratedAt: DateTime.parse(json['calibrated_at'] as String),
        params: FusionParams.fromJson(json['params'] as Map<String, dynamic>),
        forwardFromMotion: json['forward_from_motion'] as bool,
        straightOffsetDeg: (json['straight_offset_deg'] as num).toDouble(),
        quality: (json['quality'] as num).toDouble(),
        achievedTopSpeedKmh: (json['achieved_top_speed_kmh'] as num?)
            ?.toDouble(),
        brakeEvent: json['brake_event'] == null
            ? null
            : BrakeEvent.fromJson(json['brake_event'] as Map<String, dynamic>),
        skippedTasks: (json['skipped_tasks'] as List<dynamic>).cast<String>(),
        warnings: (json['warnings'] as List<dynamic>).cast<String>(),
      );

  /// Used for stop-time estimates when the rider skipped the brake test.
  static const double defaultDecelMps2 = 6.0;

  final String id;
  final String bikeId;

  /// The calibration ride whose samples back this profile.
  final String rideId;
  final DateTime calibratedAt;
  final FusionParams params;

  /// False when the forward axis is still a guess from the phone's pose.
  final bool forwardFromMotion;

  /// How far "riding straight" was from the still reading, i.e. how much
  /// the lean had to be normalized (side stand, tilted mount).
  final double straightOffsetDeg;

  /// 0..1 confidence in this calibration.
  final double quality;
  final double? achievedTopSpeedKmh;
  final BrakeEvent? brakeEvent;
  final List<String> skippedTasks;
  final List<String> warnings;

  /// Mean deceleration of the calibration stop - what the rider actually
  /// achieves, not the peak.
  double get brakingDecelMps2 {
    final e = brakeEvent;
    if (e == null || e.meanDecelMps2 < 1) return defaultDecelMps2;
    return e.meanDecelMps2;
  }

  /// Time to stop from [speedKmh] at this rider's measured braking.
  double estimatedStopTimeS(double speedKmh) =>
      (speedKmh / 3.6) / brakingDecelMps2;

  Map<String, dynamic> toJson() => {
    'id': id,
    'bike_id': bikeId,
    'ride_id': rideId,
    'calibrated_at': calibratedAt.toUtc().toIso8601String(),
    'params': params.toJson(),
    'forward_from_motion': forwardFromMotion,
    'straight_offset_deg': straightOffsetDeg,
    'quality': quality,
    'achieved_top_speed_kmh': achievedTopSpeedKmh,
    'brake_event': brakeEvent?.toJson(),
    'skipped_tasks': skippedTasks,
    'warnings': warnings,
  };

  /// Flat representation expected by the backend.
  Map<String, dynamic> toApiJson() => {
    'bike_id': bikeId,
    'ride_id': rideId,
    'calibrated_at': calibratedAt.toUtc().toIso8601String(),
    'mount_up': params.mount.up.toList(),
    'mount_forward': params.mount.forward.toList(),
    'gyro_bias': params.gyroBias.toList(),
    'linear_accel_bias': params.linearAccelBias.toList(),
    'lean_gain': params.leanGain,
    'forward_from_motion': forwardFromMotion,
    'straight_offset_deg': straightOffsetDeg,
    'quality': quality,
    'achieved_top_speed_kmh': achievedTopSpeedKmh,
    'stop_time_s': brakeEvent?.durationS,
    'stop_start_speed_kmh': brakeEvent?.startSpeedKmh,
    'stop_distance_m': brakeEvent?.distanceM,
    'max_decel_mps2': brakeEvent?.peakDecelMps2,
    'skipped_tasks': skippedTasks,
    'warnings': warnings,
  };
}
