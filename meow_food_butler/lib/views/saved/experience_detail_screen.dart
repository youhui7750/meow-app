import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/saved/share_card_page.dart';
import 'package:meow_food_butler/views/saved/experience_entry_sheet.dart';
import 'package:meow_food_butler/views/saved/widgets/experience_photo.dart';
import 'package:meow_food_butler/views/saved/widgets/photo_preview_screen.dart';
import 'package:provider/provider.dart';

class ExperienceDetailScreen extends StatelessWidget {
  final String experienceId;

  const ExperienceDetailScreen({super.key, required this.experienceId});

  void _openEditSheet(BuildContext context, ExperienceCard experience) {
    final viewModel = context.read<SavedViewModel>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ExperienceEntrySheet(
        initialExperience: experience,
        savedPlaceSuggestions: viewModel.experiences,
        onSave: (savedExperience, photos) =>
            viewModel.updateExperience(savedExperience, newPhotos: photos),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ExperienceCard experience,
  ) async {
    final viewModel = context.read<SavedViewModel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this meal?'),
        content: const Text('This experience record will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await viewModel.removeExperience(experience.id!);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  String _formatCardDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}.$month.$day';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedViewModel>(
      builder: (context, viewModel, child) {
        final experience = viewModel.experienceById(experienceId);

        if (experience == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Experience not found')),
          );
        }

        final colorScheme = Theme.of(context).colorScheme;
        final dateText = _formatTaiwanDateTime(experience.createdTime.toDate());
        final photoSources = _photoSourcesFor(experience);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => Navigator.of(context).pop(),
            ),
            centerTitle: true,
            title: Column(
              children: [
                Text(
                  'Meal experience'.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  experience.placeTitle ?? 'Unknown Food Spot',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => _openEditSheet(context, experience),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
              ),
              IconButton(
                onPressed: experience.id == null
                    ? null
                    : () => _confirmDelete(context, experience),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                color: colorScheme.error,
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShareCardPage(
                        data: RestaurantCardData(
                          name: experience.placeTitle ?? 'Unknown Restaurant',
                          address: experience.placeAddress ?? 'Unknown address',
                          personalRating: experience.personalRating,
                          personalNote: experience.personalNote ?? '',
                          photoUrls: experience.photoUrls,
                          photoPaths: experience.photoPaths,
                          date: _formatCardDate(experience.createdTime.toDate()),
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Row(
                children: [
                  Expanded(child: _StarRow(rating: experience.personalRating)),
                  Text(
                    experience.personalRating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (photoSources.isNotEmpty) ...[
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photoSources.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final source = photoSources[index];
                      final previewSources = photoSources
                          .map((s) => PhotoSource(url: s.photoUrl, path: s.photoPath))
                          .toList();

                      return GestureDetector(
                        onTap: () => PhotoPreviewScreen.show(
                          context,
                          sources: previewSources,
                          initialIndex: index,
                        ),
                        child: ExperiencePhoto(
                          key: ValueKey(
                            '${experience.id}-$index-${source.photoPath ?? source.photoUrl ?? 'empty'}',
                          ),
                          experience: experience,
                          photoUrl: source.photoUrl,
                          photoPath: source.photoPath,
                          width: 180,
                          height: 180,
                          borderRadius: 18,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
              ],
              _NoteBox(note: experience.personalNote),
              const SizedBox(height: 18),
              _InfoRow(
                icon: Icons.location_on_outlined,
                text:
                    experience.placeAddress ??
                    experience.placeTitle ??
                    'Unknown Food Spot',
              ),
              const SizedBox(height: 10),
              _InfoRow(icon: Icons.calendar_month_outlined, text: dateText),
              const SizedBox(height: 24),
              Text(
                'Tags'.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: experience.personalTags.isEmpty
                    ? [
                        Text(
                          'No tags yet',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ]
                    : experience.personalTags
                          .map(
                            (tag) => Chip(
                              label: Text('#$tag'),
                              backgroundColor: colorScheme.primaryContainer,
                              labelStyle: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                          .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String? note;

  const _NoteBox({required this.note});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your note'.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Text(note?.isNotEmpty == true ? note! : 'No note yet'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;

  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _PartialStar(fill: (rating - index).clamp(0.0, 1.0), size: 28),
        ),
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

String _formatTaiwanDateTime(DateTime date) {
  final taiwanTime = date.toUtc().add(const Duration(hours: 8));
  final year = taiwanTime.year.toString();
  final month = taiwanTime.month.toString().padLeft(2, '0');
  final day = taiwanTime.day.toString().padLeft(2, '0');
  final hour = taiwanTime.hour.toString().padLeft(2, '0');
  final minute = taiwanTime.minute.toString().padLeft(2, '0');
  return '$year/$month/$day $hour:$minute';
}

List<_PhotoSource> _photoSourcesFor(ExperienceCard experience) {
  final id = experience.id;
  final count = math.max(
    experience.photoUrls.length,
    experience.photoPaths.length,
  );
  final sources = <_PhotoSource>[];

  for (var index = 0; index < count; index += 1) {
    final photoUrl = index < experience.photoUrls.length
        ? experience.photoUrls[index]
        : null;
    final photoPath = index < experience.photoPaths.length
        ? experience.photoPaths[index]
        : null;

    if (id != null &&
        !_photoBelongsToExperience(photoUrl, id) &&
        !_photoBelongsToExperience(photoPath, id)) {
      continue;
    }

    sources.add(_PhotoSource(photoUrl: photoUrl, photoPath: photoPath));
  }

  return sources;
}

bool _photoBelongsToExperience(String? photo, String id) {
  if (photo == null) return false;
  final decoded = Uri.decodeFull(photo);
  return decoded.contains('/experiences/$id/') ||
      decoded.contains('experiences/$id/');
}

class _PhotoSource {
  final String? photoUrl;
  final String? photoPath;

  const _PhotoSource({required this.photoUrl, required this.photoPath});
}
