import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/models/bike_profile.dart';

void main() {
  test('a legacy record becomes an Other bike with its text as model', () {
    final b = BikeProfile.fromJson({
      'id': 'b',
      'model': 'Yamaha MT-07',
      'rated_top_speed_kmh': 214,
      'created_at': '2026-10-01T00:00:00Z',
    });
    expect(b.isOther, isTrue);
    expect(b.otherModel, 'Yamaha MT-07');
    expect(b.otherMake, isNull);
    expect(b.topSpeedSource, TopSpeedSource.rider);
    expect(b.ratedTopSpeedKmh, 214);
  });

  test('a catalogue bike round-trips every field', () {
    final b = BikeProfile(
      id: 'b',
      model: 'Suzuki GSX-S1000 (2021–)',
      ratedTopSpeedKmh: 250,
      createdAt: DateTime.utc(2026, 10, 1),
      catalogueModelId: 'suzuki-gsx-s1000-2021',
      catalogueVersion: '2026.10.1',
      topSpeedSource: TopSpeedSource.catalogue,
    );
    final r = BikeProfile.fromJson(b.toJson());
    expect(r.isOther, isFalse);
    expect(r.catalogueModelId, 'suzuki-gsx-s1000-2021');
    expect(r.catalogueVersion, '2026.10.1');
    expect(r.otherModel, isNull);
    expect(r.topSpeedSource, TopSpeedSource.catalogue);
    expect(r.model, b.model);
  });

  test('an Other bike round-trips and copyWith covers new fields', () {
    final b = BikeProfile(
      id: 'b',
      model: 'Foo Bar',
      ratedTopSpeedKmh: 120,
      createdAt: DateTime.utc(2026, 10, 1),
      otherMake: 'Foo',
      otherModel: 'Bar',
      otherYear: 2018,
    );
    final r = BikeProfile.fromJson(b.toJson());
    expect(r.otherMake, 'Foo');
    expect(r.otherYear, 2018);
    expect(r.topSpeedSource, TopSpeedSource.rider);
    final c = r.copyWith(
      topSpeedSource: TopSpeedSource.measured,
      otherYear: 2019,
    );
    expect(c.topSpeedSource, TopSpeedSource.measured);
    expect(c.otherYear, 2019);
    expect(c.otherMake, 'Foo');
  });
}
