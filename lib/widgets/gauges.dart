import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Circular speedometer scaled to the bike's rated top speed.
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.speedKmh,
    required this.scaleMaxKmh,
    required this.maxSpeedKmh,
    this.size = 210,
    this.reliable = true,
  });

  final double speedKmh;
  final double scaleMaxKmh;
  final double maxSpeedKmh;
  final double size;
  final bool reliable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.surface,
                  AppColors.background.withValues(alpha: 0.8),
                ],
              ),
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.3),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          CustomPaint(
            size: Size.square(size - 20),
            painter: _SpeedArcPainter(
              ratio: scaleMaxKmh <= 0 ? 0 : speedKmh / scaleMaxKmh,
              maxRatio: scaleMaxKmh <= 0 ? 0 : maxSpeedKmh / scaleMaxKmh,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                speedKmh.toStringAsFixed(0),
                style: AppText.display(
                  size * 0.25,
                  color: reliable ? Colors.white : AppColors.textFaint,
                ),
              ),
              Text('KM/H', style: AppText.label(14, color: AppColors.cyan)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'MAX ${maxSpeedKmh.toStringAsFixed(0)}',
                  style: AppText.body(
                    12,
                    color: AppColors.red,
                    weight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedArcPainter extends CustomPainter {
  _SpeedArcPainter({required this.ratio, required this.maxRatio});

  final double ratio;
  final double maxRatio;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 8);
    final bg = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, bg);

    final fg = Paint()
      ..shader = const SweepGradient(
        startAngle: _start,
        endAngle: _start + _sweep,
        colors: [AppColors.cyan, AppColors.amber, AppColors.red],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep * ratio.clamp(0.0, 1.0), false, fg);

    // Tick for the session maximum.
    if (maxRatio > 0) {
      final a = _start + _sweep * maxRatio.clamp(0.0, 1.0);
      final r = rect.width / 2;
      final tick = Paint()
        ..color = AppColors.red
        ..strokeWidth = 3;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (r - 10),
        center + Offset(math.cos(a), math.sin(a)) * (r + 10),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedArcPainter old) =>
      old.ratio != ratio || old.maxRatio != maxRatio;
}

/// Half-circle lean indicator: a needle shows the bike's current lean, red
/// marks the session maximum each side.
class LeanGauge extends StatelessWidget {
  const LeanGauge({
    super.key,
    required this.leanDeg,
    required this.maxLeftDeg,
    required this.maxRightDeg,
    this.width = 260,
  });

  final double leanDeg;
  final double maxLeftDeg;
  final double maxRightDeg;
  final double width;

  static const double scaleDeg = 60;

  @override
  Widget build(BuildContext context) {
    final side = leanDeg < -0.5
        ? 'L'
        : leanDeg > 0.5
        ? 'R'
        : '';
    return SizedBox(
      width: width,
      height: width * 0.62,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LeanPainter(
                lean: leanDeg,
                maxLeft: maxLeftDeg,
                maxRight: maxRightDeg,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${leanDeg.abs().toStringAsFixed(0)}°$side',
                  style: AppText.display(26),
                ),
                Text('LEAN', style: AppText.label(11)),
              ],
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Text(
              'L ${maxLeftDeg.toStringAsFixed(0)}°',
              style: AppText.body(
                13,
                color: AppColors.red,
                weight: FontWeight.bold,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              'R ${maxRightDeg.toStringAsFixed(0)}°',
              style: AppText.body(
                13,
                color: AppColors.red,
                weight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeanPainter extends CustomPainter {
  _LeanPainter({
    required this.lean,
    required this.maxLeft,
    required this.maxRight,
  });

  final double lean;
  final double maxLeft;
  final double maxRight;

  /// Upright points straight up; leaning right rotates clockwise.
  double _angle(double deg) =>
      -math.pi / 2 +
      (deg.clamp(-LeanGauge.scaleDeg, LeanGauge.scaleDeg) / 90) * math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    final radius = math.min(size.width / 2, size.height) - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final from = _angle(-LeanGauge.scaleDeg);
    final sweep = _angle(LeanGauge.scaleDeg) - from;

    canvas.drawArc(
      rect,
      from,
      sweep,
      false,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Fill from upright to the current lean.
    final leanPaint = Paint()
      ..color = lean.abs() > 45 ? AppColors.red : AppColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _angle(0), _angle(lean) - _angle(0), false, leanPaint);

    // Degree ticks every 15°.
    final tick = Paint()
      ..color = AppColors.textFaint
      ..strokeWidth = 2;
    for (var d = -60; d <= 60; d += 15) {
      final a = _angle(d.toDouble());
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (radius + 8),
        center + dir * (radius + (d == 0 ? 16 : 12)),
        tick,
      );
    }

    // Session max markers.
    final maxPaint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 3;
    for (final d in [if (maxLeft > 0) -maxLeft, if (maxRight > 0) maxRight]) {
      final dir = Offset(math.cos(_angle(d)), math.sin(_angle(d)));
      canvas.drawLine(
        center + dir * (radius - 9),
        center + dir * (radius + 9),
        maxPaint,
      );
    }

    // Needle.
    final needleDir = Offset(math.cos(_angle(lean)), math.sin(_angle(lean)));
    canvas.drawLine(
      center + needleDir * (radius * 0.45),
      center + needleDir * (radius - 14),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LeanPainter old) =>
      old.lean != lean || old.maxLeft != maxLeft || old.maxRight != maxRight;
}
