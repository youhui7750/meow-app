import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class CurrentMapPosition {
  final double latitude;
  final double longitude;

  const CurrentMapPosition({required this.latitude, required this.longitude});
}

CurrentMapPosition? _lastPosition;
DateTime? _lastPositionTime;

Future<CurrentMapPosition?> getCurrentMapPosition() async {
  final now = DateTime.now();
  final cachedAt = _lastPositionTime;
  final cachedPosition = _lastPosition;
  if (cachedAt != null &&
      cachedPosition != null &&
      now.difference(cachedAt) < const Duration(seconds: 20)) {
    return cachedPosition;
  }

  final completer = Completer<CurrentMapPosition?>();

  void completeOnce(CurrentMapPosition? position) {
    if (!completer.isCompleted) {
      if (position != null) {
        _lastPosition = position;
        _lastPositionTime = DateTime.now();
      }
      completer.complete(position);
    }
  }

  try {
    web.window.navigator.geolocation.getCurrentPosition(
      (web.GeolocationPosition position) {
        final coords = position.coords;
        completeOnce(
          CurrentMapPosition(
            latitude: coords.latitude,
            longitude: coords.longitude,
          ),
        );
      }.toJS,
      (web.GeolocationPositionError error) {
        debugPrint(
          'CurrentMapPosition(web): geolocation failed '
          'code=${error.code}, message=${error.message}',
        );
        completeOnce(null);
      }.toJS,
      web.PositionOptions(
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 15000,
      ),
    );
  } catch (error) {
    debugPrint('CurrentMapPosition(web): geolocation threw $error');
    completeOnce(null);
  }

  return completer.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () {
      debugPrint('CurrentMapPosition(web): geolocation timed out');
      return null;
    },
  );
}
