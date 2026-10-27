import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../screens/home_screen.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// Testing shortcut on the first-run screens: skips bike setup and the init
/// ride and opens Home. Hidden unless [AppConfig.testShortcuts] is on.
class SkipSetupButton extends StatefulWidget {
  const SkipSetupButton({super.key});

  @override
  State<SkipSetupButton> createState() => _SkipSetupButtonState();
}

class _SkipSetupButtonState extends State<SkipSetupButton> {
  bool _busy = false;

  Future<void> _skip() async {
    setState(() => _busy = true);
    await context.read<AppState>().skipSetupForTesting();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.testShortcuts) return const SizedBox.shrink();
    return TextButton.icon(
      key: const Key('skip-setup'),
      onPressed: _busy ? null : _skip,
      icon: const Icon(Icons.bug_report_outlined, size: 18),
      label: Text(
        'Skip setup (testing)',
        style: AppText.body(14, color: AppColors.textMuted),
      ),
    );
  }
}
