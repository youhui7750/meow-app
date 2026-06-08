import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meow_food_butler/models/experience_card.dart';

class ExperienceEntrySheet extends StatefulWidget {
  final ExperienceCard? initialExperience;
  final Future<void> Function(ExperienceCard experience, List<XFile> photos)
  onSave;

  const ExperienceEntrySheet({
    super.key,
    this.initialExperience,
    required this.onSave,
  });

  @override
  State<ExperienceEntrySheet> createState() => _ExperienceEntrySheetState();
}

class _ExperienceEntrySheetState extends State<ExperienceEntrySheet> {
  static const List<String> _quickTags = [
    'cozy',
    'date-night',
    'quick-bite',
    'splurge',
    'vegan-friendly',
    'good-for-groups',
    'late-night',
  ];

  late final TextEditingController _placeController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagController;
  final ImagePicker _imagePicker = ImagePicker();
  late double _rating;
  late List<String> _photoUrls;
  final List<XFile> _pendingPhotos = [];
  late List<String> _tags;
  String? _placeAddress;
  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  bool _isSubmitting = false;

  bool get _isEditing => widget.initialExperience != null;
  bool get _canSave => _rating > 0 && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExperience;
    _placeController = TextEditingController(text: initial?.placeTitle ?? '');
    _noteController = TextEditingController(text: initial?.personalNote ?? '');
    _tagController = TextEditingController();
    _rating = initial?.personalRating ?? 0;
    _photoUrls = List<String>.from(initial?.photoUrls ?? const []);
    _tags = List<String>.from(initial?.personalTags ?? const []);
    _placeAddress = initial?.placeAddress;
    _latitude = initial?.latitude;
    _longitude = initial?.longitude;
  }

  @override
  void dispose() {
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
    final tag = rawTag.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
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
          final streetParts = [
            place.name,
            place.street,
          ].where((part) => part?.trim().isNotEmpty == true).cast<String>();
          final areaParts = [
            place.locality,
            place.administrativeArea,
            place.country,
          ].where((part) => part?.trim().isNotEmpty == true).cast<String>();

          title = streetParts.isEmpty ? null : streetParts.join(', ');
          address = [...streetParts, ...areaParts].join(', ');
        }
      } on PlatformException {
        address = null;
      }

      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _placeAddress = address;
        _placeController.text =
            title ??
            address ??
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      });
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
    try {
      await widget.onSave(
        ExperienceCard(
          id: initial?.id,
          foodCardId: initial?.foodCardId,
          placeTitle: _placeController.text.trim().isEmpty
              ? 'Unknown Food Spot'
              : _placeController.text.trim(),
          placeAddress: _placeAddress,
          latitude: _latitude,
          longitude: _longitude,
          originalURL: initial?.originalURL,
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Leave blank and Meow will use your GPS to figure it out.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                      _SectionLabel('Quick add'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _quickTags
                            .where((tag) => !_tags.contains(tag))
                            .map(
                              (tag) => ActionChip(
                                label: Text('+ $tag'),
                                onPressed: () => _addTag(tag),
                              ),
                            )
                            .toList(),
                      ),
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
