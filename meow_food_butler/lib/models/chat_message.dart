import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Explicit types to let the view map data to UI variants instantly
enum ChatMessageType {
  text,           // Plain user or AI text bubbles
  recommendation, // Special layout containing a button linking to the swipe stack
  actionTimeline, // System messages (e.g., "AI Cat scheduled Friday at 7:00 PM")
  experienceCard, // Inline dining-log card (references an ExperienceCard by id)
  restaurantCards, // Inline saved/imported restaurant cards by ExperienceCard ids
}

class ChatMessage {
  final String? id;
  final String senderId;             // "user" or "ai_agent"
  final String messageText;          // The core text content or description
  final ChatMessageType type;       // Defines layout rendering rules
  final Timestamp timestamp;
  
  // Payload for interactive recommendation structures
  final List<String>? recommendedSpotIds; // References to FoodCard IDs generated for the stack
  final String? calendarEventId;         // Reference key if an event was pushed to Google Calendar
  final String? experienceId;            // Linked ExperienceCard id (client-injected card)

  ChatMessage({
    this.id,
    required this.senderId,
    required this.messageText,
    required this.type,
    Timestamp? timestamp,
    this.recommendedSpotIds,
    this.calendarEventId,
    this.experienceId,
  }) : timestamp = timestamp ?? Timestamp.now();

  /// Checks if the message belongs to the current user or the active AI butler
  bool get isFromAI => senderId == 'ai_agent';

  /// OpenAI-style role string ('user' / 'assistant') derived from [senderId].
  /// Compatibility accessor for the chat UI / [ChatService].
  String get role => isFromAI ? 'assistant' : 'user';

  /// Alias for [messageText]. Compatibility accessor for the chat UI.
  String get text => messageText;

  /// Helper utility to check if it contains actionable custom components
  bool get hasRecommendationStack => 
      type == ChatMessageType.recommendation && 
      recommendedSpotIds != null && 
      recommendedSpotIds!.isNotEmpty;

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      senderId: map['senderId'] as String? ?? 'unknown',
      messageText: map['messageText'] as String? ?? '',
      type: _parseType(map['type'] as String?),
      timestamp: map['timestamp'] as Timestamp? ?? Timestamp.now(),
      recommendedSpotIds: map['recommendedSpotIds'] != null
          ? List<String>.from(map['recommendedSpotIds'] as List<dynamic>)
          : null,
      calendarEventId: map['calendarEventId'] as String?,
      experienceId: map['experienceId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'messageText': messageText,
      'type': type.name, // Saves enum value as String ('text', 'recommendation', etc.)
      'timestamp': timestamp,
      if (recommendedSpotIds != null) 'recommendedSpotIds': recommendedSpotIds,
      if (calendarEventId != null) 'calendarEventId': calendarEventId,
      if (experienceId != null) 'experienceId': experienceId,
    };
  }

  static ChatMessageType _parseType(String? typeStr) {
    return ChatMessageType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ChatMessageType.text,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.id == id &&
        other.senderId == senderId &&
        other.messageText == messageText &&
        other.type == type &&
        other.timestamp == timestamp &&
        listEquals(other.recommendedSpotIds, recommendedSpotIds) &&
        other.calendarEventId == calendarEventId &&
        other.experienceId == experienceId;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      senderId,
      messageText,
      type,
      timestamp,
      recommendedSpotIds != null ? Object.hashAll(recommendedSpotIds!) : null,
      calendarEventId,
      experienceId,
    );
  }
}
