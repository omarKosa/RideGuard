enum SpecQuality { official, roadTest, aggregator }

enum BikeCategory {
  scooter,
  commuter,
  naked,
  sport,
  touring,
  adventure,
  cruiser,
  offRoad,
}

enum AbsFitment { yes, no, optional, unknown }

class SpecValue {
  const SpecValue({
    required this.value,
    required this.source,
    required this.quality,
  });

  factory SpecValue.fromJson(Map<String, dynamic> json) => SpecValue(
    value: (json['value'] as num).toDouble(),
    source: json['source'] as String,
    quality: _quality(json['quality'] as String),
  );

  static SpecQuality _quality(String s) => switch (s) {
    'official' => SpecQuality.official,
    'road_test' => SpecQuality.roadTest,
    'aggregator' => SpecQuality.aggregator,
    _ => throw FormatException('Unknown spec quality: $s'),
  };

  final double value;
  final String source;
  final SpecQuality quality;
}

class CatalogueModel {
  const CatalogueModel({
    required this.id,
    required this.make,
    required this.model,
    required this.yearFrom,
    required this.yearTo,
    required this.markets,
    required this.category,
    required this.abs,
    required this.displacementCc,
    this.powerKw,
    this.weightKg,
    this.topSpeedKmh,
    this.zeroTo100S,
  });

  factory CatalogueModel.fromJson(Map<String, dynamic> json) {
    SpecValue? spec(String key) => json[key] == null
        ? null
        : SpecValue.fromJson(json[key] as Map<String, dynamic>);
    return CatalogueModel(
      id: json['id'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      yearFrom: json['year_from'] as int,
      yearTo: json['year_to'] as int?,
      markets: {for (final m in json['markets'] as List) m as String},
      category: switch (json['category'] as String) {
        'scooter' => BikeCategory.scooter,
        'commuter' => BikeCategory.commuter,
        'naked' => BikeCategory.naked,
        'sport' => BikeCategory.sport,
        'touring' => BikeCategory.touring,
        'adventure' => BikeCategory.adventure,
        'cruiser' => BikeCategory.cruiser,
        'off_road' => BikeCategory.offRoad,
        final c => throw FormatException('Unknown category: $c'),
      },
      abs: switch (json['abs'] as String) {
        'yes' => AbsFitment.yes,
        'no' => AbsFitment.no,
        'optional' => AbsFitment.optional,
        'unknown' => AbsFitment.unknown,
        final a => throw FormatException('Unknown abs value: $a'),
      },
      displacementCc: SpecValue.fromJson(
        json['displacement_cc'] as Map<String, dynamic>,
      ),
      powerKw: spec('power_kw'),
      weightKg: spec('weight_kg'),
      topSpeedKmh: spec('top_speed_kmh'),
      zeroTo100S: spec('zero_to_100_s'),
    );
  }

  final String id;
  final String make;
  final String model;
  final int yearFrom;
  final int? yearTo;
  final Set<String> markets;
  final BikeCategory category;
  final AbsFitment abs;
  final SpecValue displacementCc;
  final SpecValue? powerKw;
  final SpecValue? weightKg;
  final SpecValue? topSpeedKmh;
  final SpecValue? zeroTo100S;

  String get yearsLabel => '$yearFrom–${yearTo ?? ''}';

  String get displayName => '$make $model ($yearsLabel)';
}
