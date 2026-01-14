class RideData {
  final double speed; // km/h
  final double acceleration; // m/s²
  final double rotationX; // rad/s (roll - lean angle rate)
  final double rotationY; // rad/s (pitch)
  final double rotationZ; // rad/s (yaw - turning rate)
  final double maxSpeed;
  final double estimatedStopTime; // seconds
  final double timeToTarget; // seconds to reach target speed
  final DateTime timestamp;
  final double distance; // meters traveled

  RideData({
    required this.speed,
    required this.acceleration,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.maxSpeed,
    required this.estimatedStopTime,
    required this.timeToTarget,
    required this.timestamp,
    required this.distance,
  });

  factory RideData.initial() {
    return RideData(
      speed: 0,
      acceleration: 0,
      rotationX: 0,
      rotationY: 0,
      rotationZ: 0,
      maxSpeed: 0,
      estimatedStopTime: 0,
      timeToTarget: 0,
      timestamp: DateTime.now(),
      distance: 0,
    );
  }

  RideData copyWith({
    double? speed,
    double? acceleration,
    double? rotationX,
    double? rotationY,
    double? rotationZ,
    double? maxSpeed,
    double? estimatedStopTime,
    double? timeToTarget,
    DateTime? timestamp,
    double? distance,
  }) {
    return RideData(
      speed: speed ?? this.speed,
      acceleration: acceleration ?? this.acceleration,
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      rotationZ: rotationZ ?? this.rotationZ,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      estimatedStopTime: estimatedStopTime ?? this.estimatedStopTime,
      timeToTarget: timeToTarget ?? this.timeToTarget,
      timestamp: timestamp ?? this.timestamp,
      distance: distance ?? this.distance,
    );
  }
}

class SpeedHistoryPoint {
  final DateTime time;
  final double speed;

  SpeedHistoryPoint(this.time, this.speed);
}

