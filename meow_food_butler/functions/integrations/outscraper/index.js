/**
 * Outscraper skill: query Google Maps via Outscraper and return app-shaped data.
 *
 *   fetchRestaurantDetail(query) -> FoodCard map (or null)
 *   fetchReviews(query, limit)   -> review snippet maps
 *   fetchPhotos(query, tag, n)   -> high-res photo URL list
 *
 * All accept either a place name OR a Google place_id / Maps URL (preferred — it
 * resolves the EXACT place instead of a fuzzy name match).
 */

const { prepareQuery, outscraperGet, firstPlace } = require("./client");
const { placeToFoodCard, toReviewSnippets, toPhotoUrls } = require("./transform");

async function fetchRestaurantDetail(query) {
  const processed = await prepareQuery(query);
  const data = await outscraperGet("maps/search-v3", {
    query: processed,
    limit: 1,
    language: "zh-tw",
    async: false,
  });
  const place = firstPlace(data);
  if (!place) return null;
  return placeToFoodCard(place, { fallbackName: (query || "").trim() });
}

async function fetchReviews(query, limit = 10) {
  const processed = await prepareQuery(query);
  const data = await outscraperGet("maps/reviews-v3", {
    query: processed,
    reviewsLimit: limit,
    language: "zh-tw",
    sort: "newest",
    async: false,
  });
  const place = data[0];
  return toReviewSnippets(place && place.reviews_data);
}

async function fetchPhotos(query, tag = "menu", photosLimit = 10) {
  const processed = await prepareQuery(query);
  const data = await outscraperGet("google-maps-photos", {
    query: processed,
    photosLimit: photosLimit > 0 ? photosLimit : 100,
    limit: 1,
    tag,
    language: "zh-tw",
    async: false,
  });
  let place = data[0];
  if (Array.isArray(place) && place.length) place = place[0]; // nested-list guard
  return toPhotoUrls(place && place.photos_data);
}

module.exports = { fetchRestaurantDetail, fetchReviews, fetchPhotos };
