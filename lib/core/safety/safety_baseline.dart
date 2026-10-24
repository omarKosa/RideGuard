import 'dart:math' as math;

import '../../models/incident.dart';
import 'safety_monitor.dart';
import 'safety_tuning.dart';

/// Log-spaced histogram: quantiles of a value in a few dozen numbers, so a
/// ride's statistics can be stored and combined with other rides.
class Histogram {
  Histogram({
    required this.min,
    required this.max,
    this.bins = 40,
    List<double>? counts,
  }) : counts = counts ?? List.filled(bins, 0.0);

  /// In-band oscillation of the gyro, rad/s RMS.
  factory Histogram.wobble() => Histogram(min: 0.01, max: 5);

  /// Peak total acceleration, g.
  factory Histogram.accel() => Histogram(min: 0.5, max: 20);

  factory Histogram.fromJson(Map<String, dynamic> json) => Histogram(
    min: (json['min'] as num).toDouble(),
    max: (json['max'] as num).toDouble(),
    bins: (json['counts'] as List<dynamic>).length,
    counts: [
      for (final c in json['counts'] as List<dynamic>) (c as num).toDouble(),
    ],
  );

  final double min;
  final double max;
  final int bins;
  final List<double> counts;

  double get total => counts.fold(0.0, (a, b) => a + b);

  int _bin(double v) {
    if (!(v > min)) return 0;
    if (v >= max) return bins - 1;
    final i = (math.log(v / min) / math.log(max / min) * bins).floor();
    return i.clamp(0, bins - 1);
  }

  double _upperEdge(int i) => min * math.pow(max / min, (i + 1) / bins);

  void add(double v) => counts[_bin(v)] += 1;

  /// The [q] quantile, rounded *up* to its bin edge (errs towards a higher
  /// floor, i.e. fewer false alarms). Null when empty.
  double? quantile(double q) {
    final tot = total;
    if (tot <= 0) return null;
    var acc = 0.0;
    for (var i = 0; i < bins; i++) {
      acc += counts[i];
      if (acc >= q * tot) return _upperEdge(i);
    }
    return max;
  }

  Histogram operator +(Histogram other) => Histogram(
    min: min,
    max: max,
    bins: bins,
    counts: [for (var i = 0; i < bins; i++) counts[i] + other.counts[i]],
  );

  Map<String, dynamic> toJson() => {
    'min': min,
    'max': max,
    'counts': [for (final c in counts) c.round()],
  };
}

/// Speed ranges normal riding is broken down by when uploaded.
enum SpeedBand {
  b20to40('20-40'),
  b40to60('40-60'),
  b60to90('60-90'),
  b90to120('90-120'),
  b120plus('120+');

  const SpeedBand(this.apiName);

  final String apiName;

  /// The band [kmh] falls in; null below 20 km/h (or not a number).
  static SpeedBand? of(double kmh) {
    if (!(kmh >= 20)) return null;
    if (kmh < 40) return b20to40;
    if (kmh < 60) return b40to60;
    if (kmh < 90) return b60to90;
    if (kmh < 120) return b90to120;
    return b120plus;
  }
}

/// Normal riding within one [SpeedBand]: one value per second.
class BandNoise {
  BandNoise({Histogram? wobbleRms, Histogram? wobbleHz, Histogram? peakG})
    : wobbleRms = wobbleRms ?? Histogram.wobble(),
      wobbleHz = wobbleHz ?? Histogram(min: 0.5, max: 25),
      peakG = peakG ?? Histogram.accel();

  /// Strongest wobble-band oscillation in each second.
  final Histogram wobbleRms;

  /// Frequency (Hz) of each second's strongest wobble-band shake (the
  /// same sample as [wobbleRms]); seconds without any are left out.
  final Histogram wobbleHz;

  /// Strongest jolt in each second.
  final Histogram peakG;

  double get seconds => wobbleRms.total;

  void add({required double wobble, required double? hz, required double g}) {
    wobbleRms.add(wobble);
    if (hz != null) wobbleHz.add(hz);
    peakG.add(g);
  }
}

/// What normal riding looked like during one ride: one value per second of
/// steady riding, away from any hazard.
class RideNoise {
  RideNoise({
    Histogram? wobbleRms,
    Histogram? peakG,
    this.imuHz,
    Map<SpeedBand, BandNoise>? bands,
  }) : wobbleRms = wobbleRms ?? Histogram.wobble(),
       peakG = peakG ?? Histogram.accel(),
       bands = bands ?? {};

  /// Bands are upload-only: a stored ride comes back without them.
  factory RideNoise.fromJson(Map<String, dynamic> json) => RideNoise(
    wobbleRms: Histogram.fromJson(json['wobble_rms'] as Map<String, dynamic>),
    peakG: Histogram.fromJson(json['peak_g'] as Map<String, dynamic>),
    imuHz: (json['imu_hz'] as num?)?.toDouble(),
  );

  /// Strongest wobble-band oscillation in each second.
  final Histogram wobbleRms;

  /// Strongest jolt in each second.
  final Histogram peakG;

  /// Gyroscope samples per second actually delivered by this phone.
  final double? imuHz;

