import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';

class RestaurantRepository {
  static const String _demoUid = 'demo-user';

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  RestaurantRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('users').doc(_demoUid).collection('restaurants');

  Stream<List<FoodCard>> watchRestaurants() {
    return _collection.snapshots().map((snapshot) {
      final restaurants = snapshot.docs
          .map((doc) => FoodCard.fromMap(doc.data(), doc.id))
          .toList();
      restaurants.sort((a, b) {
        final aTime = a.createdTime;
        final bTime = b.createdTime;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return restaurants;
    });
  }

  /// The most recently saved wish-list restaurant (想去, i.e. not yet visited),
  /// optionally filtered to those matching [query] (case-insensitive) by name,
  /// tags, category, subtypes, description, or address. Returns null when
  /// nothing matches.
  ///
  /// Mirrors [SavedViewModel.latestExperience] for the chat's `/latest-restaurant`
  /// test command, and exercises the same wish-list card path the butler's
  /// `searchMyPlaces` skill drives for "any ramen in my wish list?" requests.
  Future<FoodCard?> latestRestaurant({String? query}) async {
    // watchRestaurants emits newest-first, so the first match is the latest.
    final restaurants = await watchRestaurants().first;
    final needle = query?.trim().toLowerCase();
    for (final restaurant in restaurants) {
      if (restaurant.id == null) continue;
      if (restaurant.visited) continue; // wish list only
      if (needle != null &&
          needle.isNotEmpty &&
          !_matchesQuery(restaurant, needle)) {
        continue;
      }
      return restaurant;
    }
    return null;
  }

  /// Whether [restaurant] matches an already-lowercased [needle] on its name,
  /// category, subtypes, description, address, or any tag.
  bool _matchesQuery(FoodCard restaurant, String needle) {
    if (restaurant.primaryTitle.toLowerCase().contains(needle)) return true;
    if ((restaurant.category ?? '').toLowerCase().contains(needle)) return true;
    if ((restaurant.description ?? '').toLowerCase().contains(needle)) {
      return true;
    }
    if ((restaurant.formattedAddress ?? '').toLowerCase().contains(needle)) {
      return true;
    }
    for (final tag in restaurant.tags) {
      if (tag.toLowerCase().contains(needle)) return true;
    }
    for (final subtype in restaurant.subtypes) {
      if (subtype.toLowerCase().contains(needle)) return true;
    }
    return false;
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
      if (!_isUsableLookupId(id)) continue;

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

    // Mirror external (Outscraper/Google) photos into our own Storage once, so
    // cards stay readable even after the source URLs rotate or expire.
    final cached = await _cachePhotos(docRef.id, restaurant, doc.data());

    await docRef.set({
      ...restaurant.toMap(),
      'photoPaths': cached.paths,
      'photoUrls': cached.urls,
      'id': docRef.id,
      'placeId': restaurant.id,
      'createdTime': doc.exists
          ? (doc.data()?['createdTime'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
      'updatedTime': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  bool _isUsableLookupId(String? id) {
    if (id == null || id.isEmpty) return false;
    if (id.startsWith('__') && id.endsWith('__')) return false;
    return true;
  }

  Future<void> deleteRestaurant(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final docRef = _collection.doc(cleanId);
    final doc = await docRef.get();
    final data = doc.data();
    final photoPaths =
        (data?['photoPaths'] as List?)?.whereType<String>().toList() ??
            const <String>[];

    for (final path in photoPaths) {
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Non-fatal: Firestore should still reflect the user's delete action.
      }
    }

    await docRef.delete();
  }

  /// Downloads any external photo URLs into Firebase Storage under
  /// `users/{uid}/restaurants/{id}/photos/…` and returns the Storage paths +
  /// download URLs. Idempotent: if the doc was already mirrored on a previous
  /// save (it has `photoPaths`), the stored values are reused untouched. Any
  /// download that fails (e.g. browser CORS on web) keeps its original URL as a
  /// fallback so the card still renders.
  Future<_CachedPhotos> _cachePhotos(
    String docId,
    FoodCard restaurant,
    Map<String, dynamic>? existing,
  ) async {
    final existingPaths =
        (existing?['photoPaths'] as List?)?.whereType<String>().toList() ??
            const <String>[];
    if (existingPaths.isNotEmpty) {
      final existingUrls =
          (existing?['photoUrls'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      return _CachedPhotos(paths: existingPaths, urls: existingUrls);
    }

    final paths = <String>[];
    final urls = <String>[];

    for (var index = 0; index < restaurant.photoUrls.length; index += 1) {
      final url = restaurant.photoUrls[index].trim();
      if (url.isEmpty) continue;

      // Already one of our Storage URLs — keep it without re-downloading.
      if (url.contains('firebasestorage.googleapis.com')) {
        urls.add(url);
        continue;
      }

      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          urls.add(url);
          continue;
        }

        final contentType = response.headers['content-type'] ?? 'image/jpeg';
        final extension = contentType.contains('png')
            ? 'png'
            : contentType.contains('webp')
                ? 'webp'
                : 'jpg';
        final path =
            'users/$_demoUid/restaurants/$docId/photos/${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
        final ref = _storage.ref(path);

        await ref.putData(
          response.bodyBytes,
          SettableMetadata(contentType: contentType),
        );

        paths.add(path);
        urls.add(await ref.getDownloadURL());
      } catch (_) {
        // Network/CORS failure — fall back to the original external URL.
        urls.add(url);
      }
    }

    return _CachedPhotos(paths: paths, urls: urls);
  }

  Future<String?> _findExistingRestaurantId(FoodCard restaurant) async {
    final id = restaurant.id?.trim();
    if (_isUsableLookupId(id)) {
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

class _CachedPhotos {
  final List<String> paths;
  final List<String> urls;

  const _CachedPhotos({required this.paths, required this.urls});
}
