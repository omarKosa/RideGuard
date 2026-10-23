import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/api_client.dart';
import 'data/sync_service.dart';
import 'screens/bike_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/safety_briefing_screen.dart';
import 'services/app_state.dart';
import 'services/emergency_platform.dart';
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
  });

  final AppState appState;
  final SyncService sync;
  final ApiClient api;
  final SensorSource sensors;
  final EmergencyPlatform emergency;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: api),
        Provider.value(value: sensors),
        Provider.value(value: emergency),
      ],
      child: MaterialApp(
        title: 'RideGuard',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // Setup first: bike -> init ride -> riding.
        home: switch (appState.startupStep) {
          StartupStep.bikeSetup => const BikeSetupScreen(),
          StartupStep.calibration => const SafetyBriefingScreen(),
          StartupStep.ready => const HomeScreen(),
        },
      ),
    );
  }
}
