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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ExperienceCard.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> addExperience(
    ExperienceCard experience, {
    List<XFile> photos = const [],
  }) async {
    final docRef = _collection.doc();
    final baseExperience = experience.copyWith(
      id: docRef.id,
      photoPaths: const [],
      photoUrls: const [],
    );

    await docRef.set({
      ...baseExperience.toMap(),
      'createdTime': FieldValue.serverTimestamp(),
      'updatedTime': FieldValue.serverTimestamp(),
    });

    if (photos.isEmpty) return;

    final uploaded = await _uploadPhotos(docRef.id, photos);
    await docRef.update({
      'photoPaths': uploaded.paths,
      'photoUrls': uploaded.urls,
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
        SettableMetadata(contentType: 'image/$extension'),
      );

      paths.add(path);
      urls.add(await ref.getDownloadURL());
    }

    return _UploadedPhotos(paths: paths, urls: urls);
  }

  String _extensionFor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'png' || extension == 'webp') return extension;
    return 'jpg';
  }
}

class _UploadedPhotos {
  final List<String> paths;
  final List<String> urls;

  const _UploadedPhotos({required this.paths, required this.urls});
}
