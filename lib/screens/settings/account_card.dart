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

  Future<void> _rename(BuildContext context) async {
    final app = context.read<AppState>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: app.displayName ?? ''),
    );
    if (name != null) await app.renameRider(name);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final account = app.account;
    final name = app.displayName;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    name ?? account.label,
                    key: const Key('account-label'),
                    style: AppText.body(17, weight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const Key('edit-name'),
                  tooltip: 'Change name',
                  onPressed: () => _rename(context),
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.textMuted,
                ),
              ],
            ),
            if (name != account.email)
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

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().isNotEmpty;

  void _save() {
    if (_valid) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        key: const Key('name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: AppState.maxNameLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          key: const Key('save-name'),
          onPressed: _valid ? _save : null,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
