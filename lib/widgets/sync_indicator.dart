import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sync_service.dart';
import '../theme/app_theme.dart';

/// Cloud icon showing whether ride data has reached the backend.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final pending = sync.pending;
    final (icon, color, tip) = switch (sync.online) {
      false => (
        Icons.cloud_off,
        AppColors.amber,
        'Offline - $pending uploads queued',
      ),
      _ when pending > 0 => (
        Icons.cloud_upload_outlined,
        AppColors.cyan,
        '$pending uploads queued',
      ),
      _ => (Icons.cloud_done_outlined, AppColors.green, 'All data synced'),
    };
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            if (pending > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$pending',
                style: AppText.body(13, color: color, weight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
