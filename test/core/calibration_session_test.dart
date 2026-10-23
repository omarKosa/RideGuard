import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/calibration/calibration_session.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';

import '../support/ride_simulator.dart';

void main() {
  ({CalibrationSession session, MotionPipeline p, RideSimulator sim}) setUpRun(
    Mount mount,
  ) {
    final p = MotionPipeline(learningMode: true);
    final session = CalibrationSession(pipeline: p, ratedTopSpeedKmh: 160);
    final sim = RideSimulator(mount: mount);
    return (session: session, p: p, sim: sim);
  }

  void Function(SimTick) feed(CalibrationSession s) =>
      (tick) => s.update(tick.state, tick.time);

  test('a complete init ride passes every task and measures the rider', () {
    final r = setUpRun(Mount.handlebarPortrait);
    final s = r.session, p = r.p, sim = r.sim;

    sim.still(p, 6, onTick: feed(s));
    expect(s.states[CalibrationTask.holdStill], TaskState.done);

    sim.accelerateTo(p, 40, onTick: feed(s));
    sim.cruise(p, 12, onTick: feed(s));
    expect(s.states[CalibrationTask.straightLine], TaskState.done);

    sim.accelerateTo(p, 142, accel: 3, onTick: feed(s));
    sim.accelerateTo(p, 60, accel: 1.0, onTick: feed(s));
    sim.cruise(p, 3, onTick: feed(s));
    expect(s.states[CalibrationTask.topSpeed], TaskState.done);
    expect(s.achievedTopSpeedKmh, closeTo(142, 3));

    sim.brakeToStop(p, decel: 6.5, onTick: feed(s));
    sim.still(p, 1, onTick: feed(s));
    expect(s.states[CalibrationTask.brakeStop], TaskState.done);
    final brake = s.brakeEvent!;
    expect(brake.startSpeedKmh, closeTo(60, 4));
    expect(brake.durationS, closeTo(60 / 3.6 / 6.5, 1.2));
    expect(brake.peakDecelMps2, closeTo(6.5, 1.5));

    sim.accelerateTo(p, 40, onTick: feed(s));
    sim.turn(p, -20, 6, onTick: feed(s));
    sim.cruise(p, 3, onTick: feed(s));
    sim.turn(p, 22, 6, onTick: feed(s));
    sim.cruise(p, 2, onTick: feed(s));

    expect(s.isFinished, isTrue);
    expect(s.leftTurns, greaterThanOrEqualTo(1));
    expect(s.rightTurns, greaterThanOrEqualTo(1));
    expect(s.fittedGain, closeTo(1.0, 0.2));
    expect(s.forwardFlipped, isFalse);
    expect(s.skippedTasks, isEmpty);
    expect(p.forwardLearned, isTrue);

    // The learned forward axis matches the real mount.
    final learnedForward = p.mount!.forward;
    expect(
      learnedForward.angleTo(Mount.handlebarPortrait.forwardInPhone),
      lessThan(0.1),
    );
  });

  test('hold-still cannot be skipped and waits for real stillness', () {
    final r = setUpRun(Mount.euler(10, 30, 50));
    r.session.skip();
    expect(r.session.current, CalibrationTask.holdStill);
    r.sim.accelerateTo(r.p, 20, onTick: feed(r.session));
    expect(r.session.current, CalibrationTask.holdStill);
  });

  test('skipping optional tasks still finishes the session', () {
    final r = setUpRun(Mount.handlebarPortrait);
    r.sim.still(r.p, 6, onTick: feed(r.session));
    for (var i = 0; i < 4; i++) {
      r.session.skip();
    }
    expect(r.session.isFinished, isTrue);
    expect(r.session.skippedTasks, hasLength(4));
  });

  test('a backwards forward axis is detected by the lean test and fixed', () {
    final r = setUpRun(Mount.handlebarPortrait);
    final s = r.session, p = r.p, sim = r.sim;
    sim.still(p, 6, onTick: feed(s));
    s.skip(); // straight
    s.skip(); // top speed
    s.skip(); // brake
    sim.accelerateTo(p, 40, onTick: feed(s));
    sim.cruise(p, 2, onTick: feed(s));
    // Pretend forward was learned the wrong way round. (A flip before
    // accelerating is already undone by the forward-axis learner.)
    p.flipForward();
    sim.turn(p, -20, 6, onTick: feed(s));
    sim.cruise(p, 3, onTick: feed(s));
    sim.turn(p, 22, 6, onTick: feed(s));
    expect(s.isFinished, isTrue);
    expect(s.forwardFlipped, isTrue);
    expect(
      p.mount!.forward.angleTo(Mount.handlebarPortrait.forwardInPhone),
      lessThan(0.15),
    );
  });
}
