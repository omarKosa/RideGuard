import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calibration/calibration_session.dart';
import '../models/calibration_profile.dart';
import '../services/app_state.dart';
import '../services/calibration_controller.dart';
import '../services/sensor_feed.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'safety_briefing_screen.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CalibrationController(
        app: context.read<AppState>(),
        feed: SensorFeed(context.read<SensorSource>()),
      )..start(),
      child: const _CalibrationView(),
    );
  }
}

class _CalibrationView extends StatelessWidget {
  const _CalibrationView();

  Future<void> _confirmAbort(BuildContext context) async {
    final controller = context.read<CalibrationController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the init ride?'),
        content: const Text('Progress so far will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('KEEP GOING'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('STOP'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.abort();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CalibrationController>();
    final result = c.result;
    final session = c.session;

    final Widget body = switch (c.phase) {
      CalibrationPhase.running when session != null => _RunningView(
        controller: c,
        session: session,
      ),
      CalibrationPhase.finished when result != null => _ResultView(
        result: result,
      ),
      CalibrationPhase.finished ||
      CalibrationPhase.aborted => const _StoppedView(),
      _ => const Center(child: CircularProgressIndicator()),
    };

    return PopScope(
      canPop: !c.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAbort(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('INIT RIDE'),
          automaticallyImplyLeading: !c.running,
          actions: [
            if (c.running)
              TextButton.icon(
                onPressed: () => _confirmAbort(context),
                icon: const Icon(Icons.close, color: AppColors.textMuted),
                label: Text('STOP', style: AppText.label(13)),
              ),
          ],
        ),
        body: GradientBackground(child: SafeArea(top: false, child: body)),
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.controller, required this.session});

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
            child: WarningBanner(
              icon: Icons.gps_off,
              text: 'GPS unavailable - riding tasks need location access.',
            ),
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
              text:
                  'Closed track or empty legal road only. You decide what '
                  'is safe - back off any time.',
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
                _TaskStatusRow(task: t, state: session.states[t]!),
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

class _TaskStatusRow extends StatelessWidget {
  const _TaskStatusRow({required this.task, required this.state});

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

class _StoppedView extends StatelessWidget {
  const _StoppedView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.flag_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'INIT RIDE STOPPED',
            textAlign: TextAlign.center,
            style: AppText.display(18),
          ),
          const SizedBox(height: 8),
          Text(
            'RideGuard needs a calibration before tracking rides.',
            textAlign: TextAlign.center,
            style: AppText.body(16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'TRY AGAIN',
            icon: Icons.refresh,
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const SafetyBriefingScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatefulWidget {
  const _ResultView({required this.result});

  final CalibrationProfile result;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<CalibrationController>().accept();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final rated = context.read<AppState>().bike?.ratedTopSpeedKmh ?? 0;
    final top = r.achievedTopSpeedKmh;
    final brake = r.brakeEvent;
    final qualityColor = r.quality >= 0.8
        ? AppColors.green
        : r.quality >= 0.5
        ? AppColors.amber
        : AppColors.red;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text('CALIBRATED', style: AppText.display(24, color: qualityColor)),
        const SizedBox(height: 6),
        Text(
          'Quality ${(r.quality * 100).toStringAsFixed(0)}%',
          style: AppText.body(17, color: qualityColor),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: r.quality,
            minHeight: 8,
            color: qualityColor,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'TOP SPEED',
          child: _kv([
            ('Reached', top == null ? '—' : '${top.toStringAsFixed(0)} km/h'),
            ('Bike rated', '${rated.toStringAsFixed(0)} km/h'),
            if (top != null && rated > 0)
              ('Of rated', '${(top / rated * 100).toStringAsFixed(0)}%'),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'BRAKING',
          child: _kv(
            brake == null
                ? [('Brake test', 'skipped')]
                : [
                    ('Stop time', '${brake.durationS.toStringAsFixed(1)} s'),
                    ('From', '${brake.startSpeedKmh.toStringAsFixed(0)} km/h'),
                    ('Distance', '${brake.distanceM.toStringAsFixed(1)} m'),
                    (
                      'Peak decel',
                      '${brake.peakDecelMps2.toStringAsFixed(1)} m/s² '
                          '(${(brake.peakDecelMps2 / 9.81).toStringAsFixed(2)} g)',
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'PHONE MOUNT',
          child: _kv([
            (
              'Phone tilt',
              '${r.params.mount.screenTiltDeg.toStringAsFixed(0)}° from flat',
            ),
            (
              'Upright normalized by',
              '${r.straightOffsetDeg.abs().toStringAsFixed(1)}°',
            ),
            ('Riding direction', r.forwardFromMotion ? 'learned' : 'guessed'),
            ('Lean scale', r.params.leanGain.toStringAsFixed(2)),
          ]),
        ),
        for (final w in r.warnings) ...[
          const SizedBox(height: 10),
          WarningBanner(text: w, icon: Icons.info_outline),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          key: const Key('save-calibration'),
          label: 'SAVE & CONTINUE',
          icon: Icons.check,
          color: AppColors.green,
          busy: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const SafetyBriefingScreen(),
            ),
          ),
          child: const Text('REDO INIT RIDE'),
        ),
      ],
    );
  }

  Widget _kv(List<(String, String)> rows) => Column(
    children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: AppText.body(15, color: AppColors.textMuted),
                ),
              ),
              Text(v, style: AppText.body(16, weight: FontWeight.bold)),
            ],
          ),
        ),
    ],
  );
}
