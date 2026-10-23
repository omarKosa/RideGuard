import 'package:flutter/material.dart';

import '../core/calibration/calibration_session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'calibration_screen.dart';

/// Explains the init ride and makes the rider acknowledge the risks before
/// the top-speed task.
class SafetyBriefingScreen extends StatefulWidget {
  const SafetyBriefingScreen({super.key});

  static const acknowledgements = [
    'I will do the top-speed and braking tasks only on a closed track or an '
        'empty road where that speed is legal.',
    'I am wearing full protective gear (helmet, jacket, gloves, boots).',
    'My phone is firmly mounted and I will not touch it while moving. The '
        'app advances on its own and vibrates at each new task.',
    'I decide what is safe. I can skip any task, and I will back off if '
        'conditions are not right.',
  ];

  @override
  State<SafetyBriefingScreen> createState() => _SafetyBriefingScreenState();
}

class _SafetyBriefingScreenState extends State<SafetyBriefingScreen> {
  final _checked = List<bool>.filled(
    SafetyBriefingScreen.acknowledgements.length,
    false,
  );

  bool get _allChecked => _checked.every((c) => c);

  void _start() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CalibrationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('INIT RIDE')),
      body: GradientBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const WarningBanner(
                  icon: Icons.health_and_safety_outlined,
                  color: AppColors.red,
                  text:
                      'This calibration ride asks you to reach your top speed '
                      'and brake hard. Riding fast is dangerous. Obey the law '
                      'and ride within your limits.',
                ),
                const SizedBox(height: 20),
                Text('WHAT YOU WILL DO', style: AppText.label(12)),
                const SizedBox(height: 10),
                for (final (i, task) in CalibrationTask.values.indexed)
                  _TaskRow(index: i + 1, task: task),
                const SizedBox(height: 8),
                Text(
                  'Mount the phone exactly how you will ride with it - any '
                  'angle works. The app learns how it sits and normalizes the '
                  'lean reading so upright reads 0°.',
                  style: AppText.body(14, color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                Text('BEFORE YOU GO', style: AppText.label(12)),
                const SizedBox(height: 4),
                for (final (i, text)
                    in SafetyBriefingScreen.acknowledgements.indexed)
                  CheckboxListTile(
                    key: Key('ack-$i'),
                    value: _checked[i],
                    onChanged: (v) => setState(() => _checked[i] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.red,
                    title: Text(text, style: AppText.body(15)),
                  ),
                const SizedBox(height: 16),
                PrimaryButton(
                  key: const Key('start-calibration'),
                  label: 'START INIT RIDE',
                  icon: Icons.flag_outlined,
                  onPressed: _allChecked ? _start : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.index, required this.task});

  final int index;
  final CalibrationTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
            child: Text(
              '$index',
              style: AppText.body(
                13,
                color: AppColors.cyan,
                weight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title.toUpperCase(),
                  style: AppText.label(13, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  task.instruction,
                  style: AppText.body(14, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
