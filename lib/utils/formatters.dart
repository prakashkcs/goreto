class Formatters {
  /// Formats distance string (in km) to a user-friendly format.
  /// If < 1km, shows in meters (e.g. "500 m").
  /// If >= 1km, shows in km without decimals (e.g. "2 km").
  static String formatDistance(String? distanceKm) {
    if (distanceKm == null || 
        distanceKm == 'null' || 
        distanceKm.isEmpty || 
        distanceKm == '?') {
      return '? km';
    }

    final double? distance = double.tryParse(distanceKm);
    if (distance == null) return '$distanceKm km';

    if (distance < 1.0) {
      final int meters = (distance * 1000).round();
      // Avoid "0 m" if it's actually just very small but not 0
      if (meters <= 0 && distance > 0) return '1 m';
      return '$meters m';
    } else if (distance < 10.0) {
      // One decimal for nearby distances — truncating to whole km made
      // e.g. 2.7 km show as "2 km" (~1 km error).
      return '${distance.toStringAsFixed(1)} km';
    } else {
      return '${distance.round()} km';
    }
  }
}
