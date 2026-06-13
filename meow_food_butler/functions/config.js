/**
 * Shared config: model id, region, and the bound API-key secrets + resolvers.
 *
 * Secrets are declared here with `defineSecret` and must ALSO be attached to
 * each callable via `onCall({ secrets: [...] })` — only that binding populates
 * `.value()` at runtime. To (re)set one:
 *
 *   firebase functions:secrets:set GEMINI_API_KEY
 *   firebase functions:secrets:set PLACES_API_KEY
 *   firebase deploy --only functions
 */

const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

// Match the project's Firestore region (see firebase.json).
const REGION = "asia-east1";
const MODEL = "googleai/gemini-2.5-flash";
// Primary embedding model. The Gemini Developer API doesn't expose the same set
// for every key/version (text-embedding-004 can 404), so memory/store.js tries
// this first then falls through a candidate list and caches what works.
const EMBEDDER = "gemini-embedding-001";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const placesApiKey = defineSecret("PLACES_API_KEY");

// Read a bound secret's value at runtime. `.value()` throws if the secret isn't
// bound/available to this function, so guard it and fall back to env vars.
function rawGeminiSecret() {
  let key = "";
  try {
    key = geminiApiKey.value();
  } catch (e) {
    logger.error("geminiApiKey.value() threw", e);
  }
  return key || process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";
}

/**
 * Split a raw string of one-or-more keys into a deduped, ordered list. Keys may
 * be separated by newlines, commas, or whitespace (Google API keys contain none
 * of those, so this is safe).
 */
function splitKeys(raw) {
  return [
    ...new Set(
      String(raw || "")
        .split(/[\s,]+/)
        .map((s) => s.trim())
        .filter(Boolean),
    ),
  ];
}

/**
 * Gemini API keys from the bound secret / env (the deploy-time fallback source).
 * The live, redeploy-free source is the Firestore `config/gemini` doc — see
 * `agent/keys.js` `getGeminiKeys()`, which falls back to this.
 */
function resolveGeminiApiKeys() {
  return splitKeys(rawGeminiSecret());
}

/** First available key (back-compat: presence checks, embeddings). */
function resolveGeminiApiKey() {
  return resolveGeminiApiKeys()[0] || "";
}

function resolvePlacesApiKey() {
  let key = "";
  try {
    key = placesApiKey.value();
  } catch (e) {
    logger.error("placesApiKey.value() threw", e);
  }
  return key || process.env.PLACES_API_KEY || "";
}

module.exports = {
  REGION,
  MODEL,
  EMBEDDER,
  geminiApiKey,
  placesApiKey,
  resolveGeminiApiKey,
  resolveGeminiApiKeys,
  resolvePlacesApiKey,
  splitKeys,
};
