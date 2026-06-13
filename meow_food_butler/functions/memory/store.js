/**
 * Long-term memory (RAG), keyed per user.
 *
 * "First version" design: real Gemini embeddings, stored as a plain Firestore
 * array field, with nearest-neighbor computed by brute-force cosine in the
 * function. No vector index / extra dependency — fine for a demo-scale corpus.
 * Upgrade path: Firestore Vector Search (`findNearest`) once it grows.
 *
 * This is the *distilled* layer (facts/preferences), separate from the verbatim
 * chat history in `sessions/store.js`.
 */

const { googleAI } = require("@genkit-ai/googleai");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const { EMBEDDER } = require("../config");
const { memoryCol } = require("../collections");

// Cap how many memories we pull for brute-force scoring (demo-scale guard).
const MAX_SCAN = 200;

/** Embed `text` into a numeric vector via the Gemini embedding model. */
async function embed(ai, text) {
  const res = await ai.embed({
    embedder: googleAI.embedder(EMBEDDER),
    content: text,
  });
  // Genkit returns an array of `{ embedding: number[] }`; be defensive about shape.
  const first = Array.isArray(res) ? res[0] : res;
  const vector = (first && (first.embedding || first.output || first)) || [];
  return Array.isArray(vector) ? vector : [];
}

/** Cosine similarity of two equal-length numeric vectors. */
function cosine(a, b) {
  if (!a || !b || a.length !== b.length || a.length === 0) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i += 1) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

/**
 * Persist a distilled memory for a user.
 * @returns {Promise<{ saved: boolean, id?: string, error?: string }>}
 */
async function remember(ai, { userId, text, kind = "note", sessionId = null }) {
  if (!text || !text.trim()) return { saved: false, error: "empty text" };
  try {
    const embedding = await embed(ai, text);
    const ref = await memoryCol(userId).add({
      text: text.trim(),
      kind,
      embedding,
      sessionId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { saved: true, id: ref.id };
  } catch (e) {
    logger.warn("memory.remember failed", e);
    return { saved: false, error: String(e && e.message) };
  }
}

/**
 * Retrieve the top-k memories most relevant to `query` for a user.
 * Returns `[]` on empty store or any failure (recall is best-effort).
 * @returns {Promise<Array<{ text: string, kind: string, score: number }>>}
 */
async function recall(ai, { userId, query, k = 5, floor = 0.3 }) {
  if (!query || !query.trim()) return [];
  try {
    const snap = await memoryCol(userId).limit(MAX_SCAN).get();
    if (snap.empty) return [];

    const queryVec = await embed(ai, query);
    const scored = [];
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (!Array.isArray(d.embedding)) return;
      const score = cosine(queryVec, d.embedding);
      if (score >= floor) {
        scored.push({ text: d.text, kind: d.kind || "note", score });
      }
    });
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, k);
  } catch (e) {
    logger.warn("memory.recall failed", e);
    return [];
  }
}

module.exports = { embed, remember, recall, cosine };
