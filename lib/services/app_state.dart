import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/calibration/calibration_session.dart';
import '../core/fusion/motion_pipeline.dart';
import '../core/fusion/mount_orientation.dart';
import '../core/math/vec3.dart';
import '../data/local_store.dart';
import '../data/remote_repository.dart';
import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
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
  String _apiUrl = AppConfig.defaultApiUrl;

  String get riderId => _riderId;
  BikeProfile? get bike => _bike;
  CalibrationProfile? get calibration => _calibration;
  RideSummary? get lastRide => _lastRide;
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
          )
        : existing.copyWith(
            model: model.trim(),
            ratedTopSpeedKmh: ratedTopSpeedKmh,
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

  /// Testing shortcut: skips bike setup and the init ride with a placeholder
  /// bike (if none yet) and an unmeasured calibration for a phone in portrait
  /// on the bars. A calibration ride is still registered so later rides can
  /// reference the calibration on the backend.
  Future<void> skipSetupForTesting() async {
    final bike =
        _bike ?? await saveBike(model: 'Test bike', ratedTopSpeedKmh: 200);
    final now = DateTime.now();
    final rideId = _uuid.v4();
    await _remote.startRide(
      rideId: rideId,
      bikeId: bike.id,
      kind: RideKind.calibration,
      startedAt: now,
      windowMinutes: AppConfig.analysisWindowMinutes,
    );
    await saveCalibration(
      CalibrationProfile(
        id: _uuid.v4(),
        bikeId: bike.id,
        rideId: rideId,
        calibratedAt: now,
        params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
        forwardFromMotion: false,
        straightOffsetDeg: 0,
        quality: 0,
        skippedTasks: [for (final t in CalibrationTask.values) t.name],
        warnings: const ['Test setup: nothing was calibrated.'],
      ),
    );
  }

  Future<void> setLastRide(RideSummary summary) async {
    _lastRide = summary;
    await _store.setLastRide(summary);
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    _apiUrl = url.trim();
    await _store.setApiUrl(_apiUrl);
    notifyListeners();
  }
}
