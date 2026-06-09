/**
 * The butler's skills, registered as Genkit tools (Phase 0).
 *
 * These are the boxes from `agentic_flow.png`. In "Mix" mode the Gemini model is
 * real and orchestrates these tools, but the tools themselves return
 * deterministic MOCK data so the L1→L2 loop is exercisable without external API
 * keys. Each `TODO(real)` marks exactly where the real integration plugs in.
 *
 * Tools must be defined on the SAME Genkit instance that runs the flow, so this
 * is a factory: `registerTools(ai)` returns the tool refs to pass to generate().
 */

const { z } = require("genkit");
const logger = require("firebase-functions/logger");
const { db, COLLECTIONS } = require("./collections");

// Phase 0 has no auth wired yet; everything reads/writes a single demo user.
const DEMO_USER = "demo_user";

/**
 * Resolve a lat/lng into nearby restaurants via Google Places API (v1).
 * Mirrors the client's `NearbyPlacesService.restaurantsNear` so the agent sees
 * the same data the UI does. Node 24 has global `fetch`.
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

function registerTools(ai, opts = {}) {
  const placesApiKey = opts.placesApiKey || "";

  // --- L2: Where am I? (Tool: Location + Places API) -----------------------
  const whereAmI = ai.defineTool(
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

  // --- L1: Find Free Time (Tool: User Calendar) ----------------------------
  const findFreeTime = ai.defineTool(
    {
      name: "findFreeTime",
      description:
        "L1 skill. Returns the user's free time slots from their calendar. " +
        "Use this first to know WHEN to plan an outing.",
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
            startsAfter: z.string().describe("HH:mm the user becomes free"),
          }),
        ),
      }),
    },
    async () => {
      // TODO(real): Google Calendar API. Mock: free Friday after 15:20.
      return { slots: [{ day: "Friday", startsAfter: "15:20" }] };
    },
  );

  // --- L1: Memory Retrieval (Tool: Preferences DB / RAG) -------------------
  const recallMemory = ai.defineTool(
    {
      name: "recallMemory",
      description:
        "L1 skill. Retrieves the user's food preferences and relevant past " +
        "experiences (RAG). Use this to personalize recommendations.",
      inputSchema: z.object({
        query: z.string().describe("What to recall, e.g. 'dinner near campus'"),
      }),
      outputSchema: z.object({
        likes: z.array(z.string()),
        dislikes: z.array(z.string()),
        maxWalkMinutes: z.number(),
        source: z.enum(["firestore", "mock"]),
      }),
    },
    async () => {
      // Real read of the preferences collection, with a mock fallback so the
      // flow works before any prefs are seeded. TODO(real): embed `query` and
      // do nearest-neighbor over the `memory` collection too.
      const fallback = {
        likes: ["ramen"],
        dislikes: ["crowds"],
        maxWalkMinutes: 20,
        source: "mock",
      };
      try {
        const snap = await db.collection(COLLECTIONS.preferences).doc(DEMO_USER).get();
        if (!snap.exists) return fallback;
        const d = snap.data() || {};
        return {
          likes: d.likes || fallback.likes,
          dislikes: d.dislikes || fallback.dislikes,
          maxWalkMinutes: d.maxWalkMinutes ?? fallback.maxWalkMinutes,
          source: "firestore",
        };
      } catch (e) {
        logger.warn("recallMemory firestore read failed; using mock", e);
        return fallback;
      }
    },
  );

  // --- L1: Search & Parse (Tool: Web Scraper / IG Parser) ------------------
  const searchSpots = ai.defineTool(
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
    async ({ cuisine }) => {
      // TODO(real): Google Places + IG saved-links parser. Mock candidate list.
      return {
        candidates: [
          { id: "taihe-ramen", displayName: "Tai-He Ramen", rating: 4.5, approxWalkMinutes: 18 },
          { id: "menya-crowd", displayName: "Menya (busy)", rating: 4.7, approxWalkMinutes: 12 },
        ].filter(() => cuisine.toLowerCase().includes("ram") || true),
      };
    },
  );

  // --- L2: Distance Calculation (Tool: Maps API / Location) ----------------
  const routeDistance = ai.defineTool(
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

  // --- L2: Record Writing (Tool: Sentiment & Image AI) ---------------------
  const draftExperience = ai.defineTool(
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

  return [whereAmI, findFreeTime, recallMemory, searchSpots, routeDistance, draftExperience];
}

module.exports = { registerTools, searchNearby };
