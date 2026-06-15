import 'package:cloud_functions/cloud_functions.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/services/callable_json.dart';

/// Thin client for the `importInstagram` Cloud Function. All scraping, AI name
/// extraction, and Google Maps enrichment happen server-side; this just calls the
/// callable and deserializes the returned card maps. No API keys on the client.
class InstagramImportService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  Future<InstagramImportResult> import(String igUrl) async {
    final result = await _functions
        .httpsCallable('importInstagram')
        .call<Map<String, dynamic>>({'url': igUrl});

    final data = result.data;
    if (data['ok'] != true) {
      throw InstagramImportException(
        (data['reply'] as String?) ?? 'Import failed (${data['code']}).',
      );
    }

    return InstagramImportResult(
      experience: ExperienceCard.fromMap(
        normalizeCallableMap(data['experience']),
      ),
      restaurant: FoodCard.fromMap(normalizeCallableMap(data['restaurant'])),
    );
  }
}

class InstagramImportResult {
  final ExperienceCard experience;
  final FoodCard restaurant;

  const InstagramImportResult({
    required this.experience,
    required this.restaurant,
  });
}

class InstagramImportException implements Exception {
  final String message;

  const InstagramImportException(this.message);

  @override
  String toString() => message;
}
