import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';
import 'package:meow_food_butler/repositories/restaurant_repository.dart';
import 'package:meow_food_butler/services/instagram_import_service.dart';
import 'package:meow_food_butler/services/restaurant_lookup_service.dart';

// ---------------------------------------------------------------------------
// Import-status events emitted on [SavedViewModel.importEvents]
// ---------------------------------------------------------------------------

enum _ImportEventType { started, completed, reviewCreated }

class RestaurantImportEvent {
  final _ImportEventType _type;
  final String restaurantName;
  final String? foodCardId;

  /// The experience card returned by URL import; null for Outscraper-based imports.
  final ExperienceCard? linkedExperience;

  bool get isStarted => _type == _ImportEventType.started;
  bool get isCompleted => _type == _ImportEventType.completed;
  bool get isReviewCreated => _type == _ImportEventType.reviewCreated;

  RestaurantImportEvent.started(this.restaurantName)
      : _type = _ImportEventType.started,
        foodCardId = null,
        linkedExperience = null;

  RestaurantImportEvent.completed(
    this.restaurantName,
    String id, {
    this.linkedExperience,
  })  : _type = _ImportEventType.completed,
        foodCardId = id;

  RestaurantImportEvent.reviewCreated(this.restaurantName)
      : _type = _ImportEventType.reviewCreated,
        foodCardId = null,
        linkedExperience = null;
}

// ---------------------------------------------------------------------------

class SavedViewModel extends ChangeNotifier {
  final ExperienceRepository _repository;
  StreamSubscription<List<ExperienceCard>>? _subscription;

  final List<ExperienceCard> _experiences = [];
  final Set<String> _foodCardEnsuresInFlight = {};

  // Only the single most-recently imported ID is kept so the highlight moves
  // to the new card each time an import completes (Bug 2).
  String? _latestImportedId;
  final StreamController<RestaurantImportEvent> _importEvents =
      StreamController<RestaurantImportEvent>.broadcast();

  bool _isSaving = false;
  String? _errorMessage;

  SavedViewModel({ExperienceRepository? repository})
      : _repository = repository ?? ExperienceRepository() {
    _watchExperiences();
  }

  List<ExperienceCard> get experiences => List.unmodifiable(_experiences);

  /// A set containing only the single most-recently imported FoodCard ID, or
  /// empty if no import has happened yet this session. Cards whose id is in
  /// this set render with the "new import" highlight border.
  Set<String> get recentlyImportedIds =>
      _latestImportedId != null ? {_latestImportedId!} : const {};

  /// Stream of import lifecycle events.
  Stream<RestaurantImportEvent> get importEvents => _importEvents.stream;

  List<List<ExperienceCard>> get groupedExperiences {
    final map = <String, List<ExperienceCard>>{};

    for (final exp in _experiences) {
      final key = exp.foodCardId ?? exp.placeId ?? exp.placeTitle ?? exp.id;
      final safeKey = key ?? 'unknown';
      map.putIfAbsent(safeKey, () => []).add(exp);
    }

    final groupedList = map.values.toList();

    for (final group in groupedList) {
      group.sort((a, b) {
        if (a.createdTime == null && b.createdTime == null) return 0;
        if (a.createdTime == null) return 1;
        if (b.createdTime == null) return -1;
        return b.createdTime!.compareTo(a.createdTime!);
      });
    }

    groupedList.sort((a, b) {
      final aLatest = a.first.createdTime;
      final bLatest = b.first.createdTime;

      if (aLatest == null && bLatest == null) return 0;
      if (aLatest == null) return 1;
      if (bLatest == null) return -1;
      return bLatest.compareTo(aLatest);
    });

    return groupedList;
  }

  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  ExperienceCard? experienceById(String id) {
    for (final experience in _experiences) {
      if (experience.id == id) return experience;
    }
    return null;
  }

  ExperienceCard? latestExperience({String? query}) {
    final needle = query?.trim().toLowerCase();
    ExperienceCard? latest;
    for (final exp in _experiences) {
      if (exp.id == null) continue;
      if (needle != null && needle.isNotEmpty && !_matchesQuery(exp, needle)) {
        continue;
      }
      if (latest == null ||
          exp.createdTime.compareTo(latest.createdTime) > 0) {
        latest = exp;
      }
    }
    return latest;
  }

