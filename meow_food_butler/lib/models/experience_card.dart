import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ExperienceCard {
  final String? id; // Unique Firestore document ID
  final String?
  foodCardId; // Link reference to the underlying FoodCard/Restaurant
  final String? placeTitle; // User-facing restaurant/place name
  final String? placeAddress; // Human-readable address from device location
  final double? latitude;
  final double? longitude;
  final String? originalURL; // Source Instagram link (if imported)
  final List<String> photoPaths; // Firebase Storage paths for meal photos
  final List<String> photoUrls; // Download URLs cached for display
  final List<String>
  personalTags; // User or AI tags (e.g., ["Ramen", "Spicy", "DateNight"])
  final double personalRating; // User's rating for this specific experience
  final String? personalNote; // Detailed comment written by user
  final bool isDone; // Has the user visited this spot or checked it off?

  final Timestamp _createdTime;

  ExperienceCard({
    this.id,
    this.foodCardId,
    this.placeTitle,
    this.placeAddress,
    this.latitude,
    this.longitude,
    this.originalURL,
    this.photoPaths = const [],
    this.photoUrls = const [],
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
      placeTitle: map['placeTitle'] as String?,
      placeAddress: _readLocationString(map, 'address'),
      latitude:
          _readLocationDouble(map, 'latitude') ??
          _readLocationDouble(map, 'lat'),
      longitude:
          _readLocationDouble(map, 'longitude') ??
          _readLocationDouble(map, 'lng'),
      originalURL: map['originalURL'] as String?,
      photoPaths: map['photoPaths'] != null
          ? List<String>.from(map['photoPaths'] as List<dynamic>)
          : const [],
      photoUrls: map['photoUrls'] != null
          ? List<String>.from(map['photoUrls'] as List<dynamic>)
          : const [],
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
      'placeTitle': placeTitle,
      'location': latitude == null || longitude == null
          ? null
          : {
              'name': placeTitle,
              'address': placeAddress,
              'latitude': latitude,
              'longitude': longitude,
            },
      'originalURL': originalURL,
      'photoPaths': photoPaths,
      'photoUrls': photoUrls,
      'personalTags': personalTags,
      'personalRating': personalRating,
      'personalNote': personalNote,
      'createdTime': _createdTime,
      'isDone': isDone,
    };
  }

  ExperienceCard copyWith({
    String? id,
    String? foodCardId,
    String? placeTitle,
    String? placeAddress,
    double? latitude,
    double? longitude,
    String? originalURL,
    List<String>? photoPaths,
    List<String>? photoUrls,
    List<String>? personalTags,
    double? personalRating,
    String? personalNote,
    Timestamp? createdTime,
    bool? isDone,
  }) {
    return ExperienceCard(
      id: id ?? this.id,
      foodCardId: foodCardId ?? this.foodCardId,
      placeTitle: placeTitle ?? this.placeTitle,
      placeAddress: placeAddress ?? this.placeAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      originalURL: originalURL ?? this.originalURL,
      photoPaths: photoPaths ?? this.photoPaths,
      photoUrls: photoUrls ?? this.photoUrls,
      personalTags: personalTags ?? this.personalTags,
      personalRating: personalRating ?? this.personalRating,
      personalNote: personalNote ?? this.personalNote,
      createdTime: createdTime ?? this.createdTime,
      isDone: isDone ?? this.isDone,
    );
  }

  /// Structural equality override for reliable state comparisons in ViewModels
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExperienceCard &&
        other.id == id &&
        other.foodCardId == foodCardId &&
        other.placeTitle == placeTitle &&
        other.placeAddress == placeAddress &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.originalURL == originalURL &&
        listEquals(other.photoPaths, photoPaths) &&
        listEquals(other.photoUrls, photoUrls) &&
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
      placeTitle,
      placeAddress,
      latitude,
      longitude,
      originalURL,
      Object.hashAll(photoPaths),
      Object.hashAll(photoUrls),
      Object.hashAll(personalTags),
      personalRating,
      personalNote,
      isDone,
      createdTime,
    );
  }
}

String? _readLocationString(Map<String, dynamic> map, String key) {
  final location = map['location'];
  if (location is Map<String, dynamic>) {
    return location[key] as String?;
  }
  return null;
}

double? _readLocationDouble(Map<String, dynamic> map, String key) {
  final location = map['location'];
  if (location is Map<String, dynamic>) {
    return (location[key] as num?)?.toDouble();
  }
  return null;
}
