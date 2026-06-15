import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';

class RestaurantRepository {
  static const String _demoUid = 'demo-user';

  final FirebaseFirestore _firestore;

  RestaurantRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('users').doc(_demoUid).collection('restaurants');

  Stream<List<FoodCard>> watchRestaurants() {
    return _collection
        .orderBy('createdTime', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FoodCard.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<FoodCard>> restaurantsByIds(List<String> ids) async {
    final restaurants = <FoodCard>[];
    for (final id in ids) {
      final doc = await _collection.doc(id).get();
      if (doc.exists && doc.data() != null) {
        restaurants.add(FoodCard.fromMap(doc.data()!, doc.id));
      }
    }
    return restaurants;
  }

  Future<FoodCard?> findForExperience(ExperienceCard experience) async {
    final candidates = <String?>[
      experience.foodCardId,
      experience.placeId,
    ];

    for (final candidate in candidates) {
      final id = candidate?.trim();
      if (id == null || id.isEmpty) continue;

      final directDoc = await _collection.doc(id).get();
      if (directDoc.exists && directDoc.data() != null) {
        return FoodCard.fromMap(directDoc.data()!, directDoc.id);
      }

      final placeSnap =
          await _collection.where('placeId', isEqualTo: id).limit(1).get();
      if (placeSnap.docs.isNotEmpty) {
        final doc = placeSnap.docs.first;
        return FoodCard.fromMap(doc.data(), doc.id);
      }
    }

    final title = experience.placeTitle?.trim();
    if (title != null && title.isNotEmpty) {
      final titleSnap = await _collection
          .where('placeTitle', isEqualTo: title)
          .limit(1)
          .get();
      if (titleSnap.docs.isNotEmpty) {
        final doc = titleSnap.docs.first;
        return FoodCard.fromMap(doc.data(), doc.id);
      }

      final allSnap = await _collection.limit(60).get();
      for (final doc in allSnap.docs) {
        final restaurant = FoodCard.fromMap(doc.data(), doc.id);
        final restaurantTitle = restaurant.primaryTitle.trim();
        if (restaurantTitle == title ||
            restaurantTitle.contains(title) ||
            title.contains(restaurantTitle)) {
          return restaurant;
        }
      }

      return null;
    }

    final originalURL = experience.originalURL?.trim();
    if (originalURL != null && originalURL.isNotEmpty) {
      final urlSnap = await _collection
          .where('originalURL', isEqualTo: originalURL)
          .limit(1)
          .get();
      if (urlSnap.docs.isNotEmpty) {
        final doc = urlSnap.docs.first;
        return FoodCard.fromMap(doc.data(), doc.id);
      }
    }

    return null;
  }

  Future<String> saveRestaurant(FoodCard restaurant) async {
    final existingId = await _findExistingRestaurantId(restaurant);
    final docRef =
        existingId == null ? _collection.doc(_safeDocumentId(restaurant)) : _collection.doc(existingId);
    final doc = await docRef.get();

    await docRef.set({
      ...restaurant.toMap(),
      'id': docRef.id,
      'placeId': restaurant.id,
      'createdTime': doc.exists
          ? (doc.data()?['createdTime'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
      'updatedTime': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String?> _findExistingRestaurantId(FoodCard restaurant) async {
    final id = restaurant.id?.trim();
    if (id != null && id.isNotEmpty) {
      final doc = await _collection.doc(id).get();
      if (doc.exists) return doc.id;

      final placeSnap = await _collection
          .where('placeId', isEqualTo: id)
          .limit(1)
          .get();
      if (placeSnap.docs.isNotEmpty) return placeSnap.docs.first.id;
    }

    final title = restaurant.primaryTitle.trim();
    if (title.isNotEmpty && title != 'Unknown Food Spot') {
      final titleSnap = await _collection
          .where('placeTitle', isEqualTo: title)
          .limit(1)
          .get();
      if (titleSnap.docs.isNotEmpty) return titleSnap.docs.first.id;
    }

    return null;
  }

  String _safeDocumentId(FoodCard restaurant) {
    final preferred = restaurant.id?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred.replaceAll('/', '_');
    }
    return _collection.doc().id;
  }
}
