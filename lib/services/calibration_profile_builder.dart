import '../core/calibration/calibration_session.dart';
import '../core/fusion/motion_pipeline.dart';
import '../models/calibration_profile.dart';
import '../models/ride_summary.dart';

/// Turns a finished init ride into a [CalibrationProfile], scoring its
/// quality and explaining anything that was skipped or guessed.
CalibrationProfile? buildCalibrationProfile({
  required String id,
  required String bikeId,
  required RideSummary summary,
  required CalibrationSession session,
  required MotionPipeline pipeline,
  required DateTime calibratedAt,
}) {
  final params = pipeline.params;
  if (params == null) return null;

  final warnings = List<String>.of(session.warnings);
  var quality = 1.0;
  if (!pipeline.forwardLearned) {
    quality -= 0.3;
    warnings.add(
      'Riding direction was guessed from the phone position. '
      'It is learned automatically the next time you accelerate or brake '
      'in a straight line.',
    );
  }
  for (final task in session.skippedTasks) {
    switch (task) {
      case CalibrationTask.straightLine:
        quality -= 0.2;
        warnings.add(
          'Upright reference only from standing still; it is '
          'refined while riding straight.',
        );
      case CalibrationTask.topSpeed:
        quality -= 0.05;
      case CalibrationTask.brakeStop:
        quality -= 0.1;
        warnings.add(
          'No brake test: stop times use a default '
          '${CalibrationProfile.defaultDecelMps2} m/s².',
        );
      case CalibrationTask.leanTurns:
        quality -= 0.15;
        warnings.add('Lean test skipped: lean scale not verified.');
      case CalibrationTask.holdStill:
        break;
    }
  }
  if (session.forwardFlipped) {
    warnings.add('Riding direction was corrected by the lean test.');
  }

  return CalibrationProfile(
    id: id,
    bikeId: bikeId,
    rideId: summary.rideId,
    calibratedAt: calibratedAt,
    params: params,
    forwardFromMotion: pipeline.forwardLearned,
    straightOffsetDeg: pipeline.snapshot().straightOffsetDeg,
    quality: quality.clamp(0.0, 1.0),
    achievedTopSpeedKmh: session.achievedTopSpeedKmh,
    brakeEvent: session.brakeEvent,
    skippedTasks: [for (final t in session.skippedTasks) t.name],
    warnings: warnings,
  );
}
