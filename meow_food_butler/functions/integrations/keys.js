/**
 * Live provider-key resolver for the third-party integrations — same redeploy-free
 * pattern as `agent/keys.js` `getGeminiKeys()`: read from a Firestore `config/*`
 * doc at request time (briefly cached), so rotating a key is just editing a doc in
 * the console — no `secrets:set`, no redeploy.
 *
 * Doc shape (create these in the console; the Admin SDK bypasses firestore.rules,
 * which already denies clients access to `config/*`):
 *   config/apify      -> { APIFY_TOKEN: "apify_api_..." }
 *   config/outscraper -> { OUTSCRAPER_API_KEY: "..." }
 *
 * Falls back to the matching `process.env.<NAME>` (handy for the emulator) when the
 * doc is missing or empty. Returns "" when neither is set.
 */

const logger = require("firebase-functions/logger");

const { configDoc } = require("../collections");

const TTL_MS = 60 * 1000;
const _cache = new Map(); // docName -> { value, ts }

/**
 * Read one string field from a `config/<docName>` doc, with a per-doc 60 s cache
 * and an env-var fallback. Best-effort: never throws.
 */
async function getConfigValue(docName, field, envName) {
  const now = Date.now();
  const hit = _cache.get(docName);
  if (hit && now - hit.ts < TTL_MS) return hit.value;

  let value = "";
  try {
    const snap = await configDoc(docName).get();
    if (snap.exists) {
      const raw = (snap.data() || {})[field];
      if (typeof raw === "string") value = raw.trim();
    }
  } catch (e) {
    logger.warn(`getConfigValue: config/${docName} read failed; using env`, e);
  }

  if (!value) value = (process.env[envName] || "").trim();

  // Only cache non-empty so a transient empty read doesn't stick.
  if (value) _cache.set(docName, { value, ts: now });
  return value;
}

/** Apify API token from config/apify { APIFY_TOKEN } (env: APIFY_TOKEN). */
function getApifyToken() {
  return getConfigValue("apify", "APIFY_TOKEN", "APIFY_TOKEN");
}

/** Outscraper API key from config/outscraper { OUTSCRAPER_API_KEY }. */
function getOutscraperKey() {
  return getConfigValue("outscraper", "OUTSCRAPER_API_KEY", "OUTSCRAPER_API_KEY");
}

module.exports = { getApifyToken, getOutscraperKey };
