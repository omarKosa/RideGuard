import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/google_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'start_screen.dart';

/// First screen: sign in with Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      final result = await context.read<GoogleAuth>().signIn();
      await app.completeSignIn(result);
      if (mounted) _continue(app);
    } on GoogleAuthException catch (e) {
      if (mounted) setState(() => _error = e.cancelled ? null : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    final app = context.read<AppState>();
    await app.skipSignIn();
    if (mounted) _continue(app);
  }

  void _continue(AppState app) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => startScreenFor(app.startupStep)),
  );

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLogo(),
                    const SizedBox(height: 12),
                    Text(
                      'Lean angle, braking and crash alerts for your rides.',
                      textAlign: TextAlign.center,
                      style: AppText.body(16, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 48),
                    _GoogleButton(busy: _busy, onPressed: _signIn),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      WarningBanner(
                        key: const Key('sign-in-error'),
                        icon: Icons.error_outline,
                        color: AppColors.red,
                        text: error,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Your Google account keeps your rides linked to you.',
                      textAlign: TextAlign.center,
                      style: AppText.body(13, color: AppColors.textFaint),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      TextButton(
                        key: const Key('skip-sign-in'),
                        onPressed: _busy ? null : _skip,
                        child: const Text('SKIP SIGN-IN (DEBUG BUILD)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        key: const Key('google-sign-in'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            // Shrinks rather than overflowing on narrow phones / big fonts.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'G',
                      style: AppText.display(
                        20,
                        color: const Color(0xFF4285F4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Continue with Google',
                      style: AppText.body(
                        17,
                        color: Colors.black87,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
