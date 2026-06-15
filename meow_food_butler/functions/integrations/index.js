/**
 * Integrations barrel: third-party API logic, one folder per provider.
 *
 *   apify/      — Instagram scraping
 *   outscraper/ — Google Maps via Outscraper (place detail / reviews / photos)
 *   extract/    — AI restaurant-name extraction (Gemini)
 *   pipeline.js — the IG import orchestrator (apify → extract → outscraper → cards)
 *   keys.js     — live provider keys from Firestore config/* docs
 *
 * Keys are read at request time (see keys.js) — no defineSecret/redeploy to rotate.
 */

const apify = require("./apify");
const outscraper = require("./outscraper");
const extract = require("./extract");
const { importInstagram } = require("./pipeline");
const { getApifyToken, getOutscraperKey } = require("./keys");

module.exports = {
  apify,
  outscraper,
  extract,
  importInstagram,
  // Re-exported for the single-place lookup callable.
  fetchRestaurantDetail: outscraper.fetchRestaurantDetail,
  fetchReviews: outscraper.fetchReviews,
  fetchPhotos: outscraper.fetchPhotos,
  getApifyToken,
  getOutscraperKey,
};
