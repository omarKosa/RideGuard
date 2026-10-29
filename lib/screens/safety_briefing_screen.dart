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
                  'Mount the phone how you will ride with it, then follow the '
                  'steps. Tap a step for details.',
                  style: AppText.body(15, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                for (final (i, task) in CalibrationTask.values.indexed)
                  _TaskRow(index: i + 1, task: task),
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({required this.index, required this.task});

  final int index;
  final CalibrationTask task;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
              child: Text(
                '${widget.index}',
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.task.title.toUpperCase(),
                      style: AppText.label(13, color: Colors.white),
                    ),
                  ),
                  if (_open) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.task.instruction,
                      style: AppText.body(14, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              _open ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
