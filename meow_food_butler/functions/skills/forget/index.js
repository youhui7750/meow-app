/**
 * Skill: forget (memory delete) — remove stale facts about the user.
 *
 * Call when the user changes or retracts a preference (e.g. "I don't like ramen
 * anymore", "actually I prefer udon now") so the old fact stops being recalled.
 * Deletes the distilled memories most similar to `query` (RAG delete path).
 * `userId` arrives via Genkit `context`.
 */

const { z } = require("genkit");

const { DEMO_USER } = require("../../collections");
const memory = require("../../memory/store");

function defineForget(ai) {
  return ai.defineTool(
    {
      name: "forget",
      description:
        "Delete a durable fact or preference the user no longer holds. Call this " +
        "when the user changes or retracts a preference (e.g. 'I don't like ramen " +
        "anymore', 'I no longer avoid crowds'). When a preference is REPLACED, call " +
        "forget for the old one and remember for the new one. Pass the old fact as " +
        "`query`, phrased like how it was originally saved.",
      inputSchema: z.object({
        query: z
          .string()
          .describe("The stale fact to remove, phrased standalone, e.g. 'likes ramen'"),
      }),
      outputSchema: z.object({
        deleted: z.number(),
        texts: z.array(z.string()),
      }),
    },
    async ({ query }, { context }) => {
      const userId = (context && context.userId) || DEMO_USER;
      return memory.forget(ai, { userId, query });
    },
  );
}

module.exports = { defineForget };
