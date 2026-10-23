import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/safety/safety_baseline.dart';
import '../core/safety/safety_monitor.dart';
import '../core/safety/safety_tuning.dart';
import '../models/incident.dart';
import '../services/safety_controller.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Puts the crash alert over [child] and warnings on top of it, driven by
/// the [SafetyController] above it.
class SafetyLayer extends StatelessWidget {
  const SafetyLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final safety = context.watch<SafetyController>();
    final warning = safety.warning;
    return Stack(
      children: [
        child,
        if (warning != null && safety.phase == SafetyPhase.idle)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Material(
              color: Colors.transparent,
              child: WarningBanner(
                key: const Key('hazard-warning'),
                icon: Icons.report_problem,
                color: AppColors.amber,
                text: describeWarning(warning),
              ),
            ),
          ),
        if (safety.phase != SafetyPhase.idle)
          Positioned.fill(child: _CrashAlert(safety: safety)),
      ],
    );
  }
}

String describeWarning(Incident i) {
  final speed = '${i.speedKmh.toStringAsFixed(0)} km/h';
  return switch (i.kind) {
    HazardKind.wobble =>
      'Speed wobble at $speed '
          '(${i.wobbleHz?.toStringAsFixed(1) ?? '?'} Hz). Ease off the '
          'throttle smoothly, keep a light grip on the bars.',
    HazardKind.impact =>
      'Hard impact (${i.peakAccelG?.toStringAsFixed(1) ?? '?'} g) at '
          '$speed. Check tyres and wheels when safe.',
    HazardKind.extremeLean =>
      'Extreme lean (${i.leanDeg.abs().toStringAsFixed(0)}°) at $speed. '
          'You are near the limit of grip.',
    HazardKind.crash => 'Crash detected.',
  };
}

class _CrashAlert extends StatelessWidget {
  const _CrashAlert({required this.safety});

  final SafetyController safety;

  @override
  Widget build(BuildContext context) {
    final contact = safety.contact;
    final outcome = safety.crash?.outcome;
    final (String title, String detail) = switch (safety.phase) {
      SafetyPhase.countdown => (
        '${safety.secondsLeft}',
        contact == null
            ? 'No emergency contact set. The alarm keeps sounding.'
            : 'Calling ${contact.name} in ${safety.secondsLeft} s',
      ),
      SafetyPhase.called => (
        'CALLED',
        outcome == IncidentOutcome.dialerOpened
            ? 'Dialer opened for ${contact?.name ?? 'your contact'} - '
                  'no permission to call directly.'
            : 'Called ${contact?.name ?? 'your contact'}.',
      ),
      _ => (
        'ALARM',
        outcome == IncidentOutcome.callFailed
            ? 'The call to ${contact?.name ?? 'your contact'} failed.'
            : 'No emergency contact set.',
      ),
    };

    return Material(
      key: const Key('crash-alert'),
      color: AppColors.redDeep,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.car_crash, color: Colors.white, size: 72),
              const SizedBox(height: 12),
              Text(
                'CRASH DETECTED',
                textAlign: TextAlign.center,
                style: AppText.display(26).copyWith(letterSpacing: 2),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppText.display(72),
              ),
              const SizedBox(height: 12),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppText.body(20, weight: FontWeight.w700),
              ),
              const Spacer(),
              _HoldButton(
                label: safety.phase == SafetyPhase.countdown
                    ? "HOLD - I'M OK"
                    : 'HOLD TO DISMISS',
                onHold: safety.dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Needs a deliberate press: rain or debris on a fallen phone's screen can
/// register as taps.
class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.label, required this.onHold});

  final String label;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('dismiss-crash'),
      onLongPress: onHold,
      child: Container(
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppText.display(
            22,
            color: AppColors.redDeep,
          ).copyWith(letterSpacing: 2),
        ),
      ),
    );
  }
}

/// How sensitive detection currently is on this mount, and why.
class SafetyLearningSummary extends StatelessWidget {
  const SafetyLearningSummary({
    super.key,
    required this.baseline,
    this.showWarnings = true,
  });

  final SafetyBaseline? baseline;

  /// Off where the warnings are already listed elsewhere.
  final bool showWarnings;

  @override
  Widget build(BuildContext context) {
    final b = baseline;
    final tuning = b?.tuning ?? SafetyTuning.defaults;
    final learned = b?.ridingSeconds ?? 0;
    String level(double value, double def, double max) => value <= def
        ? 'default'
        : value >= max
        ? 'least sensitive'
        : '+${((value / def - 1) * 100).toStringAsFixed(0)}%';

    final rows = <(String, String)>[
      (
        'Learned from',
        learned < SafetyBaseline.minRidingSeconds
            ? 'not enough riding yet'
            : '${(learned / 60).toStringAsFixed(0)} min of riding'
                  '${b!.rides > 1 ? ' (${b.rides} rides)' : ''}',
      ),
      (
        'Wobble threshold',
        tuning.wobbleDetectable
            ? '${tuning.wobbleMinRms.toStringAsFixed(2)} rad/s '
                  '(${level(tuning.wobbleMinRms, SafetyTuning.defaultWobbleRms, SafetyTuning.maxWobbleRms)})'
            : 'off - phone too slow',
      ),
      (
        'Impact threshold',
        '${tuning.impactG.toStringAsFixed(1)} g '
            '(${level(tuning.impactG, SafetyTuning.defaultImpactG, SafetyTuning.maxImpactG)})',
      ),
      ('Extreme lean', '${tuning.extremeLeanDeg.toStringAsFixed(0)}°'),
      if (b?.imuHz != null) ('Motion data', '${b!.imuHz!.round()} Hz'),
      if ((b?.falseAlarms ?? 0) > 0) ('Marked not real', '${b!.falseAlarms}'),
      if ((b?.cancelledCrashes ?? 0) > 0)
        ('Crash alarms cancelled', '${b!.cancelledCrashes}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    k,
                    style: AppText.body(15, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    v,
                    textAlign: TextAlign.end,
                    style: AppText.body(15, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        if (showWarnings)
          for (final w in tuning.warnings) ...[
            const SizedBox(height: 8),
            WarningBanner(text: w, icon: Icons.vibration),
          ],
      ],
    );
  }
}
