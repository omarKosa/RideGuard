import 'package:flutter/material.dart';

import '../core/analysis/ride_analyzer.dart';
import '../models/incident.dart';
import '../models/ride_summary.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/safety_overlay.dart';

class RideSummaryScreen extends StatelessWidget {
  const RideSummaryScreen({
    super.key,
    required this.summary,
    this.incidents = const [],
  });

  final RideSummary summary;

  /// Hazards detected on this ride.
  final List<Incident> incidents;

  @override
  Widget build(BuildContext context) {
    final t = summary.totals;
    return Scaffold(
      appBar: AppBar(title: const Text('RIDE SUMMARY')),
      body: GradientBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(
                '${formatDuration(summary.duration)} · '
                '${formatDistance(t.distanceM)} · '
                'avg ${t.avgMovingSpeedKmh.toStringAsFixed(0)} km/h',
                style: AppText.body(16, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              _StatsCard(title: 'WHOLE RIDE', stats: t),
              const SizedBox(height: 12),
              _StatsCard(
                title: 'LAST ${summary.windowMinutes} MIN',
                stats: summary.window,
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'STOPS (${summary.brakeEvents.length})',
                child: summary.brakeEvents.isEmpty
                    ? Text(
                        'No stops from 20+ km/h recorded.',
                        style: AppText.body(15, color: AppColors.textMuted),
                      )
                    : Column(
                        children: [
                          for (final e in summary.brakeEvents.reversed.take(20))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e.startSpeedKmh.toStringAsFixed(0)} km/h → 0',
                                      style: AppText.body(15),
                                    ),
                                  ),
                                  Text(
                                    '${e.durationS.toStringAsFixed(1)} s · '
                                    '${e.distanceM.toStringAsFixed(0)} m · '
                                    '${e.peakDecelMps2.toStringAsFixed(1)} m/s²',
                                    style: AppText.body(
                                      14,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (incidents.isNotEmpty) ...[
                const SizedBox(height: 12),
                _IncidentsCard(incidents: incidents),
              ],
              if (summary.mountRealignments > 0) ...[
                const SizedBox(height: 12),
                WarningBanner(
                  icon: Icons.screen_rotation_alt,
                  text:
                      'The phone moved in its mount '
                      '${summary.mountRealignments}× during the ride; lean '
                      'was re-normalized automatically. Tighten the holder.',
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'DONE',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.stats});

  final String title;
  final RideStats stats;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: [
          StatTile(
            label: 'TOP SPEED',
            value: stats.maxSpeedKmh.toStringAsFixed(0),
            icon: Icons.speed,
          ),
          StatTile(
            label: 'MAX LEAN L',
            value: '${stats.maxLeanLeftDeg.toStringAsFixed(0)}°',
            icon: Icons.turn_left,
            color: AppColors.amber,
          ),
          StatTile(
            label: 'MAX LEAN R',
            value: '${stats.maxLeanRightDeg.toStringAsFixed(0)}°',
            icon: Icons.turn_right,
            color: AppColors.amber,
          ),
          StatTile(
            label: 'MAX STOP TIME',
            value: '${stats.maxStopTimeS.toStringAsFixed(1)}s',
            icon: Icons.stop_circle_outlined,
            color: AppColors.red,
          ),
          StatTile(
            label: 'BEST DECEL',
            value: stats.bestDecelMps2.toStringAsFixed(1),
            icon: Icons.south,
            color: AppColors.red,
          ),
          StatTile(
            label: 'STOPS',
            value: '${stats.brakeEvents}',
            icon: Icons.front_hand_outlined,
          ),
        ],
      ),
    );
  }
}

/// What was detected on the ride, and what the rider said about each alert
/// on the cards after it.
class _IncidentsCard extends StatelessWidget {
  const _IncidentsCard({required this.incidents});

  final List<Incident> incidents;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'SAFETY ALERTS (${incidents.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final incident in incidents)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(
                    incident.kind.critical
                        ? Icons.car_crash
                        : Icons.report_problem,
                    color: incident.kind.critical
                        ? AppColors.red
                        : AppColors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      incident.kind.critical
                          ? 'Crash at '
                                '${incident.speedKmh.toStringAsFixed(0)} km/h '
                                '- ${crashOutcomeText(incident.outcome)}'
                          : describeWarning(incident).split('. ').first,
                      style: AppText.body(15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(switch (incident.riderLabel) {
                    RiderLabel.yes => 'You said: it happened',
                    RiderLabel.no => 'You said: not real',
                    null => 'No answer',
                  }, style: AppText.body(13, color: AppColors.textMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
