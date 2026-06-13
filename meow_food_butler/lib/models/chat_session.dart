import 'package:cloud_firestore/cloud_firestore.dart';

/// A single chat conversation ("session"), like one entry in Claude's session
/// list. Messages live in a `messages` subcollection under the session doc.
class ChatSession {
  final String id;
  final String title;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  })  : createdAt = createdAt ?? Timestamp.now(),
        updatedAt = updatedAt ?? Timestamp.now();

  /// A user-facing label, falling back to a friendly default for empty chats.
  String get displayTitle => title.trim().isEmpty ? 'New chat' : title;

  factory ChatSession.fromMap(Map<String, dynamic> map, String id) {
    return ChatSession(
      id: id,
      title: map['title'] as String? ?? '',
      createdAt: map['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: map['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatSession &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
}
