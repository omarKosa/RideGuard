import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/safety/safety_baseline.dart';
import '../core/safety/safety_monitor.dart';
import '../core/safety/safety_tuning.dart';
import '../data/local_store.dart';
import '../data/remote_repository.dart';
import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/emergency_contact.dart';
import '../models/incident.dart';
import '../models/ride_summary.dart';

enum StartupStep { bikeSetup, calibration, ready }

/// Who is riding what, how the phone is calibrated, and user settings.
class AppState extends ChangeNotifier {
  AppState({required LocalStore store, required RemoteRepository remote})
    : _store = store,
      _remote = remote;

  final LocalStore _store;
  final RemoteRepository _remote;
  static const _uuid = Uuid();

  late String _riderId;
  BikeProfile? _bike;
  CalibrationProfile? _calibration;
  RideSummary? _lastRide;
  EmergencyContact? _emergencyContact;
  SafetyBaseline? _safetyBaseline;
  String _apiUrl = AppConfig.defaultApiUrl;

  String get riderId => _riderId;
  BikeProfile? get bike => _bike;
  CalibrationProfile? get calibration => _calibration;
  RideSummary? get lastRide => _lastRide;
  EmergencyContact? get emergencyContact => _emergencyContact;

  /// What has been learned about normal riding on the current mount. A new
  /// calibration (possibly a new mount) starts over.
  SafetyBaseline? get safetyBaseline {
    final b = _safetyBaseline;
    return b != null && b.calibrationId == _calibration?.id ? b : null;
  }

  SafetyTuning get safetyTuning =>
      safetyBaseline?.tuning ?? SafetyTuning.defaults;
  String get apiUrl => _apiUrl;
  RemoteRepository get remote => _remote;

  /// The first screen depends on how far setup got.
  StartupStep get startupStep {
    final bike = _bike;
    if (bike == null) return StartupStep.bikeSetup;
    final cal = _calibration;
    if (cal == null || cal.bikeId != bike.id) return StartupStep.calibration;
    return StartupStep.ready;
  }

  Future<void> load() async {
    var riderId = _store.riderId;
    if (riderId == null) {
      riderId = _uuid.v4();
      await _store.setRiderId(riderId);
    }
    _riderId = riderId;
    _bike = _store.bike;
    _calibration = _store.calibration;
    _lastRide = _store.lastRide;
    _emergencyContact = _store.emergencyContact;
    _safetyBaseline = _store.safetyBaseline;
    _apiUrl = _store.apiUrl ?? AppConfig.defaultApiUrl;
    notifyListeners();
  }

  /// Creates or updates the bike. Changing the model or top speed of an
  /// existing bike keeps its calibration; the phone mount did not change.
  Future<BikeProfile> saveBike({
    required String model,
    required double ratedTopSpeedKmh,
  }) async {
    final existing = _bike;
    final bike = existing == null
        ? BikeProfile(
            id: _uuid.v4(),
            model: model.trim(),
            ratedTopSpeedKmh: ratedTopSpeedKmh,
            createdAt: DateTime.now(),
            otherModel: model.trim(),
          )
        : existing.copyWith(
            model: model.trim(),
            ratedTopSpeedKmh: ratedTopSpeedKmh,
            otherModel: model.trim(),
            topSpeedSource: TopSpeedSource.rider,
          );
    _bike = bike;
    await _store.setBike(bike);
    await _remote.upsertRider(_riderId);
    await _remote.upsertBike(_riderId, bike);
    notifyListeners();
    return bike;
  }

  Future<void> saveCalibration(CalibrationProfile profile) async {
    _calibration = profile;
    await _store.setCalibration(profile);
    await _remote.saveCalibration(profile);
    notifyListeners();
  }

  Future<void> setLastRide(RideSummary summary) async {
    _lastRide = summary;
    await _store.setLastRide(summary);
    notifyListeners();
  }

  Future<void> saveSafetyBaseline(SafetyBaseline? baseline) async {
    _safetyBaseline = baseline;
    await _store.setSafetyBaseline(baseline);
    notifyListeners();
  }

  /// Merges a finished ride's normal-riding statistics into the baseline.
  Future<void> learnFromRide(
    RideNoise noise, {
    required List<Incident> incidents,
  }) async {
    final calibration = _calibration;
    if (calibration == null) return;
    final base =
        safetyBaseline ?? SafetyBaseline(calibrationId: calibration.id);
    await saveSafetyBaseline(
      base.withRide(
        noise,
        cancelledCrashes: incidents
            .where((i) => i.outcome == IncidentOutcome.cancelled)
            .length,
      ),
    );
  }

  /// The rider says [incident] was not real: detection on this mount gets
  /// just less sensitive than that event, and the label is uploaded.
  Future<Incident> markFalseAlarm(Incident incident) async {
    final marked = incident.markedFalseAlarm();
    final calibration = _calibration;
    if (calibration != null) {
      final base =
          safetyBaseline ?? SafetyBaseline(calibrationId: calibration.id);
      final updated = switch (incident.kind) {
        HazardKind.wobble when incident.wobbleRms != null =>
          base.withFalseWobble(incident.wobbleRms!),
        HazardKind.impact when incident.peakAccelG != null =>
          base.withFalseImpact(incident.peakAccelG!),
        HazardKind.extremeLean => base.withFalseLean(incident.leanDeg),
        _ => base,
      };
      await saveSafetyBaseline(updated);
    }
    await _remote.saveIncident(marked);
    return marked;
  }

  /// Back to default sensitivity; learning starts again from the next ride.
  Future<void> resetSafetyLearning() async {
    final calibration = _calibration;
    await saveSafetyBaseline(
      calibration == null
          ? null
          : SafetyBaseline(calibrationId: calibration.id),
    );
  }

  /// Stays on the phone only; the backend never sees the contact.
  Future<void> setEmergencyContact(EmergencyContact? contact) async {
    _emergencyContact = contact;
    await _store.setEmergencyContact(contact);
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    _apiUrl = url.trim();
    await _store.setApiUrl(_apiUrl);
    notifyListeners();
  }
}
