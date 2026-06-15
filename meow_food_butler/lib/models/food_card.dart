import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Necessary for JSON datatype integration.

class FoodCard {
  final String? id; // Restaurant document id, usually Google Place ID when available.
  final String? originalURL; // The parsed source (Instagram, Google Maps, ...)
  final String? formattedAddress; // Google/Outscraper full address.
  final double? rating; // Public restaurant rating.
  final int? reviews; // Public review count.
  final String? phone;
  final String? website;
  final String? priceRange; // $, $$, $$$, or a local range string.
  final String? category;
  final List<String> subtypes;
  final String? description;
  final Map<String, dynamic>? workingHours;
  final dynamic popularTimes;
  final List<Map<String, dynamic>> reviewSnippets;
  final String? typicalTimeSpent;
  final String? menuLink;
  final String? bookingLink;
  final bool? verified;
  final bool visited;
  final List<String> tags;
  final List<String> photoPaths;
  final List<String> photoUrls;
  final List<DisplayName> displayNames; // Localized place names.
  final LocationCoordinate? location; // Coords for our map to render the place.
  final Timestamp? createdTime;
  final Timestamp? updatedTime;

  FoodCard({
    this.id,
    this.originalURL,
    this.formattedAddress,
    this.rating,
    this.reviews,
    this.phone,
    this.website,
    this.priceRange,
    this.category,
    this.subtypes = const [],
    this.description,
    this.workingHours,
    this.popularTimes,
    this.reviewSnippets = const [],
    this.typicalTimeSpent,
    this.menuLink,
    this.bookingLink,
    this.verified,
    this.visited = false,
    this.tags = const [],
    this.photoPaths = const [],
    this.photoUrls = const [],
    required this.displayNames,
    this.location,
    this.createdTime,
    this.updatedTime,
  });

