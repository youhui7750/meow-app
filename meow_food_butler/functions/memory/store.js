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

// Embedding models to try, best first. The Gemini Developer API exposes a
// different set per key/version (we've seen text-embedding-004 return 404), so
// we fall through this list and cache the first that works. Keys must be embedded
// with the SAME model for read+write — fine here since the cache is process-wide
// and the memory collection starts empty.
const EMBED_CANDIDATES = [
  EMBEDDER,
  "gemini-embedding-001",
  "text-embedding-004",
  "embedding-001",
].filter((v, i, arr) => v && arr.indexOf(v) === i);
let _workingEmbedder = null;

/** Embed `text` into a numeric vector via the Gemini embedding model. */
async function embed(ai, text) {
  const candidates = _workingEmbedder ? [_workingEmbedder] : EMBED_CANDIDATES;
  let lastErr;
  for (const model of candidates) {
    try {
      const res = await ai.embed({ embedder: googleAI.embedder(model), content: text });
      // Genkit returns an array of `{ embedding: number[] }`; be defensive about shape.
      const first = Array.isArray(res) ? res[0] : res;
      const vector = (first && (first.embedding || first.output || first)) || [];
      if (Array.isArray(vector) && vector.length) {
        if (_workingEmbedder !== model) {
          _workingEmbedder = model;
          logger.info(`memory: using embedding model "${model}"`);
        }
        return vector;
      }
    } catch (e) {
      lastErr = e;
      // Try the next candidate (e.g. on 404 model-not-found for this key).
    }
  }
  throw lastErr || new Error("no embedding model produced a vector");
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

/**
 * Delete a user's memories that match `query` above a (high) similarity floor.
 * Used when the user retracts or changes a preference, so stale facts don't keep
 * getting recalled. Best-effort: returns `{ deleted, texts }`, never throws.
 *
 * The floor defaults high (0.82) so we only remove memories that clearly mean
 * the same thing as `query` — better to leave a borderline memory than to wipe
 * an unrelated one.
 * @returns {Promise<{ deleted: number, texts: string[] }>}
 */
async function forget(ai, { userId, query, floor = 0.82, max = 20 }) {
  if (!query || !query.trim()) return { deleted: 0, texts: [] };
  try {
    const snap = await memoryCol(userId).limit(MAX_SCAN).get();
    if (snap.empty) return { deleted: 0, texts: [] };

    const queryVec = await embed(ai, query);
    const matches = [];
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (!Array.isArray(d.embedding)) return;
      if (cosine(queryVec, d.embedding) >= floor) {
        matches.push({ ref: doc.ref, text: d.text });
      }
    });
    if (!matches.length) return { deleted: 0, texts: [] };

    const victims = matches.slice(0, max);
    const batch = memoryCol(userId).firestore.batch();
    victims.forEach((m) => batch.delete(m.ref));
    await batch.commit();
    return { deleted: victims.length, texts: victims.map((m) => m.text) };
  } catch (e) {
    logger.warn("memory.forget failed", e);
    return { deleted: 0, texts: [] };
  }
}

module.exports = { embed, remember, recall, forget, cosine };
