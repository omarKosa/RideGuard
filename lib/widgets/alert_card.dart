import 'package:flutter/material.dart';

import '../core/safety/safety_monitor.dart';
import '../models/incident.dart';
import '../theme/app_theme.dart';
import 'safety_overlay.dart';

/// One alert to answer: what was detected, and the question. [drag] is
/// the swipe progress (positive towards YES): the card tilts and gets
/// stamped with the answer it is heading for.
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.incident, required this.drag});

  final Incident incident;
  final double drag;

  static const _titles = {
    HazardKind.crash: 'CRASH',
    HazardKind.wobble: 'SPEED WOBBLE',
    HazardKind.impact: 'HARD IMPACT',
    HazardKind.extremeLean: 'EXTREME LEAN',
  };

  static const _icons = {
    HazardKind.crash: Icons.car_crash,
    HazardKind.wobble: Icons.waves,
    HazardKind.impact: Icons.report_problem,
    HazardKind.extremeLean: Icons.turn_sharp_right,
  };

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final crash = i.kind.critical;
    final t = i.detectedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final detail = [
      ?hazardMeasure(i),
      '${i.speedKmh.toStringAsFixed(0)} km/h',
      '${two(t.hour)}:${two(t.minute)}',
      if (crash) crashOutcomeText(i.outcome),
    ].join(' · ');
    final yes = drag > 0;
    final stampColor = yes ? AppColors.green : AppColors.amber;
    final stamp = (drag.abs() * 3).clamp(0.0, 1.0);

    return Transform.rotate(
      angle: drag * 0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: stamp > 0 ? stampColor : AppColors.border,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _icons[i.kind],
                    size: 46,
                    color: crash ? AppColors.red : AppColors.amber,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _titles[i.kind]!,
                    textAlign: TextAlign.center,
                    style: AppText.display(17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: AppText.body(14, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    crash
                        ? 'Was this a real crash or fall?'
                        : 'Did this really happen?',
                    textAlign: TextAlign.center,
                    style: AppText.body(19, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (stamp > 0)
              Align(
                alignment: yes ? Alignment.topLeft : Alignment.topRight,
                child: Opacity(
                  opacity: stamp,
                  child: Transform.rotate(
                    angle: yes ? -0.2 : 0.2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: stampColor, width: 3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        yes ? 'IT HAPPENED' : 'NOT REAL',
                        style: AppText.display(14, color: stampColor),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
