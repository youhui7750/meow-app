/**
 * Firestore foundation for the agent (Phase 0).
 *
 * Collections are created lazily by Firestore on first write — there's nothing
 * to "provision". This module just centralizes their names and a shared admin /
 * db handle so every tool refers to the same identifiers.
 */

const admin = require("firebase-admin");

// Cloud Functions provide default credentials; initialize once per instance.
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/** Canonical collection names used across the agent's tools. */
const COLLECTIONS = {
  foodCards: "food_cards", // FoodCard candidates (Places-shaped)
  experiences: "experiences", // ExperienceCard saved records
  preferences: "preferences", // per-user structured prefs (RAG source)
  memory: "memory", // per-user memory log / embeddings (RAG source)
};

module.exports = { admin, db, COLLECTIONS };
