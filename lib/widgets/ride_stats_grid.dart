import 'package:flutter/material.dart';

import '../core/analysis/ride_analyzer.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Whole-ride numbers. Tapping a tile explains it in one line.
class RideStatsGrid extends StatelessWidget {
  const RideStatsGrid({
    super.key,
    required this.stats,
    this.showDistance = true,
  });

  final RideStats stats;

  /// Off where the distance is already shown (the summary's header line).
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        _ExplainedTile(
          label: 'TOP SPEED',
          value: stats.maxSpeedKmh.toStringAsFixed(0),
          icon: Icons.speed,
          explanation: 'Your fastest speed on this ride, in km/h, from GPS.',
        ),
        _ExplainedTile(
          label: 'MAX LEAN L',
          value: '${stats.maxLeanLeftDeg.toStringAsFixed(0)}°',
          icon: Icons.turn_left,
          color: AppColors.amber,
          explanation:
              'Your deepest lean into a left turn, above '
              '${RideAnalyzer.minLeanSpeedKmh.toStringAsFixed(0)} km/h.',
        ),
        _ExplainedTile(
          label: 'MAX LEAN R',
          value: '${stats.maxLeanRightDeg.toStringAsFixed(0)}°',
          icon: Icons.turn_right,
          color: AppColors.amber,
          explanation:
              'Your deepest lean into a right turn, above '
              '${RideAnalyzer.minLeanSpeedKmh.toStringAsFixed(0)} km/h.',
        ),
        _ExplainedTile(
          label: 'MAX STOP TIME',
          value: '${stats.maxStopTimeS.toStringAsFixed(1)}s',
          icon: Icons.stop_circle_outlined,
          color: AppColors.red,
          explanation:
              'The longest it took you to brake from 20+ km/h to a stop.',
        ),
        _ExplainedTile(
          label: 'BEST DECEL',
          value: stats.bestDecelMps2.toStringAsFixed(1),
          icon: Icons.south,
          color: AppColors.red,
          explanation:
              'Your hardest braking, in m/s². About 10 is as hard as a '
              'road bike can stop (1 g).',
        ),
        if (showDistance)
          _ExplainedTile(
            label: 'DISTANCE',
            value: formatDistance(stats.distanceM),
            icon: Icons.route,
            explanation: 'How far you have ridden on this ride.',
          )
        else
          _ExplainedTile(
            label: 'STOPS',
            value: '${stats.brakeEvents}',
            icon: Icons.front_hand_outlined,
            explanation: 'How many times you braked from 20+ km/h to a stop.',
          ),
      ],
    );
  }
}

class _ExplainedTile extends StatelessWidget {
  const _ExplainedTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.explanation,
    this.color = AppColors.cyan,
  });

  final String label;
  final String value;
  final IconData icon;
  final String explanation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('stat-$label'),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(label, style: AppText.display(15, color: color)),
          content: Text(explanation, style: AppText.body(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
      child: StatTile(label: label, value: value, icon: icon, color: color),
    );
  }
}
