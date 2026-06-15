/**
 * Raw Outscraper HTTP client + query helpers — the server-side port of the Dart
 * `OutscraperService` plumbing (key handling, query prep, short-URL expansion,
 * place-id detection, photo upscaling). No card shaping here — that's transform.js.
 */

const logger = require("firebase-functions/logger");

const { getOutscraperKey } = require("../keys");

const BASE = "https://api.app.outscraper.com";
const TIMEOUT_MS = 60 * 1000; // sync (async:false) calls; cap well under the fn deadline.

/** A google place_id ("ChIJ…") or a long opaque id, vs. a normal place name. */
function looksLikePlaceId(value) {
  const v = (value || "").trim();
  return v.startsWith("ChIJ") || /^[A-Za-z0-9_-]{24,}$/.test(v);
}

/** Follow redirects on a Google short link to recover the full Maps URL. */
async function expandUrl(url) {
  try {
    const res = await fetch(url, {
      method: "HEAD",
      redirect: "follow",
      signal: AbortSignal.timeout(10 * 1000),
    });
    return res.url || url;
  } catch (e) {
    logger.warn("outscraper.expandUrl failed", { url, message: e && e.message });
    return url;
  }
}

/**
 * Normalize a query the way the app expects: expand short links, and turn a bare
 * place_id into a Maps URL so Outscraper resolves the EXACT place (not a fuzzy
 * name match). Plain names pass through untouched.
 */
async function prepareQuery(query) {
  let q = (query || "").trim();
  if (q.includes("goo.gl") || q.includes("maps.app")) q = await expandUrl(q);
  if (!q.startsWith("http") && looksLikePlaceId(q)) {
    q = `https://www.google.com/maps/place/?q=place_id:${q}`;
  }
  return q;
}

/** Upscale a Google photo URL to a large fixed size (mirrors the Dart helper). */
function toHighResPhotoUrl(rawUrl) {
  const url = (rawUrl || "").trim();
  if (!url) return null;

  const targetSize = "=w3200-h2000-k-no";
  const sizePattern = /=w\d+-h\d+(?:-[^?&]*)?/;
  if (sizePattern.test(url)) return url.replace(sizePattern, targetSize);

  const queryStart = url.indexOf("?");
  if (queryStart === -1) return `${url}${targetSize}`;
  return `${url.slice(0, queryStart)}${targetSize}${url.slice(queryStart)}`;
}

/**
 * GET an Outscraper endpoint with the key header and a hard timeout. Returns the
 * parsed `data` array (Outscraper wraps results under `{ data: [...] }`), or [].
 */
async function outscraperGet(path, params) {
  const key = await getOutscraperKey();
  if (!key) {
    logger.warn("outscraperGet: no OUTSCRAPER_API_KEY configured");
    return [];
  }

  const url = new URL(`${BASE}/${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));

  try {
    const res = await fetch(url, {
      headers: { "X-API-KEY": key },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) {
      logger.error("outscraperGet non-200", { path, status: res.status });
      return [];
    }
    const body = await res.json();
    return Array.isArray(body.data) ? body.data : [];
  } catch (e) {
    logger.error("outscraperGet failed", { path, message: e && e.message });
    return [];
  }
}

/** First place object in a `data` array, unwrapping any nested-list nesting. */
function firstPlace(data) {
  if (!Array.isArray(data) || data.length === 0) return null;
  let first = data[0];
  while (Array.isArray(first) && first.length) first = first[0];
  return first && typeof first === "object" ? first : null;
}

module.exports = {
  looksLikePlaceId,
  prepareQuery,
  toHighResPhotoUrl,
  outscraperGet,
  firstPlace,
};
