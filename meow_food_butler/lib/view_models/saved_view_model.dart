import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';

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

  // Original flat list of all experiences
  List<ExperienceCard> get experiences => List.unmodifiable(_experiences);

  // NEW: Grouped list by restaurant
  List<List<ExperienceCard>> get groupedExperiences {
    final map = <String, List<ExperienceCard>>{};

    for (final exp in _experiences) {
      // Grouping priority: foodCardId > placeId > placeTitle > id
      final key = exp.foodCardId ?? exp.placeId ?? exp.placeTitle ?? exp.id;
      final safeKey = key ?? 'unknown';
      
      map.putIfAbsent(safeKey, () => []).add(exp);
    }

    final groupedList = map.values.toList();

    // 1. Sort experiences within each restaurant group (newest meal first)
    for (final group in groupedList) {
      group.sort((a, b) {
        if (a.createdTime == null && b.createdTime == null) return 0;
        if (a.createdTime == null) return 1;
        if (b.createdTime == null) return -1;
        return b.createdTime!.compareTo(a.createdTime!);
      });
    }

    // 2. Sort the restaurant groups themselves (most recently updated restaurant first)
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

  Future<void> addExperience(
    ExperienceCard experience, {
    List<XFile> photos = const [],
  }) async {
    await _runSaveAction(
      () => _repository.addExperience(experience, photos: photos),
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

    await _runSaveAction(() => _repository.deleteExperience(experience));
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