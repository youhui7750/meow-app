import 'package:flutter/material.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/saved/experience_detail_screen.dart';
import 'package:meow_food_butler/views/saved/experience_entry_sheet.dart';
import 'package:provider/provider.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  void _openExperienceSheet(
    BuildContext context, {
    ExperienceCard? experience,
  }) {
    final viewModel = context.read<SavedViewModel>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ExperienceEntrySheet(
        initialExperience: experience,
        onSave: (savedExperience, photos) async {
          if (experience == null) {
            await viewModel.addExperience(savedExperience, photos: photos);
          } else {
            await viewModel.updateExperience(
              savedExperience,
              newPhotos: photos,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Dining Experiences')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExperienceSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Log meal'),
      ),
      body: Consumer<SavedViewModel>(
        builder: (context, viewModel, child) {
          final experiences = viewModel.experiences;

          if (experiences.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No meals logged yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save your first dining memory with a rating, note, and tags.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: experiences.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final experience = experiences[index];
              return _ExperienceCardTile(
                experience: experience,
                onTap: () {
                  final id = experience.id;
                  if (id == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          ExperienceDetailScreen(experienceId: id),
                    ),
                  );
                },
                onEdit: () =>
                    _openExperienceSheet(context, experience: experience),
                onDelete: () {
                  final id = experience.id;
                  if (id != null) viewModel.removeExperience(id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ExperienceCardTile extends StatelessWidget {
  final ExperienceCard experience;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExperienceCardTile({
    required this.experience,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = experience.createdTime.toDate();
    final dateText = '${date.month}/${date.day}/${date.year}';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: experience.photoUrls.isEmpty
                        ? Container(
                            width: 56,
                            height: 56,
                            color: colorScheme.primaryContainer,
                            child: Icon(
                              Icons.restaurant,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : Image.network(
                            experience.photoUrls.first,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 56,
                                  height: 56,
                                  color: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          experience.placeTitle ?? 'Unknown Food Spot',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _MiniStarRow(rating: experience.personalRating),
                            const SizedBox(width: 4),
                            Text(
                              experience.personalRating.toStringAsFixed(1),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.amber.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              dateText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              if (experience.personalNote?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  experience.personalNote!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (experience.personalTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: experience.personalTags
                      .map(
                        (tag) => Chip(
                          label: Text('#$tag'),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStarRow extends StatelessWidget {
  final double rating;

  const _MiniStarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(right: 1),
          child: _MiniPartialStar(fill: (rating - index).clamp(0.0, 1.0)),
        ),
      ),
    );
  }
}

class _MiniPartialStar extends StatelessWidget {
  final double fill;

  const _MiniPartialStar({required this.fill});

  @override
  Widget build(BuildContext context) {
    const size = 14.0;
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
