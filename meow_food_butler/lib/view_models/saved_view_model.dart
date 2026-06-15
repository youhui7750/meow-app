import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';
import 'package:meow_food_butler/repositories/restaurant_repository.dart';
import 'package:meow_food_butler/services/restaurant_lookup_service.dart';

class SavedViewModel extends ChangeNotifier {
  final ExperienceRepository _repository;
  StreamSubscription<List<ExperienceCard>>? _subscription;

  final List<ExperienceCard> _experiences = [];

  bool _isSaving = false;
  String? _errorMessage;

  SavedViewModel({ExperienceRepository? repository})
      : _repository = repository ?? ExperienceRepository() {
    _watchExperiences();
  }

  List<ExperienceCard> get experiences => List.unmodifiable(_experiences);

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

  /// The most recently logged experience, optionally filtered to those matching
  /// [query] (case-insensitive) by place name, tags, or note. Returns null when
  /// nothing matches.
  ///
  /// Backs the chat assistant's dining-log cards: no [query] answers "show my
  /// last meal", and a [query] like "ramen" answers "find the last time I ate
  /// ramen". Kept here (not in the view) so the matching rules live with the
  /// experience data.
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

  /// Whether [exp] matches an already-lowercased [needle] on its place name,
  /// any tag, or its note.
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
  }) async {
    if (!_experiences.any((e) => e.id == experience.id)) {
      _experiences.insert(0, experience);
      notifyListeners();
    }
    ExperienceCard? saved;
    await _runSaveAction(() async {
      saved = await _repository.addExperience(experience, photos: photos);
    });
    // Fire-and-forget: ensure a FoodCard exists so Saved tab has Google data
    if (saved != null) { unawaited(_ensureFoodCard(saved!)); }
  }

  /// Checks if a FoodCard already exists for [experience] in Firestore; if not,
  /// fetches one from Outscraper and saves it, then links it back to the
  /// experience so future opens skip the API call entirely.
  Future<void> _ensureFoodCard(ExperienceCard experience) async {
    if (experience.foodCardId != null && experience.foodCardId!.isNotEmpty) return;
    final expId = experience.id;
    if (expId == null || expId.isEmpty) return;

    try {
      final restaurantRepo = RestaurantRepository();
      final existing = await restaurantRepo.findForExperience(experience);
      if (existing != null) {
        await ExperienceRepository().linkFoodCard(expId, existing.id ?? '');
        return;
      }

      final fetched = await _fetchForExperience(experience);
      if (fetched == null) return;

      final savedId = await restaurantRepo.saveRestaurant(fetched);
      if (savedId.isNotEmpty) {
        await ExperienceRepository().linkFoodCard(expId, savedId);
      }
    } catch (_) {
      // Background — never surface errors to the UI
    }
  }

  /// Resolves lookup priority: placeId → googleMapsUrl → name + address query.
  Future<FoodCard?> _fetchForExperience(ExperienceCard experience) async {
    final placeId = experience.placeId?.trim();
    final mapsUrl = experience.googleMapsUrl?.trim();

    final String? effectivePlaceId;
    final String? effectiveQuery;

    if (placeId != null && placeId.isNotEmpty) {
      effectivePlaceId = placeId;
      effectiveQuery = experience.placeTitle?.trim();
    } else if (mapsUrl != null && mapsUrl.isNotEmpty) {
      effectivePlaceId = mapsUrl;
      effectiveQuery = experience.placeTitle?.trim();
    } else {
      effectivePlaceId = null;
      final parts = [experience.placeTitle?.trim(), experience.placeAddress?.trim()]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      effectiveQuery = parts.isNotEmpty ? parts.join(', ') : null;
    }

    if (effectivePlaceId == null &&
        (effectiveQuery == null || effectiveQuery.isEmpty)) return null;

    return RestaurantLookupService().fetch(
      placeId: effectivePlaceId,
      query: effectiveQuery,
      originalURL: experience.originalURL,
      tags: experience.personalTags,
      visited: experience.isDone,
    );
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
    super.dispose();
  }
}