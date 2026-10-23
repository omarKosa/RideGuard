import 'dart:math' as math;

/// Immutable 3D vector used for sensor readings and mount axes.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  factory Vec3.fromList(List<dynamic> values) {
    if (values.length != 3) {
      throw ArgumentError.value(values, 'values', 'expected 3 components');
    }
    return Vec3(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
      (values[2] as num).toDouble(),
    );
  }

  static const zero = Vec3(0, 0, 0);
  static const unitX = Vec3(1, 0, 0);
  static const unitY = Vec3(0, 1, 0);
  static const unitZ = Vec3(0, 0, 1);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => math.sqrt(dot(this));

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  Vec3 normalized() {
    final len = length;
    if (len < 1e-9) return Vec3.zero;
    return this / len;
  }

  /// Component of this vector perpendicular to [unitAxis].
  Vec3 rejectFrom(Vec3 unitAxis) => this - unitAxis * dot(unitAxis);

  /// Angle in radians between this vector and [o].
  double angleTo(Vec3 o) {
    final denom = length * o.length;
    if (denom < 1e-12) return 0;
    return math.acos((dot(o) / denom).clamp(-1.0, 1.0));
  }

  /// Linear blend towards [o]; t=0 is this, t=1 is [o].
  Vec3 lerp(Vec3 o, double t) => this + (o - this) * t;

  /// Rotates this vector about [unitAxis] by [angle] radians (Rodrigues).
  Vec3 rotated(Vec3 unitAxis, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return this * c +
        unitAxis.cross(this) * s +
        unitAxis * (unitAxis.dot(this) * (1 - c));
  }

  List<double> toList() => [x, y, z];

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}
