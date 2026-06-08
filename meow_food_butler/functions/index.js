/**
 * Cloud Functions for "Meow Food Butler".
 *
 * Thick backend: the chat assistant's heavy lifting lives here. The Flutter app
 * is a thin client (`lib/services/ai_agent_service.dart`) that just calls the
 * `chatWithButler` callable and renders whatever it returns.
 *
 * This is a DUMMY implementation: no model is actually called and no API key is
 * required. Instead it reports the current provider/credential state so the UI
 * can surface it (API key missing, quota exceeded, model not found, …). The
 * real Genkit wiring is scaffolded in comments below — drop it in once an API
 * key is configured.
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// Match the project's Firestore region (see firebase.json) and cap instances.
setGlobalOptions({ maxInstances: 10, region: "asia-east1" });

const MODEL = "googleai/gemini-2.5-flash";

// ---------------------------------------------------------------------------
// Genkit wiring (intended real implementation — kept as scaffolding).
//
//   npm i genkit @genkit-ai/googleai
//   firebase functions:secrets:set GEMINI_API_KEY
//
//   const { genkit } = require("genkit");
//   const { googleAI } = require("@genkit-ai/googleai");
//
//   const ai = genkit({ plugins: [googleAI()] });
//
//   const butlerFlow = ai.defineFlow("butlerFlow", async (prompt) => {
//     const { text } = await ai.generate({
//       model: googleAI.model("gemini-2.5-flash"),
//       system:
//         "You are a friendly cat butler that recommends food spots. End replies with 'Meow'.",
//       prompt,
//     });
//     return text;
//   });
//
// Then, in the handler below, replace `runButlerFlowDummy(prompt)` with
// `await butlerFlow(prompt)`.
// ---------------------------------------------------------------------------

/** Build the structured payload the frontend expects. */
function state(code, reply, ok = false) {
  return { ok, code, model: MODEL, reply };
}

/**
 * Dummy stand-in for the Genkit flow. Returns no real model output; it reports
 * the provider state instead. Test hooks let the client force any state without
 * real keys: send "/quota", "/model", or "/ok" as the prompt.
 */
async function runButlerFlowDummy(prompt) {
  const apiKey =
    process.env.GEMINI_API_KEY ||
    process.env.GOOGLE_API_KEY ||
    process.env.GOOGLE_GENAI_API_KEY ||
    "";

  const hook = prompt.trim().toLowerCase();

  // --- Forced states for testing the UI without configuring anything --------
  if (hook === "/quota") {
    return state(
      "QUOTA_EXCEEDED",
      `📉 Quota exceeded for ${MODEL}. The provider plan ran out of requests/tokens — try again later or upgrade the plan.`,
    );
  }
  if (hook === "/model") {
    return state(
      "MODEL_NOT_FOUND",
      `🚫 Model "${MODEL}" not found or not enabled for this project/key.`,
    );
  }
  if (hook === "/ok") {
    return state(
      "OK",
      `😺 (dummy) Meow! How about a cozy ramen spot in Da'an? You said: "${prompt}".`,
      true,
    );
  }

  // --- Real credential state ------------------------------------------------
  if (!apiKey) {
    return state(
      "API_KEY_MISSING",
      `🔑 API key not found. No GEMINI_API_KEY/GOOGLE_API_KEY is configured, so ${MODEL} cannot be reached. ` +
        `Backend is in dummy mode — set a key and enable the Genkit flow to get real replies.`,
    );
  }

  // Key present, but the Genkit flow above is still commented out.
  return state(
    "DUMMY_OK",
    `😺 (dummy ${MODEL}) API key detected ✅ — but the Genkit flow is still a stub. You said: "${prompt}".`,
    true,
  );
}

/**
 * Callable: `chatWithButler({ prompt })` -> { ok, code, model, reply }.
 * The frontend always renders `reply`; `code`/`ok` describe provider state.
 */
exports.chatWithButler = onCall(async (request) => {
  const prompt = request.data && request.data.prompt;
  if (typeof prompt !== "string" || prompt.trim() === "") {
    throw new HttpsError("invalid-argument", "A non-empty `prompt` is required.");
  }

  logger.info("chatWithButler called", { promptLength: prompt.length });
  const result = await runButlerFlowDummy(prompt);
  logger.info("chatWithButler result", { code: result.code, ok: result.ok });
  return result;
});
