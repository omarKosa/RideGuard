import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Ends the ride on a single tap.
class StopButton extends StatelessWidget {
  const StopButton({super.key, required this.onStop, required this.busy});

  final VoidCallback onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('stop-ride'),
      onTap: busy ? null : onStop,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.red, AppColors.redDeep],
          ),
          borderRadius: BorderRadius.circular(16),
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
              'STOP RIDE',
              style: AppText.display(16).copyWith(letterSpacing: 3),
            ),
          ],
        ),
      ),
    );
  }
}
