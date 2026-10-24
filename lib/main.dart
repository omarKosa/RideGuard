import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/outbox.dart';
import 'data/remote_repository.dart';
import 'data/sync_service.dart';
import 'services/app_state.dart';
import 'services/emergency_platform.dart';
import 'services/phone_info.dart';
import 'services/sensor_feed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final store = await LocalStore.open();
  final docs = await getApplicationDocumentsDirectory();

  // The API URL lives in AppState (editable in Settings); the client reads
  // it on every request.
  late final AppState appState;
  final api = ApiClient(baseUrl: () => appState.apiUrl);
  final sync = SyncService(
    api: api,
    store: FileOutboxStore(Directory('${docs.path}/outbox')),
  );
  appState = AppState(
    store: store,
    remote: RemoteRepository(sync),
    phoneInfo: readPhoneInfo,
  );
  await appState.load();
  await sync.init();

  runApp(
    RideGuardApp(
      appState: appState,
      sync: sync,
      api: api,
      sensors: DeviceSensorSource(),
      emergency: const DeviceEmergencyPlatform(),
    ),
  );
}
