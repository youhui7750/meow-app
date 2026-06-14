/**
 * Small geo helpers shared by the location skills. No external deps — just real
 * math, so nothing here is mock.
 */

const EARTH_RADIUS_M = 6371000;
// Comfortable walking pace ~4.8 km/h ≈ 80 m/min.
const WALK_METERS_PER_MIN = 80;

const toRad = (deg) => (deg * Math.PI) / 180;

/** Great-circle distance in metres between two {latitude, longitude} points. */
function haversineMeters(a, b) {
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

/** Rough straight-line walking time in whole minutes (>= 1). */
function walkMinutes(meters) {
  return Math.max(1, Math.round(meters / WALK_METERS_PER_MIN));
}

module.exports = { haversineMeters, walkMinutes };
