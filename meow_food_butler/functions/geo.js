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

// Past this, "walking time" stops being meaningful — nobody walks it, so we
// report distance only instead of an absurd figure like "walk 780 min".
const WALKABLE_LIMIT_M = 2500;

/**
 * Turn a raw metre distance into a clean, ready-to-print label plus the values
 * behind it. Distance is shown in metres under 1 km and kilometres above it;
 * the walking time is only carried when the place is actually walkable.
 *
 * @param {number|null|undefined} meters
 * @returns {{ distanceMeters: number|null, walkMinutes: number|null, distanceLabel: string|null }}
 */
function formatDistance(meters) {
  if (typeof meters !== "number" || !isFinite(meters)) {
    return { distanceMeters: null, walkMinutes: null, distanceLabel: null };
  }
  const m = Math.round(meters);
  const distanceText =
    m < 1000 ? `${m} 公尺` : `${(m / 1000).toFixed(1)} 公里`;
  if (m <= WALKABLE_LIMIT_M) {
    const mins = walkMinutes(m);
    return {
      distanceMeters: m,
      walkMinutes: mins,
      distanceLabel: `走路約 ${mins} 分鐘（${distanceText}）`,
    };
  }
  return { distanceMeters: m, walkMinutes: null, distanceLabel: `距離約 ${distanceText}` };
}

module.exports = { haversineMeters, walkMinutes, formatDistance };
