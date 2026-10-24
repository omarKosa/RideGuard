import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/safety_overlay.dart';

/// What crash/wobble detection has learned about this mount.
class SafetyLearningCard extends StatelessWidget {
  const SafetyLearningCard({super.key});

  Future<void> _reset(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset safety learning?'),
        content: const Text(
          'Alerts go back to default sensitivity and the app learns again '
          'from your next rides. Do this after changing the phone mount.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (ok == true) await app.resetSafetyLearning();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SectionCard(
      title: 'SAFETY LEARNING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Every ride teaches the app how this bike and mount normally '
            'vibrate, so road buzz is not mistaken for a wobble. Learning '
            'only ever makes alerts less sensitive, never past a safe limit.',
            style: AppText.body(14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          SafetyLearningSummary(baseline: app.safetyBaseline),
          if (app.calibration != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('reset-safety-learning'),
              onPressed: () => _reset(context),
              icon: const Icon(Icons.restart_alt),
              label: const Text('RESET LEARNING'),
            ),
          ],
        ],
      ),
    );
  }
}
