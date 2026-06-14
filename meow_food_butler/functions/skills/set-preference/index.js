/**
 * Skill: setPreference — set the user's one structured, computable constraint.
 *
 * Writes `users/{uid}/preferences/profile.maxWalkMinutes` — the only preference
 * that must be a number the agent can filter candidates with. Tastes (liked /
 * disliked cuisines, places enjoyed) are NOT stored here; they belong in
 * free-text RAG memory via `remember` / `forget`. `userId` arrives via Genkit
 * `context`.
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");

const { prefsDoc, DEMO_USER } = require("../../collections");

function defineSetPreference(ai) {
  return ai.defineTool(
    {
      name: "setPreference",
      description:
        "Set the user's max walk time in minutes — the one preference that must " +
        "be a number the agent filters spots with. Call this when the user states " +
        "or changes how far they'll walk (e.g. 'I'll walk up to 15 minutes'). For " +
        "tastes (cuisines they like/dislike, places they enjoyed) use remember / " +
        "forget instead, NOT this tool.",
      inputSchema: z.object({
        maxWalkMinutes: z.number().describe("new max walk time in minutes"),
      }),
      outputSchema: z.object({
        saved: z.boolean(),
        maxWalkMinutes: z.number().nullable(),
        error: z.string().optional(),
      }),
    },
    async ({ maxWalkMinutes }, { context }) => {
      const userId = (context && context.userId) || DEMO_USER;
      try {
        await prefsDoc(userId).set({ maxWalkMinutes }, { merge: true });
        return { saved: true, maxWalkMinutes };
      } catch (e) {
        logger.warn("setPreference write failed", e);
        return { saved: false, maxWalkMinutes: null, error: String(e && e.message) };
      }
    },
  );
}

module.exports = { defineSetPreference };
