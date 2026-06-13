/**
 * Live Gemini key provider — lets you rotate keys WITHOUT redeploying.
 *
 * Keys are read from the Firestore `config/gemini` doc at request time (cached
 * briefly), so changing them is just editing one doc in the console; the change
 * takes effect within the cache TTL with no `secrets:set` + redeploy cycle (the
 * deploy-time secret only ever pins a fixed version — the usual "I changed the
 * key but it still uses the old one" trap).
 *
 * Doc shape (either form works):
 *   config/gemini -> { keys: ["AIza...A", "AIza...B"] }
 *   config/gemini -> { keys: "AIza...A, AIza...B" }
 *
 * Falls back to the bound GEMINI_API_KEY secret / env when the doc is missing or
 * empty, so nothing breaks before the doc is created.
 */

const logger = require("firebase-functions/logger");

const { configDoc } = require("../collections");
const { resolveGeminiApiKeys, splitKeys } = require("../config");

const TTL_MS = 60 * 1000;
let _cache = { keys: [], ts: 0 };

/** Ordered, deduped list of currently-usable Gemini keys. Best-effort. */
async function getGeminiKeys() {
  const now = Date.now();
  if (_cache.keys.length && now - _cache.ts < TTL_MS) return _cache.keys;

  let keys = [];
  try {
    const snap = await configDoc("gemini").get();
    if (snap.exists) {
      const raw = (snap.data() || {}).keys;
      keys = splitKeys(Array.isArray(raw) ? raw.join("\n") : raw);
    }
  } catch (e) {
    logger.warn("getGeminiKeys: config/gemini read failed; using secret", e);
  }

  // Fall back to the bound secret / env if the config doc is missing/empty.
  if (!keys.length) keys = resolveGeminiApiKeys();

  // Only cache non-empty results so a transient empty read doesn't stick.
  if (keys.length) _cache = { keys, ts: now };
  return keys;
}

/** Drop the cache (e.g. after a known key change) so the next call re-reads. */
function invalidateGeminiKeysCache() {
  _cache = { keys: [], ts: 0 };
}

module.exports = { getGeminiKeys, invalidateGeminiKeysCache };
