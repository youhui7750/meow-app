/**
 * Firestore foundation for the agent.
 *
 * Everything is stored under a per-user tree (`users/{uid}/…`) so going
 * multi-user later is just a matter of swapping the id. Collections are created
 * lazily by Firestore on first write — there's nothing to "provision".
 *
 *   users/{uid}/sessions/{sessionId}              { title, createdAt, updatedAt }
 *   users/{uid}/sessions/{sessionId}/messages/{m} { role, text, createdAt }
 *   users/{uid}/memory/{m}                         { text, kind, embedding, … }
 *   users/{uid}/preferences/profile                { likes, dislikes, maxWalkMinutes }
 */

const admin = require("firebase-admin");

// Cloud Functions provide default credentials; initialize once per instance.
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Phase 0 has no auth wired yet; everything reads/writes a single demo user.
// Keep this in sync with the client's user id.
const DEMO_USER = "demo_user";

const userRef = (uid) => db.collection("users").doc(uid);
const sessionsCol = (uid) => userRef(uid).collection("sessions");
const messagesCol = (uid, sessionId) =>
  sessionsCol(uid).doc(sessionId).collection("messages");
const memoryCol = (uid) => userRef(uid).collection("memory");
const prefsDoc = (uid) => userRef(uid).collection("preferences").doc("profile");

module.exports = {
  admin,
  db,
  DEMO_USER,
  userRef,
  sessionsCol,
  messagesCol,
  memoryCol,
  prefsDoc,
};
