import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../core/analysis/ride_analyzer.dart';
import '../models/ride_sample.dart';
import '../services/app_state.dart';
import '../services/emergency_platform.dart';
import '../services/ride_controller.dart';
import '../services/safety_controller.dart';
import '../services/sensor_feed.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/gauges.dart';
import '../widgets/safety_overlay.dart';
import '../widgets/sync_indicator.dart';
import 'ride_summary_screen.dart';

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
                  _Header(elapsed: c.elapsed),
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
                  _WindowCard(controller: c, window: window),
                  const SizedBox(height: 12),
                  SizedBox(height: 170, child: _SpeedChart(samples: c.chart)),
                  const SizedBox(height: 20),
                  _HoldToStopButton(onStop: _stop, busy: _stopping),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.red,
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'RIDING',
            style: AppText.display(
              14,
              color: AppColors.red,
            ).copyWith(letterSpacing: 2),
          ),
        ),
        const SyncIndicator(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer, color: AppColors.cyan, size: 16),
              const SizedBox(width: 6),
              Text(formatDuration(elapsed), style: AppText.display(15)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Analysis over the rolling "last N minutes" buffer.
class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.controller, required this.window});

  final RideController controller;
  final RideStats window;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'LAST ${AppConfig.analysisWindowMinutes} MIN',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              StatTile(
                label: 'TOP SPEED',
                value: window.maxSpeedKmh.toStringAsFixed(0),
                icon: Icons.speed,
              ),
              StatTile(
                label: 'MAX LEAN L',
                value: '${window.maxLeanLeftDeg.toStringAsFixed(0)}°',
                icon: Icons.turn_left,
                color: AppColors.amber,
              ),
              StatTile(
                label: 'MAX LEAN R',
                value: '${window.maxLeanRightDeg.toStringAsFixed(0)}°',
                icon: Icons.turn_right,
                color: AppColors.amber,
              ),
              StatTile(
                label: 'MAX STOP TIME',
                value: '${window.maxStopTimeS.toStringAsFixed(1)}s',
                icon: Icons.stop_circle_outlined,
                color: AppColors.red,
              ),
              StatTile(
                label: 'BEST DECEL',
                value: window.bestDecelMps2.toStringAsFixed(1),
                icon: Icons.south,
                color: AppColors.red,
              ),
              StatTile(
                label: 'DISTANCE',
                value: formatDistance(window.distanceM),
                icon: Icons.route,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Stop from here: ~${controller.estimatedStopTimeS.toStringAsFixed(1)} s'
                  ' (your measured braking)',
                  style: AppText.body(14, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (controller.lastBrake != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.history, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last stop: ${controller.lastBrake!.startSpeedKmh.toStringAsFixed(0)} km/h '
                    'in ${controller.lastBrake!.durationS.toStringAsFixed(1)} s, '
                    '${controller.lastBrake!.distanceM.toStringAsFixed(0)} m',
                    style: AppText.body(14, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SpeedChart extends StatelessWidget {
  const _SpeedChart({required this.samples});

  final List<RideSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return SectionCard(
        title: 'SPEED & LEAN',
        child: Center(
          child: Text(
            'Collecting data...',
            style: AppText.body(14, color: AppColors.textFaint),
          ),
        ),
      );
    }
    final t0 = samples.first.time;
    double x(RideSample s) => s.time.difference(t0).inMilliseconds / 1000;
    // Thin out to ~1 point per second; the chart does not need 10 Hz.
    final step = math.max(1, samples.length ~/ 120);
    final pts = [for (var i = 0; i < samples.length; i += step) samples[i]];
    final top = pts.map((s) => s.speedKmh).fold<double>(0, math.max);
    final maxY = math.max(60.0, (top / 50).ceil() * 50.0);
    // Lean is drawn on the same axis: 0..maxY maps to -60..+60°.
    double leanY(double deg) => maxY / 2 + deg.clamp(-60, 60) / 60 * maxY / 2;

    return SectionCard(
      title: 'SPEED & LEAN · LAST 2 MIN',
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Expanded(
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: 0,
            maxX: x(pts.last),
            minY: 0,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: maxY / 4,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: AppText.body(10, color: AppColors.textFaint),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final s in pts) FlSpot(x(s), s.speedKmh)],
                isCurved: true,
                color: AppColors.cyan,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.cyan.withValues(alpha: 0.12),
                ),
              ),
              LineChartBarData(
                spots: [for (final s in pts) FlSpot(x(s), leanY(s.leanDeg))],
                isCurved: true,
                color: AppColors.amber,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stopping needs a deliberate long press so a glove brush can't end the
/// recording.
class _HoldToStopButton extends StatelessWidget {
  const _HoldToStopButton({required this.onStop, required this.busy});

  final VoidCallback onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('stop-ride'),
      onLongPress: busy ? null : onStop,
      onTap: busy
          ? null
          : () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Hold the button to stop the ride'),
                ),
              ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.red, AppColors.redDeep],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.stop, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              'HOLD TO STOP',
              style: AppText.display(16).copyWith(letterSpacing: 3),
            ),
          ],
        ),
      ),
    );
  }
}
