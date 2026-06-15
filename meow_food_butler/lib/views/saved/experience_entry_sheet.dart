import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/services/nearby_places_service.dart';
import 'package:meow_food_butler/view_models/app_settings_view_model.dart';
import 'package:provider/provider.dart';

class ExperienceEntrySheet extends StatefulWidget {
  final ExperienceCard? initialExperience;
  final List<ExperienceCard> savedPlaceSuggestions;
  final Future<void> Function(ExperienceCard experience, List<XFile> photos)
  onSave;

  const ExperienceEntrySheet({
    super.key,
    this.initialExperience,
    this.savedPlaceSuggestions = const [],
    required this.onSave,
  });

  @override
  State<ExperienceEntrySheet> createState() => _ExperienceEntrySheetState();
}

class _ExperienceEntrySheetState extends State<ExperienceEntrySheet> {
  static const List<String> _quickTags = [
    '氣氛好',
    '朋友聚餐',
    'CP值高',
    '平價',
    '需要排隊',
  ];

  late final TextEditingController _placeController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagController;
  final ImagePicker _imagePicker = ImagePicker();
  final NearbyPlacesService _nearbyPlacesService = NearbyPlacesService();
  Timer? _placeSearchDebounce;
  late double _rating;
  late List<String> _photoUrls;
  final List<XFile> _pendingPhotos = [];
  late List<String> _tags;
  List<NearbyPlace> _placeSearchResults = const [];
  String? _placeId;
  String? _placeAddress;
  double? _latitude;
  double? _longitude;
  bool _isSearchingPlaces = false;
  bool _isApplyingPlaceSelection = false;
  bool _isLocating = false;
  bool _isSubmitting = false;
  bool _showPlaceRequiredHint = false;

  bool get _isEditing => widget.initialExperience != null;
  bool get _canSave => _rating > 0 && !_isSubmitting;
  bool get _isPlaceEmpty => _placeController.text.trim().isEmpty;

  List<String> get _quickAddTags {
    final tags = <String>[];

    void addTag(String rawTag) {
      final tag = rawTag.trim();
      if (tag.isEmpty || _tags.contains(tag) || tags.contains(tag)) return;
      tags.add(tag);
    }

    for (final tag in _quickTags) {
      addTag(tag);
    }

    for (final experience in widget.savedPlaceSuggestions) {
      for (final tag in experience.personalTags) {
        addTag(tag);
      }
    }

    return tags;
  }

  List<_QuickTagGroup> _visibleQuickTagGroups(
    List<AppTagGroup> quickTagGroups,
  ) {
    final groups = <_QuickTagGroup>[];

    for (final group in quickTagGroups) {
      final tags = _availableQuickTags(group.tags);
      if (tags.isNotEmpty) {
        groups.add(_QuickTagGroup(group.label, tags));
      }
    }

    return groups;
  }

  List<String> _availableQuickTags(Iterable<String> rawTags) {
    final tags = <String>[];
    for (final rawTag in rawTags) {
      final tag = rawTag.trim();
      if (tag.isEmpty || _tags.contains(tag) || tags.contains(tag)) continue;
      tags.add(tag);
    }
    return tags;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExperience;
    _placeController = TextEditingController(text: initial?.placeTitle ?? '');
    _noteController = TextEditingController(text: initial?.personalNote ?? '');
    _tagController = TextEditingController();
    _placeController.addListener(_onPlaceQueryChanged);
    _showPlaceRequiredHint = _placeController.text.trim().isEmpty;
    _rating = initial?.personalRating ?? 0;
    _photoUrls = List<String>.from(initial?.photoUrls ?? const []);
    _tags = List<String>.from(initial?.personalTags ?? const []);
    _placeId = initial?.placeId;
    _placeAddress = initial?.placeAddress;
    _latitude = initial?.latitude;
    _longitude = initial?.longitude;
  }

