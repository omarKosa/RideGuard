import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/calibration/calibration_session.dart';
import '../core/fusion/motion_pipeline.dart';
import '../core/safety/safety_baseline.dart';
import '../core/safety/safety_monitor.dart';
import '../core/safety/safety_tuning.dart';
import '../models/calibration_profile.dart';
import '../models/ride_summary.dart';
import 'app_state.dart';
import 'calibration_profile_builder.dart';
import 'keep_awake.dart';
import 'ride_recorder.dart';
import 'safety_controller.dart';
import 'sensor_feed.dart';

enum CalibrationPhase { idle, starting, running, finished, aborted }

/// Runs the init (calibration) ride: sensors -> learning pipeline ->
/// guided tasks -> [CalibrationProfile]. The ride's samples are uploaded
/// like any other ride, tagged as a calibration ride.
class CalibrationController extends ChangeNotifier {
  CalibrationController({
    required AppState app,
    required SensorFeed feed,
    SafetyController? safety,
    DateTime Function()? clock,
    KeepAwake? keepAwake,
  }) : _app = app,
       _feed = feed,
       _safety = safety,
       _clock = clock ?? DateTime.now,
       _keepAwake = keepAwake ?? keepScreenAwake;

  final AppState _app;
  final SensorFeed _feed;
  final SafetyController? _safety;
  final DateTime Function() _clock;
  final KeepAwake _keepAwake;
  static const _uuid = Uuid();

  MotionPipeline? _pipeline;
  CalibrationSession? _session;
  RideRecorder? _recorder;
  SafetyMonitor? _monitor;
  RideNoise? _noise;
  SafetyBaseline? _safetyBaseline;
  MotionState? _state;
  CalibrationProfile? _result;
  CalibrationTask? _lastTask;
  CalibrationPhase _phase = CalibrationPhase.idle;
  bool _finishing = false;
  bool _disposed = false;

  CalibrationSession? get session => _session;
  MotionState? get state => _state;
  CalibrationProfile? get result => _result;

  /// What the init ride learned about normal riding on this mount; saved
  /// with the calibration.
  SafetyBaseline? get safetyBaseline => _safetyBaseline;
  CalibrationPhase get phase => _phase;

  /// Sensors are live (starting up or recording).
  bool get running =>
      _phase == CalibrationPhase.starting || _phase == CalibrationPhase.running;
  bool get gpsAvailable => _feed.gpsAvailable;
  String? get sensorError => _feed.sensorError;

  Future<void> start() async {
    final bike = _app.bike;
    if (bike == null) throw StateError('Set up a bike before calibrating');
    _phase = CalibrationPhase.starting;
    _notify();
    final pipeline = MotionPipeline(learningMode: true);
    _pipeline = pipeline;
    _session = CalibrationSession(
      pipeline: pipeline,
      ratedTopSpeedKmh: bike.ratedTopSpeedKmh,
    );
    _lastTask = _session!.current;
    _result = null;
    _recorder = RideRecorder(
      rideId: _uuid.v4(),
      kind: RideKind.calibration,
      bikeId: bike.id,
      remote: _app.remote,
      clock: _clock,
    );
    await _recorder!.start();
    // Best effort; never delay recording on a plugin call.
    unawaited(_keepAwake(true));
    // The top-speed run and the hard stop are the riskiest part of using the
    // app, so crash detection runs here too.
    final safety = _safety?..begin(_recorder!.rideId);
    // Possibly a new mount: start from default sensitivity.
    _monitor = safety == null ? null : SafetyMonitor(onHazard: safety.report);
    _noise = null;
    _safetyBaseline = null;
    await _feed.start(pipeline, _onTick, safety: _monitor);
    if (_phase == CalibrationPhase.starting) _phase = CalibrationPhase.running;
    _notify();
  }

  void skip() {
    _session?.skip();
    _afterUpdate();
  }

  Future<void> abort() async {
    if (!running) return;
    _phase = CalibrationPhase.aborted;
    await _stop(RideStatus.aborted);
    _notify();
  }

  void _onTick(MotionState s) {
    final session = _session;
    if (session == null || _phase != CalibrationPhase.running) return;
    _state = s;
    _recorder?.record(s);
    session.update(s, _clock());
    _afterUpdate();
  }

  void _afterUpdate() {
    final session = _session;
    if (session == null) return;
    if (session.current != _lastTask) {
      _lastTask = session.current;
      // Feel the progress without looking at the phone.
      HapticFeedback.heavyImpact();
    }
    if (session.isFinished && running && !_finishing) {
      _finishing = true;
      _complete();
    }
    _notify();
  }

  Future<void> _complete() async {
    final summary = await _stop(RideStatus.completed);
    _result = _buildProfile(summary);
    _phase = CalibrationPhase.finished;
    _finishing = false;
    _notify();
  }

  Future<RideSummary?> _stop(RideStatus status) async {
    await _feed.stop();
    _safety?.end();
    unawaited(_keepAwake(false));
    final noise = _noise = _monitor?.takeNoise();
    return _recorder?.finish(
      status: status,
      safetyStats: noise?.toApiJson(SafetyTuning.defaults),
    );
  }

  /// Saves the result as the active calibration, with what was learned
  /// about this mount's vibration.
  Future<void> accept() async {
    final result = _result;
    if (result == null) return;
    await _app.saveCalibration(result);
    await _app.saveSafetyBaseline(
      _safetyBaseline ?? SafetyBaseline(calibrationId: result.id),
    );
  }

  CalibrationProfile? _buildProfile(RideSummary? summary) {
    final bike = _app.bike;
    if (bike == null || summary == null) return null;
    final id = _uuid.v4();
    final noise = _noise;
    final baseline = noise == null
        ? null
        : SafetyBaseline(calibrationId: id).withRide(noise);
    _safetyBaseline = baseline;
    return buildCalibrationProfile(
      id: id,
      bikeId: bike.id,
      summary: summary,
      session: _session!,
      pipeline: _pipeline!,
      calibratedAt: _clock(),
      extraWarnings: [
        if (baseline != null &&
            baseline.ridingSeconds < SafetyBaseline.minRidingSeconds)
          'Not enough riding at 20+ km/h to learn how this mount vibrates: '
              'safety alerts start at default sensitivity and adapt as you '
              'ride.',
        ...?baseline?.tuning.warnings,
      ],
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (running) {
      _phase = CalibrationPhase.aborted;
      _feed.stop();
      _safety?.end();
      unawaited(_keepAwake(false));
      _recorder?.finish(status: RideStatus.aborted);
    }
    super.dispose();
  }
}
