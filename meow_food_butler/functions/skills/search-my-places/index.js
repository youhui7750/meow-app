/**
 * Skill: searchMyPlaces (L1) — find restaurants from the user's saved/imported
 * My Places, not their dining-log history.
 *
 * Use this when the user asks what they could eat from places they already
 * saved/imported, e.g. "我有什麼想吃的拉麵嗎". The client renders the matching
 * restaurant cards from the returned UI action.
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");

const { restaurantsCol, DEMO_USER } = require("../../collections");
const { haversineMeters, formatDistance } = require("../../geo");

const SCAN_LIMIT = 150;
const RESULT_LIMIT = 5;
// A bare "what's on my wishlist?" browse can surface more cards than a focused
// craving search, since there's no keyword narrowing it down.
const BROWSE_LIMIT = 10;

function matchesNeedle(data, needle) {
  const haystack = [
    data.placeTitle,
    data.formattedAddress,
    data.placeAddress,
    data.category,
    ...(Array.isArray(data.subtypes) ? data.subtypes : []),
    data.description,
    data.region,
    data.personalNote,
    ...(Array.isArray(data.tags) ? data.tags : []),
    ...(Array.isArray(data.personalTags) ? data.personalTags : []),
  ]
    .filter((s) => typeof s === "string" && s)
    .join(" ")
    .toLowerCase();
  return haystack.includes(needle);
}

function coordinatesOf(data) {
  const location = data.location || {};
  const latitude =
    typeof data.latitude === "number" ? data.latitude : location.latitude;
  const longitude =
    typeof data.longitude === "number" ? data.longitude : location.longitude;
  if (typeof latitude !== "number" || typeof longitude !== "number") {
    return null;
  }
  return { latitude, longitude };
}

function isNotDonePlace(data) {
  return data.visited !== true && data.isDone !== true;
}

function defineSearchMyPlaces(ai) {
  return ai.defineTool(
    {
      name: "searchMyPlaces",
      description:
        "Find restaurants from the user's imported / want-to-go My Places. " +
        "Call this when the user asks what they want to eat or want to visit " +
        "from saved/imported places. Pass a craving/cuisine/tag/place keyword to " +
        "filter; OMIT query (or pass an empty string) to LIST ALL of their " +
        "want-to-go places — use that for broad asks like '我有什麼想吃的', " +
        "'show my wishlist', or 'any imported restaurants?'. Do not use this for " +
        "completed dining logs. This returns card ids and the app displays the " +
        "restaurant cards automatically.",
      inputSchema: z.object({
        query: z
          .string()
          .optional()
          .describe(
            "Craving/cuisine/tag keyword, e.g. '拉麵', 'ramen', '咖啡廳'. " +
              "Omit or leave empty to list ALL want-to-go places.",
          ),
      }),
      outputSchema: z.object({
        found: z.boolean(),
        query: z.string(),
        count: z.number(),
        candidates: z.array(
          z.object({
            id: z.string(),
            placeTitle: z.string().nullable(),
            rating: z.number().nullable(),
            distanceMeters: z.number().nullable(),
            walkMinutes: z.number().nullable(),
            distanceLabel: z.string().nullable(),
          }),
        ),
      }),
    },
    async ({ query }, { context }) => {
      const userId = (context && context.userId) || DEMO_USER;
      const needle = (query || "").trim().toLowerCase();
      // No keyword => browse mode: list every want-to-go place.
      const browse = !needle;

      let docs = [];
      try {
        const snap = await restaurantsCol(userId)
          .orderBy("createdTime", "desc")
          .limit(SCAN_LIMIT)
          .get();
        docs = snap.docs;
      } catch (e) {
        logger.warn("searchMyPlaces: restaurants read failed", e);
      }

      const loc = context && context.location;
      const hasLoc =
        loc && typeof loc.latitude === "number" && typeof loc.longitude === "number";

      const candidates = docs
        .map((doc) => ({ id: doc.id, data: doc.data() || {} }))
        .filter(({ data }) => isNotDonePlace(data))
        .filter(({ data }) => browse || matchesNeedle(data, needle))
        .map(({ id, data }) => {
          const here = coordinatesOf(data);
          const dist =
            hasLoc && here
              ? formatDistance(haversineMeters(loc, here))
              : { distanceMeters: null, walkMinutes: null, distanceLabel: null };
          return {
            id,
            placeTitle:
              typeof data.placeTitle === "string"
                ? data.placeTitle
                : Array.isArray(data.displayNames) &&
                    data.displayNames[0] &&
                    typeof data.displayNames[0].text === "string"
                  ? data.displayNames[0].text
                  : null,
            rating:
              typeof data.rating === "number" ? data.rating : null,
            distanceMeters: dist.distanceMeters,
            walkMinutes: dist.walkMinutes,
            distanceLabel: dist.distanceLabel,
          };
        })
        .sort((a, b) => {
          if (a.distanceMeters != null || b.distanceMeters != null) {
            return (a.distanceMeters ?? 1e12) - (b.distanceMeters ?? 1e12);
          }
          return 0;
        })
        .slice(0, browse ? BROWSE_LIMIT : RESULT_LIMIT);

      if (candidates.length && context && Array.isArray(context.actions)) {
        const ids = candidates.map((candidate) => candidate.id);
        context.actions.push({
          type: "showRestaurantCards",
          experienceIds: ids,
          recommendedSpotIds: ids,
        });
      }

      return {
        found: candidates.length > 0,
        query: query || "",
        count: candidates.length,
        candidates,
      };
    },
  );
}

module.exports = { defineSearchMyPlaces };
