import 'package:flutter/widgets.dart';

import '../services/app_state.dart';
import 'bike_setup/bike_setup_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'safety_briefing_screen.dart';

/// The screen for how far setup got: sign in -> bike -> init ride -> home.
Widget startScreenFor(StartupStep step) => switch (step) {
  StartupStep.signIn => const LoginScreen(),
  StartupStep.bikeSetup => const BikeSetupScreen(),
  StartupStep.calibration => const SafetyBriefingScreen(),
  StartupStep.ready => const HomeScreen(),
};
