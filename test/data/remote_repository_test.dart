import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/models/bike_profile.dart';

import '../support/fakes.dart';

void main() {
  test(
    'legacy bike with a 70-char model sends other_model clipped to 60',
    () async {
      final s = offlineFirstStack();
      final model = 'M' * 70;
      final bike = BikeProfile.fromJson({
        'id': 'b1',
        'model': model,
        'rated_top_speed_kmh': 200,
        'created_at': '2026-10-01T00:00:00Z',
      });
      await s.remote.upsertBike('r1', bike);
      await s.sync.flush();
      final body = s.backend.bodiesFor('PUT', '/v1/bikes/b1').single;
      expect((body['other_model'] as String).length, 60);
      expect(body['model'], model);
      expect(body['catalogue_model_id'], isNull);
    },
  );
}
