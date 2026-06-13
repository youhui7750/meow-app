/**
 * Skill: recallMemory (L1) — personalize via the user's prefs + RAG memory.
 *
 * Returns structured preferences (likes/dislikes/maxWalkMinutes) from the
 * user's profile doc, plus the top-k relevant distilled memories retrieved by
 * embedding the query (RAG). `userId` arrives via Genkit `context`.
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");

const { prefsDoc, DEMO_USER } = require("../../collections");
const memory = require("../../memory/store");

function defineRecallMemory(ai) {
  return ai.defineTool(
    {
      name: "recallMemory",
      description:
        "L1 skill. Retrieves the user's food preferences and relevant past " +
        "memories (RAG). Use this to personalize recommendations.",
      inputSchema: z.object({
        query: z.string().describe("What to recall, e.g. 'dinner near campus'"),
      }),
      outputSchema: z.object({
        likes: z.array(z.string()),
        dislikes: z.array(z.string()),
        maxWalkMinutes: z.number(),
        source: z.enum(["firestore", "mock"]),
        memories: z.array(
          z.object({
            text: z.string(),
            kind: z.string(),
            score: z.number(),
          }),
        ),
      }),
    },
    async ({ query }, { context }) => {
      const userId = (context && context.userId) || DEMO_USER;

      // RAG recall over the distilled memory collection (best-effort).
      const memories = await memory.recall(ai, { userId, query });

      // Structured prefs from the profile doc, with a mock fallback so the flow
      // works before any prefs are seeded.
      const fallback = {
        likes: ["ramen"],
        dislikes: ["crowds"],
        maxWalkMinutes: 20,
        source: "mock",
      };
      try {
        const snap = await prefsDoc(userId).get();
        if (!snap.exists) return { ...fallback, memories };
        const d = snap.data() || {};
        return {
          likes: d.likes || fallback.likes,
          dislikes: d.dislikes || fallback.dislikes,
          maxWalkMinutes: d.maxWalkMinutes ?? fallback.maxWalkMinutes,
          source: "firestore",
          memories,
        };
      } catch (e) {
        logger.warn("recallMemory prefs read failed; using mock", e);
        return { ...fallback, memories };
      }
    },
  );
}

module.exports = { defineRecallMemory };
