/// Detection thresholds for one bike and mount, learned by [SafetyBaseline]
/// from normal riding and from false alarms the rider reported.
///
/// Learning only ever makes detection *less* sensitive than the defaults,
/// and never beyond the caps, so a vibrating mount or a few "false alarm"
/// taps can't switch detection off.
class SafetyTuning {
  const SafetyTuning({
    this.wobbleMinRms = defaultWobbleRms,
    this.wobbleMaxHz = defaultWobbleMaxHz,
    this.impactG = defaultImpactG,
    this.extremeLeanDeg = defaultExtremeLeanDeg,
    this.warnings = const [],
  });

  /// Oscillating rotation (rad/s RMS) that counts as a wobble.
  static const double defaultWobbleRms = 0.5;
  static const double maxWobbleRms = 1.0;

  static const double wobbleMinHz = 3;
  static const double defaultWobbleMaxHz = 12;

  /// Total acceleration that counts as an impact.
  static const double defaultImpactG = 4.0;
  static const double maxImpactG = 6.0;

  static const double defaultExtremeLeanDeg = 55;
  static const double maxExtremeLeanDeg = 65;

  static const defaults = SafetyTuning();

  final double wobbleMinRms;

  /// Highest wobble frequency this phone's sensor rate can resolve.
  final double wobbleMaxHz;
  final double impactG;
  final double extremeLeanDeg;

  /// Things the rider should know about this setup.
  final List<String> warnings;

  bool get wobbleDetectable => wobbleMaxHz > wobbleMinHz;

  Map<String, dynamic> toApiJson() => {
    'wobble_threshold_rms': _r(wobbleMinRms),
    'wobble_max_hz': _r(wobbleMaxHz),
    'impact_threshold_g': _r(impactG),
    'extreme_lean_deg': _r(extremeLeanDeg),
  };
}

double _r(double v) => double.parse(v.toStringAsFixed(3));
