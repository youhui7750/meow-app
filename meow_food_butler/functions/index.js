/**
 * Cloud Functions for "Meow Food Butler".
 *
 * Thick backend: the chat assistant's heavy lifting lives here. The Flutter app
 * is a thin client (`lib/services/ai_agent_service.dart`) that just calls the
 * `chatWithButler` callable and renders whatever it returns.
 *
 * The callable always returns a structured payload `{ ok, code, model, reply }`
 * so the UI can surface provider/credential state (key missing, quota exceeded,
 * model not found, …) instead of a generic "internal error".
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const { genkit } = require("genkit");
const { googleAI } = require("@genkit-ai/googleai");
const { registerTools } = require("./tools");

// Match the project's Firestore region (see firebase.json) and cap instances.
setGlobalOptions({ maxInstances: 10, region: "asia-east1" });

const MODEL = "googleai/gemini-2.5-flash";

// Cat-butler persona + how to drive the L1→L2 agent flow (see agent_design.md).
const SYSTEM_PROMPT = [
  "You are the Meow Food Butler: a wise, friendly cat butler who recommends food spots.",
  "Speak in a cat-like tone — end sentences with 'meow', 'nya', or 'prrr', varying with the mood.",
  "When the user asks where they are (or you need their current position), call the",
  "whereAmI tool. If it returns permissionGranted=false, gently ask them to enable",
  "location permission. When it returns nearby places, do NOT assert a single spot —",
  "tell them the most likely one first and offer the other candidates to pick from.",
  "You also plan in two layers. L1 (Planning): call findFreeTime, recallMemory, then searchSpots",
  "to build a candidate list. L2 (Execution): use routeDistance to keep only spots within the",
  "user's max walk time, recommend one, and after a visit use draftExperience to write it up.",
  "Always respect the user's preferences and constraints from recallMemory.",
  "Keep replies concise and end with a cat sound.",
].join(" ");

// ---------------------------------------------------------------------------
// Secret binding.
//
// IMPORTANT: `firebase apphosting:secrets:access GEMINI_API_KEY` only proves the
// secret exists in Secret Manager — it does NOT expose it to a Cloud Function.
// For Functions v2 the secret must be declared here AND attached to the function
// via the `secrets:` option below; only then is `geminiApiKey.value()` populated
// at runtime. To (re)set the value:
//
//   firebase functions:secrets:set GEMINI_API_KEY
//   firebase deploy --only functions
// ---------------------------------------------------------------------------
const geminiApiKey = defineSecret("GEMINI_API_KEY");

// Google Places key for the whereAmI tool. Falls back to the key the client
// already ships so this works immediately, with no extra setup.
// TODO (hardening): move to a bound secret —
//   firebase functions:secrets:set PLACES_API_KEY
// then add `placesApiKeySecret` to the function's `secrets:` array and read it
// here, and drop the literal fallback.
const FALLBACK_PLACES_API_KEY = "AIzaSyCMd1wINmFXLfqbiVwh-zdorui6R-wPgKU";

function resolvePlacesApiKey() {
  return process.env.PLACES_API_KEY || FALLBACK_PLACES_API_KEY;
}

/** Build the structured payload the frontend expects. */
function state(code, reply, ok = false) {
  return { ok, code, model: MODEL, reply };
}

// Cache the Genkit instance + tool refs across warm invocations so we don't
// re-init per call. Tools must be defined on the instance that runs the flow.
let _butler = null;
function getButler(apiKey) {
  if (_butler) return _butler;
  // Pass the key explicitly rather than relying on process.env so the binding is
  // unambiguous regardless of how the secret is surfaced.
  const instance = genkit({ plugins: [googleAI({ apiKey })] });
  const tools = registerTools(instance, { placesApiKey: resolvePlacesApiKey() });
  _butler = { instance, tools };
  return _butler;
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

/**
 * Run the real Genkit flow. Returns the structured `state(...)` payload in all
 * cases — never throws — so the frontend always has something to render.
 *
 * Test hooks let the client force a state without configuring anything: send
 * "/quota", "/model", or "/ok" as the prompt.
 */
async function runButlerFlow(prompt, location) {
  const hook = prompt.trim().toLowerCase();

  // --- Forced states for testing the UI without real calls ------------------
  if (hook === "/quota") {
    return state(
      "QUOTA_EXCEEDED",
      `📉 (forced) Quota exceeded for ${MODEL}.`,
    );
  }
  if (hook === "/model") {
    return state(
      "MODEL_NOT_FOUND",
      `🚫 (forced) Model "${MODEL}" not found or not enabled.`,
    );
  }
  if (hook === "/ok") {
    return state(
      "OK",
      `😺 (forced) Meow! How about a cozy ramen spot in Da'an? You said: "${prompt}".`,
      true,
    );
  }

  // --- Credential check before we even try ----------------------------------
  let apiKey = "";
  try {
    apiKey = geminiApiKey.value();
  } catch (e) {
    // .value() throws if the secret isn't bound/available to this function.
    logger.error("geminiApiKey.value() threw", e);
  }
  apiKey = apiKey || process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";

  if (!apiKey) {
    return state(
      "API_KEY_MISSING",
      `🔑 GEMINI_API_KEY is NOT available to this function. ` +
        `Note: \`apphosting:secrets:access\` does not bind a secret to Cloud Functions. ` +
        `Run \`firebase functions:secrets:set GEMINI_API_KEY\` and redeploy so the ` +
        `\`secrets: [geminiApiKey]\` binding can inject it.`,
    );
  }

  // --- Real model call (with tool-calling) ----------------------------------
  try {
    const { instance, tools } = getButler(apiKey);
    const { text } = await instance.generate({
      model: googleAI.model("gemini-2.5-flash"),
      system: SYSTEM_PROMPT,
      tools,
      prompt,
      // Per-request context propagated to tools (e.g. whereAmI reads `location`).
      // Concurrency-safe: not shared module state.
      context: location ? { location } : undefined,
    });
    return state("OK", text, true);
  } catch (err) {
    logger.error("Gemini generate() failed", {
      status: err && (err.status || err.code),
      message: err && err.message,
    });
    return classifyError(err);
  }
}

/**
 * Callable: `chatWithButler({ prompt })` -> { ok, code, model, reply }.
 * The frontend always renders `reply`; `code`/`ok` describe provider state.
 */
exports.chatWithButler = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    const data = request.data || {};
    const prompt = data.prompt;
    if (typeof prompt !== "string" || prompt.trim() === "") {
      throw new HttpsError("invalid-argument", "A non-empty `prompt` is required.");
    }

    // Optional GPS coordinates sent by the client when permission is granted.
    let location;
    const rawLoc = data.location;
    if (
      rawLoc &&
      typeof rawLoc.latitude === "number" &&
      typeof rawLoc.longitude === "number"
    ) {
      location = { latitude: rawLoc.latitude, longitude: rawLoc.longitude };
    }

    logger.info("chatWithButler called", {
      promptLength: prompt.length,
      hasLocation: Boolean(location),
    });
    const result = await runButlerFlow(prompt, location);
    logger.info("chatWithButler result", { code: result.code, ok: result.ok });
    return result;
  },
);
