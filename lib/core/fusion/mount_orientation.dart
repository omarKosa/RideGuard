import 'dart:math' as math;

import '../math/vec3.dart';

/// How the phone sits on the bike: the bike's up and forward axes expressed
/// in the phone's own sensor frame.
///
/// Every sensor reading is projected onto these axes, so lean, yaw and
/// forward acceleration come out the same no matter how the phone is
/// mounted (portrait on the bars, flat on the tank, sideways, upside down).
class MountOrientation {
  MountOrientation._(this.up, this.forward);

  /// Builds an orthonormal mount from a measured [up] (gravity reaction while
  /// upright) and a rough forward direction, which is projected onto the
  /// horizontal plane.
  factory MountOrientation.fromUpAndForward(Vec3 up, Vec3 forwardHint) {
    final u = up.normalized();
    if (u == Vec3.zero) {
      throw ArgumentError.value(up, 'up', 'must be non-zero');
    }
    var f = forwardHint.rejectFrom(u);
    if (f.length < 1e-3) f = provisionalForwardHint(u).rejectFrom(u);
    return MountOrientation._(u, f.normalized());
  }

  /// Mount with a guessed forward axis, used until forward is learned from
  /// acceleration.
  factory MountOrientation.provisional(Vec3 up) =>
      MountOrientation.fromUpAndForward(up, provisionalForwardHint(up));

  factory MountOrientation.fromJson(Map<String, dynamic> json) =>
      MountOrientation.fromUpAndForward(
        Vec3.fromList(json['up'] as List<dynamic>),
        Vec3.fromList(json['forward'] as List<dynamic>),
      );

  /// Typical mounts: portrait on the bars with the screen facing the rider
  /// (forward is out of the back of the phone, -z) or flat on the tank
  /// (forward is the top edge, +y). Pick whichever is more horizontal.
  static Vec3 provisionalForwardHint(Vec3 up) {
    const back = Vec3(0, 0, -1);
    const top = Vec3(0, 1, 0);
    final u = up.normalized();
    return back.rejectFrom(u).length >= top.rejectFrom(u).length ? back : top;
  }

  /// Unit vector, phone frame, pointing up when the bike is upright.
  final Vec3 up;

  /// Unit vector, phone frame, pointing towards the front wheel.
  final Vec3 forward;

  /// Unit vector, phone frame, pointing to the rider's right.
  Vec3 get right => forward.cross(up);

  double forwardOf(Vec3 v) => v.dot(forward);
  double rightOf(Vec3 v) => v.dot(right);
  double upOf(Vec3 v) => v.dot(up);

  /// Lean (radians, + = right) implied by a gravity reaction reading. Only
  /// meaningful when the bike is not turning or accelerating.
  double rollOf(Vec3 gravity) => math.atan2(-rightOf(gravity), upOf(gravity));

  /// Pitch (radians, + = nose up) implied by a gravity reaction reading.
  double pitchOf(Vec3 gravity) => math.atan2(forwardOf(gravity), upOf(gravity));

  MountOrientation withUp(Vec3 newUp) =>
      MountOrientation.fromUpAndForward(newUp, forward);

  MountOrientation withForward(Vec3 forwardHint) =>
      MountOrientation.fromUpAndForward(up, forwardHint);

  /// Same up axis, forward reversed. Used when the lean test shows the
  /// learned forward axis points backwards.
  MountOrientation flipped() => MountOrientation._(up, -forward);

  /// Angle between the phone's screen normal and the bike's up axis, i.e.
  /// how far from "flat on the tank" the phone is mounted. Purely
  /// informational.
  double get screenTiltDeg => up.angleTo(Vec3.unitZ) * 180 / math.pi;

  Map<String, dynamic> toJson() => {
    'up': up.toList(),
    'forward': forward.toList(),
  };
}
