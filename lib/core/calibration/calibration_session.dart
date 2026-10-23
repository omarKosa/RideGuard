import 'dart:math' as math;

import '../../models/brake_event.dart';
import '../analysis/brake_detector.dart';
import '../fusion/estimators.dart';
import '../fusion/motion_pipeline.dart';

enum CalibrationTask {
  holdStill(
    title: 'Hold still',
    instruction:
        'Bike upright and OFF the side stand, phone in its final '
        'mount. Engine may run. Do not touch the phone.',
    skippable: false,
  ),
  straightLine(
    title: 'Ride straight',
    instruction:
        'Ride in a straight line at a steady 20+ km/h. This teaches '
        'the app what "upright" reads like with your mount.',
  ),
  topSpeed(
    title: 'Top speed run',
    instruction:
        'Only on a closed track or empty, legal road: build up to '
        'the fastest speed you can SAFELY reach, then ease off.',
  ),
  brakeStop(
    title: 'Brake to a stop',
    instruction:
        'From 30+ km/h, brake firmly - not an emergency stop - all '
        'the way to a standstill, upright and in a straight line.',
  ),
  leanTurns(
    title: 'Lean test',
    instruction:
        'Ride a few relaxed curves or a figure-eight: at least one '
        'clear LEFT and one clear RIGHT turn at 15+ km/h.',
  );

  const CalibrationTask({
    required this.title,
    required this.instruction,
    this.skippable = true,
  });

  final String title;
  final String instruction;
  final bool skippable;
}

enum TaskState { pending, active, done, skipped }

/// Guides the init ride task by task, deciding automatically when each task
/// is complete so the rider never has to touch the phone while moving.
class CalibrationSession {
  CalibrationSession({required this.pipeline, required this.ratedTopSpeedKmh}) {
    _states[CalibrationTask.values.first] = TaskState.active;
  }

  static const double stillSeconds = 4;
  static const double straightSeconds = 8;
  static const double minStraightKmh = 20;
  static const double minTopSpeedKmh = 40;
  static const double minBrakeStartKmh = 25;
  static const double turnLeanDeg = 8;
  static const double turnHoldSeconds = 1.5;
  static const double minTurnKmh = 15;

  final MotionPipeline pipeline;
  final double ratedTopSpeedKmh;

  final Map<CalibrationTask, TaskState> _states = {
    for (final t in CalibrationTask.values) t: TaskState.pending,
  };
  int _index = 0;
  double? _lastT;

  double _progress = 0;
  String _detail = '';

  // Measurements.
  double _straightTime = 0;
  double _peakSpeed = 0;
  double _backedOffFor = 0;
  final BrakeDetector _brakes = BrakeDetector(
    minStartSpeedKmh: minBrakeStartKmh,
  );
  BrakeEvent? _bestBrake;
  int _leftTurns = 0;
  int _rightTurns = 0;
  int _turnSign = 0;
  double _turnHeld = 0;
  bool _turnCounted = false;
  double _gyroLean = 0;
  double _physAtStraight = 0;
  final List<(double, double)> _gainPairs = [];
  double? _fittedGain;
  bool _forwardFlipped = false;

  final List<String> warnings = [];

  Map<CalibrationTask, TaskState> get states => Map.unmodifiable(_states);
  bool get isFinished => _index >= CalibrationTask.values.length;
  CalibrationTask? get current =>
      isFinished ? null : CalibrationTask.values[_index];

  /// 0..1 progress of the current task.
  double get progress => _progress;

  /// Live, task-specific status line.
  String get detail => _detail;

  double? get achievedTopSpeedKmh => _peakSpeed > 0 ? _peakSpeed : null;
  BrakeEvent? get brakeEvent => _bestBrake;
  int get leftTurns => _leftTurns;
  int get rightTurns => _rightTurns;
  double? get fittedGain => _fittedGain;
  bool get forwardFlipped => _forwardFlipped;

  List<CalibrationTask> get skippedTasks => [
    for (final e in _states.entries)
      if (e.value == TaskState.skipped) e.key,
  ];

  void update(MotionState s, DateTime now) {
    final dt = _lastT == null ? 0.0 : (s.t - _lastT!).clamp(0.0, 1.0);
    _lastT = s.t;

    // These run in the background so a good top speed or stop made "early"
    // still counts.
    final task = current;
    if (task != null && task.index >= CalibrationTask.topSpeed.index) {
      if (s.speedReliable) _peakSpeed = math.max(_peakSpeed, s.speedKmh);
      final event = _brakes.add(now, s.speedKmh);
      if (event != null &&
          (_bestBrake == null ||
              event.peakDecelMps2 > _bestBrake!.peakDecelMps2)) {
        _bestBrake = event;
      }
    }

    switch (task) {
      case null:
        return;
      case CalibrationTask.holdStill:
        _updateHoldStill(s);
      case CalibrationTask.straightLine:
        _updateStraight(s, dt);
      case CalibrationTask.topSpeed:
        _updateTopSpeed(s, dt);
      case CalibrationTask.brakeStop:
        _updateBrake(s);
      case CalibrationTask.leanTurns:
        _updateTurns(s, dt);
    }
  }

