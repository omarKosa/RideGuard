import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/phone_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  test('rider upload carries the phone model', () async {
    SharedPreferences.setMockInitialValues({});
    final stack = offlineFirstStack();
    final app = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      phoneInfo: () async =>
          const PhoneInfo(model: 'Pixel 9', osVersion: 'Android 16'),
    );
    await app.load();
    await app.saveBike(model: 'Vespa', ratedTopSpeedKmh: 90);
    await Future<void>.delayed(Duration.zero);

    final bodies = stack.backend.bodiesFor('PUT', '/v1/riders/');
    expect(bodies, isNotEmpty);
    expect(bodies.last['phone_model'], 'Pixel 9');
    expect(bodies.last['os_version'], 'Android 16');
  });

  test('a failing reader falls back to unknown', () async {
    SharedPreferences.setMockInitialValues({});
    final stack = offlineFirstStack();
    final app = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      phoneInfo: () async => throw StateError('no plugin'),
    );
    await app.load();
    expect(app.phone.model, isNull);
  });
}
