/**
 * Skill: searchSpots (L1) — candidate food spots for a cuisine/area.
 *
 * Mock candidate list for now. TODO(real): Google Places + IG saved-links parser.
 */

const { z } = require("genkit");

function defineSearchSpots(ai) {
  return ai.defineTool(
    {
      name: "searchSpots",
      description:
        "L1 skill. Searches web recommendations / IG saved links for candidate " +
        "food spots matching cuisine and area. Returns a candidate list.",
      inputSchema: z.object({
        cuisine: z.string().describe("e.g. 'ramen'"),
        area: z.string().optional().describe("neighborhood / near a place"),
      }),
      outputSchema: z.object({
        candidates: z.array(
          z.object({
            id: z.string(),
            displayName: z.string(),
            rating: z.number(),
            approxWalkMinutes: z.number(),
          }),
        ),
      }),
    },
    async () => {
      // TODO(real): Google Places + IG saved-links parser. Mock candidate list.
      return {
        candidates: [
          { id: "taihe-ramen", displayName: "Tai-He Ramen", rating: 4.5, approxWalkMinutes: 18 },
          { id: "menya-crowd", displayName: "Menya (busy)", rating: 4.7, approxWalkMinutes: 12 },
        ],
      };
    },
  );
}

module.exports = { defineSearchSpots };
