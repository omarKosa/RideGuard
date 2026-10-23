import '../config/app_config.dart';
import '../core/analysis/ride_analyzer.dart';
import '../core/fusion/motion_pipeline.dart';
import '../data/remote_repository.dart';
import '../models/brake_event.dart';
import '../models/ride_sample.dart';
import '../models/ride_summary.dart';

/// Turns a stream of [MotionState]s into numbered samples, feeds the
/// rolling-window analyzer, and uploads samples in batches.
class RideRecorder {
  RideRecorder({
    required this.rideId,
    required this.kind,
    required this.bikeId,
    required RemoteRepository remote,
    this.calibrationId,
    DateTime Function()? clock,
  }) : _remote = remote,
       _clock = clock ?? DateTime.now,
       analyzer = RideAnalyzer(
         window: const Duration(minutes: AppConfig.analysisWindowMinutes),
       );

  final String rideId;
  final RideKind kind;
  final String bikeId;
  final String? calibrationId;
  final RemoteRepository _remote;
  final DateTime Function() _clock;
  final RideAnalyzer analyzer;

  final List<RideSample> _pending = [];
  DateTime? _startedAt;
  DateTime? _lastFlush;
  int _seq = 0;
  int _realignments = 0;

  DateTime? get startedAt => _startedAt;
  int get sampleCount => _seq;
  Future<void> start() async {
    final now = _clock();
    _startedAt = now;
    _lastFlush = now;
    await _remote.startRide(
      rideId: rideId,
      bikeId: bikeId,
      kind: kind,
      startedAt: now,
      windowMinutes: AppConfig.analysisWindowMinutes,
      calibrationId: calibrationId,
    );
  }

  /// Records one processed state. Returns a brake event if one completed.
  BrakeEvent? record(MotionState state) {
    final now = _clock();
    // Wall clocks can step backwards (NTP); keep the buffer ordered.
    final last = analyzer.buffer.last?.time;
    final time = last != null && !now.isAfter(last)
        ? last.add(const Duration(milliseconds: 1))
        : now;
    final sample = RideSample.fromState(_seq++, time, state);
    _realignments = state.mountRealignments;
    _pending.add(sample);
    final event = analyzer.add(sample);

    if (_pending.length >= AppConfig.uploadBatchSize ||
        time.difference(_lastFlush!) >= AppConfig.uploadInterval) {
      _flush(time);
    }
    return event;
  }

  void _flush(DateTime now) {
    _lastFlush = now;
    if (_pending.isEmpty) return;
    final batch = List<RideSample>.of(_pending);
    _pending.clear();
    _remote.addSamples(rideId, batch);
  }

  Future<RideSummary> finish({RideStatus status = RideStatus.completed}) async {
    final now = _clock();
    _flush(now);
    final summary = RideSummary(
      rideId: rideId,
      kind: kind,
      status: status,
      startedAt: _startedAt ?? now,
      endedAt: now,
      windowMinutes: AppConfig.analysisWindowMinutes,
      totals: analyzer.totals(),
      window: analyzer.windowStats(),
      brakeEvents: List.of(analyzer.events),
      mountRealignments: _realignments,
      sampleCount: _seq,
    );
    await _remote.finishRide(summary);
    return summary;
  }
}
