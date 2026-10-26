/// When the rider may mark an order delivered.
class DeliveryRules {
  /// Straight-line distance from the order's location that unlocks the Delivered button.
  static const double radiusMeters = 400.0;

  /// Most GPS error (the phone's reported accuracy) given to the rider's benefit.
  static const double maxGpsSlackMeters = 50.0;

  /// [distanceMeters] is from the rider to the order's own location (null = no GPS fix yet).
  /// An order without a location cannot be checked, so it is not locked.
  static bool canDeliver({
    required bool orderHasLocation,
    required double? distanceMeters,
    double? gpsAccuracyMeters,
  }) {
    if (!orderHasLocation) return true;
    if (distanceMeters == null) return false;
    final slack = (gpsAccuracyMeters ?? 0.0).clamp(0.0, maxGpsSlackMeters);
    return distanceMeters - slack <= radiusMeters;
  }
}
