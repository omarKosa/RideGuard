import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calibration_profile.dart';
import '../../services/app_state.dart';
import '../../services/calibration_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/key_value_rows.dart';
import '../../widgets/safety_overlay.dart';
import '../home_screen.dart';
import '../safety_briefing_screen.dart';

class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.result});

  final CalibrationProfile result;

  @override
  State<ResultView> createState() => ResultViewState();
}

class ResultViewState extends State<ResultView> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<CalibrationController>().accept();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final rated = context.read<AppState>().bike?.ratedTopSpeedKmh ?? 0;
    final top = r.achievedTopSpeedKmh;
    final brake = r.brakeEvent;
    final qualityColor = r.quality >= 0.8
        ? AppColors.green
        : r.quality >= 0.5
        ? AppColors.amber
        : AppColors.red;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text('CALIBRATED', style: AppText.display(24, color: qualityColor)),
        const SizedBox(height: 6),
        Text(
          'Quality ${(r.quality * 100).toStringAsFixed(0)}%',
          style: AppText.body(17, color: qualityColor),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: r.quality,
            minHeight: 8,
            color: qualityColor,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'TOP SPEED',
          child: KeyValueRows(
            rows: [
              ('Reached', top == null ? '—' : '${top.toStringAsFixed(0)} km/h'),
              ('Bike rated', '${rated.toStringAsFixed(0)} km/h'),
              if (top != null && rated > 0)
                ('Of rated', '${(top / rated * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'BRAKING',
          child: KeyValueRows(
            rows: brake == null
                ? [('Brake test', 'skipped')]
                : [
                    ('Stop time', '${brake.durationS.toStringAsFixed(1)} s'),
                    ('From', '${brake.startSpeedKmh.toStringAsFixed(0)} km/h'),
                    ('Distance', '${brake.distanceM.toStringAsFixed(1)} m'),
                    (
                      'Peak decel',
                      '${brake.peakDecelMps2.toStringAsFixed(1)} m/s² '
                          '(${(brake.peakDecelMps2 / 9.81).toStringAsFixed(2)} g)',
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'PHONE MOUNT',
          child: KeyValueRows(
            rows: [
              (
                'Phone tilt',
                '${r.params.mount.screenTiltDeg.toStringAsFixed(0)}° from flat',
              ),
              (
                'Upright normalized by',
                '${r.straightOffsetDeg.abs().toStringAsFixed(1)}°',
              ),
              ('Riding direction', r.forwardFromMotion ? 'learned' : 'guessed'),
              ('Lean scale', r.params.leanGain.toStringAsFixed(2)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'SAFETY ALERTS',
          child: SafetyLearningSummary(
            baseline: context.read<CalibrationController>().safetyBaseline,
            // They are part of the calibration warnings below.
            showWarnings: false,
          ),
        ),
        for (final w in r.warnings) ...[
          const SizedBox(height: 10),
          WarningBanner(text: w, icon: Icons.info_outline),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          key: const Key('save-calibration'),
          label: 'SAVE & CONTINUE',
          icon: Icons.check,
          color: AppColors.green,
          busy: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const SafetyBriefingScreen(),
            ),
          ),
          child: const Text('REDO INIT RIDE'),
        ),
      ],
    );
  }
}
