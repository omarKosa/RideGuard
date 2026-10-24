import '../core/analysis/performance_meter.dart';
import '../core/catalogue/spec_check.dart';
import 'text_clip.dart';

/// What the init ride measured, kept so a corrected model can be re-checked
/// without another init ride.
class InitReadings {
  const InitReadings({
    required this.calibrationId,
    required this.rideId,
    required this.readings,
    this.imuHz,
  });

  factory InitReadings.fromJson(Map<String, dynamic> json) => InitReadings(
    calibrationId: json['calibration_id'] as String,
    rideId: json['ride_id'] as String,
    readings: PerformanceReadings.fromJson(
      json['readings'] as Map<String, dynamic>,
    ),
    imuHz: (json['imu_hz'] as num?)?.toDouble(),
  );

  final String calibrationId;
  final String rideId;
  final PerformanceReadings readings;
  final double? imuHz;

  Map<String, dynamic> toJson() => {
    'calibration_id': calibrationId,
    'ride_id': rideId,
    'readings': readings.toJson(),
    'imu_hz': imuHz,
  };
}

/// One spec check record: the init ride's readings judged against the
/// bike's model (or saved as data for an "Other" bike).
class ModelCheck {
  const ModelCheck({
    required this.id,
    required this.bikeId,
    required this.calibrationId,
    required this.rideId,
    required this.reason,
    required this.checkedAt,
    required this.check,
    this.catalogueModelId,
    this.catalogueVersion,
    this.otherMake,
    this.otherModel,
    this.otherYear,
    this.imuHz,
    this.phoneModel,
  });

  static const initRide = 'init_ride';
  static const modelCorrected = 'model_corrected';

  final String id;
  final String bikeId;
  final String calibrationId;
  final String rideId;

  /// [initRide] or [modelCorrected].
  final String reason;
  final DateTime checkedAt;
  final String? catalogueModelId;
  final String? catalogueVersion;
  final String? otherMake;
  final String? otherModel;
  final int? otherYear;
  final double? imuHz;
  final String? phoneModel;
  final SpecCheck check;

  /// Shape of the backend's ModelCheckIn.
  Map<String, dynamic> toApiJson() {
    final hz = imuHz;
    return {
      'reason': reason,
      'calibration_id': calibrationId,
      'ride_id': rideId,
      'checked_at': checkedAt.toUtc().toIso8601String(),
      'catalogue_model_id': catalogueModelId,
      'catalogue_version': catalogueVersion,
      'other_make': clipText(otherMake, 40),
      'other_model': clipText(otherModel, 60),
      'other_year': otherYear,
      'phone_model': clipText(phoneModel, 80),
      'imu_hz': hz != null && hz > 0 && hz <= 1000 ? hz : null,
      'expected': check.envelope?.toApiJson(),
      'measured': check.measured.toApiJson(),
      'results': check.resultsApiJson(),
      'mismatch': check.mismatch,
    };
  }
}
