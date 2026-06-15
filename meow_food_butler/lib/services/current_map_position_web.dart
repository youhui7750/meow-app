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

  final currentPosition = await _getCurrentPosition(
    enableHighAccuracy: false,
    timeoutMilliseconds: 15000,
    maximumAgeMilliseconds: 600000,
  );
  if (currentPosition != null) return currentPosition;

  final precisePosition = await _getCurrentPosition(
    enableHighAccuracy: true,
    timeoutMilliseconds: 30000,
    maximumAgeMilliseconds: 0,
  );
  if (precisePosition != null) return precisePosition;

  // Desktop Chrome sometimes returns code=3 for getCurrentPosition even after
  // permission is granted. A short watchPosition fallback often receives the
  // next available network/Wi-Fi fix without asking permission again.
  return _watchForPosition();
}

Future<CurrentMapPosition?> _getCurrentPosition({
  required bool enableHighAccuracy,
  required int timeoutMilliseconds,
  required int maximumAgeMilliseconds,
}) {
  final completer = Completer<CurrentMapPosition?>();

  void completeOnce(CurrentMapPosition? position) {
    if (completer.isCompleted) return;
    _cachePosition(position);
    completer.complete(position);
  }

  try {
    web.window.navigator.geolocation.getCurrentPosition(
      (web.GeolocationPosition position) {
        completeOnce(_fromWebPosition(position));
      }.toJS,
      (web.GeolocationPositionError error) {
        debugPrint(
          'CurrentMapPosition(web): geolocation failed '
          'code=${error.code}, message=${error.message}',
        );
        completeOnce(null);
      }.toJS,
      web.PositionOptions(
        enableHighAccuracy: enableHighAccuracy,
        timeout: timeoutMilliseconds,
        maximumAge: maximumAgeMilliseconds,
      ),
    );
  } catch (error) {
    debugPrint('CurrentMapPosition(web): geolocation threw $error');
    completeOnce(null);
  }

  return completer.future.timeout(
    Duration(milliseconds: timeoutMilliseconds + 3000),
    onTimeout: () {
      debugPrint('CurrentMapPosition(web): geolocation timed out');
      return null;
    },
  );
}

Future<CurrentMapPosition?> _watchForPosition() {
  final completer = Completer<CurrentMapPosition?>();
  int? watchId;

  void finish(CurrentMapPosition? position) {
    if (completer.isCompleted) return;
    if (watchId != null) {
      web.window.navigator.geolocation.clearWatch(watchId!);
    }
    _cachePosition(position);
    completer.complete(position);
  }

  try {
    watchId = web.window.navigator.geolocation.watchPosition(
      (web.GeolocationPosition position) {
        finish(_fromWebPosition(position));
      }.toJS,
      (web.GeolocationPositionError error) {
        debugPrint(
          'CurrentMapPosition(web): watch failed '
          'code=${error.code}, message=${error.message}',
        );
        if (error.code == 3) return;
        finish(null);
      }.toJS,
      web.PositionOptions(
        enableHighAccuracy: true,
        timeout: 45000,
        maximumAge: 600000,
      ),
    );
  } catch (error) {
    debugPrint('CurrentMapPosition(web): watch threw $error');
    finish(null);
  }

  return completer.future.timeout(
    const Duration(seconds: 48),
    onTimeout: () {
      debugPrint('CurrentMapPosition(web): watch timed out');
      if (watchId != null) {
        web.window.navigator.geolocation.clearWatch(watchId!);
      }
      return null;
    },
  );
}

CurrentMapPosition _fromWebPosition(web.GeolocationPosition position) {
  final coords = position.coords;
  return CurrentMapPosition(
    latitude: coords.latitude,
    longitude: coords.longitude,
  );
}

void _cachePosition(CurrentMapPosition? position) {
  if (position == null) return;
  _lastPosition = position;
  _lastPositionTime = DateTime.now();
}
