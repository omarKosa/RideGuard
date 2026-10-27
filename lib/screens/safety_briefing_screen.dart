import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calibration/calibration_session.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/init_ride_warning_dialog.dart';
import 'calibration/calibration_screen.dart';
import 'home_screen.dart';

/// Explains the init ride. The safety warning and acknowledgements appear
/// in a popup only when the rider taps START INIT RIDE, so the page itself
/// stays calm; the rider can also skip the init ride for now.
class SafetyBriefingScreen extends StatelessWidget {
  const SafetyBriefingScreen({super.key});

  Future<void> _start(BuildContext context) async {
    if (!await InitRideWarningDialog.show(context) || !context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CalibrationScreen()),
    );
  }

  Future<void> _skip(BuildContext context) async {
    await context.read<AppState>().skipInitRide();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bike = app.bike;
    // Redoing an existing calibration: nothing to skip, back leaves.
    final canSkip = bike != null && app.calibration?.bikeId != bike.id;
    return Scaffold(
      appBar: AppBar(title: const Text('INIT RIDE')),
      body: GradientBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A short guided ride teaches RideGuard how your phone sits '
                  'on your bike, so lean, speed and braking read right.',
                  style: AppText.body(15, color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                Text('WHAT YOU WILL DO', style: AppText.label(12)),
                const SizedBox(height: 10),
                for (final (i, task) in CalibrationTask.values.indexed)
                  _TaskRow(index: i + 1, task: task),
                const SizedBox(height: 8),
                Text(
                  'Mount the phone exactly how you will ride with it - any '
                  'angle works. The app learns how it sits and normalizes the '
                  'lean reading so upright reads 0°.',
                  style: AppText.body(14, color: AppColors.textMuted),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  key: const Key('start-calibration'),
                  label: 'START INIT RIDE',
                  icon: Icons.flag_outlined,
                  onPressed: () => _start(context),
                ),
                if (canSkip) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('skip-init-ride'),
                    onPressed: () => _skip(context),
                    child: const Text('SKIP FOR NOW'),
                  ),
                  Text(
                    'You can ride right away; readings are less accurate '
                    'until you do the init ride from the home screen.',
                    textAlign: TextAlign.center,
                    style: AppText.body(13, color: AppColors.textFaint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.index, required this.task});

  final int index;
  final CalibrationTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
            child: Text(
              '$index',
              style: AppText.body(
                13,
                color: AppColors.cyan,
                weight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title.toUpperCase(),
                  style: AppText.label(13, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  task.instruction,
                  style: AppText.body(14, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
