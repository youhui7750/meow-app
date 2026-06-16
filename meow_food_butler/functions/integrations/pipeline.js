/**
 * Instagram import pipeline — the integrator (server-side port of the Dart
 * `instagram_import_vm.dart::pipelineImportAndBuildCard`). Ties together apify +
 * extract + outscraper and assembles the `{ experience, restaurant }` maps the
 * client deserializes with `ExperienceCard.fromMap` / `FoodCard.fromMap`.
 *
 * Returns a fail-safe envelope: `{ ok, code, reply?, experience?, restaurant? }`.
 */

const logger = require("firebase-functions/logger");

const apify = require("./apify");
const outscraper = require("./outscraper");
const { extractRestaurantName } = require("./extract");

const FALLBACK_TAGS = ["IG匯入", "待吃清單"];

/** Pull ASCII hashtags from the caption (mirrors the Dart `#(\w+)` regex). */
function extractHashtags(text) {
  return [...String(text || "").matchAll(/#(\w+)/g)].map((m) => m[1]);
}

/** Dedup + order-preserving photo-URL merge. */
function mergePhotoUrls(base, extra) {
  const seen = new Set();
  const merged = [];
  for (const url of [...(base || []), ...(extra || [])]) {
    const trimmed = (url || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    merged.push(trimmed);
  }
  return merged;
}

/** Assemble the ExperienceCard map (nests `location` exactly like its toMap). */
function buildExperienceMap({ detail, igUrl, photoUrls, tags, caption }) {
  const placeId = detail ? detail.id : null;
  const placeTitle = detail ? detail.displayNames[0].title : null;
  const placeAddress = detail ? detail.formattedAddress : null;
  const lat = detail && detail.location ? detail.location.latitude : null;
  const lng = detail && detail.location ? detail.location.longitude : null;

  return {
    foodCardId: null,
    placeId,
    placeTitle,
    region: null,
    location:
      lat != null && lng != null
        ? { placeId, name: placeTitle, address: placeAddress, region: null, latitude: lat, longitude: lng }
        : null,
    originalURL: igUrl,
    googleMapsUrl: detail ? detail.googleMapsUrl : null,
    photoPaths: [],
    photoUrls,
    personalTags: tags,
    personalRating: 0,
    personalNote: caption,
    isDone: false,
    // createdTime omitted on purpose: FoodCard/ExperienceCard.fromMap default it
    // to Timestamp.now() client-side (a callable can't carry a Firestore Timestamp).
  };
}

/** Apply the import overlay to a FoodCard map (mirrors FoodCard.copyForImport). */
function applyImport(card, { igUrl, tags, photoUrls, reviewSnippets }) {
  return {
    ...card,
    originalURL: igUrl,
    visited: false,
    tags,
    photoUrls,
    reviewSnippets,
  };
}

/** Minimal FoodCard map when Outscraper returns nothing. */
function fallbackFoodCard({ igUrl, placeTitle, address, photoUrls, tags, reviewSnippets }) {
  return {
    id: null,
    originalURL: igUrl,
    formattedAddress: address || null,
    visited: false,
    tags,
    photoUrls,
    photoPaths: [],
    reviewSnippets,
    subtypes: [],
    displayNames: [{ title: placeTitle || "Unknown Food Spot", languageCode: "zh-TW" }],
    location: null,
  };
}

/**
 * @param {string} igUrl
 * @returns {Promise<object>} fail-safe envelope.
 */
async function importInstagram(igUrl) {
  const url = (igUrl || "").trim();
  if (!url) return { ok: false, code: "bad-url", reply: "😿 No Instagram link was provided, nya." };

  // 1. Apify: caption + check-in location.
  const ig = await apify.fetchIgCaptionAndLocation(url);
  if (!ig || !ig.caption) {
    return { ok: false, code: "ig-unreadable", reply: "😿 I couldn't read that post — is the link public?" };
  }
  const { caption } = ig;

  // 2. Query: extract restaurant name from caption only (location tag ignored).
  const query = await extractRestaurantName(caption);
  if (!query) {
    return { ok: false, code: "no-restaurant", reply: "😿 I couldn't spot a clear restaurant name in that post." };
  }
  logger.info("importInstagram query resolved", { query });

  // 3. Outscraper — detail + menu photos + reviews IN PARALLEL.
  const [detail, menuPhotos, reviewSnippets] = await Promise.all([
    outscraper.fetchRestaurantDetail(query),
    outscraper.fetchPhotos(query, "menu", 5),
    outscraper.fetchReviews(query, 3),
  ]);

  // 4. Tags from caption hashtags (with fallback).
  let tags = extractHashtags(caption);
  if (tags.length === 0) tags = [...FALLBACK_TAGS];

  // 5. Merge photo URLs (detail photo first, then menu photos).
  const photoUrls = mergePhotoUrls(detail ? detail.photoUrls : [], menuPhotos);

  // 6. Assemble experience + restaurant maps.
  const experience = buildExperienceMap({ detail, igUrl: url, photoUrls, tags, caption });
  const restaurant = detail
    ? applyImport(detail, { igUrl: url, tags, photoUrls, reviewSnippets })
    : fallbackFoodCard({
        igUrl: url,
        placeTitle: experience.placeTitle || query,
        address: experience.location ? experience.location.address : null,
        photoUrls,
        tags,
        reviewSnippets,
      });

  return { ok: true, code: "ok", experience, restaurant };
}

module.exports = { importInstagram };
