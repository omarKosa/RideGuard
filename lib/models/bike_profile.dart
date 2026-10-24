/// Where the rated top speed came from.
enum TopSpeedSource { catalogue, rider, measured }

class BikeProfile {
  const BikeProfile({
    required this.id,
    required this.model,
    required this.ratedTopSpeedKmh,
    required this.createdAt,
    this.catalogueModelId,
    this.catalogueVersion,
    this.otherMake,
    this.otherModel,
    this.otherYear,
    this.topSpeedSource = TopSpeedSource.rider,
  });

  /// Stored by the app before the catalogue: free text, no source.
  static bool isLegacyJson(Map<String, dynamic> json) =>
      !json.containsKey('top_speed_source');

  factory BikeProfile.fromJson(Map<String, dynamic> json) {
    final model = json['model'] as String;
    final legacy = isLegacyJson(json);
    return BikeProfile(
      id: json['id'] as String,
      model: model,
      ratedTopSpeedKmh: (json['rated_top_speed_kmh'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      catalogueModelId: json['catalogue_model_id'] as String?,
      catalogueVersion: json['catalogue_version'] as String?,
      otherMake: json['other_make'] as String?,
      otherModel: legacy ? model : json['other_model'] as String?,
      otherYear: json['other_year'] as int?,
      topSpeedSource: legacy
          ? TopSpeedSource.rider
          : TopSpeedSource.values.byName(json['top_speed_source'] as String),
    );
  }

  static const double minTopSpeedKmh = 40;
  static const double maxTopSpeedKmh = 420;

  final String id;
  final String model;

  /// The fastest the rider says the bike can go.
  final double ratedTopSpeedKmh;
  final DateTime createdAt;

  final String? catalogueModelId;
  final String? catalogueVersion;
  final String? otherMake;
  final String? otherModel;
  final int? otherYear;
  final TopSpeedSource topSpeedSource;

  bool get isOther => catalogueModelId == null;

  BikeProfile copyWith({
    String? model,
    double? ratedTopSpeedKmh,
    String? catalogueModelId,
    String? catalogueVersion,
    String? otherMake,
    String? otherModel,
    int? otherYear,
    TopSpeedSource? topSpeedSource,
  }) => BikeProfile(
    id: id,
    model: model ?? this.model,
    ratedTopSpeedKmh: ratedTopSpeedKmh ?? this.ratedTopSpeedKmh,
    createdAt: createdAt,
    catalogueModelId: catalogueModelId ?? this.catalogueModelId,
    catalogueVersion: catalogueVersion ?? this.catalogueVersion,
    otherMake: otherMake ?? this.otherMake,
    otherModel: otherModel ?? this.otherModel,
    otherYear: otherYear ?? this.otherYear,
    topSpeedSource: topSpeedSource ?? this.topSpeedSource,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'model': model,
    'rated_top_speed_kmh': ratedTopSpeedKmh,
    'created_at': createdAt.toUtc().toIso8601String(),
    'catalogue_model_id': catalogueModelId,
    'catalogue_version': catalogueVersion,
    'other_make': otherMake,
    'other_model': otherModel,
    'other_year': otherYear,
    'top_speed_source': topSpeedSource.name,
  };
}
