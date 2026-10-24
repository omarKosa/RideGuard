import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/calibration_controller.dart';
import '../../services/emergency_platform.dart';
import '../../services/safety_controller.dart';
import '../../services/sensor_feed.dart';
import '../../theme/app_theme.dart';
import '../../widgets/alert_review.dart';
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
      child: const CalibrationView(),
    );
  }
}

/// The init ride's screens, driven by the [CalibrationController] and
/// [SafetyController] above it: tasks, then any alert cards, then the
/// result.
class CalibrationView extends StatefulWidget {
  const CalibrationView({super.key});

  @override
  State<CalibrationView> createState() => _CalibrationViewState();
}

class _CalibrationViewState extends State<CalibrationView> {
  final _review = GlobalKey<AlertReviewState>();

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
    // Alerts from the init ride are asked about before the result.
    final reviewing =
        c.phase == CalibrationPhase.finished &&
        !c.alertsReviewed &&
        c.incidents.isNotEmpty;

    final Widget body = switch (c.phase) {
      CalibrationPhase.running when session != null => RunningView(
        controller: c,
        session: session,
      ),
      _ when reviewing => AlertReview(
        key: _review,
        incidents: c.incidents,
        onLabel: c.labelIncident,
        onDone: c.finishReview,
      ),
      CalibrationPhase.finished when result != null => ResultView(
        result: result,
      ),
      CalibrationPhase.finished ||
      CalibrationPhase.aborted => const StoppedView(),
      _ => const Center(child: CircularProgressIndicator()),
    };

    return PopScope(
      canPop: !c.running && !reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back on the cards is SKIP.
        if (reviewing) return _review.currentState?.skip();
        final alerting =
            context.read<SafetyController>().phase != SafetyPhase.idle;
        if (!alerting) _confirmAbort(context);
      },
      child: SafetyLayer(
        child: Scaffold(
          appBar: reviewing
              ? null
              : AppBar(
                  title: const Text('INIT RIDE'),
                  automaticallyImplyLeading: !c.running,
                  actions: [
                    if (c.running)
                      TextButton.icon(
                        onPressed: () => _confirmAbort(context),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textMuted,
                        ),
                        label: Text('STOP', style: AppText.label(13)),
                      ),
                  ],
                ),
          body: GradientBackground(
            child: SafeArea(top: reviewing, child: body),
          ),
        ),
      ),
    );
  }
}
