/**
 * Verbatim chat history (the "session" layer), keyed per user.
 *
 * Backend is the single writer of messages so ordering is consistent; the
 * client streams the same paths read-only. Message docs use the client's
 * `ChatMessage` schema (`senderId`/`messageText`/`type`/`timestamp`) so the
 * Flutter model deserializes them directly. Separate from the distilled
 * `memory/store.js` (RAG) layer.
 */

const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const { sessionsCol, messagesCol } = require("../collections");

const AI_SENDER = "ai_agent";
const USER_SENDER = "user";

/** Append a message and bump the session's `updatedAt` (+ seed title once). */
async function appendMessage(userId, sessionId, { role, text }) {
  const senderId = role === "assistant" ? AI_SENDER : USER_SENDER;
  await messagesCol(userId, sessionId).add({
    senderId,
    messageText: text,
    type: "text",
    timestamp: FieldValue.serverTimestamp(),
  });

  const sessionRef = sessionsCol(userId).doc(sessionId);
  const update = { updatedAt: FieldValue.serverTimestamp() };
  if (senderId === USER_SENDER) {
    const snap = await sessionRef.get();
    if (!snap.exists || !(snap.data() || {}).title) {
      update.title = text.slice(0, 40);
    }
  }
  await sessionRef.set(update, { merge: true });
}

/**
 * Last `n` messages of a session, oldest-first, mapped to Genkit `messages`
 * (`{ role: 'user'|'model', content: [{ text }] }`). Best-effort: returns `[]`
 * on failure so a history read never breaks a reply.
 */
async function recentMessages(userId, sessionId, n = 10) {
  try {
    const snap = await messagesCol(userId, sessionId)
      .orderBy("timestamp", "desc")
      .limit(n)
      .get();
    const docs = snap.docs.reverse(); // back to oldest-first
    return docs.map((doc) => {
      const d = doc.data() || {};
      return {
        role: d.senderId === AI_SENDER ? "model" : "user",
        content: [{ text: d.messageText || "" }],
      };
    });
  } catch (e) {
    logger.warn("sessions.recentMessages failed", e);
    return [];
  }
}

module.exports = { appendMessage, recentMessages };
