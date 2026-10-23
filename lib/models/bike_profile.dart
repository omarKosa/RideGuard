class BikeProfile {
  const BikeProfile({
    required this.id,
    required this.model,
    required this.ratedTopSpeedKmh,
    required this.createdAt,
  });

  factory BikeProfile.fromJson(Map<String, dynamic> json) => BikeProfile(
    id: json['id'] as String,
    model: json['model'] as String,
    ratedTopSpeedKmh: (json['rated_top_speed_kmh'] as num).toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  static const double minTopSpeedKmh = 40;
  static const double maxTopSpeedKmh = 420;

  final String id;
  final String model;

  /// The fastest the rider says the bike can go.
  final double ratedTopSpeedKmh;
  final DateTime createdAt;

  BikeProfile copyWith({String? model, double? ratedTopSpeedKmh}) =>
      BikeProfile(
        id: id,
        model: model ?? this.model,
        ratedTopSpeedKmh: ratedTopSpeedKmh ?? this.ratedTopSpeedKmh,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'model': model,
    'rated_top_speed_kmh': ratedTopSpeedKmh,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