  factory FoodCard.fromMap(Map<String, dynamic> map, [String? id]) {
    return FoodCard(
      id: id ?? (map['id'] as String?) ?? (map['placeId'] as String?),
      originalURL: map['originalURL'] as String?,
      formattedAddress:
          map['formattedAddress'] as String? ?? map['placeAddress'] as String?,
      // API numbers can arrive as int or double; safely cast to double
      rating: (map['rating'] as num?)?.toDouble(),
      reviews: (map['reviews'] as num?)?.toInt(),
      phone: map['phone'] as String?,
      website: map['website'] as String?,
      priceRange: map['priceRange'] as String? ?? map['range'] as String?,
      category: map['category'] as String?,
      subtypes: _readStringList(map['subtypes']),
      description: map['description'] as String?,
      workingHours: _readMap(map, 'workingHours'),
      popularTimes: map['popularTimes'] ?? map['popular_times'],
      reviewSnippets: _readMapList(map['reviewSnippets']),
      typicalTimeSpent: map['typicalTimeSpent'] as String?,
      menuLink: map['menuLink'] as String?,
      bookingLink: map['bookingLink'] as String?,
      verified: map['verified'] as bool?,
      visited: map['visited'] as bool? ?? false,
      tags: map['tags'] != null
          ? List<String>.from(map['tags'] as List<dynamic>)
          : const [],
      photoPaths: map['photoPaths'] != null
          ? List<String>.from(map['photoPaths'] as List<dynamic>)
          : const [],
      photoUrls: map['photoUrls'] != null
          ? List<String>.from(map['photoUrls'] as List<dynamic>)
          : const [],
      displayNames: map['displayName'] != null
          ? [DisplayName.fromMap(map['displayName'] as Map<String, dynamic>)]
          : (map['displayNames'] as List<dynamic>?)
                  ?.map((e) => DisplayName.fromMap(e as Map<String, dynamic>))
                  .toList() ??
              const [],
      location: map['location'] != null
          ? LocationCoordinate.fromMap(map['location'] as Map<String, dynamic>)
          : null,
      createdTime: map['createdTime'] as Timestamp?,
      updatedTime: map['updatedTime'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'placeId': id,
      'placeTitle': primaryTitle,
      'placeAddress': formattedAddress,
      'originalURL': originalURL,
      'formattedAddress': formattedAddress,
      'rating': rating,
      'reviews': reviews,
      'phone': phone,
      'website': website,
      'priceRange': priceRange,
      'category': category,
      'subtypes': subtypes,
      'description': description,
      'workingHours': workingHours,
      'popularTimes': popularTimes,
      'reviewSnippets': reviewSnippets,
      'typicalTimeSpent': typicalTimeSpent,
      'menuLink': menuLink,
      'bookingLink': bookingLink,
      'verified': verified,
      'visited': visited,
      'tags': tags,
      'photoPaths': photoPaths,
      'photoUrls': photoUrls,
      'displayNames': displayNames.map((e) => e.toMap()).toList(),
      'location': location?.toMap(),
      'createdTime': createdTime,
      'updatedTime': updatedTime,
    };
  }

  /// Helper getter to fetch the principal application title fallback string
  String get primaryTitle {
    if (displayNames.isEmpty) return "Unknown Food Spot";
    // Prioritize English or match your target region code if preferred
    final preferredName = displayNames.firstWhere(
      (name) => name.languageCode == 'en',
      orElse: () => displayNames.first,
    );
    return preferredName.title ?? "Unknown Food Spot";
  }

  FoodCard copyForImport({
    String? originalURL,
    bool? visited,
    List<String>? tags,
    List<String>? photoUrls,
    List<Map<String, dynamic>>? reviewSnippets,
  }) {
    return FoodCard(
      id: id,
      originalURL: originalURL ?? this.originalURL,
      formattedAddress: formattedAddress,
      rating: rating,
      reviews: reviews,
      phone: phone,
      website: website,
      priceRange: priceRange,
      category: category,
      subtypes: subtypes,
      description: description,
      workingHours: workingHours,
      popularTimes: popularTimes,
      reviewSnippets: reviewSnippets ?? this.reviewSnippets,
      typicalTimeSpent: typicalTimeSpent,
      menuLink: menuLink,
      bookingLink: bookingLink,
      verified: verified,
      visited: visited ?? this.visited,
      tags: tags ?? this.tags,
      photoPaths: photoPaths,
      photoUrls: photoUrls ?? this.photoUrls,
      displayNames: displayNames,
      location: location,
      createdTime: createdTime,
      updatedTime: updatedTime,
    );
  }

  /// Structural equality overrides are mandatory for structural stack swiping comparisons
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoodCard &&
        other.id == id &&
        other.originalURL == originalURL &&
        other.formattedAddress == formattedAddress &&
        other.rating == rating &&
        other.reviews == reviews &&
        other.phone == phone &&
        other.website == website &&
        other.priceRange == priceRange &&
        other.category == category &&
        listEquals(other.subtypes, subtypes) &&
        other.description == description &&
        mapEquals(other.workingHours, workingHours) &&
        other.popularTimes == popularTimes &&
        listEquals(other.reviewSnippets, reviewSnippets) &&
        other.typicalTimeSpent == typicalTimeSpent &&
        other.menuLink == menuLink &&
        other.bookingLink == bookingLink &&
        other.verified == verified &&
        other.visited == visited &&
        listEquals(other.tags, tags) &&
        listEquals(other.photoPaths, photoPaths) &&
        listEquals(other.photoUrls, photoUrls) &&
        listEquals(other.displayNames, displayNames) &&
        other.location == location &&
        other.createdTime == createdTime &&
        other.updatedTime == updatedTime;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      originalURL,
      formattedAddress,
      rating,
      reviews,
      phone,
      website,
      priceRange,
      category,
      Object.hashAll(subtypes),
      description,
      workingHours == null ? null : Object.hashAll(workingHours!.entries),
      popularTimes,
      Object.hashAll(reviewSnippets),
      typicalTimeSpent,
      menuLink,
      bookingLink,
      verified,
      visited,
      Object.hashAll(tags),
      Object.hashAll(photoPaths),
      Object.hashAll(photoUrls),
      Object.hashAll(displayNames),
      location,
      createdTime,
      updatedTime,
    ]);
  }
}

Map<String, dynamic>? _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<String> _readStringList(Object? value) {
  if (value == null) return const [];
  if (value is String) {
    return value
        .split(RegExp(r'[,、]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

class DisplayName {
  String? title;
  String? languageCode;

  DisplayName({
    this.title,
    this.languageCode,
  });

  factory DisplayName.fromMap(Map<String, dynamic> map) {
    return DisplayName(
      title: (map['text'] ?? map['title']) as String?,
      languageCode: map['languageCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': title,
      'languageCode': languageCode,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DisplayName &&
        other.title == title &&
        other.languageCode == languageCode;
  }

  @override
  int get hashCode => Object.hash(title, languageCode);
}

class LocationCoordinate {
  final double? longitude; // 經
  final double? latitude;   // 緯

  LocationCoordinate({
    required this.longitude,
    required this.latitude,
  });

  factory LocationCoordinate.fromMap(Map<String, dynamic> map) {
    return LocationCoordinate(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationCoordinate &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

// [PLACE API RETURN DATA]
// 
// {
//   "places": [
//     {
//       "formattedAddress": "123 Meat St, Taipei City, Taiwan",
//       "rating": 4.5,
//       "displayName": {
//         "text": "Prime Steakhouse",
//         "languageCode": "en"
//       }
//     },
//   ]
// }
