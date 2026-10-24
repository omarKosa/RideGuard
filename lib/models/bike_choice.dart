import 'catalogue_model.dart';

/// What the rider picked on the bike setup page.
sealed class BikeChoice {
  const BikeChoice();
}

/// A model from the bundled catalogue. [riderTopSpeedKmh] is required when
/// the catalogue has no sourced top speed for it.
class CatalogueChoice extends BikeChoice {
  CatalogueChoice({required this.model, this.riderTopSpeedKmh})
    : assert(
        model.topSpeedKmh != null || riderTopSpeedKmh != null,
        'The rider must give a top speed when the catalogue has none',
      );

  final CatalogueModel model;
  final double? riderTopSpeedKmh;
}

/// "My bike isn't listed": typed make/model/year and the rider's top speed.
class OtherChoice extends BikeChoice {
  const OtherChoice({
    required this.make,
    required this.model,
    this.year,
    required this.topSpeedKmh,
  });

  final String make;
  final String model;
  final int? year;
  final double topSpeedKmh;
}
