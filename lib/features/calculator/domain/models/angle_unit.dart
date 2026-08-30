/// Angle unit applied to trigonometric and inverse trigonometric functions.
enum AngleUnit {
  degree('DEG'),
  radian('RAD');

  const AngleUnit(this.label);

  final String label;

  AngleUnit get toggled =>
      this == AngleUnit.degree ? AngleUnit.radian : AngleUnit.degree;

  /// Converts [value], expressed in this unit, into radians.
  double toRadians(double value) =>
      this == AngleUnit.radian ? value : value * 3.141592653589793 / 180.0;

  /// Converts [radians] into this unit.
  double fromRadians(double radians) =>
      this == AngleUnit.radian ? radians : radians * 180.0 / 3.141592653589793;
}
