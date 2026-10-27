import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The init ride's safety warning and the rider's acknowledgements, shown
/// only when they tap START INIT RIDE.
class InitRideWarningDialog extends StatefulWidget {
  const InitRideWarningDialog({super.key});

  static const warning =
      'This calibration ride asks you to reach your top speed and brake '
      'hard. Riding fast is dangerous. Obey the law and ride within your '
      'limits.';

  static const acknowledgements = [
    'I will do the top-speed and braking tasks only on a closed track or an '
        'empty road where that speed is legal.',
    'I am wearing full protective gear (helmet, jacket, gloves, boots).',
    'My phone is firmly mounted and I will not touch it while moving. The '
        'app advances on its own and vibrates at each new task.',
    'I decide what is safe. I can skip any task, and I will back off if '
        'conditions are not right.',
  ];

  /// True when the rider ticked every box and chose START.
  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => const InitRideWarningDialog(),
      ) ??
      false;

  @override
  State<InitRideWarningDialog> createState() => _InitRideWarningDialogState();
}

class _InitRideWarningDialogState extends State<InitRideWarningDialog> {
  final _checked = List<bool>.filled(
    InitRideWarningDialog.acknowledgements.length,
    false,
  );

  bool get _allChecked => _checked.every((c) => c);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('init-ride-warning'),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      icon: const Icon(
        Icons.health_and_safety_outlined,
        color: AppColors.amber,
        size: 36,
      ),
      title: Text('BEFORE YOU START', style: AppText.display(17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              InitRideWarningDialog.warning,
              style: AppText.body(15, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            for (final (i, text)
                in InitRideWarningDialog.acknowledgements.indexed)
              CheckboxListTile(
                key: Key('ack-$i'),
                value: _checked[i],
                onChanged: (v) => setState(() => _checked[i] = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.red,
                title: Text(text, style: AppText.body(15)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel-init-ride'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const Key('confirm-init-ride'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: _allChecked ? () => Navigator.of(context).pop(true) : null,
          child: const Text('START'),
        ),
      ],
    );
  }
}
