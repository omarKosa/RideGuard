import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/google_auth.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

/// Who is signed in, and signing out.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  Future<void> _signOut(BuildContext context) async {
    final app = context.read<AppState>();
    await context.read<GoogleAuth>().signOut();
    await app.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AppState>().account;
    return SectionCard(
      title: 'ACCOUNT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account == null)
            Text(
              'Not signed in (debug build).',
              style: AppText.body(15, color: AppColors.textMuted),
            )
          else ...[
            Text(
              account.label,
              key: const Key('account-label'),
              style: AppText.body(17, weight: FontWeight.bold),
            ),
            if (account.label != account.email)
              Text(
                account.email,
                style: AppText.body(14, color: AppColors.textMuted),
              ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('sign-out'),
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
            label: Text(account == null ? 'SIGN IN' : 'SIGN OUT'),
          ),
        ],
      ),
    );
  }
}
