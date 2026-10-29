import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Future<(AppState, RecordingBackend, LocalStore, dynamic)> _open() async {
  final stack = offlineFirstStack();
  final store = await LocalStore.open();
  await store.setAccount(testAccount);
  final app = AppState(
    store: store,
    remote: stack.remote,
    catalogue: realCatalogue(),
  );
  await app.load();
  return (app, stack.backend, store, stack.sync);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'the rider can change their name; it shows at once and is sent',
    () async {
      final (app, backend, store, sync) = await _open();
      expect(app.displayName, 'Mona'); // from the Google account

      expect(await app.renameRider('  Omar   K '), isTrue);
      expect(app.displayName, 'Omar K');
      expect(store.displayName, 'Omar K');

      await sync.flush();
      final sent = backend.bodiesFor('PUT', '/v1/riders/${app.riderId}/name');
      expect(sent.single['name'], 'Omar K');
    },
  );

  test('a blank or too long name is refused and nothing is sent', () async {
    final (app, backend, _, sync) = await _open();
    expect(await app.renameRider('   '), isFalse);
    expect(await app.renameRider('x' * 61), isFalse);
    await sync.flush();
    expect(app.displayName, 'Mona');
    expect(backend.bodiesFor('PUT', '/name'), isEmpty);
  });

  test('a rename made while the network drops is kept and resent', () async {
    final (app, backend, _, sync) = await _open();
    // Riding: the phone hops between cell towers, so requests fail.
    backend.status = (_) => 503;
    await app.renameRider('Omar');
    await sync.flush();
    expect(app.displayName, 'Omar'); // the screen already shows it
    expect(sync.pending, greaterThan(0));

    // A new connection comes up; the same request goes through.
    backend.status = (_) => 200;
    for (var i = 0; i < 50 && sync.pending > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(sync.pending, 0);
    final sent = backend.bodiesFor('PUT', '/v1/riders/${app.riderId}/name');
    expect(sent.last['name'], 'Omar');
    expect(sent.length, greaterThan(1)); // tried again after the failure
  });

  test('the chosen name survives a restart; signing out forgets it', () async {
    final (app, _, _, sync) = await _open();
    await app.renameRider('Omar');
    await sync.flush();

    final (again, _, _, _) = await _open();
    expect(again.displayName, 'Omar');

    await again.signOut();
    expect(again.displayName, isNull);
    final (afterSignOut, _, _, _) = await _open();
    expect(afterSignOut.displayName, 'Mona');
  });
}
