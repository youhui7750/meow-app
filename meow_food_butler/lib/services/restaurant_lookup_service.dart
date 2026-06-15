import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/services/callable_json.dart';

/// Thin client for the `fetchRestaurant` Cloud Function — a single Google Maps
/// place lookup via Outscraper (detail + menu photos + reviews, server-side).
/// Prefer [placeId] (resolves the exact place); fall back to a [query] string.
class RestaurantLookupService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// Returns the enriched [FoodCard], or null when nothing was found / the call
  /// failed. [originalURL], [tags], and [visited] are optional overlay fields.
  Future<FoodCard?> fetch({
    String? placeId,
    String? query,
    String? originalURL,
    List<String>? tags,
    bool visited = false,
  }) async {
    final payload = <String, dynamic>{'visited': visited};
    if (placeId != null && placeId.trim().isNotEmpty) {
      payload['placeId'] = placeId.trim();
    }
    if (query != null && query.trim().isNotEmpty) {
      payload['query'] = query.trim();
    }
    if (!payload.containsKey('placeId') && !payload.containsKey('query')) {
      return null;
    }
    if (originalURL != null) payload['originalURL'] = originalURL;
    if (tags != null) payload['tags'] = tags;

    try {
      final result = await _functions
          .httpsCallable('fetchRestaurant')
          .call<Map<String, dynamic>>(payload);
      final data = result.data;
      if (data['ok'] != true) {
        debugPrint(
          'RestaurantLookupService: fetchRestaurant returned ${data['code']}',
        );
        return null;
      }
      return FoodCard.fromMap(normalizeCallableMap(data['restaurant']));
    } catch (error) {
      debugPrint('RestaurantLookupService: fetch failed: $error');
      return null;
    }
  }
}
