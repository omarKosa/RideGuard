import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/analysis/ride_analyzer.dart';
import '../core/fusion/motion_pipeline.dart';
import '../models/brake_event.dart';
import '../models/calibration_profile.dart';
import '../models/ride_sample.dart';
import '../models/ride_summary.dart';
import 'app_state.dart';
import 'keep_awake.dart';
import 'ride_recorder.dart';
import 'sensor_feed.dart';

/// A regular ride using the saved calibration.
class RideController extends ChangeNotifier {
  RideController({
    required AppState app,
    required SensorFeed feed,
    DateTime Function()? clock,
    KeepAwake? keepAwake,
  }) : _app = app,
       _feed = feed,
       _clock = clock ?? DateTime.now,
       _keepAwake = keepAwake ?? keepScreenAwake;

  /// Speed/lean chart span on the ride screen.
  static const chartSpan = Duration(minutes: 2);

  final AppState _app;
  final SensorFeed _feed;
  final DateTime Function() _clock;
  final KeepAwake _keepAwake;
  static const _uuid = Uuid();

  RideRecorder? _recorder;
  CalibrationProfile? _calibration;
  MotionState? _state;
  RideStats _window = const RideStats();
  RideStats _totals = const RideStats();
  List<RideSample> _chart = const [];
  BrakeEvent? _lastBrake;
  bool _riding = false;
  bool _disposed = false;
  int _ticks = 0;

  bool get riding => _riding;
  MotionState? get state => _state;
  RideStats get window => _window;
  RideStats get totals => _totals;
  List<RideSample> get chart => _chart;
  BrakeEvent? get lastBrake => _lastBrake;
  bool get gpsAvailable => _feed.gpsAvailable;
  String? get sensorError => _feed.sensorError;
  DateTime? get startedAt => _recorder?.startedAt;
  Duration get elapsed =>
      startedAt == null ? Duration.zero : _clock().difference(startedAt!);

  /// Time to stop from the current speed at the rider's measured braking.
  double get estimatedStopTimeS {
    final speed = _state?.speedKmh ?? 0;
    return _calibration?.estimatedStopTimeS(speed) ??
        (speed / 3.6) / CalibrationProfile.defaultDecelMps2;
  }

  Future<void> start() async {
    final bike = _app.bike;
    final calibration = _app.calibration;
    if (bike == null || calibration == null) {
      throw StateError('Calibrate before riding');
    }
    _calibration = calibration;
    final recorder = RideRecorder(
      rideId: _uuid.v4(),
      kind: RideKind.ride,
      bikeId: bike.id,
      calibrationId: calibration.id,
      remote: _app.remote,
      clock: _clock,
    );
    _recorder = recorder;
    _window = const RideStats();
    _totals = const RideStats();
    _chart = const [];
    _lastBrake = null;
    _ticks = 0;
    await recorder.start();
    _riding = true;
    // Best effort; never delay recording on a plugin call.
    unawaited(_keepAwake(true));
    await _feed.start(MotionPipeline(params: calibration.params), _onTick);
    _notify();
  }

  void _onTick(MotionState s) {
    final recorder = _recorder;
    if (recorder == null || !_riding) return;
    _state = s;
    final brake = recorder.record(s);
    if (brake != null) _lastBrake = brake;
    // Full-window analysis once a second; live values every tick.
    if (_ticks++ % 10 == 0 || brake != null) _refreshAnalysis();
    _notify();
  }

  void _refreshAnalysis() {
    final analyzer = _recorder?.analyzer;
    if (analyzer == null) return;
    _window = analyzer.windowStats();
    _totals = analyzer.totals();
    _chart = analyzer.recent(chartSpan);
  }

  Future<RideSummary?> stop() async {
    final recorder = _recorder;
    if (!_riding || recorder == null) return null;
    _riding = false;
    await _feed.stop();
    unawaited(_keepAwake(false));
    final summary = await recorder.finish();
    await _app.setLastRide(summary);
    _notify();
    return summary;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_riding) {
      _riding = false;
      _feed.stop();
      unawaited(_keepAwake(false));
      _recorder?.finish(status: RideStatus.aborted);
    }
    super.dispose();
  }
}
