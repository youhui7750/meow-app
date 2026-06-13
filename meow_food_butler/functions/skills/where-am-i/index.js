/**
 * Skill: whereAmI (L2) — resolve the user's GPS into named nearby places.
 *
 * Reads the GPS coordinates the client passed via Genkit `context.location`,
 * then queries Google Places (v1) `searchNearby`. Real integration.
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");

/**
 * Resolve a lat/lng into nearby restaurants via Google Places API (v1).
 * Node 24 has global `fetch`.
 */
async function searchNearby(latitude, longitude, apiKey) {
  const resp = await fetch(
    "https://places.googleapis.com/v1/places:searchNearby",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.location",
      },
      body: JSON.stringify({
        includedTypes: ["restaurant"],
        maxResultCount: 10,
        locationRestriction: {
          circle: {
            center: { latitude, longitude },
            radius: 150.0,
          },
        },
      }),
    },
  );

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Places searchNearby ${resp.status}: ${body.slice(0, 300)}`);
  }

  const data = await resp.json();
  return (data.places || []).map((p) => ({
    id: p.id,
    name: (p.displayName && p.displayName.text) || "Unknown restaurant",
    address: p.formattedAddress || null,
  }));
}

function defineWhereAmI(ai, { placesApiKey = "" } = {}) {
  return ai.defineTool(
    {
      name: "whereAmI",
      description:
        "Resolve the user's CURRENT real-world location into named place(s). " +
        "Call this whenever the user asks where they are, or when you need their " +
        "current position. It uses the GPS coordinates the app passed in. If no " +
        "coordinates are available, it returns permissionGranted=false — then ask " +
        "the user to enable location permission. Do NOT assert a single place; " +
        "present the top nearby candidates and let the user pick.",
      inputSchema: z.object({}),
      outputSchema: z.object({
        permissionGranted: z.boolean(),
        latitude: z.number().optional(),
        longitude: z.number().optional(),
        nearby: z
          .array(z.object({ name: z.string(), address: z.string().nullable() }))
          .optional(),
        note: z.string().optional(),
      }),
    },
    async (_input, { context }) => {
      const loc = context && context.location;
      if (
        !loc ||
        typeof loc.latitude !== "number" ||
        typeof loc.longitude !== "number"
      ) {
        return {
          permissionGranted: false,
          note:
            "No GPS coordinates were provided by the app. Ask the user to grant " +
            "location permission, then try again.",
        };
      }

      if (!placesApiKey) {
        return {
          permissionGranted: true,
          latitude: loc.latitude,
          longitude: loc.longitude,
          note:
            "Got the coordinates but no Places API key is configured, so I can't " +
            "name the spot. Share the raw lat/lng with the user.",
        };
      }

      try {
        const nearby = await searchNearby(loc.latitude, loc.longitude, placesApiKey);
        return {
          permissionGranted: true,
          latitude: loc.latitude,
          longitude: loc.longitude,
          nearby: nearby.slice(0, 5),
          note: nearby.length
            ? "Offer these as candidates; the closest is first."
            : "No restaurants within ~150m; share the coordinates instead.",
        };
      } catch (e) {
        logger.warn("whereAmI Places lookup failed", e);
        return {
          permissionGranted: true,
          latitude: loc.latitude,
          longitude: loc.longitude,
          note: `Places lookup failed (${e.message}). Share the coordinates instead.`,
        };
      }
    },
  );
}

module.exports = { defineWhereAmI, searchNearby };
