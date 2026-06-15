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
  resolvePlacesApiKey,
} = require("./config");
const { DEMO_USER } = require("./collections");
const { getButler } = require("./agent/butler");
const { getGeminiKeys } = require("./agent/keys");
const { runButlerFlow } = require("./agent/flow");
const memory = require("./memory/store");
const sessions = require("./sessions/store");
const integrations = require("./integrations");

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

    // RAG recall (best-effort). Use the first live key; only build the butler
    // when a key is present so we never cache a broken instance for later calls.
    let recalled = [];
    const keys = await getGeminiKeys();
    if (keys.length) {
      const { instance } = getButler(keys[0]);
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
    // Skip a blank/whitespace-only assistant reply (it happens when the model
    // leans entirely on a tool's UI action) so it never shows as an empty
    // bubble or gets replayed as context.
    if (result.ok) {
      await sessions.appendMessage(userId, sessionId, { role: "user", text: prompt });
      if (typeof result.reply === "string" && result.reply.trim() !== "") {
        await sessions.appendMessage(userId, sessionId, {
          role: "assistant",
          text: result.reply,
        });
      }
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
    if (!(await getGeminiKeys()).length) missing.push("GEMINI_API_KEY");
    if (!resolvePlacesApiKey()) missing.push("PLACES_API_KEY");
    // Integration keys live in Firestore config/* docs (redeploy-free).
    if (!(await integrations.getApifyToken())) missing.push("APIFY_TOKEN");
    if (!(await integrations.getOutscraperKey())) missing.push("OUTSCRAPER_API_KEY");

    if (missing.length === 0) {
      return { ok: true, missing, reply: null };
    }

    const effectFor = {
      GEMINI_API_KEY: "I can't think or chat without GEMINI_API_KEY",
      PLACES_API_KEY: "I can't name nearby places without PLACES_API_KEY",
      APIFY_TOKEN: "I can't read Instagram posts without APIFY_TOKEN",
      OUTSCRAPER_API_KEY: "I can't look up restaurant details without OUTSCRAPER_API_KEY",
    };
    const effects = missing.map((k) => effectFor[k] || `I'm missing ${k}`).join("; ");
    const reply =
      `😿 Heads up: ${missing.join(" and ")} ` +
      `${missing.length > 1 ? "are" : "is"} not configured, so ${effects}. ` +
      `Set ${missing.length > 1 ? "them" : "it"} with ` +
      "`firebase functions:secrets:set <NAME>` and redeploy, nya.";

    logger.warn("checkApiKeys: missing keys", { missing });
    return { ok: false, missing, reply };
  },
);

/**
 * Callable: `importInstagram({ url })` -> { ok, code, experience?, restaurant? }.
 *
 * Runs the full IG import pipeline server-side (Apify scrape -> AI name extraction
 * -> Outscraper enrichment) and returns `ExperienceCard` / `FoodCard` maps the
 * client deserializes directly. Bound to `geminiApiKey` for the extraction step;
 * the Apify/Outscraper keys are read live from Firestore config/* docs.
 *
 * Long-running (Apify polls), so the default 60 s timeout is raised.
 */
exports.importInstagram = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    const url = (request.data || {}).url;
    if (typeof url !== "string" || url.trim() === "") {
      throw new HttpsError("invalid-argument", "A non-empty `url` is required.");
    }
    logger.info("importInstagram called", { url });
    const result = await integrations.importInstagram(url);
    logger.info("importInstagram result", { code: result.code, ok: result.ok });
    return result;
  },
);

/**
 * Callable: `fetchRestaurant({ placeId?, query?, originalURL?, tags?, visited? })`
 *   -> { ok, code, restaurant? }.
 *
 * Single-place Google Maps lookup via Outscraper. Prefer `placeId` (resolves the
 * EXACT place); falls back to a `query` string. Detail + menu photos + reviews are
 * fetched in parallel and merged into one `FoodCard` map. The optional overlay
 * fields mirror `FoodCard.copyForImport` for callers enriching a saved place.
 */
exports.fetchRestaurant = onCall(
  { timeoutSeconds: 120, memory: "512MiB" },
  async (request) => {
    const data = request.data || {};
    const lookup =
      (typeof data.placeId === "string" && data.placeId.trim()) ||
      (typeof data.query === "string" && data.query.trim()) ||
      "";
    if (!lookup) {
      throw new HttpsError("invalid-argument", "A `placeId` or `query` is required.");
    }

    const [detail, menuPhotos, reviewSnippets] = await Promise.all([
      integrations.fetchRestaurantDetail(lookup),
      integrations.fetchPhotos(lookup, "menu", 5),
      integrations.fetchReviews(lookup, 3),
    ]);
    if (!detail) {
      return { ok: false, code: "not-found", reply: "😿 I couldn't find that place on the map." };
    }

    const seen = new Set();
    const photoUrls = [...(detail.photoUrls || []), ...menuPhotos]
      .map((u) => (u || "").trim())
      .filter((u) => u && !seen.has(u) && seen.add(u))
      .slice(0, 5);

    const restaurant = {
      ...detail,
      photoUrls,
      reviewSnippets,
      originalURL:
        typeof data.originalURL === "string" ? data.originalURL : detail.originalURL || null,
      visited: typeof data.visited === "boolean" ? data.visited : false,
      tags: Array.isArray(data.tags) ? data.tags : [],
    };

    logger.info("fetchRestaurant result", { hasDetail: true, photos: photoUrls.length });
    return { ok: true, code: "ok", restaurant };
  },
);
