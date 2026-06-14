import 'package:geolocator/geolocator.dart';

class DistanceService {
  const DistanceService._();

  static double? metersBetween({
    required double? fromLatitude,
    required double? fromLongitude,
    required double? toLatitude,
    required double? toLongitude,
  }) {
    if (fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      fromLatitude,
      fromLongitude,
      toLatitude,
      toLongitude,
    );
  }

  static String? formatMeters(double? meters) {
    if (meters == null) return null;
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static Map<String, dynamic>? toAiDistancePayload(double? meters) {
    final label = formatMeters(meters);
    if (meters == null || label == null) return null;

    return {
      'distanceMeters': meters.round(),
      'distanceLabel': label,
    };
  }
}
