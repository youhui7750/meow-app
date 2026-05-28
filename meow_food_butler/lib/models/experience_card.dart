import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ExperienceCard {
  final String? id;                  // Unique Firestore document ID
  final String? foodCardId;          // Link reference to the underlying FoodCard/Restaurant
  final String? originalURL;         // Source Instagram link (if imported)
  final List<String> personalTags;   // User or AI tags (e.g., ["Ramen", "Spicy", "DateNight"])
  final double personalRating;       // User's rating for this specific experience
  final String? personalNote;        // Detailed comment written by user
  final bool isDone;                 // Has the user visited this spot or checked it off?
  
  final Timestamp _createdTime;

  ExperienceCard({
    this.id,
    this.foodCardId,
    this.originalURL,
    required this.personalTags,
    required this.personalRating,
    this.personalNote,
    Timestamp? createdTime,
    this.isDone = false,
  }) : _createdTime = createdTime ?? Timestamp.now();

  /// Exposes the internal timestamp safely with a immediate fallback wrapper
  Timestamp get createdTime => _createdTime;

  /// Factory constructor to parse Cloud Firestore documents smoothly
  factory ExperienceCard.fromMap(Map<String, dynamic> map, String id) {
    return ExperienceCard(
      id: id,
      foodCardId: map['foodCardId'] as String?,
      originalURL: map['originalURL'] as String?,
      // Safely parse Firestore arrays into List<String>
      personalTags: map['personalTags'] != null
          ? List<String>.from(map['personalTags'] as List<dynamic>)
          : const [],
      personalRating: (map['personalRating'] as num?)?.toDouble() ?? 0.0,
      personalNote: map['personalNote'] as String?,
      createdTime: map['createdTime'] as Timestamp?,
      isDone: map['isDone'] as bool? ?? false,
    );
  }

  /// Converts properties into an organized Map format ready to send to Firestore
  Map<String, dynamic> toMap() {
    return {
      'foodCardId': foodCardId,
      'originalURL': originalURL,
      'personalTags': personalTags,
      'personalRating': personalRating,
      'personalNote': personalNote,
      'createdTime': _createdTime,
      'isDone': isDone,
    };
  }

  /// Structural equality override for reliable state comparisons in ViewModels
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExperienceCard &&
        other.id == id &&
        other.foodCardId == foodCardId &&
        other.originalURL == originalURL &&
        listEquals(other.personalTags, personalTags) &&
        other.personalRating == personalRating &&
        other.personalNote == personalNote &&
        other.isDone == isDone &&
        other.createdTime == createdTime;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      foodCardId,
      originalURL,
      Object.hashAll(personalTags),
      personalRating,
      personalNote,
      isDone,
      createdTime,
    );
  }
}