  /// The same seconds, split by speed (for later analysis; thresholds use
  /// the ride-wide histograms).
  final Map<SpeedBand, BandNoise> bands;

  double get ridingSeconds => wobbleRms.total;

  /// Per-ride summary uploaded with the ride.
  Map<String, dynamic> toApiJson(SafetyTuning tuning) => {
    'riding_s': ridingSeconds.round(),
    'wobble_rms_p99': _r(wobbleRms.quantile(0.99)),
    'peak_g_p99': _r(peakG.quantile(0.99)),
    'imu_hz': _r(imuHz),
    ...tuning.toApiJson(),
    'bands': [
      for (final band in SpeedBand.values)
        if (bands[band] case final b? when b.seconds > 0)
          {
            'band': band.apiName,
            'seconds': b.seconds.round(),
            'wobble_rms': b.wobbleRms.toJson(),
            'wobble_hz': b.wobbleHz.toJson(),
            'peak_g': b.peakG.toJson(),
          },
    ],
  };

  /// Local storage (the safety baseline); leaves out [bands].
  Map<String, dynamic> toJson() => {
    'wobble_rms': wobbleRms.toJson(),
    'peak_g': peakG.toJson(),
    'imu_hz': imuHz,
  };
}

/// Everything the app has learned about normal riding on one mount (one
/// calibration), and the thresholds that follow from it.
///
/// Every ride is merged in, the init ride first. The floor is the 99th
/// percentile of normal riding, so a single pothole doesn't move it, and
/// thresholds sit well above it:
/// * wobble = 3 × floor of wobble-band oscillation
/// * impact = 1.25 × floor of per-second peak acceleration
///
/// Warnings the rider said did not happen push the matching threshold
/// just above that event. Cancelled crashes are only counted: "I'm OK"
/// doesn't mean it wasn't a crash, so crash detection never loosens.
class SafetyBaseline {
  SafetyBaseline({
    required this.calibrationId,
    this.recentRides = const [],
    this.imuHz,
    this.rides = 0,
    this.falseWobbleRms,
    this.falseImpactG,
    this.falseLeanDeg,
    this.falseAlarms = 0,
    this.cancelledCrashes = 0,
  });

  factory SafetyBaseline.fromJson(Map<String, dynamic> json) => SafetyBaseline(
    calibrationId: json['calibration_id'] as String,
    recentRides: [
      for (final r in json['recent_rides'] as List<dynamic>)
        RideNoise.fromJson(r as Map<String, dynamic>),
    ],
    imuHz: (json['imu_hz'] as num?)?.toDouble(),
    rides: json['rides'] as int,
    falseWobbleRms: (json['false_wobble_rms'] as num?)?.toDouble(),
    falseImpactG: (json['false_impact_g'] as num?)?.toDouble(),
    falseLeanDeg: (json['false_lean_deg'] as num?)?.toDouble(),
    falseAlarms: json['false_alarms'] as int,
    cancelledCrashes: json['cancelled_crashes'] as int,
  );

  /// The floors come from the most recent rides covering this much riding;
  /// older rides are dropped, so fixing a rattling mount is picked up.
  static const double windowSeconds = 3 * 3600;

  /// Bounds storage when there are many short rides.
  static const int maxRecentRides = 60;

  /// Riding needed before thresholds move off the defaults.
  static const double minRidingSeconds = 60;

  static const double wobbleFactor = 3;
  static const double impactFactor = 1.25;

  /// The mount this was learned on.
  final String calibrationId;

  /// Oldest first.
  final List<RideNoise> recentRides;
  final double? imuHz;

  /// Rides learned from in total, including ones no longer in the window.
  final int rides;

  /// Strongest events the rider said were not real.
  final double? falseWobbleRms;
  final double? falseImpactG;
  final double? falseLeanDeg;
  final int falseAlarms;
  final int cancelledCrashes;

  Histogram get wobbleRms =>
      recentRides.fold(Histogram.wobble(), (h, r) => h + r.wobbleRms);
  Histogram get peakG =>
      recentRides.fold(Histogram.accel(), (h, r) => h + r.peakG);

  /// Seconds of riding behind the floors.
  double get ridingSeconds =>
      recentRides.fold(0.0, (s, r) => s + r.ridingSeconds);

  SafetyBaseline _copy({
    List<RideNoise>? recentRides,
    double? imuHz,
    int? rides,
    double? falseWobbleRms,
    double? falseImpactG,
    double? falseLeanDeg,
    int? falseAlarms,
    int? cancelledCrashes,
  }) => SafetyBaseline(
    calibrationId: calibrationId,
    recentRides: recentRides ?? this.recentRides,
    imuHz: imuHz ?? this.imuHz,
    rides: rides ?? this.rides,
    falseWobbleRms: falseWobbleRms ?? this.falseWobbleRms,
    falseImpactG: falseImpactG ?? this.falseImpactG,
    falseLeanDeg: falseLeanDeg ?? this.falseLeanDeg,
    falseAlarms: falseAlarms ?? this.falseAlarms,
    cancelledCrashes: cancelledCrashes ?? this.cancelledCrashes,
  );

