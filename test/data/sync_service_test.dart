import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/data/outbox.dart';

import '../support/fakes.dart';

void main() {
  test('delivers jobs in order', () async {
    final s = offlineFirstStack();
    await s.sync.enqueue('PUT', '/v1/rides/a', {'n': 1});
    await s.sync.enqueue('POST', '/v1/rides/a/samples', {'n': 2});
    await s.sync.enqueue('PUT', '/v1/rides/a/summary', {'n': 3});
    await s.sync.flush();
    expect(s.backend.requests.map((r) => r.url.path), [
      '/v1/rides/a',
      '/v1/rides/a/samples',
      '/v1/rides/a/summary',
    ]);
    expect(s.sync.pending, 0);
    expect(s.sync.online, isTrue);
  });

  test('keeps the job and retries after a server error', () async {
    final s = offlineFirstStack();
    var calls = 0;
    s.backend.status = (_) => ++calls == 1 ? 503 : 200;
    await s.sync.enqueue('PUT', '/v1/rides/a', {});
    await s.sync.enqueue('POST', '/v1/rides/a/samples', {});
    await s.sync.flush();
    expect(s.sync.pending, 2, reason: 'nothing skipped past the failure');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.sync.pending, 0);
    expect(s.backend.requests.map((r) => r.url.path).toList(), [
      '/v1/rides/a',
      '/v1/rides/a',
      '/v1/rides/a/samples',
    ]);
  });

  test('drops a request the server rejects as invalid', () async {
    final s = offlineFirstStack();
    s.backend.status = (r) => r.url.path.endsWith('bad') ? 422 : 200;
    await s.sync.enqueue('PUT', '/v1/bad', {});
    await s.sync.enqueue('PUT', '/v1/good', {});
    await s.sync.flush();
    expect(s.sync.pending, 0);
    expect(s.sync.dropped, 1);
    expect(s.backend.requests.last.url.path, '/v1/good');
  });

  test('queued jobs survive an app restart', () async {
    final dir = await Directory.systemTemp.createTemp('outbox');
    addTearDown(() => dir.delete(recursive: true));

    final first = offlineFirstStack(store: FileOutboxStore(dir));
    first.backend.status = (_) => 503; // offline for the whole ride
    await first.sync.enqueue('PUT', '/v1/rides/r1', {'kind': 'ride'});
    await first.sync.enqueue('POST', '/v1/rides/r1/samples', {'samples': []});
    first.sync.dispose();

    final second = offlineFirstStack(store: FileOutboxStore(dir));
    await second.sync.init();
    await second.sync.flush();
    expect(second.backend.requests.map((r) => r.url.path), [
      '/v1/rides/r1',
      '/v1/rides/r1/samples',
    ]);
    expect(await FileOutboxStore(dir).load(), isEmpty);
  });
}
