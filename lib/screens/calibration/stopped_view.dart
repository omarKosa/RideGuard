import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../safety_briefing_screen.dart';

class StoppedView extends StatelessWidget {
  const StoppedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.flag_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'INIT RIDE STOPPED',
            textAlign: TextAlign.center,
            style: AppText.display(18),
          ),
          const SizedBox(height: 8),
          Text(
            'RideGuard needs a calibration before tracking rides.',
            textAlign: TextAlign.center,
            style: AppText.body(16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'TRY AGAIN',
            icon: Icons.refresh,
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const SafetyBriefingScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
