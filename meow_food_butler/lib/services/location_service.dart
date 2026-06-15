import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Reusable GPS + permission helper.
///
/// The agent runs server-side and cannot read the device GPS, so the client
/// resolves coordinates here and sends them with the chat prompt. The first call
/// that needs permission triggers the OS/browser permission dialog (the
/// "permission check"); later calls return immediately once a decision is made.
class LocationService {
  /// Best-effort current coordinates, or `null` if location services are off,
  /// permission is denied, or a fix can't be obtained in time. Never throws —
  /// chat should still work without location.
  static Future<({double latitude, double longitude})?> tryGetLatLng() async {
    try {
      // On web `isLocationServiceEnabled()` always returns true; on mobile it
      // reflects the OS toggle.
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('LocationService: location services disabled.');
        return null;
      }
    } catch (e) {
      debugPrint('LocationService: isLocationServiceEnabled failed: $e');
    }

    // Permission: request if undecided. If the user previously blocked it
    // (denied/deniedForever), the browser/OS will NOT re-prompt — we can only
    // ask again once it's back to `denied`.
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('LocationService: permission check failed: $e');
      return null;
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('LocationService: permission not granted ($permission).');
      return null;
    }

    // Prefer a cached fix on mobile (instant, no GPS spin-up). NOT supported on
    // web — geolocator_web throws UnsupportedError, so skip it there.
    if (!kIsWeb) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return (latitude: last.latitude, longitude: last.longitude);
        }
      } catch (e) {
        debugPrint('LocationService: getLastKnownPosition skipped: $e');
      }
    }

    // Live fix. On web a coarse network fix is fine and avoids code=3 timeouts
    // that a GPS-grade (high accuracy) request triggers in desktop browsers.
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 17));
      return (latitude: pos.latitude, longitude: pos.longitude);
    } catch (e) {
      debugPrint('LocationService: getCurrentPosition failed: $e');
      return null;
    }
  }
}