  @override
  void dispose() {
    _placeSearchDebounce?.cancel();
    _placeController.dispose();
    _noteController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _setRatingFromTap(Offset localPosition, double width) {
    final raw = (localPosition.dx / width * 5).clamp(0.0, 5.0);
    setState(() => _rating = (raw * 2).ceil() / 2);
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceAll(RegExp(r'\s+'), '-');
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  void _onPlaceQueryChanged() {
    if (_isApplyingPlaceSelection) return;

    _placeSearchDebounce?.cancel();
    if (_placeId != null || _placeAddress != null || _latitude != null) {
      setState(() {
        _placeId = null;
        _placeAddress = null;
        _latitude = null;
        _longitude = null;
      });
    }

    final query = _placeController.text.trim();
    if (_showPlaceRequiredHint != query.isEmpty) {
      setState(() => _showPlaceRequiredHint = query.isEmpty);
    }

    if (query.length < 2) {
      if (_placeSearchResults.isNotEmpty || _isSearchingPlaces) {
        setState(() {
          _placeSearchResults = const [];
          _isSearchingPlaces = false;
        });
      }
      return;
    }

    _placeSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (_isSubmitting) return;

    setState(() => _isSearchingPlaces = true);
    try {
      final savedResults = _savedPlaceResults(query);
      final googleResults = await _nearbyPlacesService.searchRestaurants(query);
      final results = _mergePlaceResults(savedResults, googleResults);
      if (!mounted || _placeController.text.trim() != query) return;
      setState(() => _placeSearchResults = results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _placeSearchResults = const []);
    } finally {
      if (mounted) setState(() => _isSearchingPlaces = false);
    }
  }

  void _selectPlace(NearbyPlace place) {
    _placeSearchDebounce?.cancel();
    _isApplyingPlaceSelection = true;
    setState(() {
      _placeId = place.placeId.isEmpty ? null : place.placeId;
      _placeAddress = place.address;
      _latitude = place.latitude;
      _longitude = place.longitude;
      _placeSearchResults = const [];
      _isSearchingPlaces = false;
      _placeController.text = place.name;
    });
    _isApplyingPlaceSelection = false;
    FocusScope.of(context).unfocus();
  }

  List<NearbyPlace> _savedPlaceResults(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.length < 2) return const [];

    final results = <NearbyPlace>[];
    final seenNames = <String>{};

    for (final experience in widget.savedPlaceSuggestions) {
      final name = experience.placeTitle?.trim();
      if (name == null || name.isEmpty) continue;

      final address = experience.placeAddress?.trim();
      final searchableText = [
        name,
        address,
      ].whereType<String>().join(' ').toLowerCase();
      if (!searchableText.contains(normalizedQuery)) continue;

      final key = '$name|${address ?? ''}'.toLowerCase();
      if (!seenNames.add(key)) continue;

      results.add(
        NearbyPlace(
          placeId: experience.placeId ?? '',
          name: name,
          address: address,
          latitude: experience.latitude,
          longitude: experience.longitude,
        ),
      );
    }

    return results;
  }

  List<NearbyPlace> _mergePlaceResults(
    List<NearbyPlace> savedResults,
    List<NearbyPlace> googleResults,
  ) {
    final merged = <NearbyPlace>[];
    final seen = <String>{};

    for (final place in [...savedResults, ...googleResults]) {
      final key = place.placeId.isNotEmpty
          ? place.placeId
          : '${place.name}|${place.address ?? ''}'.toLowerCase();
      if (!seen.add(key)) continue;
      merged.add(place);
    }

    return merged;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    XFile? photo;

    try {
      photo = await _imagePicker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1600,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo picker is not ready. Fully stop the app and run flutter run again. (${error.code})',
          ),
        ),
      );
      return;
    }

    final pickedPhoto = photo;
    if (pickedPhoto == null) return;
    setState(() => _pendingPhotos.add(pickedPhoto));
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating || _isSubmitting) return;
    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _LocationException(
          'Please turn on location services first.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const _LocationException('Location permission was denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw const _LocationException(
          'Location permission is permanently denied. Enable it in Settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      String? address;
      String? title;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final streetParts = _locationParts([place.name, place.street]);
          final areaParts = _locationParts([
            place.locality,
            place.administrativeArea,
            place.country,
          ]);

          title = streetParts.isEmpty ? null : streetParts.join(', ');
          address = _joinLocationParts([...streetParts, ...areaParts]);
        }
      } catch (_) {
        address = null;
      }

      if (!mounted) return;
      final fallbackPlace = NearbyPlace(
        placeId: '',
        name:
            title ??
            address ??
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        address: address,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final selectedPlace = await _chooseNearbyRestaurant(
        latitude: position.latitude,
        longitude: position.longitude,
        fallbackPlace: fallbackPlace,
      );

      if (!mounted || selectedPlace == null) return;
      _selectPlace(selectedPlace);
    } on _LocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not get location: $error')));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<NearbyPlace?> _chooseNearbyRestaurant({
    required double latitude,
    required double longitude,
    required NearbyPlace fallbackPlace,
  }) async {
    var places = <NearbyPlace>[];
    var lookupMessage = 'Select the restaurant you are at.';

    try {
      places = await _nearbyPlacesService.restaurantsNear(
        latitude: latitude,
        longitude: longitude,
      );
      if (places.isEmpty && !_nearbyPlacesService.hasApiKey) {
        lookupMessage =
            'Places API key is not set. Using GPS location only for now.';
      } else if (places.isEmpty) {
        lookupMessage =
            'No nearby restaurants found. Use GPS location instead.';
      }
    } on NearbyPlacesException catch (error) {
      lookupMessage = '${error.message} Use GPS location instead.';
    } catch (_) {
      lookupMessage =
          'Could not load nearby restaurants. Use GPS location instead.';
    }

    if (!mounted) return null;
    return showModalBottomSheet<NearbyPlace>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nearby restaurants',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                lookupMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: places.length + 1,
                  separatorBuilder: (context, index) =>
                      Divider(color: colorScheme.outlineVariant),
                  itemBuilder: (context, index) {
                    if (index == places.length) {
                      return ListTile(
                        leading: const Icon(Icons.my_location),
                        title: const Text('Use GPS location only'),
                        subtitle: Text(
                          fallbackPlace.address ?? fallbackPlace.name,
                        ),
                        onTap: () => Navigator.of(context).pop(fallbackPlace),
                      );
                    }

                    final place = places[index];
                    return ListTile(
                      leading: const Icon(Icons.restaurant_outlined),
                      title: Text(place.name),
                      subtitle: place.address == null
                          ? null
                          : Text(place.address!),
                      onTap: () => Navigator.of(context).pop(place),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _removePhotoUrl(String url) {
    setState(() => _photoUrls.remove(url));
  }

  void _removePendingPhoto(XFile photo) {
    setState(() => _pendingPhotos.remove(photo));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSubmitting = true);

    final initial = widget.initialExperience;
    if (_isPlaceEmpty) {
      setState(() => _showPlaceRequiredHint = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the place name.')),
      );
    }

    final placeTitle = _placeController.text.trim().isEmpty
        ? 'Unknown Food Spot'
        : _placeController.text.trim();
    final region = _regionFromLocationText([
      _placeAddress,
      placeTitle,
      initial?.region,
    ]);

    try {
      await widget.onSave(
        ExperienceCard(
          id: initial?.id,
          foodCardId: initial?.foodCardId,
          placeId: _placeId,
          placeTitle: placeTitle,
          placeAddress: _placeAddress,
          region: region,
          latitude: _latitude,
          longitude: _longitude,
          originalURL: initial?.originalURL,
          photoPaths: List.unmodifiable(initial?.photoPaths ?? const []),
          photoUrls: List.unmodifiable(_photoUrls),
          personalTags: List.unmodifiable(_tags),
          personalRating: _rating,
          personalNote: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          createdTime: initial?.createdTime,
          isDone: true,
        ),
        List.unmodifiable(_pendingPhotos),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quickTagGroups = context
        .watch<AppSettingsViewModel>()
        .quickTagGroups;
    final visibleQuickTagGroups = _visibleQuickTagGroups(quickTagGroups);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              isEditing: _isEditing,
              canSave: _canSave,
              isSubmitting: _isSubmitting,
              onClose: _isSubmitting ? null : () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isSubmitting
                  ? const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  : const SizedBox(height: 10),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: AbsorbPointer(
                absorbing: _isSubmitting,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSubmitting) ...[
                        Text(
                          'Uploading photos and saving your meal...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            size: 18,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tell me how that bite was -- I will log it for you.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('Your rating'),
                      const SizedBox(height: 8),
                      _RatingSelector(
                        rating: _rating,
                        onTapRating: _setRatingFromTap,
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('Meal experience'),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 104,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ..._photoUrls.map(
                              (url) => _PhotoPreview(
                                url: url,
                                onRemove: () => _removePhotoUrl(url),
                              ),
                            ),
                            ..._pendingPhotos.map(
                              (photo) => _PendingPhotoPreview(
                                photo: photo,
                                onRemove: () => _removePendingPhoto(photo),
                              ),
                            ),
                            _PhotoActionTile(
                              icon: Icons.camera_alt_outlined,
                              label: 'Take',
                              onTap: () => _pickPhoto(ImageSource.camera),
                            ),
                            _PhotoActionTile(
                              icon: Icons.upload_outlined,
                              label: 'Upload',
                              onTap: () => _pickPhoto(ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _noteController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: 'What did you order? How was it?',
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('Place'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _placeController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Where was it? (e.g. Ippudo Tokyo)',
                          prefixIcon: Icon(
                            Icons.location_on_outlined,
                            color: colorScheme.primary,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      _PlaceSearchResults(
                        isSearching: _isSearchingPlaces,
                        places: _placeSearchResults,
                        onSelected: _selectPlace,
                      ),
                      if (_showPlaceRequiredHint && _isPlaceEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Please fill in the place name so this meal is easier to find later.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _isLocating ? null : _useCurrentLocation,
                        icon: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          _isLocating
                              ? 'Finding current location...'
                              : 'Use current location',
                        ),
                      ),
                      if (_placeAddress?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(
                          _placeAddress!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionLabel('Your tags'),
                      const SizedBox(height: 10),
                      if (_tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _tags
                                .map(
                                  (tag) => InputChip(
                                    label: Text('#$tag'),
                                    onDeleted: () => _removeTag(tag),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: _addTag,
                              decoration: InputDecoration(
                                hintText: 'add your own tag',
                                prefixIcon: const Icon(Icons.tag),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: () => _addTag(_tagController.text),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add tag',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (visibleQuickTagGroups.isNotEmpty) ...[
                        _SectionLabel('Quick add'),
                        const SizedBox(height: 8),
                        ...visibleQuickTagGroups.map(
                          (group) => _QuickTagGroupChips(
                            group: group,
                            onSelected: _addTag,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationException implements Exception {
  final String message;

  const _LocationException(this.message);
}

class _QuickTagGroup {
  final String label;
  final List<String> tags;

  const _QuickTagGroup(this.label, this.tags);
}

class _QuickTagGroupChips extends StatelessWidget {
  final _QuickTagGroup group;
  final ValueChanged<String> onSelected;

  const _QuickTagGroupChips({
    required this.group,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.tags
                .map(
                  (tag) => ActionChip(
                    label: Text('+ $tag'),
                    onPressed: () => onSelected(tag),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

List<String> _locationParts(List<String?> values) {
  return values
      .map((value) => value?.trim())
      .where((value) => value != null && value.isNotEmpty)
      .cast<String>()
      .toList();
}

String? _joinLocationParts(List<String> values) {
  final uniqueValues = <String>[];
  for (final value in values) {
    if (!uniqueValues.contains(value)) uniqueValues.add(value);
  }
  return uniqueValues.isEmpty ? null : uniqueValues.join(', ');
}

String? _regionFromLocationText(List<String?> values) {
  final text = values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ')
      .replaceAll('臺', '台');
  if (text.isEmpty) return null;

  const regionPatterns = <String, List<String>>{
    '台北': ['台北市', '台北'],
    '新北': ['新北市', '新北'],
    '桃園': ['桃園市', '桃園'],
    '新竹': ['新竹市', '新竹縣', '新竹'],
    '苗栗': ['苗栗縣', '苗栗'],
    '台中': ['台中市', '台中'],
    '彰化': ['彰化縣', '彰化'],
    '南投': ['南投縣', '南投'],
    '雲林': ['雲林縣', '雲林'],
    '嘉義': ['嘉義市', '嘉義縣', '嘉義'],
    '台南': ['台南市', '台南'],
    '高雄': ['高雄市', '高雄'],
    '屏東': ['屏東縣', '屏東'],
    '宜蘭': ['宜蘭縣', '宜蘭'],
    '花蓮': ['花蓮縣', '花蓮'],
    '台東': ['台東縣', '台東'],
    '基隆': ['基隆市', '基隆'],
    '澎湖': ['澎湖縣', '澎湖'],
    '金門': ['金門縣', '金門'],
    '連江': ['連江縣', '馬祖', '連江'],
  };

  for (final entry in regionPatterns.entries) {
    if (entry.value.any(text.contains)) return entry.key;
  }

  return null;
}

class _Header extends StatelessWidget {
  final bool isEditing;
  final bool canSave;
  final bool isSubmitting;
  final VoidCallback? onClose;
  final VoidCallback onSave;

  const _Header({
    required this.isEditing,
    required this.canSave,
    required this.isSubmitting,
    required this.onClose,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Back',
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                isEditing ? 'Edit entry' : 'New entry',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                isEditing ? 'Edit your meal' : 'Rate a meal',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: canSave ? onSave : null,
          icon: isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(isSubmitting ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class _PlaceSearchResults extends StatelessWidget {
  final bool isSearching;
  final List<NearbyPlace> places;
  final ValueChanged<NearbyPlace> onSelected;

  const _PlaceSearchResults({
    required this.isSearching,
    required this.places,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSearching && places.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: isSearching
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Searching restaurants...'),
                ],
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: places.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: colorScheme.outlineVariant),
              itemBuilder: (context, index) {
                final place = places[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.restaurant_outlined),
                  title: Text(place.name),
                  subtitle: place.address == null ? null : Text(place.address!),
                  onTap: () => onSelected(place),
                );
              },
            ),
    );
  }
}

class _RatingSelector extends StatelessWidget {
  final double rating;
  final void Function(Offset localPosition, double width) onTapRating;

  const _RatingSelector({required this.rating, required this.onTapRating});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xfffffbef),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffffe7ae)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      onTapRating(details.localPosition, constraints.maxWidth),
                  onHorizontalDragUpdate: (details) =>
                      onTapRating(details.localPosition, constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (index) => Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _PartialStar(
                          fill: (rating - index).clamp(0.0, 1.0),
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rating == 0 ? '--' : rating.toStringAsFixed(1),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'OUT OF 5',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartialStar extends StatelessWidget {
  final double fill;
  final double size;

  const _PartialStar({required this.fill, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Icon(Icons.star_border, size: size, color: Colors.blueGrey.shade200),
          ClipRect(
            clipper: _WidthClipper(fill),
            child: Icon(Icons.star, size: size, color: Colors.amber.shade600),
          ),
        ],
      ),
    );
  }
}

class _WidthClipper extends CustomClipper<Rect> {
  final double factor;

  const _WidthClipper(this.factor);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * factor, size.height);
  }

  @override
  bool shouldReclip(_WidthClipper oldClipper) => oldClipper.factor != factor;
}

class _PhotoActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PhotoActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.outlineVariant,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _PhotoPreview({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.network(
              url,
              width: 104,
              height: 104,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 104,
                height: 104,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filled(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingPhotoPreview extends StatelessWidget {
  final XFile photo;
  final VoidCallback onRemove;

  const _PendingPhotoPreview({required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: photo.readAsBytes(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;

        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: bytes == null
                    ? Container(
                        width: 104,
                        height: 104,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      )
                    : Image.memory(
                        bytes,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}
