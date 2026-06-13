/**
 * Structured result payloads + provider-error classification.
 *
 * The callable always returns `{ ok, code, model, reply }` so the UI can surface
 * provider/credential state (key missing, quota exceeded, model not found, …)
 * instead of a generic "internal error".
 */

const { MODEL } = require("../config");

/** Build the structured payload the frontend expects. */
function state(code, reply, ok = false) {
  return { ok, code, model: MODEL, reply };
}

/**
 * Classify a thrown Genkit/Gemini error into one of our structured states.
 * Google AI errors typically embed the HTTP status both as a numeric `status`
 * and inside the message string (e.g. "[429 Too Many Requests]").
 */
function classifyError(err) {
  const msg = String((err && (err.message || err.detail)) || err || "");
  const status = err && (err.status || err.statusCode || err.code);
  const haystack = `${status} ${msg}`.toLowerCase();

  // Auth / bad key.
  if (
    haystack.includes("api_key_invalid") ||
    haystack.includes("api key not valid") ||
    haystack.includes("invalid api key") ||
    haystack.includes("401") ||
    haystack.includes("unauthenticated")
  ) {
    return state(
      "API_KEY_INVALID",
      `🔑 GEMINI_API_KEY detected, but it is INVALID or rejected by the provider. ` +
        `Re-set it with \`firebase functions:secrets:set GEMINI_API_KEY\` and redeploy. ` +
        `Raw error: ${msg}`,
    );
  }

  // Quota / rate limit.
  if (
    haystack.includes("429") ||
    haystack.includes("resource_exhausted") ||
    haystack.includes("quota") ||
    haystack.includes("rate limit") ||
    haystack.includes("too many requests")
  ) {
    return state(
      "QUOTA_EXCEEDED",
      `📉 GEMINI_API_KEY detected, but the QUOTA / rate limit for ${MODEL} is exhausted. ` +
        `The key's plan ran out of requests/tokens — wait and retry, or upgrade the plan / enable billing. ` +
        `Raw error: ${msg}`,
    );
  }

  // Permission / API not enabled.
  if (
    haystack.includes("403") ||
    haystack.includes("permission_denied") ||
    haystack.includes("permission denied") ||
    haystack.includes("api has not been used") ||
    haystack.includes("is disabled")
  ) {
    return state(
      "PERMISSION_DENIED",
      `⛔ GEMINI_API_KEY detected, but PERMISSION was denied for ${MODEL}. ` +
        `The Generative Language API may not be enabled for this key's project, or the key is restricted. ` +
        `Raw error: ${msg}`,
    );
  }

  // Model not found / not enabled.
  if (
    haystack.includes("404") ||
    haystack.includes("not_found") ||
    haystack.includes("not found") ||
    haystack.includes("is not supported") ||
    haystack.includes("unknown model")
  ) {
    return state(
      "MODEL_NOT_FOUND",
      `🚫 GEMINI_API_KEY detected, but model "${MODEL}" was NOT FOUND / not enabled for this key. ` +
        `Raw error: ${msg}`,
    );
  }

  // Anything else.
  return state(
    "UPSTREAM_ERROR",
    `⚠️ GEMINI_API_KEY detected, but the call to ${MODEL} failed for an unexpected reason. ` +
      `Raw error: ${msg}`,
  );
}

module.exports = { state, classifyError };
