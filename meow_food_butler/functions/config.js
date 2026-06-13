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
const EMBEDDER = "text-embedding-004"; // googleai/text-embedding-004

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const placesApiKey = defineSecret("PLACES_API_KEY");

// Read a bound secret's value at runtime. `.value()` throws if the secret isn't
// bound/available to this function, so guard it and fall back to env vars.
function resolveGeminiApiKey() {
  let key = "";
  try {
    key = geminiApiKey.value();
  } catch (e) {
    logger.error("geminiApiKey.value() threw", e);
  }
  return key || process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";
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
  resolvePlacesApiKey,
};
