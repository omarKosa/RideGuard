import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analysis/ride_analyzer.dart';
import '../models/incident.dart';
import '../models/ride_summary.dart';
import '../services/app_state.dart';
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

/// What was detected on the ride. Warnings the rider marks as not real
/// make detection on this mount slightly less sensitive.
class _IncidentsCard extends StatefulWidget {
  const _IncidentsCard({required this.incidents});

  final List<Incident> incidents;

  @override
  State<_IncidentsCard> createState() => _IncidentsCardState();
}

class _IncidentsCardState extends State<_IncidentsCard> {
  late final List<Incident> _incidents = List.of(widget.incidents);

  Future<void> _markFalse(int i) async {
    final marked = await context.read<AppState>().markFalseAlarm(_incidents[i]);
    if (mounted) setState(() => _incidents[i] = marked);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'SAFETY ALERTS (${_incidents.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mark warnings that were not real; the app learns from it. '
            'Crashes are never loosened this way.',
            style: AppText.body(13, color: AppColors.textMuted),
          ),
          for (final (i, incident) in _incidents.indexed)
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
                                '- ${_outcomeText(incident.outcome)}'
                          : describeWarning(incident).split('. ').first,
                      style: AppText.body(15),
                    ),
                  ),
                  if (!incident.kind.critical)
                    incident.falseAlarm
                        ? Text(
                            'NOT REAL',
                            style: AppText.label(
                              12,
                              color: AppColors.textFaint,
                            ),
                          )
                        : TextButton(
                            key: Key('false-alarm-$i'),
                            onPressed: () => _markFalse(i),
                            child: const Text('NOT REAL'),
                          ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _outcomeText(IncidentOutcome o) => switch (o) {
    IncidentOutcome.cancelled => 'you cancelled',
    IncidentOutcome.called => 'contact called',
    IncidentOutcome.dialerOpened => 'dialer opened',
    IncidentOutcome.callFailed => 'call failed',
    IncidentOutcome.noContact => 'no contact set',
    IncidentOutcome.pending || IncidentOutcome.warned => 'pending',
  };
}
