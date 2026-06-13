/**
 * Cloud Functions for "Meow Food Butler" — thin entry point.
 *
 * The chat assistant's heavy lifting lives in the modules this requires:
 *   config.js     — model id, region, bound secrets + resolvers
 *   agent/        — butler (genkit + persona), errors, flow (generate pipeline)
 *   skills/       — one folder per skill (Genkit tools)
 *   memory/       — RAG long-term memory (embed/remember/recall)
 *   sessions/     — verbatim chat history (append/recent messages)
 *
 * The Flutter app is a thin client that calls `chatWithButler` and renders
 * `reply`; `code`/`ok` describe provider/credential state.
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const {
  REGION,
  geminiApiKey,
  placesApiKey,
  resolveGeminiApiKey,
  resolvePlacesApiKey,
} = require("./config");
const { DEMO_USER } = require("./collections");
const { getButler } = require("./agent/butler");
const { runButlerFlow } = require("./agent/flow");
const memory = require("./memory/store");
const sessions = require("./sessions/store");

setGlobalOptions({ maxInstances: 10, region: REGION });

/** Parse the optional GPS coordinates the client sends when permission is granted. */
function parseLocation(raw) {
  if (raw && typeof raw.latitude === "number" && typeof raw.longitude === "number") {
    return { latitude: raw.latitude, longitude: raw.longitude };
  }
  return undefined;
}

/** Parse the optional device-local time ({ local: "Fri 13:00", iso }). */
function parseNow(raw) {
  if (raw && typeof raw === "object") {
    const local = typeof raw.local === "string" ? raw.local : undefined;
    const iso = typeof raw.iso === "string" ? raw.iso : undefined;
    if (local || iso) return { local, iso };
  }
  return undefined;
}

/**
 * Callable: `chatWithButler({ prompt, sessionId, userId?, location?, now? })`
 *   -> { ok, code, model, reply, sessionId }.
 *
 * Persists the conversation, replays recent turns for multi-turn context, and
 * recalls relevant long-term memory (RAG) — then runs the generate pipeline.
 */
exports.chatWithButler = onCall(
  { secrets: [geminiApiKey, placesApiKey] },
  async (request) => {
    const data = request.data || {};
    const prompt = data.prompt;
    if (typeof prompt !== "string" || prompt.trim() === "") {
      throw new HttpsError("invalid-argument", "A non-empty `prompt` is required.");
    }
    const sessionId = data.sessionId;
    if (typeof sessionId !== "string" || sessionId.trim() === "") {
      throw new HttpsError("invalid-argument", "A `sessionId` is required.");
    }
    const userId = typeof data.userId === "string" && data.userId ? data.userId : DEMO_USER;
    const location = parseLocation(data.location);
    const now = parseNow(data.now);

    // Read prior turns BEFORE persisting the new one, so history is clean and a
    // failed reply never pollutes the conversation.
    const history = await sessions.recentMessages(userId, sessionId);

    // RAG recall (best-effort). Only build the butler when the key is present so
    // we never cache a broken instance for later real calls.
    let recalled = [];
    const apiKey = resolveGeminiApiKey();
    if (apiKey) {
      const { instance } = getButler(apiKey);
      recalled = await memory.recall(instance, { userId, query: prompt });
    }

    logger.info("chatWithButler called", {
      promptLength: prompt.length,
      hasLocation: Boolean(location),
      hasNow: Boolean(now),
      historyLen: history.length,
      recalledLen: recalled.length,
    });

    const result = await runButlerFlow(prompt, {
      location,
      now,
      userId,
      sessionId,
      history,
      recalled,
    });

    // Persist the exchange only on success, so errors don't litter history.
    if (result.ok) {
      await sessions.appendMessage(userId, sessionId, { role: "user", text: prompt });
      await sessions.appendMessage(userId, sessionId, { role: "assistant", text: result.reply });
    }

    logger.info("chatWithButler result", { code: result.code, ok: result.ok });
    return { ...result, sessionId };
  },
);

/**
 * Callable: `checkApiKeys()` -> { ok, missing, reply }.
 *
 * Lets the client post a heads-up in chat at startup when a required backend
 * key isn't configured. `reply` is a ready-to-render, cat-toned message (or
 * null when everything is configured).
 */
exports.checkApiKeys = onCall(
  { secrets: [geminiApiKey, placesApiKey] },
  async () => {
    const missing = [];
    if (!resolveGeminiApiKey()) missing.push("GEMINI_API_KEY");
    if (!resolvePlacesApiKey()) missing.push("PLACES_API_KEY");

    if (missing.length === 0) {
      return { ok: true, missing, reply: null };
    }

    const effects = missing
      .map((k) =>
        k === "GEMINI_API_KEY"
          ? "I can't think or chat without GEMINI_API_KEY"
          : "I can't name nearby places without PLACES_API_KEY",
      )
      .join("; ");
    const reply =
      `😿 Heads up: ${missing.join(" and ")} ` +
      `${missing.length > 1 ? "are" : "is"} not configured, so ${effects}. ` +
      `Set ${missing.length > 1 ? "them" : "it"} with ` +
      "`firebase functions:secrets:set <NAME>` and redeploy, nya.";

    logger.warn("checkApiKeys: missing keys", { missing });
    return { ok: false, missing, reply };
  },
);
