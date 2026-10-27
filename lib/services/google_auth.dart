import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';
import '../models/rider_account.dart';

/// A finished Google sign-in: who signed in, and the ID token the backend
/// verifies to link the account to this rider.
class GoogleSignInResult {
  const GoogleSignInResult({required this.account, required this.idToken});

  final RiderAccount account;
  final String? idToken;
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message, {this.cancelled = false});

  final String message;

  /// The rider closed the Google dialog; not an error worth showing.
  final bool cancelled;

  @override
  String toString() => message;
}

abstract interface class GoogleAuth {
  /// Shows Google's account chooser. Throws [GoogleAuthException].
  Future<GoogleSignInResult> signIn();

  Future<void> signOut();
}

/// Google sign-in through the platform (Credential Manager on Android).
class DeviceGoogleAuth implements GoogleAuth {
  DeviceGoogleAuth({String serverClientId = AppConfig.googleServerClientId})
    : _serverClientId = serverClientId;

  final String _serverClientId;
  Future<void>? _initialized;

  Future<void> _init() => _initialized ??= GoogleSignIn.instance.initialize(
    serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
  );

  @override
  Future<GoogleSignInResult> signIn() async {
    if (_serverClientId.isEmpty) {
      throw const GoogleAuthException(
        'Google sign-in is not set up in this build '
        '(GOOGLE_SERVER_CLIENT_ID is missing).',
      );
    }
    try {
      await _init();
      final user = await GoogleSignIn.instance.authenticate();
      return GoogleSignInResult(
        account: RiderAccount(
          googleId: user.id,
          email: user.email,
          name: user.displayName,
        ),
        idToken: user.authentication.idToken,
      );
    } on GoogleSignInException catch (e) {
      final cancelled =
          e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted;
      throw GoogleAuthException(
        cancelled
            ? 'Sign-in was cancelled.'
            : 'Google sign-in failed (${e.code.name}). Check your connection '
                  'and try again.',
        cancelled: cancelled,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Signing out locally is what matters; the platform may not have a
      // session at all (e.g. debug skip).
    }
  }
}
