/// Build-time and default configuration.
///
/// The backend URL can be set at build time with
/// `--dart-define=RIDEGUARD_API_URL=http://192.168.1.20:8000` and changed at
/// runtime in Settings. The default reaches the host machine from the
/// Android emulator.
class AppConfig {
  const AppConfig._();

  static const String defaultApiUrl = String.fromEnvironment(
    'RIDEGUARD_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// The Web OAuth client id from the Google Cloud console. Google sign-in
  /// needs it to return an ID token the backend can verify; set it with
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    // Public identifier (not a secret); override at build time if needed.
    defaultValue:
        '111524898029-jigisj0ri9nh417ofla9ibm1lkbujte9.apps.googleusercontent.com',
  );

  /// Rolling analysis window ("buffer load") in minutes. Fixed by design so
  /// every ride is analysed the same way.
  static const int analysisWindowMinutes = 15;

  /// Processed samples per second (buffer, analysis and upload rate).
  static const int sampleHz = 10;

  static const Duration imuSamplingPeriod = Duration(milliseconds: 20);
  static const int uploadBatchSize = 100;
  static const Duration uploadInterval = Duration(seconds: 5);

  /// Time the rider has to cancel after a crash before the emergency contact
  /// is called.
  static const Duration crashCountdown = Duration(seconds: 30);
}
