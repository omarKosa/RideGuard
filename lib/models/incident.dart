import '../core/safety/safety_monitor.dart';

/// What happened after a hazard was detected.
enum IncidentOutcome {
  /// Crash countdown still running.
  pending('pending'),

  /// Warning-level hazard: the rider was alerted.
  warned('warned'),

  /// The rider said they are OK before the countdown ran out.
  cancelled('cancelled'),

  /// The emergency contact was called.
  called('called'),

  /// No call permission: the dialer was opened with the number.
  dialerOpened('dialer_opened'),
  callFailed('call_failed'),

  /// No emergency contact set; only the alarm sounded.
  noContact('no_contact');

  const IncidentOutcome(this.apiName);

  final String apiName;
}

/// The rider's answer to "Did this really happen?" after the ride.
enum RiderLabel { yes, no }

/// A detected hazard, as stored and uploaded.
class Incident {
  const Incident({
    required this.id,
    required this.rideId,
    required this.kind,
    required this.detectedAt,
    required this.speedKmh,
    required this.leanDeg,
    required this.outcome,
    this.peakAccelG,
    this.wobbleHz,
    this.wobbleRms,
    this.latitude,
    this.longitude,
    this.resolvedAt,
    this.riderLabel,
    this.labelledAt,
  }) : assert((riderLabel == null) == (labelledAt == null));

  factory Incident.fromHazard({
    required String id,
    required String rideId,
    required Hazard hazard,
    required DateTime detectedAt,
  }) => Incident(
    id: id,
    rideId: rideId,
    kind: hazard.kind,
    detectedAt: detectedAt,
    speedKmh: hazard.speedKmh,
    leanDeg: hazard.leanDeg,
    peakAccelG: hazard.peakAccelG,
    wobbleHz: hazard.wobbleHz,
    wobbleRms: hazard.wobbleRms,
    latitude: hazard.latitude,
    longitude: hazard.longitude,
    outcome: hazard.kind.critical
        ? IncidentOutcome.pending
        : IncidentOutcome.warned,
  );

  final String id;
  final String rideId;
  final HazardKind kind;
  final DateTime detectedAt;
  final double speedKmh;
  final double leanDeg;
  final double? peakAccelG;
  final double? wobbleHz;
  final double? wobbleRms;
  final double? latitude;
  final double? longitude;
  final IncidentOutcome outcome;
  final DateTime? resolvedAt;

  /// What the rider answered after the ride; null when not asked or
  /// skipped. On a crash it is data only: it never loosens detection.
  final RiderLabel? riderLabel;
  final DateTime? labelledAt;

  Incident _copy({
    IncidentOutcome? outcome,
    DateTime? resolvedAt,
    RiderLabel? riderLabel,
    DateTime? labelledAt,
  }) => Incident(
    id: id,
    rideId: rideId,
    kind: kind,
    detectedAt: detectedAt,
    speedKmh: speedKmh,
    leanDeg: leanDeg,
    peakAccelG: peakAccelG,
    wobbleHz: wobbleHz,
    wobbleRms: wobbleRms,
    latitude: latitude,
    longitude: longitude,
    outcome: outcome ?? this.outcome,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    riderLabel: riderLabel ?? this.riderLabel,
    labelledAt: labelledAt ?? this.labelledAt,
  );

  Incident resolve(IncidentOutcome outcome, DateTime at) =>
      _copy(outcome: outcome, resolvedAt: at);

  /// The rider's answer, given at [at].
  Incident labelled(RiderLabel label, DateTime at) =>
      _copy(riderLabel: label, labelledAt: at);

  static const _kindApiNames = {
    HazardKind.crash: 'crash',
    HazardKind.wobble: 'wobble',
    HazardKind.impact: 'impact',
    HazardKind.extremeLean: 'extreme_lean',
  };

  Map<String, dynamic> toApiJson() => {
    'kind': _kindApiNames[kind],
    'detected_at': detectedAt.toUtc().toIso8601String(),
    'speed_kmh': _round(speedKmh.clamp(0, 500), 2),
    'lean_deg': _round(leanDeg.clamp(-90, 90), 2),
    'peak_accel_g': peakAccelG == null
        ? null
        : _round(peakAccelG!.clamp(0, 100), 2),
    'wobble_hz': wobbleHz == null ? null : _round(wobbleHz!.clamp(0.1, 25), 2),
    'wobble_rms': wobbleRms == null
        ? null
        : _round(wobbleRms!.clamp(0, 100), 3),
    'latitude': latitude,
    'longitude': longitude,
    'outcome': outcome.apiName,
    'resolved_at': resolvedAt?.toUtc().toIso8601String(),
    // Always both or neither; an upload without them clears a stored
    // label, so every copy uploaded after labelling must carry it.
    'rider_label': riderLabel?.name,
    'labelled_at': labelledAt?.toUtc().toIso8601String(),
  };
}

double _round(num value, int digits) =>
    double.parse(value.toDouble().toStringAsFixed(digits));
