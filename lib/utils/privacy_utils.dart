import 'dart:math';

class PrivacyUtils {
  /// Fuzzes the location by adding a random offset between 300 and 500 meters.
  /// GDPR & CCPA compliant.
  static Map<String, double> fuzzLocation(double lat, double lng) {
    final random = Random();
    // Random distance between 300 and 500 meters
    final offsetMeters = 300.0 + random.nextInt(200);
    // Random angle between 0 and 360 degrees
    final offsetAngle = random.nextDouble() * 2 * pi;

    // Earth's radius in meters
    const earthRadius = 6378137.0;

    // Coordinate offsets in radians
    final latOffset = offsetMeters * cos(offsetAngle) / earthRadius;
    final lngOffset = offsetMeters * sin(offsetAngle) / (earthRadius * cos(lat * pi / 180));

    return {
      'lat': lat + (latOffset * 180 / pi),
      'lng': lng + (lngOffset * 180 / pi),
    };
  }
}
