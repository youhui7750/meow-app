/**
 * Skill: recallMemory (L1) — personalize via the user's RAG memory + the one
 * structured constraint that must be computable.
 *
 * Tastes (likes/dislikes, places enjoyed) live in free-text RAG memory and come
 * back as `memories[]`. The profile doc holds only `maxWalkMinutes`, because
 * that one is a number the agent filters candidates with. `userId` arrives via
 * Genkit `context`.
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
        "L1 skill. Retrieves relevant past memories about the user (RAG) plus " +
        "their max walk time, to personalize recommendations. Tastes (likes/" +
        "dislikes, places enjoyed) come back in `memories`.",
      inputSchema: z.object({
        query: z.string().describe("What to recall, e.g. 'dinner near campus'"),
      }),
      outputSchema: z.object({
        // null = no walk-time limit recorded yet; don't filter on it.
        maxWalkMinutes: z.number().nullable(),
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

      // RAG recall over the distilled memory collection (best-effort) — this is
      // where tastes/preferences live now.
      const memories = await memory.recall(ai, { userId, query });

      // The profile holds only the one computable constraint. No seeded values:
      // null until the user sets it, so the agent never invents a limit.
      let maxWalkMinutes = null;
      try {
        const snap = await prefsDoc(userId).get();
        if (snap.exists) maxWalkMinutes = snap.data().maxWalkMinutes ?? null;
      } catch (e) {
        logger.warn("recallMemory prefs read failed; no walk limit", e);
      }
      return { maxWalkMinutes, memories };
    },
  );
}

module.exports = { defineRecallMemory };
