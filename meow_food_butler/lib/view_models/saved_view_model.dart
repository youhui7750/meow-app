import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';

class SavedViewModel extends ChangeNotifier {
  final ExperienceRepository _repository;
  StreamSubscription<List<ExperienceCard>>? _subscription;

  final List<ExperienceCard> _experiences = [
    ExperienceCard(
      id: 'seed-exp-ramen',
      placeTitle: 'Ippudo Tokyo',
      photoUrls: const [
        'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=600&q=80',
      ],
      personalTags: const ['ramen', 'warm'],
      personalRating: 4.5,
      personalNote: 'Broth was rich and cozy. Good spot for a rainy night.',
      isDone: true,
    ),
    ExperienceCard(
      id: 'seed-exp-matcha',
      placeTitle: 'Matcha Maiden',
      photoUrls: const [
        'https://images.unsplash.com/photo-1515823064-d6e0c04616a7?auto=format&fit=crop&w=600&q=80',
      ],
      personalTags: const ['dessert', 'afternoon'],
      personalRating: 5,
      personalNote: 'Loved the crepe cake and the calm interior.',
      isDone: true,
    ),
  ];

  bool _isSaving = false;
  String? _errorMessage;

  SavedViewModel({ExperienceRepository? repository})
    : _repository = repository ?? ExperienceRepository() {
    _watchExperiences();
  }

  List<ExperienceCard> get experiences => List.unmodifiable(_experiences);
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
      fallback: () {
        final id =
            experience.id ?? 'exp-${DateTime.now().microsecondsSinceEpoch}';
        _experiences.insert(0, experience.copyWith(id: id));
      },
    );
  }

  Future<void> updateExperience(
    ExperienceCard experience, {
    List<XFile> newPhotos = const [],
  }) async {
    await _runSaveAction(
      () => _repository.updateExperience(experience, newPhotos: newPhotos),
      fallback: () {
        final id = experience.id;
        if (id == null) return;

        final index = _experiences.indexWhere((item) => item.id == id);
        if (index == -1) return;

        _experiences[index] = experience;
      },
    );
  }

  Future<void> removeExperience(String id) async {
    final experience = experienceById(id);
    if (experience == null) return;

    await _runSaveAction(
      () => _repository.deleteExperience(experience),
      fallback: () => _experiences.removeWhere((item) => item.id == id),
    );
  }

  Future<void> _runSaveAction(
    Future<void> Function() action, {
    required VoidCallback fallback,
  }) async {
    if (_isSaving) return;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      fallback();
      _errorMessage = 'Saved locally. Cloud sync failed: $error';
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
