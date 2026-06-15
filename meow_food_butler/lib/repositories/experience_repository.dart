import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';

class ExperienceRepository {
  static const String _demoUid = 'demo-user';

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  ExperienceRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('users').doc(_demoUid).collection('experiences');

  Stream<List<ExperienceCard>> watchExperiences() {
    return _collection
        .orderBy('createdTime', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final experiences = <ExperienceCard>[];

          for (final doc in snapshot.docs) {
            var experience = ExperienceCard.fromMap(doc.data(), doc.id);
            if (experience.photoUrls.isEmpty &&
                experience.photoPaths.isNotEmpty) {
              final urls = await _downloadUrlsFor(experience.photoPaths);
              if (urls.isNotEmpty) {
                experience = experience.copyWith(photoUrls: urls);
                await doc.reference.update({
                  'photoUrls': urls,
                  'updatedTime': FieldValue.serverTimestamp(),
                });
              }
            }
            experiences.add(experience);
          }

          return experiences;
        });
  }

  Future<void> addExperience(
    ExperienceCard experience, {
    List<XFile> photos = const [],
  }) async {
    final docRef = _collection.doc();
    final uploaded = photos.isEmpty
        ? const _UploadedPhotos(paths: [], urls: [])
        : await _uploadPhotos(docRef.id, photos);
    final savedExperience = experience.copyWith(
      id: docRef.id,
      photoPaths: uploaded.paths,
      photoUrls: uploaded.urls,
    );

    await docRef.set({
      ...savedExperience.toMap(),
      'createdTime': FieldValue.serverTimestamp(),
      'updatedTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateExperience(
    ExperienceCard experience, {
    List<XFile> newPhotos = const [],
  }) async {
    final id = experience.id;
    if (id == null) return;

    final uploaded = newPhotos.isEmpty
        ? const _UploadedPhotos(paths: [], urls: [])
        : await _uploadPhotos(id, newPhotos);

    final nextPhotoPaths = [...experience.photoPaths, ...uploaded.paths];
    final nextPhotoUrls = [...experience.photoUrls, ...uploaded.urls];

    await _collection.doc(id).update({
      ...experience
          .copyWith(photoPaths: nextPhotoPaths, photoUrls: nextPhotoUrls)
          .toMap(),
      'updatedTime': FieldValue.serverTimestamp(),
    });
  }

  /// Link an experience to the restaurant/FoodCard doc that was resolved for it,
  /// so the next detail open is a Firestore read instead of another Outscraper
  /// fetch. No-op write is harmless; callers guard against relinking.
  Future<void> linkFoodCard(String experienceId, String foodCardId) async {
    await _collection.doc(experienceId).update({
      'foodCardId': foodCardId,
      'updatedTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExperience(ExperienceCard experience) async {
    for (final path in experience.photoPaths) {
      try {
        await _storage.ref(path).delete();
      } on FirebaseException {
        // Keep deleting the record even if an old photo is already gone.
      }
    }

    final id = experience.id;
    if (id != null) {
      await _collection.doc(id).delete();
    }
  }

  Future<_UploadedPhotos> _uploadPhotos(
    String experienceId,
    List<XFile> photos,
  ) async {
    final paths = <String>[];
    final urls = <String>[];

    for (var index = 0; index < photos.length; index += 1) {
      final photo = photos[index];
      final extension = _extensionFor(photo.name);
      final path =
          'users/$_demoUid/experiences/$experienceId/photos/${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
      final ref = _storage.ref(path);

      await ref.putData(
        await photo.readAsBytes(),
        SettableMetadata(contentType: _contentTypeFor(extension)),
      );

      paths.add(path);
      urls.add(await ref.getDownloadURL());
    }

    return _UploadedPhotos(paths: paths, urls: urls);
  }

  Future<List<String>> _downloadUrlsFor(List<String> paths) async {
    final urls = <String>[];
    for (final path in paths) {
      try {
        urls.add(await _storage.ref(path).getDownloadURL());
      } on FirebaseException {
        // Ignore broken legacy paths; the UI will keep the placeholder.
      }
    }
    return urls;
  }

  String _extensionFor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'png' || extension == 'webp') return extension;
    return 'jpg';
  }

  String _contentTypeFor(String extension) {
    if (extension == 'jpg') return 'image/jpeg';
    return 'image/$extension';
  }
}

class _UploadedPhotos {
  final List<String> paths;
  final List<String> urls;

  const _UploadedPhotos({required this.paths, required this.urls});
}
