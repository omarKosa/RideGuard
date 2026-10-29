import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../models/ride_summary.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ride_stats_grid.dart';
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
              SectionCard(
                title: 'WHOLE RIDE',
                child: RideStatsGrid(stats: t, showDistance: false),
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
                      'Phone moved in its mount ${summary.mountRealignments}×. '
                      'Tighten the holder.',
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