  /// Adds one ride's normal-riding statistics.
  SafetyBaseline withRide(RideNoise noise, {int cancelledCrashes = 0}) {
    final window = [...recentRides, if (noise.ridingSeconds > 0) noise];
    var total = window.fold(0.0, (s, r) => s + r.ridingSeconds);
    // Drop the oldest rides the newer ones already cover.
    while (window.length > 1 &&
        (total - window.first.ridingSeconds >= windowSeconds ||
            window.length > maxRecentRides)) {
      total -= window.removeAt(0).ridingSeconds;
    }
    return _copy(
      recentRides: List.unmodifiable(window),
      imuHz: noise.imuHz,
      rides: rides + 1,
      cancelledCrashes: this.cancelledCrashes + cancelledCrashes,
    );
  }

  SafetyBaseline withFalseWobble(double rms) => _copy(
    falseWobbleRms: math.max(falseWobbleRms ?? 0, rms),
    falseAlarms: falseAlarms + 1,
  );

  SafetyBaseline withFalseImpact(double g) => _copy(
    falseImpactG: math.max(falseImpactG ?? 0, g),
    falseAlarms: falseAlarms + 1,
  );

  SafetyBaseline withFalseLean(double leanDeg) => _copy(
    falseLeanDeg: math.max(falseLeanDeg ?? 0, leanDeg.abs()),
    falseAlarms: falseAlarms + 1,
  );

  /// Learns from the rider's answer on [i]: NO on a warning raises that
  /// threshold just above the event. Crashes and YES change nothing.
  SafetyBaseline withLabel(Incident i) {
    if (i.riderLabel != RiderLabel.no) return this;
    return switch (i.kind) {
      HazardKind.wobble when i.wobbleRms != null => withFalseWobble(
        i.wobbleRms!,
      ),
      HazardKind.impact when i.peakAccelG != null => withFalseImpact(
        i.peakAccelG!,
      ),
      HazardKind.extremeLean => withFalseLean(i.leanDeg),
      _ => this,
    };
  }

  SafetyTuning get tuning {
    final warnings = <String>[];
    var wobble = SafetyTuning.defaultWobbleRms;
    var impact = SafetyTuning.defaultImpactG;
    var lean = SafetyTuning.defaultExtremeLeanDeg;
    var maxHz = SafetyTuning.defaultWobbleMaxHz;

    if (ridingSeconds >= minRidingSeconds) {
      final wobbleFloor = wobbleRms.quantile(0.99)!;
      final impactFloor = peakG.quantile(0.99)!;
      wobble = math.max(wobble, wobbleFactor * wobbleFloor);
      impact = math.max(impact, impactFactor * impactFloor);
      if (wobble > SafetyTuning.maxWobbleRms) {
        warnings.add(
          'Strong vibration reaches the phone '
          '(${wobbleFloor.toStringAsFixed(2)} rad/s in normal riding). '
          'Wobble alerts are at their least sensitive; a firmer or '
          'vibration-damped mount helps.',
        );
      }
      if (impact > SafetyTuning.maxImpactG) {
        warnings.add(
          'The phone takes hard knocks in its mount '
          '(${impactFloor.toStringAsFixed(1)} g in normal riding). Impact '
          'alerts are at their least sensitive.',
        );
      }
    }

    final fw = falseWobbleRms, fi = falseImpactG, fl = falseLeanDeg;
    if (fw != null) wobble = math.max(wobble, fw * 1.15);
    if (fi != null) impact = math.max(impact, fi * 1.1);
    if (fl != null) lean = math.max(lean, fl + 3);
    wobble = math.min(wobble, SafetyTuning.maxWobbleRms);
    impact = math.min(impact, SafetyTuning.maxImpactG);
    lean = math.min(lean, SafetyTuning.maxExtremeLeanDeg);

    final hz = imuHz;
    if (hz != null && hz < 4 * SafetyTuning.defaultWobbleMaxHz) {
      // ~4 samples per oscillation are needed to count reversals.
      maxHz = hz / 4;
      warnings.add(
        maxHz <= SafetyTuning.wobbleMinHz
            ? 'This phone delivers motion data at only ${hz.round()} Hz - '
                  'too slow to detect speed wobbles. Crash detection still '
                  'works.'
            : 'This phone delivers motion data at ${hz.round()} Hz: wobbles '
                  'faster than ${maxHz.toStringAsFixed(0)} Hz may be missed.',
      );
    }

    return SafetyTuning(
      wobbleMinRms: wobble,
      wobbleMaxHz: maxHz,
      impactG: impact,
      extremeLeanDeg: lean,
      warnings: warnings,
    );
  }

  Map<String, dynamic> toJson() => {
    'calibration_id': calibrationId,
    'recent_rides': [for (final r in recentRides) r.toJson()],
    'imu_hz': imuHz,
    'rides': rides,
    'false_wobble_rms': falseWobbleRms,
    'false_impact_g': falseImpactG,
    'false_lean_deg': falseLeanDeg,
    'false_alarms': falseAlarms,
    'cancelled_crashes': cancelledCrashes,
  };
}

double? _r(double? v) => v == null ? null : double.parse(v.toStringAsFixed(3));
