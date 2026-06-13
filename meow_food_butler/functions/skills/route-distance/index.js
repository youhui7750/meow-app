/**
 * Skill: routeDistance (L2) — walking time from the user to a candidate spot.
 *
 * Mock per known spot for now. TODO(real): Google Maps Distance Matrix.
 */

const { z } = require("genkit");

function defineRouteDistance(ai) {
  return ai.defineTool(
    {
      name: "routeDistance",
      description:
        "L2 skill. Computes walking time from the user's origin to a candidate " +
        "spot. Use to filter candidates by the user's max walk time.",
      inputSchema: z.object({
        spotId: z.string(),
        origin: z.string().optional().describe("origin address or 'current'"),
      }),
      outputSchema: z.object({
        spotId: z.string(),
        walkMinutes: z.number(),
      }),
    },
    async ({ spotId }) => {
      // TODO(real): Google Maps Distance Matrix. Mock per known spot.
      const table = { "taihe-ramen": 18, "menya-crowd": 12 };
      return { spotId, walkMinutes: table[spotId] ?? 25 };
    },
  );
}

module.exports = { defineRouteDistance };
