/**
 * Skill: draftExperience (L2) — draft an ExperienceCard after a visit.
 *
 * Mock for now. TODO(real): sentiment over notes + vision over uploaded photos.
 */

const { z } = require("genkit");

function defineDraftExperience(ai) {
  return ai.defineTool(
    {
      name: "draftExperience",
      description:
        "L2 skill. After a visit, drafts an ExperienceCard (tags, rating, " +
        "summary) from the user's notes and photos for them to edit and save.",
      inputSchema: z.object({
        spotId: z.string(),
        notes: z.string().optional(),
        photoCount: z.number().optional(),
      }),
      outputSchema: z.object({
        spotId: z.string(),
        tags: z.array(z.string()),
        rating: z.number(),
        summary: z.string(),
      }),
    },
    async ({ spotId, notes }) => {
      // TODO(real): sentiment over `notes` + vision over uploaded photos.
      return {
        spotId,
        tags: ["ramen", "cozy", "quiet"],
        rating: 4,
        summary: notes
          ? `Drafted from your note: "${notes}".`
          : "A cozy bowl of ramen — quiet and satisfying.",
      };
    },
  );
}

module.exports = { defineDraftExperience };
