// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class CurrentMapPosition {
  final double latitude;
  final double longitude;

  const CurrentMapPosition({required this.latitude, required this.longitude});
}

Future<CurrentMapPosition?> getCurrentMapPosition() async {
  final geolocation = html.window.navigator.geolocation;
  final position = await geolocation.getCurrentPosition(
    enableHighAccuracy: true,
    timeout: const Duration(seconds: 10),
    maximumAge: const Duration(seconds: 15),
  );
  final coords = position.coords;
  if (coords == null) {
    return null;
  }

  final latitude = coords.latitude;
  final longitude = coords.longitude;

  if (latitude == null || longitude == null) {
    return null;
  }

  return CurrentMapPosition(
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
  );
}
