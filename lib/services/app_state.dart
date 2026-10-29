import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/catalogue/spec_check.dart';
import '../core/safety/safety_baseline.dart';
import '../core/safety/safety_tuning.dart';
import '../data/bike_catalogue.dart';
import '../data/local_store.dart';
import '../data/remote_repository.dart';
import '../models/bike_choice.dart';
import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/emergency_contact.dart';
import '../models/incident.dart';
import '../models/model_check.dart';
import '../models/rider_account.dart';
import '../models/ride_summary.dart';
import 'google_auth.dart';
import 'phone_info.dart';

enum StartupStep { signIn, bikeSetup, calibration, ready }

/// Who is riding what, how the phone is calibrated, and user settings.
class AppState extends ChangeNotifier {
  AppState({
    required LocalStore store,
    required RemoteRepository remote,
    required BikeCatalogue catalogue,
    PhoneInfoReader? phoneInfo,
  }) : _store = store,
       _remote = remote,
       _catalogue = catalogue,
       _readPhone = phoneInfo ?? (() async => PhoneInfo.unknown);

  final LocalStore _store;
  final RemoteRepository _remote;
  final BikeCatalogue _catalogue;
  final PhoneInfoReader _readPhone;
  PhoneInfo _phone = PhoneInfo.unknown;
  static const _uuid = Uuid();

  late String _riderId;
  BikeProfile? _bike;
  CalibrationProfile? _calibration;
  RideSummary? _lastRide;
  EmergencyContact? _emergencyContact;
  SafetyBaseline? _safetyBaseline;
  InitReadings? _initReadings;
  RiderAccount? _account;
  String? _displayName;
  bool _signInSkipped = false;
  String? _initRideSkippedFor;
  String _apiUrl = AppConfig.defaultApiUrl;

  PhoneInfo get phone => _phone;
  BikeCatalogue get catalogue => _catalogue;
  String get riderId => _riderId;
  BikeProfile? get bike => _bike;
  CalibrationProfile? get calibration => _calibration;
  RideSummary? get lastRide => _lastRide;
  EmergencyContact? get emergencyContact => _emergencyContact;

  /// The Google account the rider signed in with.
  RiderAccount? get account => _account;

  /// Longest name the backend accepts.
  static const maxNameLength = 60;

  /// What to call the rider: the name they chose, else their Google name or
  /// email, else null (debug build without sign-in).
  String? get displayName => _displayName ?? _account?.label;

  /// Debug builds only: sign-in was skipped.
  bool get signInSkipped => _signInSkipped;

  /// The rider chose to ride without doing the init ride for this bike.
  /// Rides then learn the phone mount on the go with default settings.
  bool get initRideSkipped {
    final bike = _bike;
    return bike != null &&
        _initRideSkippedFor == bike.id &&
        !_calibratedFor(bike);
  }

  bool _calibratedFor(BikeProfile bike) => _calibration?.bikeId == bike.id;

  /// What has been learned about normal riding on the current mount. A new
  /// calibration (possibly a new mount) starts over.
  SafetyBaseline? get safetyBaseline {
    final b = _safetyBaseline;
    return b != null && b.calibrationId == _calibration?.id ? b : null;
  }

  /// What the current calibration's init ride measured.
  InitReadings? get initReadings {
    final r = _initReadings;
    return r != null && r.calibrationId == _calibration?.id ? r : null;
  }

  SafetyTuning get safetyTuning =>
      safetyBaseline?.tuning ?? SafetyTuning.defaults;
  String get apiUrl => _apiUrl;
  RemoteRepository get remote => _remote;

  /// The first screen depends on how far setup got.
  StartupStep get startupStep {
    if (_account == null && !_signInSkipped) return StartupStep.signIn;
    final bike = _bike;
    if (bike == null) return StartupStep.bikeSetup;
    if (!_calibratedFor(bike) && _initRideSkippedFor != bike.id) {
      return StartupStep.calibration;
    }
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
    _initReadings = _store.initReadings;
    _account = _store.account;
    _displayName = _store.displayName;
    _signInSkipped = kDebugMode && _store.signInSkipped;
    _initRideSkippedFor = _store.initRideSkippedFor;
    _apiUrl = _store.apiUrl ?? AppConfig.defaultApiUrl;
    try {
      _phone = await _readPhone();
    } catch (_) {
      _phone = PhoneInfo.unknown;
    }
    await _syncExisting(legacyBike: _store.bikeIsLegacy);
    notifyListeners();
  }

