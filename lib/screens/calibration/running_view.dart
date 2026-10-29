import 'package:flutter/material.dart';

import '../../core/calibration/calibration_session.dart';
import '../../services/calibration_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class RunningView extends StatelessWidget {
  const RunningView({
    super.key,
    required this.controller,
    required this.session,
  });

  final CalibrationController controller;
  final CalibrationSession session;

  @override
  Widget build(BuildContext context) {
    final task = session.current;
    final state = controller.state;
    if (task == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final step = CalibrationTask.values.indexOf(task) + 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (!controller.gpsAvailable)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: WarningBanner(icon: Icons.gps_off, text: 'GPS unavailable'),
          ),
        if (controller.sensorError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WarningBanner(
              color: AppColors.red,
              text: controller.sensorError!,
            ),
          ),
        if (task == CalibrationTask.topSpeed ||
            task == CalibrationTask.brakeStop)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: WarningBanner(
              color: AppColors.red,
              text: 'Closed track or empty legal road only',
            ),
          ),
        SectionCard(
          borderColor: AppColors.cyan.withValues(alpha: 0.4),
          title: 'TASK $step OF ${CalibrationTask.values.length}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title.toUpperCase(), style: AppText.display(24)),
              const SizedBox(height: 10),
              Text(task.instruction, style: AppText.body(17)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: session.progress,
                  minHeight: 10,
                  backgroundColor: AppColors.border,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                session.detail,
                key: const Key('task-detail'),
                style: AppText.body(
                  18,
                  color: AppColors.cyan,
                  weight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'SPEED KM/H',
                value: (state?.speedKmh ?? 0).toStringAsFixed(0),
                icon: Icons.speed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'LEAN',
                value: '${(state?.leanDeg ?? 0).toStringAsFixed(0)}°',
                icon: Icons.screen_rotation_alt,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'PEAK KM/H',
                value: (session.achievedTopSpeedKmh ?? 0).toStringAsFixed(0),
                icon: Icons.trending_up,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'PROGRESS',
          child: Column(
            children: [
              for (final t in CalibrationTask.values)
                TaskStatusRow(task: t, state: session.states[t]!),
            ],
          ),
        ),
        if (task.skippable) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('skip-task'),
            onPressed: controller.skip,
            icon: const Icon(Icons.skip_next),
            label: const Text('SKIP THIS TASK'),
          ),
        ],
      ],
    );
  }
}

class TaskStatusRow extends StatelessWidget {
  const TaskStatusRow({super.key, required this.task, required this.state});

  final CalibrationTask task;
  final TaskState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      TaskState.done => (Icons.check_circle, AppColors.green),
      TaskState.active => (Icons.radio_button_checked, AppColors.cyan),
      TaskState.skipped => (Icons.remove_circle_outline, AppColors.amber),
      TaskState.pending => (Icons.radio_button_unchecked, AppColors.textFaint),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.title,
              style: AppText.body(
                16,
                color: state == TaskState.pending
                    ? AppColors.textFaint
                    : Colors.white,
              ),
            ),
          ),
          if (state == TaskState.skipped)
            Text('skipped', style: AppText.body(13, color: AppColors.amber)),
        ],
      ),
    );
  }
}
