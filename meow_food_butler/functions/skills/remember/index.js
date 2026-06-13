/**
 * Skill: remember (memory write) — persist a durable fact about the user.
 *
 * Call when the user shares a lasting preference, constraint, or a place they
 * liked. Embeds + stores it so future sessions can recall it (RAG write path).
 * `userId` arrives via Genkit `context`.
 */

const { z } = require("genkit");

const { DEMO_USER } = require("../../collections");
const memory = require("../../memory/store");

function defineRemember(ai) {
  return ai.defineTool(
    {
      name: "remember",
      description:
        "Save a durable fact or preference about the user to long-term memory " +
        "(e.g. 'loves spicy ramen', 'dislikes queues', 'enjoyed Tai-He Ramen'). " +
        "Call this whenever the user reveals something worth remembering across " +
        "conversations. Keep the saved text short and self-contained.",
      inputSchema: z.object({
        text: z.string().describe("The fact to remember, phrased standalone"),
        kind: z
          .enum(["preference", "constraint", "experience", "note"])
          .optional()
          .describe("Category of memory; defaults to 'note'"),
      }),
      outputSchema: z.object({
        saved: z.boolean(),
        id: z.string().optional(),
        error: z.string().optional(),
      }),
    },
    async ({ text, kind = "note" }, { context }) => {
      const userId = (context && context.userId) || DEMO_USER;
      const sessionId = (context && context.sessionId) || null;
      return memory.remember(ai, { userId, text, kind, sessionId });
    },
  );
}

module.exports = { defineRemember };
