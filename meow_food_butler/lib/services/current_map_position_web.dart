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
        // High accuracy forces a GPS-grade fix that browsers (especially on
        // desktop) often can't satisfy in time, yielding code=3 timeouts.
        // A coarse network/Wi-Fi fix is plenty for "near me" lookups.
        enableHighAccuracy: false,
        timeout: 15000,
        // Accept a recently cached browser fix (up to 5 min) to skip the
        // round-trip entirely when one is available.
        maximumAge: 300000,
      ),
    );
  } catch (error) {
    debugPrint('CurrentMapPosition(web): geolocation threw $error');
    completeOnce(null);
  }

  return completer.future.timeout(
    const Duration(seconds: 17),
    onTimeout: () {
      debugPrint('CurrentMapPosition(web): geolocation timed out');
      return null;
    },
  );
}
