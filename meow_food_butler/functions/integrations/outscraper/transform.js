/**
 * Outscraper place JSON -> the app's card/review/photo shapes.
 *
 * `placeToFoodCard` returns a plain map that the Flutter `FoodCard.fromMap`
 * deserializes directly (camelCase keys matching `FoodCard.toMap`), so the client
 * needs no transform code of its own.
 */

const { toHighResPhotoUrl } = require("./client");

const str = (v) => (typeof v === "string" && v.trim() ? v : v == null ? null : String(v));
const num = (v) => (typeof v === "number" ? v : typeof v === "string" && v.trim() ? Number(v) : null);

function readStringList(v) {
  if (Array.isArray(v)) return v.map((x) => String(x).trim()).filter(Boolean);
  if (typeof v === "string") return v.split(/[,、]/).map((s) => s.trim()).filter(Boolean);
  return [];
}

/** Outscraper `search-v3` place object -> FoodCard map (fromMap-ready). */
function placeToFoodCard(place, { fallbackName } = {}) {
  if (!place || typeof place !== "object") return null;

  const name = str(place.name) || fallbackName || null;
  const latitude = num(place.latitude);
  const longitude = num(place.longitude);
  const photo = toHighResPhotoUrl(str(place.photo));

  return {
    id: str(place.place_id) || str(place.google_id) || str(place.cid),
    placeId: str(place.place_id) || str(place.google_id) || str(place.cid),
    googleMapsUrl: str(place.location_link),
    formattedAddress: str(place.address),
    rating: num(place.rating),
    reviews: num(place.reviews),
    phone: str(place.phone),
    website: str(place.website),
    priceRange: str(place.range) || str(place.prices),
    category: str(place.category) || str(place.type),
    subtypes: readStringList(place.subtypes),
    description: str(place.description),
    workingHours:
      place.working_hours && typeof place.working_hours === "object"
        ? place.working_hours
        : null,
    popularTimes: place.popular_times ?? null,
    typicalTimeSpent: str(place.typical_time_spent),
    menuLink: str(place.menu_link),
    bookingLink: str(place.booking_appointment_link),
    verified: typeof place.verified === "boolean" ? place.verified : null,
    photoUrls: photo ? [photo] : [],
    photoPaths: [],
    tags: [],
    reviewSnippets: [],
    displayNames: [{ title: name || "Unknown Food Spot", languageCode: "zh-TW" }],
    location:
      latitude != null && longitude != null ? { latitude, longitude } : null,
  };
}

/** Outscraper `reviews-v3` `reviews_data` -> the app's review snippet maps. */
function toReviewSnippets(reviewsData) {
  if (!Array.isArray(reviewsData)) return [];
  return reviewsData.map((r) => ({
    author: r.author_title ?? "",
    author_id: r.author_id ?? "",
    rating: r.review_rating ?? null,
    text: r.review_text ?? "",
    likes: r.review_likes ?? null,
    datetime: r.review_datetime_utc ?? "",
    relative_time: r.review_timestamp ?? "",
    response: r.owner_answer ?? "",
    response_time: r.owner_answer_timestamp_datetime_utc ?? "",
  }));
}

/** Outscraper photos `photos_data` -> high-res photo URL list. */
function toPhotoUrls(photosData) {
  if (!Array.isArray(photosData)) return [];
  return photosData
    .map((p) => toHighResPhotoUrl(p.photo_url_large || p.photo_url))
    .filter((url) => url && url.length);
}

module.exports = { placeToFoodCard, toReviewSnippets, toPhotoUrls };
