import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/calibration_controller.dart';
import '../../services/emergency_platform.dart';
import '../../services/safety_controller.dart';
import '../../services/sensor_feed.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/safety_overlay.dart';
import 'result_view.dart';
import 'running_view.dart';
import 'stopped_view.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => SafetyController(
            app: context.read<AppState>(),
            platform: context.read<EmergencyPlatform>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => CalibrationController(
            app: context.read<AppState>(),
            feed: SensorFeed(context.read<SensorSource>()),
            safety: context.read<SafetyController>(),
          )..start(),
        ),
      ],
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
      CalibrationPhase.running when session != null => RunningView(
        controller: c,
        session: session,
      ),
      CalibrationPhase.finished when result != null => ResultView(
        result: result,
      ),
      CalibrationPhase.finished ||
      CalibrationPhase.aborted => const StoppedView(),
      _ => const Center(child: CircularProgressIndicator()),
    };

    return PopScope(
      canPop: !c.running,
      onPopInvokedWithResult: (didPop, _) {
        final alerting =
            context.read<SafetyController>().phase != SafetyPhase.idle;
        if (!didPop && !alerting) _confirmAbort(context);
      },
      child: SafetyLayer(
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
      ),
    );
  }
}
