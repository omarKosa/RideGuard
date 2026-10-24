import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sync_indicator.dart';

class RideHeader extends StatelessWidget {
  const RideHeader({super.key, required this.elapsed});

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
