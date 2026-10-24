import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/data/bike_catalogue.dart';

void main() {
  final raw = File('backend/app/catalogue/bikes.json').readAsStringSync();
  final cat = BikeCatalogue.parse(raw);

  test('makes follow the file make_order', () {
    final order = (jsonDecode(raw)['make_order'] as List).cast<String>();
    expect(cat.makes, order);
  });

  test('byId resolves and builds the display name', () {
    final m = cat.byId('suzuki-gsx-s1000-2021')!;
    expect(m.displayName, 'Suzuki GSX-S1000 (2021–)');
    expect(m.yearsLabel, '2021–');
    expect(cat.byId('nope'), isNull);
  });

  test('modelsFor lists both generations, newer first', () {
    final list = cat.modelsFor('Suzuki');
    expect(list, isNotEmpty);
    final gens = list.where((m) => m.model == 'GSX-S1000').toList();
    expect(gens.map((m) => m.id), [
      'suzuki-gsx-s1000-2021',
      'suzuki-gsx-s1000-2015',
    ]);
    expect(cat.byId('suzuki-gsx-s1000-2015')!.yearsLabel, startsWith('2015–'));
  });

  test('specs parse with quality and nullable fields', () {
    final adv = cat.byId('honda-adv350-2022')!;
    expect(adv.displacementCc.value, 330);
    expect(adv.displacementCc.quality, SpecQuality.official);
    expect(adv.topSpeedKmh, isNull);
    expect(adv.category, BikeCategory.scooter);
    expect(adv.abs, AbsFitment.yes);
    expect(adv.markets, {'tr'});
    expect(cat.version, isNotEmpty);
  });
}
