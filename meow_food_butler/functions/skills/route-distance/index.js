/**
 * Skill: routeDistance (L2) — walking distance/time from the user to a spot.
 *
 * Real straight-line (haversine) estimate from the user's current GPS
 * (`context.location`) to the candidate's coordinates. No mock data. searchSpots
 * already returns distance for its candidates, so this is mainly for spots the
 * user names that didn't come through searchSpots. An upgrade to Google Routes
 * API would replace haversine with true walking routes.
 */

const { z } = require("genkit");

const { haversineMeters, walkMinutes } = require("../../geo");

function defineRouteDistance(ai) {
  return ai.defineTool(
    {
      name: "routeDistance",
      description:
        "L2 skill. Estimates walking distance and time from the user's current " +
        "location to a spot's coordinates. Use it to check a candidate against " +
        "the user's max walk time. Needs the spot's latitude/longitude.",
      inputSchema: z.object({
        latitude: z.number().describe("destination latitude"),
        longitude: z.number().describe("destination longitude"),
        spotName: z.string().optional().describe("for reference in your reply"),
      }),
      outputSchema: z.object({
        originKnown: z.boolean(),
        distanceMeters: z.number().nullable(),
        walkMinutes: z.number().nullable(),
        note: z.string().optional(),
      }),
    },
    async ({ latitude, longitude }, { context }) => {
      const loc = context && context.location;
      const hasLoc =
        loc && typeof loc.latitude === "number" && typeof loc.longitude === "number";
      if (!hasLoc) {
        return {
          originKnown: false,
          distanceMeters: null,
          walkMinutes: null,
          note: "No origin GPS available; can't measure the walk.",
        };
      }
      const distanceMeters = Math.round(haversineMeters(loc, { latitude, longitude }));
      return {
        originKnown: true,
        distanceMeters,
        walkMinutes: walkMinutes(distanceMeters),
        note: "Straight-line estimate (not a routed path).",
      };
    },
  );
}

module.exports = { defineRouteDistance };
