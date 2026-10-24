import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/emergency_platform.dart';
import '../../services/ride_controller.dart';
import '../../services/safety_controller.dart';
import '../../services/sensor_feed.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/gauges.dart';
import '../../widgets/safety_overlay.dart';
import '../ride_summary_screen.dart';
import 'hold_to_stop_button.dart';
import 'ride_header.dart';
import 'speed_chart.dart';
import 'window_card.dart';

class RideScreen extends StatelessWidget {
  const RideScreen({super.key});

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
          create: (context) => RideController(
            app: context.read<AppState>(),
            feed: SensorFeed(context.read<SensorSource>()),
            safety: context.read<SafetyController>(),
          )..start(),
        ),
      ],
      child: const _RideView(),
    );
  }
}

class _RideView extends StatefulWidget {
  const _RideView();

  @override
  State<_RideView> createState() => _RideViewState();
}

class _RideViewState extends State<_RideView> {
  bool _stopping = false;

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    final summary = await context.read<RideController>().stop();
    if (!mounted) return;
    final incidents = context.read<SafetyController>().incidents;
    if (summary == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            RideSummaryScreen(summary: summary, incidents: incidents),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RideController>();
    final app = context.watch<AppState>();
    final bike = app.bike!;
    final s = c.state;
    final window = c.window;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Back must not end the ride (and cancel the crash call) while the
        // crash alert is up.
        final alerting =
            context.read<SafetyController>().phase != SafetyPhase.idle;
        if (!didPop && !alerting) _stop();
      },
      child: SafetyLayer(
        child: Scaffold(
          body: GradientBackground(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  RideHeader(elapsed: c.elapsed),
                  if (app.emergencyContact == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: WarningBanner(
                        icon: Icons.contact_phone_outlined,
                        text:
                            'No emergency contact: a crash will sound the '
                            'alarm but call no one. Add one in Settings.',
                      ),
                    ),
                  if (!c.gpsAvailable)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: WarningBanner(
                        icon: Icons.gps_off,
                        text:
                            'GPS unavailable - speed, distance and stop '
                            'times are paused. Lean still works.',
                      ),
                    ),
                  if (c.sensorError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: WarningBanner(
                        color: AppColors.red,
                        text: c.sensorError!,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: SpeedGauge(
                      speedKmh: s?.speedKmh ?? 0,
                      scaleMaxKmh: bike.ratedTopSpeedKmh,
                      maxSpeedKmh: c.totals.maxSpeedKmh,
                      reliable: s?.speedReliable ?? false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: LeanGauge(
                      leanDeg: s?.leanDeg ?? 0,
                      maxLeftDeg: window.maxLeanLeftDeg,
                      maxRightDeg: window.maxLeanRightDeg,
                    ),
                  ),
                  if ((s?.straightOffsetDeg.abs() ?? 0) >= 1 ||
                      (s?.mountRealignments ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Mount normalized by '
                        '${s!.straightOffsetDeg.abs().toStringAsFixed(1)}°'
                        '${s.mountRealignments > 0 ? ' · re-aligned ${s.mountRealignments}×' : ''}',
                        textAlign: TextAlign.center,
                        style: AppText.body(13, color: AppColors.textFaint),
                      ),
                    ),
                  const SizedBox(height: 16),
                  WindowCard(controller: c, window: window),
                  const SizedBox(height: 12),
                  SizedBox(height: 170, child: SpeedChart(samples: c.chart)),
                  const SizedBox(height: 20),
                  HoldToStopButton(onStop: _stop, busy: _stopping),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
