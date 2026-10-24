import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/data/api_client.dart';
import 'package:ride_guard/data/bike_catalogue.dart';
import 'package:ride_guard/data/outbox.dart';
import 'package:ride_guard/data/remote_repository.dart';
import 'package:ride_guard/data/sync_service.dart';
import 'package:ride_guard/services/emergency_platform.dart';
import 'package:ride_guard/services/sensor_feed.dart';

/// Sensor source fed by the test.
class FakeSensorSource implements SensorSource {
  FakeSensorSource({this.access = LocationAccess.granted});

  final LocationAccess access;
  // Synchronous so replayed data is processed at the time it is emitted.
  final accel = StreamController<ImuEvent>.broadcast(sync: true);
  final linear = StreamController<ImuEvent>.broadcast(sync: true);
  final gyro = StreamController<ImuEvent>.broadcast(sync: true);
  final gps = StreamController<LocationEvent>.broadcast(sync: true);

  @override
  Future<LocationAccess> requestLocation() async => access;
  @override
  Stream<ImuEvent> accelerometer() => accel.stream;
  @override
  Stream<ImuEvent> userAccelerometer() => linear.stream;
  @override
  Stream<ImuEvent> gyroscope() => gyro.stream;
  @override
  Stream<LocationEvent> location() => gps.stream;

  void emitImu(Vec3 a, Vec3 lin, Vec3 g, DateTime ts) {
    accel.add(ImuEvent(a, ts));
    linear.add(ImuEvent(lin, ts));
    gyro.add(ImuEvent(g, ts));
  }
}

/// Records alarm and call requests instead of making noise.
class FakeEmergencyPlatform implements EmergencyPlatform {
  final List<String> events = [];
  CallResult callResult = CallResult.placed;
  bool permission = true;

  /// Null while silent.
  bool? alarmUrgent;

  @override
  Future<void> startAlarm({required bool urgent}) async {
    events.add(urgent ? 'alarm' : 'alert');
    alarmUrgent = urgent;
  }

  @override
  Future<void> stopAlarm() async {
    events.add('stop');
    alarmUrgent = null;
  }

  @override
  Future<CallResult> call(String number) async {
    events.add('call $number');
    return callResult;
  }

  @override
  Future<bool> requestCallPermission() async => permission;
}

/// Records every request and answers with [status] (default 200).
class RecordingBackend {
  final List<http.Request> requests = [];
  int Function(http.Request request) status = (_) => 200;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final code = status(request);
    return http.Response(
      code < 300 ? '{"status":"ok"}' : '{"detail":"nope"}',
      code,
      headers: {'content-type': 'application/json'},
    );
  });

  List<Map<String, dynamic>> bodiesFor(String method, Pattern path) => [
    for (final r in requests)
      if (r.method == method && r.url.path.contains(path))
        jsonDecode(r.body) as Map<String, dynamic>,
  ];
}

({SyncService sync, RemoteRepository remote, RecordingBackend backend})
offlineFirstStack({OutboxStore? store}) {
  final backend = RecordingBackend();
  final api = ApiClient(
    baseUrl: () => 'http://backend.test',
    client: backend.client,
  );
  final sync = SyncService(
    api: api,
    store: store ?? MemoryOutboxStore(),
    backoff: (_) => const Duration(milliseconds: 10),
  );
  return (sync: sync, remote: RemoteRepository(sync), backend: backend);
}

BikeCatalogue? _catalogue;

/// The bundled catalogue, read from the repo (tests run from its root).
BikeCatalogue realCatalogue() => _catalogue ??= BikeCatalogue.parse(
  File(BikeCatalogue.assetPath).readAsStringSync(),
);