  /// Brings the server up to date for a rider who already has a bike:
  /// a changed (or never sent) phone model/OS, and a bike stored before
  /// the catalogue, which is re-saved in the new format and sent once as
  /// an Other bike. A new rider gets both from [saveBike].
  Future<void> _syncExisting({required bool legacyBike}) async {
    final bike = _bike;
    if (bike == null) return;
    final phone = _phone;
    final sent = _store.sentPhone;
    final known = phone.model != null || phone.osVersion != null;
    if (known &&
        (sent == null ||
            sent.model != phone.model ||
            sent.osVersion != phone.osVersion)) {
      await _remote.upsertRider(_riderId, phone);
      await _store.setSentPhone(phone);
    }
    if (legacyBike) {
      await _store.setBike(bike);
      await _remote.upsertBike(_riderId, bike);
    }
  }

  /// Keeps the signed-in account and links it to this rider on the server
  /// (the rider is upserted first so the link has something to attach to).
  Future<void> completeSignIn(GoogleSignInResult result) async {
    _account = result.account;
    _signInSkipped = false;
    await _store.setAccount(result.account);
    await _store.setSignInSkipped(false);
    final token = result.idToken;
    if (token != null) {
      await _remote.upsertRider(_riderId, _phone);
      await _store.setSentPhone(_phone);
      await _remote.linkGoogle(_riderId, token);
    }
    notifyListeners();
  }

  /// Changes the name shown for the rider. Saved on the phone straight
  /// away; the server copy goes through the outbox, which keeps retrying
  /// while the phone's network changes during a ride. Returns false for a
  /// name that is blank or too long.
  Future<bool> renameRider(String name) async {
    final clean = name.trim().split(RegExp(r'\s+')).join(' ');
    if (clean.isEmpty || clean.length > maxNameLength) return false;
    if (clean == displayName) return true;
    _displayName = clean;
    await _store.setDisplayName(clean);
    notifyListeners();
    await _remote.setRiderName(_riderId, clean);
    return true;
  }

  /// Debug builds only: use the app without a Google account.
  Future<void> skipSignIn() async {
    if (!kDebugMode) return;
    _signInSkipped = true;
    await _store.setSignInSkipped(true);
    notifyListeners();
  }

  /// Back to the login screen. Bike, calibration and rides stay on the
  /// phone; signing in again picks them up.
  Future<void> signOut() async {
    _account = null;
    _displayName = null;
    _signInSkipped = false;
    await _store.setAccount(null);
    await _store.setDisplayName(null);
    await _store.setSignInSkipped(false);
    notifyListeners();
  }

  /// Rides without the init ride for the current bike, until it is done.
  Future<void> skipInitRide() async {
    final bike = _bike;
    if (bike == null) return;
    _initRideSkippedFor = bike.id;
    await _store.setInitRideSkippedFor(bike.id);
    notifyListeners();
  }

  /// Creates or updates the bike.
  ///
  /// A first bike, or [differentBike], gets a new id and starts over: no
  /// calibration, safety baseline or init readings (the old bike's records
  /// stay on the server under the old id). Otherwise the bike keeps its id
  /// and calibration (the phone mount did not change); if the model changed
  /// the stored init-ride readings are re-checked against the new model.
  Future<BikeProfile> saveBike(
    BikeChoice choice, {
    bool differentBike = false,
  }) async {
    final existing = _bike;
    final fresh = existing == null || differentBike;
    var bike = _bikeFor(
      choice,
      id: fresh ? _uuid.v4() : existing.id,
      createdAt: fresh ? DateTime.now() : existing.createdAt,
    );
    final modelChanged = !fresh && !_sameModel(existing, bike);
    if (!fresh &&
        !modelChanged &&
        existing.topSpeedSource == TopSpeedSource.measured) {
      // Same model: what the init ride proved still takes priority.
      bike = bike.copyWith(
        ratedTopSpeedKmh: existing.ratedTopSpeedKmh,
        topSpeedSource: TopSpeedSource.measured,
      );
    }
    if (existing != null && differentBike) {
      _calibration = null;
      _safetyBaseline = null;
      _initReadings = null;
      await _store.setCalibration(null);
      await _store.setSafetyBaseline(null);
      await _store.setInitReadings(null);
    }
    _bike = bike;
    await _store.setBike(bike);
    await _remote.upsertRider(_riderId, _phone);
    await _store.setSentPhone(_phone);
    await _remote.upsertBike(_riderId, bike);
    final readings = initReadings;
    if (modelChanged && readings != null) {
      await _check(readings, ModelCheck.modelCorrected);
    }
    notifyListeners();
    return _bike!;
  }

