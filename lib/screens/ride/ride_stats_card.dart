import 'package:flutter/material.dart';

import '../../core/analysis/ride_analyzer.dart';
import '../../services/ride_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/ride_stats_grid.dart';

/// The ride so far; tap a number for what it means.
class RideStatsCard extends StatelessWidget {
  const RideStatsCard({
    super.key,
    required this.controller,
    required this.totals,
  });

  final RideController controller;
  final RideStats totals;

  @override
  Widget build(BuildContext context) {
    final last = controller.lastBrake;
    return SectionCard(
      title: 'THIS RIDE',
      child: Column(
        children: [
          RideStatsGrid(stats: totals),
          if (last != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.history, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last stop: ${last.startSpeedKmh.toStringAsFixed(0)} km/h '
                    'in ${last.durationS.toStringAsFixed(1)} s',
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
