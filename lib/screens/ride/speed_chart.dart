import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/ride_sample.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class SpeedChart extends StatelessWidget {
  const SpeedChart({super.key, required this.samples});

  final List<RideSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return SectionCard(
        title: 'SPEED & LEAN',
        child: Center(
          child: Text(
            'Collecting data...',
            style: AppText.body(14, color: AppColors.textFaint),
          ),
        ),
      );
    }
    final t0 = samples.first.time;
    double x(RideSample s) => s.time.difference(t0).inMilliseconds / 1000;
    // Thin out to ~1 point per second; the chart does not need 10 Hz.
    final step = math.max(1, samples.length ~/ 120);
    final pts = [for (var i = 0; i < samples.length; i += step) samples[i]];
    final top = pts.map((s) => s.speedKmh).fold<double>(0, math.max);
    final maxY = math.max(60.0, (top / 50).ceil() * 50.0);
    // Lean is drawn on the same axis: 0..maxY maps to -60..+60°.
    double leanY(double deg) => maxY / 2 + deg.clamp(-60, 60) / 60 * maxY / 2;

    return SectionCard(
      title: 'SPEED & LEAN · LAST 2 MIN',
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Expanded(
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: 0,
            maxX: x(pts.last),
            minY: 0,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: maxY / 4,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: AppText.body(10, color: AppColors.textFaint),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final s in pts) FlSpot(x(s), s.speedKmh)],
                isCurved: true,
                color: AppColors.cyan,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.cyan.withValues(alpha: 0.12),
                ),
              ),
              LineChartBarData(
                spots: [for (final s in pts) FlSpot(x(s), leanY(s.leanDeg))],
                isCurved: true,
                color: AppColors.amber,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