  BikeProfile _bikeFor(
    BikeChoice choice, {
    required String id,
    required DateTime createdAt,
  }) {
    switch (choice) {
      case CatalogueChoice(:final model, :final riderTopSpeedKmh):
        final catalogueTop = model.topSpeedKmh?.value;
        final top = catalogueTop ?? riderTopSpeedKmh;
        if (top == null) {
          throw ArgumentError('${model.id} has no top speed; ask the rider');
        }
        return BikeProfile(
          id: id,
          model: model.displayName,
          ratedTopSpeedKmh: top,
          createdAt: createdAt,
          catalogueModelId: model.id,
          catalogueVersion: _catalogue.version,
          topSpeedSource: catalogueTop != null
              ? TopSpeedSource.catalogue
              : TopSpeedSource.rider,
        );
      case OtherChoice(
        :final make,
        :final model,
        :final year,
        :final topSpeedKmh,
      ):
        final m = make.trim();
        final name = model.trim();
        return BikeProfile(
          id: id,
          model: m.isEmpty ? name : '$m $name',
          ratedTopSpeedKmh: topSpeedKmh,
          createdAt: createdAt,
          otherMake: m.isEmpty ? null : m,
          otherModel: name,
          otherYear: year,
        );
    }
  }

  static bool _sameModel(BikeProfile a, BikeProfile b) =>
      a.catalogueModelId == b.catalogueModelId &&
      (a.catalogueModelId != null ||
          (a.otherMake == b.otherMake &&
              (a.otherModel ?? a.model) == (b.otherModel ?? b.model) &&
              a.otherYear == b.otherYear));

  /// End of the init ride: keeps what it measured, checks it against the
  /// bike's model and uploads the check. Call after [saveCalibration].
  Future<void> recordInitRide(
    CalibrationProfile cal,
    InitReadings readings,
  ) async {
    if (readings.calibrationId != cal.id) {
      throw ArgumentError('Readings are from another calibration');
    }
    _initReadings = readings;
    await _store.setInitReadings(readings);
    // The check belongs to the bike the calibration was made on.
    if (_bike?.id == cal.bikeId) await _check(readings, ModelCheck.initRide);
    notifyListeners();
  }

  /// Judges [readings] against the current bike's model, uploads the
  /// check, then applies effective specs: an impossible measured top speed
  /// takes priority over the stated one.
  Future<void> _check(InitReadings readings, String reason) async {
    final bike = _bike!;
    final id = bike.catalogueModelId;
    final check = SpecCheck.run(
      id == null ? null : _catalogue.byId(id),
      readings.readings,
    );
    await _remote.saveModelCheck(
      ModelCheck(
        id: _uuid.v4(),
        bikeId: bike.id,
        calibrationId: readings.calibrationId,
        rideId: readings.rideId,
        reason: reason,
        checkedAt: DateTime.now(),
        catalogueModelId: id,
        // The version whose data built the envelope, not the one saved
        // with the bike.
        catalogueVersion: id == null ? null : _catalogue.version,
        otherMake: bike.isOther ? bike.otherMake : null,
        otherModel: bike.isOther ? (bike.otherModel ?? bike.model) : null,
        otherYear: bike.isOther ? bike.otherYear : null,
        imuHz: readings.imuHz,
        phoneModel: _phone.model,
        check: check,
      ),
    );
    final measured = readings.readings.sustainedTopSpeedKmh;
    if (check.results[SpecItem.topSpeed] == CheckResult.mismatch &&
        measured != null) {
      final updated = bike.copyWith(
        ratedTopSpeedKmh: measured.clamp(
          BikeProfile.minTopSpeedKmh,
          BikeProfile.maxTopSpeedKmh,
        ),
        topSpeedSource: TopSpeedSource.measured,
      );
      _bike = updated;
      await _store.setBike(updated);
      await _remote.upsertBike(_riderId, updated);
    }
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

  /// The rider's answer on a ride's alert: NO on a warning makes detection
  /// on this mount just less sensitive than that event (never on a crash);
  /// the answer is uploaded either way.
  Future<Incident> labelIncident(Incident incident, RiderLabel label) async {
    final labelled = incident.labelled(label, DateTime.now());
    final calibration = _calibration;
    if (calibration != null) {
      final base =
          safetyBaseline ?? SafetyBaseline(calibrationId: calibration.id);
      final updated = base.withLabel(labelled);
      if (!identical(updated, base)) await saveSafetyBaseline(updated);
    }
    await _remote.saveIncident(labelled);
    return labelled;
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
