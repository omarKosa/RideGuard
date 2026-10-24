import 'dart:math' as math;

import '../../models/catalogue_model.dart';
import '../analysis/performance_meter.dart';

double _r2(double v) => double.parse(v.toStringAsFixed(2));

/// What the model can physically do: upper bounds, not typical values.
class ModelEnvelope {
  const ModelEnvelope({
    this.topSpeedKmh,
    this.maxAccelMps2,
    required this.maxDecelMps2,
  });

  factory ModelEnvelope.of(CatalogueModel m) {
    double? accel;
    final t = m.zeroTo100S?.value;
    final p = m.powerKw?.value;
    final w = m.weightKg?.value;
    if (t != null && t > 0) {
      accel = math.min(1.1 * g, 1.5 * (100 / 3.6) / t);
    } else if (p != null && w != null) {
      accel = math.max(
        minAccelFloor,
        math.min(1.1 * g, 60 * p / (w + riderKg)),
      );
    }
    final noAbs = m.abs == AbsFitment.no || m.abs == AbsFitment.unknown;
    final lowGrip =
        m.category == BikeCategory.scooter ||
        m.category == BikeCategory.commuter;
    final decel = lowGrip && noAbs
        ? 0.8 * g
        : m.abs == AbsFitment.yes
        ? 1.1 * g
        : 1.0 * g;
    return ModelEnvelope(
      topSpeedKmh: m.topSpeedKmh?.value,
      maxAccelMps2: accel,
      maxDecelMps2: decel,
    );
  }

  static const g = 9.81;
  /// Floor of the power-to-weight bound: even a 125 commuter launches at
  /// 3-4 m/s2, so anything less would call normal riding impossible.
  static const minAccelFloor = 5.0;
  static const riderKg = 80.0;

  final double? topSpeedKmh;
  final double? maxAccelMps2;
  final double maxDecelMps2;

  Map<String, dynamic> toApiJson() => {
    'top_speed_kmh': topSpeedKmh == null ? null : _r2(topSpeedKmh!),
    'max_accel_mps2': maxAccelMps2 == null ? null : _r2(maxAccelMps2!),
    'max_decel_mps2': _r2(maxDecelMps2),
  };
}

enum CheckResult {
  match('match'),
  mismatch('mismatch'),
  notTested('not_tested');

  const CheckResult(this.api);
  final String api;
}

enum SpecItem {
  topSpeed('top_speed'),
  acceleration('acceleration'),
  braking('braking');

  const SpecItem(this.api);
  final String api;
}

/// Judges init-ride readings against the model. Only physically impossible
/// readings are a mismatch; gentle riding is "not tested".
class SpecCheck {
  const SpecCheck({
    required this.envelope,
    required this.measured,
    required this.results,
  });

  static const topSpeedFactor = 1.07;
  static const topSpeedSlackKmh = 3.0;
  static const impossibleFactor = 1.2;
  static const matchFactor = 0.8;
  static const topMatchFactor = 0.9;

  final ModelEnvelope? envelope;
  final PerformanceReadings measured;
  final Map<SpecItem, CheckResult> results;

  bool get mismatch => results.values.contains(CheckResult.mismatch);

  Map<String, dynamic> resultsApiJson() => {
    for (final e in results.entries) e.key.api: e.value.api,
  };

  static SpecCheck run(CatalogueModel? model, PerformanceReadings measured) {
    if (model == null) {
      return SpecCheck(
        envelope: null,
        measured: measured,
        results: {for (final i in SpecItem.values) i: CheckResult.notTested},
      );
    }
    final env = ModelEnvelope.of(model);
    return SpecCheck(
      envelope: env,
      measured: measured,
      results: {
        SpecItem.topSpeed: _top(env.topSpeedKmh, measured.sustainedTopSpeedKmh),
        SpecItem.acceleration: _accel(env.maxAccelMps2, measured.peakAccelMps2),
        SpecItem.braking: _brake(env.maxDecelMps2, measured),
      },
    );
  }

  static CheckResult _top(double? top, double? v) {
    if (top == null || v == null) return CheckResult.notTested;
    final limit = top * topSpeedFactor + topSpeedSlackKmh;
    if (v > limit) return CheckResult.mismatch;
    if (v >= topMatchFactor * top) return CheckResult.match;
    return CheckResult.notTested;
  }

  static CheckResult _accel(double? max, double? v) {
    if (max == null || v == null) return CheckResult.notTested;
    if (v > impossibleFactor * max) return CheckResult.mismatch;
    if (v >= matchFactor * max) return CheckResult.match;
    return CheckResult.notTested;
  }

  /// A stop's mean deceleration comes from GPS speeds, so stops that began
  /// at a glitch (or can't be told apart from one) are not judged; the
  /// IMU's peak deceleration always is.
  static CheckResult _brake(double max, PerformanceReadings m) {
    final peak = m.peakDecelMps2;
    if ((peak != null && peak > impossibleFactor * max) ||
        m.judgeableStops.any((s) => s.meanDecelMps2 > impossibleFactor * max)) {
      return CheckResult.mismatch;
    }
    if (peak != null && peak >= matchFactor * max) return CheckResult.match;
    return CheckResult.notTested;
  }
}
