import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/analysis/ride_analyzer.dart';
import '../../services/ride_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Analysis over the rolling "last N minutes" buffer.
class WindowCard extends StatelessWidget {
  const WindowCard({super.key, required this.controller, required this.window});

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
