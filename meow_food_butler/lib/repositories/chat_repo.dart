import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meow_food_butler/models/chat_message.dart';
import 'package:meow_food_butler/models/chat_session.dart';

/// Firestore access for chat sessions + their messages.
///
/// Sessions are created/listed/switched purely client-side; chat *messages* are
/// written by the `chatWithButler` Cloud Function (single writer) and only read
/// here. Mirrors [ExperienceRepository]'s per-user (`users/{uid}/…`) layout.
///
/// Keep [_demoUid] in sync with the backend's `DEMO_USER` (`functions/collections.js`).
class ChatRepository {
  static const String _demoUid = 'demo-user';

  final FirebaseFirestore _firestore;

  ChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection('users').doc(_demoUid).collection('sessions');

  CollectionReference<Map<String, dynamic>> _messages(String sessionId) =>
      _sessions.doc(sessionId).collection('messages');

  /// Sessions newest-activity first, for the session list.
  Stream<List<ChatSession>> watchSessions() {
    return _sessions.orderBy('updatedAt', descending: true).snapshots().map(
          (snap) => snap.docs
              .map((doc) => ChatSession.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Create an empty session and return its id. Title is filled in by the
  /// backend from the first user message.
  Future<String> createSession() async {
    final now = FieldValue.serverTimestamp();
    final ref = await _sessions.add({
      'title': '',
      'createdAt': now,
      'updatedAt': now,
    });
    return ref.id;
  }

  /// Messages of a session, oldest-first (the chat view reverses for display).
  Stream<List<ChatMessage>> watchMessages(String sessionId) {
    return _messages(sessionId).orderBy('timestamp').snapshots().map(
          (snap) => snap.docs
              .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }
}