  bool _matchesQuery(ExperienceCard exp, String needle) {
    if ((exp.placeTitle ?? '').toLowerCase().contains(needle)) return true;
    if ((exp.personalNote ?? '').toLowerCase().contains(needle)) return true;
    for (final tag in exp.personalTags) {
      if (tag.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  Future<void> addExperience(
    ExperienceCard experience, {
    List<XFile> photos = const [],
    bool emitReviewCreated = true,
  }) async {
    if (!_experiences.any((e) => e.id == experience.id)) {
      _experiences.insert(0, experience);
      notifyListeners();
    }
    ExperienceCard? saved;
    await _runSaveAction(() async {
      saved = await _repository.addExperience(experience, photos: photos);
    });
    if (saved != null) {
      if (emitReviewCreated) {
        _importEvents.add(
          RestaurantImportEvent.reviewCreated(saved!.placeTitle ?? '餐廳'),
        );
      }
      // Fire Outscraper in the background — must not block the UI.
      unawaited(_ensureFoodCard(saved!));
    }
  }

  /// Imports a restaurant from an Instagram / Google Maps URL without blocking
  /// the UI. Progress is surfaced via [importEvents]; the result is also applied
  /// to [recentlyImportedIds] so the card gets a highlight border.
  Future<void> importFromUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    _importEvents.add(RestaurantImportEvent.started('貼文餐廳'));
    try {
      final result = await InstagramImportService().import(trimmed);
      final restaurantRepo = RestaurantRepository();
      final savedId = await restaurantRepo.saveRestaurant(result.restaurant);
      if (savedId.isEmpty) return;

      final expWithCard = result.experience.copyWith(foodCardId: savedId);
      // Skip reviewCreated — `completed` below covers the user notification.
      await addExperience(expWithCard, emitReviewCreated: false);

      _latestImportedId = savedId;
      _importEvents.add(
        RestaurantImportEvent.completed(
          result.restaurant.primaryTitle,
          savedId,
          linkedExperience: expWithCard,
        ),
      );
      notifyListeners();
    } catch (error) {
      debugPrint('SavedViewModel.importFromUrl failed: $error');
    }
  }

  /// Checks if a FoodCard already exists for [experience]; if not, fetches one
  /// from Outscraper and saves it, then links it back to the experience.
  Future<void> _ensureFoodCard(ExperienceCard experience) async {
    if (experience.foodCardId != null && experience.foodCardId!.isNotEmpty) return;
    if (!experience.isDone) return;
    final expId = experience.id;
    if (expId == null || expId.isEmpty) return;
    if (!_foodCardEnsuresInFlight.add(expId)) return;

    try {
      final restaurantRepo = RestaurantRepository();
      final existing = await restaurantRepo.findForExperience(experience);
      if (existing != null) {
        final existingId = existing.id ?? '';
        if (existingId.isNotEmpty) {
          await ExperienceRepository().linkFoodCard(expId, existingId);
          // Bug 2: bump updatedTime so this restaurant sorts to "recent" top.
          unawaited(restaurantRepo.touchRestaurant(existingId));
        }
        return;
      }

      final restaurantName = experience.placeTitle ?? 'Unknown Restaurant';
      _importEvents.add(RestaurantImportEvent.started(restaurantName));

      final fetched = await _fetchForExperience(experience);
      if (fetched == null) {
        debugPrint(
          'SavedViewModel: restaurant lookup returned null for ${experience.placeTitle}',
        );
        return;
      }

      final savedId = await restaurantRepo.saveRestaurant(fetched);
      if (savedId.isNotEmpty) {
        await ExperienceRepository().linkFoodCard(expId, savedId);
        // Replace old highlight with this new import (Bug 2: only one at a time).
        _latestImportedId = savedId;
        _importEvents.add(
          RestaurantImportEvent.completed(fetched.primaryTitle, savedId),
        );
        notifyListeners();
      }
    } catch (error) {
      debugPrint(
        'SavedViewModel: ensure FoodCard failed for ${experience.placeTitle}: $error',
      );
    } finally {
      _foodCardEnsuresInFlight.remove(expId);
    }
  }

  /// Resolves lookup priority: placeId → googleMapsUrl → skip.
  /// Text-only queries are excluded to prevent unrelated restaurant matches.
  Future<FoodCard?> _fetchForExperience(ExperienceCard experience) async {
    final placeId = _usablePlaceId(experience.placeId);
    final mapsUrl = experience.googleMapsUrl?.trim();

    if (placeId != null && placeId.isNotEmpty) {
      return RestaurantLookupService().fetch(
        placeId: placeId,
        query: experience.placeTitle?.trim(),
        originalURL: experience.originalURL,
        tags: experience.personalTags,
        visited: experience.isDone,
      );
    }

    if (mapsUrl != null && mapsUrl.isNotEmpty) {
      return RestaurantLookupService().fetch(
        placeId: mapsUrl,
        query: experience.placeTitle?.trim(),
        originalURL: experience.originalURL,
        tags: experience.personalTags,
        visited: experience.isDone,
      );
    }

    return null;
  }

  String? _usablePlaceId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('__') && trimmed.endsWith('__')) return null;
    return trimmed;
  }

  Future<void> updateExperience(
    ExperienceCard experience, {
    List<XFile> newPhotos = const [],
  }) async {
    await _runSaveAction(
      () => _repository.updateExperience(experience, newPhotos: newPhotos),
    );
  }

  Future<void> removeExperience(String id) async {
    final experience = experienceById(id);
    if (experience == null) return;

    _experiences.removeWhere((e) => e.id == id);
    notifyListeners();

    await _runSaveAction(() => _repository.deleteExperience(experience));
  }

  Future<void> removeMultipleExperiences(List<ExperienceCard> targetExperiences) async {
    if (targetExperiences.isEmpty) return;

    final idsToRemove = targetExperiences.map((e) => e.id).toSet();
    _experiences.removeWhere((e) => idsToRemove.contains(e.id));
    notifyListeners();

    for (final exp in targetExperiences) {
      try {
        await _repository.deleteExperience(exp);
      } catch (e) {
        debugPrint('Batch delete failed for ${exp.id}: $e');
      }
    }
  }

  Future<void> addMultipleExperiences(List<ExperienceCard> experiencesToAdd) async {
    if (experiencesToAdd.isEmpty) return;

    for (final exp in experiencesToAdd) {
      if (!_experiences.any((e) => e.id == exp.id)) {
        _experiences.insert(0, exp);
      }
    }
    notifyListeners();

    for (final exp in experiencesToAdd) {
      try {
        await _repository.addExperience(exp);
      } catch (e) {
        debugPrint('Batch add failed for ${exp.id}: $e');
      }
    }
  }

  Future<void> _runSaveAction(Future<void> Function() action) async {
    if (_isSaving) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _errorMessage = 'Cloud sync failed: $error';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _watchExperiences() {
    _subscription = _repository.watchExperiences().listen(
      (items) {
        _experiences
          ..clear()
          ..addAll(items);
        _errorMessage = null;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = 'Cloud sync unavailable: $error';
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _importEvents.close();
    super.dispose();
  }
}
