/**
 * Skill: searchSpots (L1) — real candidate food spots for a craving, near the
 * user. Google Places (v1) Text Search, biased to the user's current GPS
 * (`context.location`). No mock data: if there's no location, no API key, or no
 * matches, it says so honestly and returns an empty list.
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");

const { haversineMeters, walkMinutes } = require("../../geo");

/**
 * Google Places (v1) Text Search around the user. Node 24 has fetch.
 *
 * `rankPreference: DISTANCE` makes Places rank by proximity rather than text
 * relevance, so a famous-but-far spot in the same district doesn't outrank a
 * closer match. We still keep `locationBias` (Text Search circles are a bias,
 * not a hard restriction) and enforce real nearness by post-filtering on the
 * distance we compute ourselves.
 */
async function searchText({ query, latitude, longitude, apiKey, radius = 1500 }) {
  const resp = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
        "places.id,places.displayName,places.formattedAddress,places.location,places.rating",
    },
    body: JSON.stringify({
      textQuery: query,
      maxResultCount: 10,
      rankPreference: "DISTANCE",
      locationBias: {
        circle: { center: { latitude, longitude }, radius },
      },
    }),
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Places searchText ${resp.status}: ${body.slice(0, 300)}`);
  }

  const data = await resp.json();
  return (data.places || []).map((p) => ({
    id: p.id,
    displayName: (p.displayName && p.displayName.text) || "Unknown spot",
    address: p.formattedAddress || null,
    rating: typeof p.rating === "number" ? p.rating : null,
    location: p.location || null,
  }));
}

function defineSearchSpots(ai, { placesApiKey = "" } = {}) {
  return ai.defineTool(
    {
      name: "searchSpots",
      description:
        "L1 skill. Finds REAL nearby food spots matching a craving (cuisine or " +
        "dish) around the user's current location. Returns a candidate list with " +
        "rating and walking distance, closest first. If it returns no candidates, " +
        "tell the user plainly that you couldn't find a match nearby — do NOT " +
        "invent places or ask them to re-spell the dish.",
      inputSchema: z.object({
        cuisine: z
          .string()
          .describe("the craving to search for, e.g. 'ramen' or 'peanut roll ice cream'"),
      }),
      outputSchema: z.object({
        locationKnown: z.boolean(),
        candidates: z.array(
          z.object({
            id: z.string(),
            displayName: z.string(),
            address: z.string().nullable(),
            rating: z.number().nullable(),
            distanceMeters: z.number().nullable(),
            walkMinutes: z.number().nullable(),
            latitude: z.number().nullable(),
            longitude: z.number().nullable(),
          }),
        ),
        note: z.string().optional(),
      }),
    },
    async ({ cuisine }, { context }) => {
      const loc = context && context.location;
      const hasLoc =
        loc && typeof loc.latitude === "number" && typeof loc.longitude === "number";

      if (!hasLoc) {
        return {
          locationKnown: false,
          candidates: [],
          note:
            "No GPS coordinates available. If location permission is on, call " +
            "whereAmI; otherwise ask the user to enable location.",
        };
      }
      if (!placesApiKey) {
        return {
          locationKnown: true,
          candidates: [],
          note: "No Places API key configured, so I can't search for real spots.",
        };
      }

      try {
        const radius = 1500;
        const places = await searchText({
          query: cuisine,
          latitude: loc.latitude,
          longitude: loc.longitude,
          apiKey: placesApiKey,
          radius,
        });
        const ranked = places
          .map((p) => {
            const here = p.location && {
              latitude: p.location.latitude,
              longitude: p.location.longitude,
            };
            const distanceMeters = here
              ? Math.round(haversineMeters(loc, here))
              : null;
            return {
              id: p.id,
              displayName: p.displayName,
              address: p.address,
              rating: p.rating,
              distanceMeters,
              walkMinutes: distanceMeters != null ? walkMinutes(distanceMeters) : null,
              latitude: here ? here.latitude : null,
              longitude: here ? here.longitude : null,
            };
          })
          .sort((a, b) => (a.distanceMeters ?? 1e12) - (b.distanceMeters ?? 1e12));

        // Enforce real nearness: keep only spots within the search radius. If the
        // bias still let only far results through, return the single closest with
        // a note so the agent can be honest that it's farther than usual.
        const near = ranked.filter(
          (c) => c.distanceMeters != null && c.distanceMeters <= radius,
        );
        if (near.length) {
          return { locationKnown: true, candidates: near, note: "Real results, closest first." };
        }
        if (ranked.length) {
          return {
            locationKnown: true,
            candidates: ranked.slice(0, 1),
            note:
              `Nothing matching "${cuisine}" within ${radius}m. The closest is ` +
              `${ranked[0].distanceMeters}m away — tell the user it's farther than usual, don't pretend it's close.`,
          };
        }
        return {
          locationKnown: true,
          candidates: [],
          note: `No spots matching "${cuisine}" nearby — tell the user honestly.`,
        };
      } catch (e) {
        logger.warn("searchSpots Places lookup failed", e);
        return {
          locationKnown: true,
          candidates: [],
          note: `Places search failed (${e.message}). Tell the user you couldn't search right now.`,
        };
      }
    },
  );
}

module.exports = { defineSearchSpots, searchText };
