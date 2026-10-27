import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/api_client.dart';
import 'data/sync_service.dart';
import 'screens/start_screen.dart';
import 'services/app_state.dart';
import 'services/emergency_platform.dart';
import 'services/google_auth.dart';
import 'services/sensor_feed.dart';
import 'theme/app_theme.dart';

class RideGuardApp extends StatelessWidget {
  const RideGuardApp({
    super.key,
    required this.appState,
    required this.sync,
    required this.api,
    required this.sensors,
    required this.emergency,
    required this.googleAuth,
  });

  final AppState appState;
  final SyncService sync;
  final ApiClient api;
  final SensorSource sensors;
  final EmergencyPlatform emergency;
  final GoogleAuth googleAuth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: api),
        Provider.value(value: sensors),
        Provider.value(value: emergency),
        Provider.value(value: googleAuth),
      ],
      child: MaterialApp(
        title: 'RideGuard',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // Setup first: sign in -> bike -> init ride -> riding.
        home: startScreenFor(appState.startupStep),
      ),
    );
  }
}
