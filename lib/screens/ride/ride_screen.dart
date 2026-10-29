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
import '../alert_review_screen.dart';
import '../ride_summary_screen.dart';
import '../settings/emergency_contact_screen.dart';
import 'ride_header.dart';
import 'ride_stats_card.dart';
import 'speed_chart.dart';
import 'stop_button.dart';

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
    final navigator = Navigator.of(context);
    if (summary == null) {
      navigator.pop();
      return;
    }
    // The safety controller has ended: nothing re-uploads these incidents
    // after the rider labels them.
    final incidents = await reviewAlerts(
      navigator,
      context.read<SafetyController>().incidents,
      context.read<AppState>().labelIncident,
    );
    if (!mounted) return;
    navigator.pushReplacement(
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
    final totals = c.totals;

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
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: WarningBanner(
                        key: const Key('no-contact-banner'),
                        icon: Icons.contact_phone_outlined,
                        text: 'No emergency contact',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const EmergencyContactScreen(),
                          ),
                        ),
                      ),
                    ),
                  if (!c.gpsAvailable)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: WarningBanner(
                        icon: Icons.gps_off,
                        text: 'GPS unavailable',
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
                      maxLeftDeg: totals.maxLeanLeftDeg,
                      maxRightDeg: totals.maxLeanRightDeg,
                    ),
                  ),
                  const SizedBox(height: 16),
                  RideStatsCard(controller: c, totals: totals),
                  const SizedBox(height: 12),
                  SizedBox(height: 170, child: SpeedChart(samples: c.chart)),
                  const SizedBox(height: 20),
                  StopButton(onStop: _stop, busy: _stopping),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
