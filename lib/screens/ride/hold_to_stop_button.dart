import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Stopping needs a deliberate long press so a glove brush can't end the
/// recording.
class HoldToStopButton extends StatelessWidget {
  const HoldToStopButton({super.key, required this.onStop, required this.busy});

  final VoidCallback onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('stop-ride'),
      onLongPress: busy ? null : onStop,
      onTap: busy
          ? null
          : () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Hold the button to stop the ride'),
                ),
              ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.red, AppColors.redDeep],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
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
              'HOLD TO STOP',
              style: AppText.display(16).copyWith(letterSpacing: 3),
            ),
          ],
        ),
      ),
    );
  }
}
