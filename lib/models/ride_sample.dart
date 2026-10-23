import '../core/fusion/estimators.dart';
import '../core/fusion/motion_pipeline.dart';

/// One processed reading (10 Hz) - what goes into the analysis buffer and
/// what is uploaded to the backend.
class RideSample {
  const RideSample({
    required this.seq,
    required this.time,
    required this.speedKmh,
    required this.speedSource,
    required this.leanDeg,
    required this.rollRateDps,
    required this.yawRateDps,
    required this.forwardAccel,
    required this.lateralAccel,
    this.latitude,
    this.longitude,
    this.gpsAccuracyM,
  });

  factory RideSample.fromState(int seq, DateTime time, MotionState s) =>
      RideSample(
        seq: seq,
        time: time,
        speedKmh: s.speedKmh,
        speedSource: s.speedSource,
        leanDeg: s.leanDeg,
        rollRateDps: radToDeg(s.rollRate),
        yawRateDps: radToDeg(s.yawRate),
        forwardAccel: s.forwardAccel,
        lateralAccel: s.lateralAccel,
        latitude: s.lastFix?.latitude,
        longitude: s.lastFix?.longitude,
        gpsAccuracyM: s.lastFix?.accuracyM,
      );

  final int seq;
  final DateTime time;
  final double speedKmh;
  final SpeedSource speedSource;
  final double leanDeg;
  final double rollRateDps;
  final double yawRateDps;
  final double forwardAccel;
  final double lateralAccel;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracyM;

  bool get speedReliable =>
      speedSource == SpeedSource.gps ||
      speedSource == SpeedSource.deadReckoning;

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'recorded_at': time.toUtc().toIso8601String(),
    'speed_kmh': _round(speedKmh.clamp(0, 500), 2),
    'speed_source': speedSource.name,
    'lean_deg': _round(leanDeg.clamp(-90, 90), 2),
    'roll_rate_dps': _round(rollRateDps.clamp(-2000, 2000), 2),
    'yaw_rate_dps': _round(yawRateDps.clamp(-2000, 2000), 2),
    'forward_accel_mps2': _round(forwardAccel.clamp(-100, 100), 3),
    'lateral_accel_mps2': _round(lateralAccel.clamp(-100, 100), 3),
    'latitude': latitude,
    'longitude': longitude,
    'gps_accuracy_m': gpsAccuracyM == null ? null : _round(gpsAccuracyM!, 1),
  };
}

double _round(num value, int digits) =>
    double.parse(value.toDouble().toStringAsFixed(digits));