  void skip() {
    final task = current;
    if (task == null || !task.skippable) return;
    _states[task] = TaskState.skipped;
    _advance();
  }

  // ------------------------------------------------------------------ tasks

  void _updateHoldStill(MotionState s) {
    final still = s.isStill && s.speedKmh < 2;
    final held = still ? s.stillFor : 0.0;
    _progress = (held / stillSeconds).clamp(0.0, 1.0);
    _detail = still
        ? 'Hold it... ${held.toStringAsFixed(1)} / ${stillSeconds.toInt()} s'
        : 'Movement detected - keep the bike and phone still';
    if (held >= stillSeconds && pipeline.captureStillReference()) _complete();
  }

  void _updateStraight(MotionState s, double dt) {
    if (!s.speedReliable) {
      _detail = 'Waiting for GPS speed...';
      return;
    }
    final qualifies =
        s.speedKmh >= minStraightKmh &&
        s.yawRate.abs() < 0.05 &&
        s.forwardAccel.abs() < 1.0;
    if (qualifies) _straightTime += dt;
    _progress = (_straightTime / straightSeconds).clamp(0.0, 1.0);
    _detail = s.speedKmh < minStraightKmh
        ? 'Speed up to ${minStraightKmh.toInt()}+ km/h'
        : qualifies
        ? 'Good - hold it straight '
              '(${_straightTime.toStringAsFixed(1)} / ${straightSeconds.toInt()} s)'
        : 'Keep it straight and steady';
    if (_straightTime >= straightSeconds) _complete();
  }

  void _updateTopSpeed(MotionState s, double dt) {
    final pct = ratedTopSpeedKmh <= 0 ? 0.0 : _peakSpeed / ratedTopSpeedKmh;
    _progress = pct.clamp(0.0, 1.0);
    final backingOff =
        _peakSpeed >= minTopSpeedKmh && s.speedKmh < _peakSpeed * 0.8;
    _backedOffFor = backingOff ? _backedOffFor + dt : 0;
    _detail =
        'Peak ${_peakSpeed.toStringAsFixed(0)} km/h · '
        '${(pct * 100).toStringAsFixed(0)}% of ${ratedTopSpeedKmh.toStringAsFixed(0)}';
    if (_backedOffFor >= 2 || pct >= 0.98) _complete();
  }

  void _updateBrake(MotionState s) {
    final best = _bestBrake;
    if (best != null) {
      _progress = 1;
      _complete();
      return;
    }
    _progress = _brakes.isBraking ? 0.5 : 0;
    _detail = _brakes.isBraking
        ? 'Braking... all the way to a stop'
        : s.speedKmh < 30
        ? 'Get to 30+ km/h, then brake to a full stop'
        : 'Now brake firmly to a full stop';
  }

  void _updateTurns(MotionState s, double dt) {
    final phys = s.physicsLeanDeg;
    _gyroLean += radToDeg(s.rollRate) * dt;

    // Re-anchor the gyro integral whenever we are riding straight.
    if (phys.abs() < 2 && s.yawRate.abs() < 0.05) {
      _gyroLean = 0;
      _physAtStraight = phys;
    }

    final sign = s.speedKmh >= minTurnKmh && phys.abs() >= turnLeanDeg
        ? phys.sign.toInt()
        : 0;
    if (sign != 0 && sign == _turnSign) {
      _turnHeld += dt;
    } else if (phys.abs() < 3 || sign != 0) {
      _turnSign = sign;
      _turnHeld = 0;
      _turnCounted = false;
    }

    if (_turnSign != 0 && !_turnCounted && _turnHeld >= turnHoldSeconds) {
      _turnCounted = true;
      if (_turnSign < 0) {
        _leftTurns++;
      } else {
        _rightTurns++;
      }
      _gainPairs.add((_gyroLean, phys - _physAtStraight));
    }

    final have = math.min(_leftTurns, 1) + math.min(_rightTurns, 1);
    _progress = have / 2;
    _detail = 'Left turns: $_leftTurns · Right turns: $_rightTurns';
    if (_leftTurns >= 1 && _rightTurns >= 1) {
      _fitGain();
      _complete();
    }
  }

  /// Least-squares fit of gyro-integrated lean to physics lean. A negative
  /// slope means the learned forward axis points backwards.
  void _fitGain() {
    var sxy = 0.0, sxx = 0.0;
    for (final (gyro, phys) in _gainPairs) {
      sxy += gyro * phys;
      sxx += gyro * gyro;
    }
    if (sxx < 1) {
      warnings.add('Lean test too gentle to verify the gyro scale.');
      return;
    }
    var gain = sxy / sxx;
    if (gain < 0) {
      pipeline.flipForward();
      _forwardFlipped = true;
      gain = -gain;
    }
    if (gain < 0.7 || gain > 1.4) {
      warnings.add(
        'Lean test was inconsistent (gain '
        '${gain.toStringAsFixed(2)}); using the raw gyro scale.',
      );
      return;
    }
    _fittedGain = gain;
    pipeline.setLeanGain(gain);
  }

  void _complete() {
    _states[current!] = TaskState.done;
    _advance();
  }

  void _advance() {
    _index++;
    _progress = 0;
    _detail = '';
    final next = current;
    if (next != null) _states[next] = TaskState.active;
  }
}
