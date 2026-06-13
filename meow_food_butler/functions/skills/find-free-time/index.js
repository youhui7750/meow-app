/**
 * Skill: findFreeTime (L1) — the user's free time slots from their calendar.
 *
 * Mock data for now, but anchored to the user's real date (read from
 * `context.now.iso`) so "Friday" resolves to a concrete upcoming day.
 * TODO(real): Google Calendar API.
 */

const { z } = require("genkit");

function defineFindFreeTime(ai) {
  return ai.defineTool(
    {
      name: "findFreeTime",
      description:
        "L1 skill. Returns the user's free time slots from their calendar. " +
        "Use this first to know WHEN to plan an outing. Defaults to the current " +
        "week, anchored to the user's real date.",
      inputSchema: z.object({
        weekOf: z
          .string()
          .optional()
          .describe("ISO date inside the week to inspect; defaults to this week"),
      }),
      outputSchema: z.object({
        slots: z.array(
          z.object({
            day: z.string(),
            date: z.string().describe("YYYY-MM-DD of that slot"),
            startsAfter: z.string().describe("HH:mm the user becomes free"),
          }),
        ),
      }),
    },
    async ({ weekOf }, { context }) => {
      // Prefer the explicit weekOf, then the user's local `now`, then server UTC.
      const nowIso = (context && context.now && context.now.iso) || null;
      const base = new Date(weekOf || nowIso || Date.now());
      // Days from `base` to this week's Friday (getDay: 0=Sun … 5=Fri).
      const daysToFriday = (5 - base.getDay() + 7) % 7;
      const friday = new Date(base);
      friday.setDate(base.getDate() + daysToFriday);
      const date = friday.toISOString().slice(0, 10);
      return { slots: [{ day: "Friday", date, startsAfter: "15:20" }] };
    },
  );
}

module.exports = { defineFindFreeTime };
