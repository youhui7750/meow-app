import 'package:flutter/material.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/saved/experience_entry_sheet.dart';
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
        final date = experience.createdTime.toDate();
        final dateText =
            '${date.year}/${date.month}/${date.day} ${_formatTime(date)}';

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
                onPressed: () {},
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
              if (experience.photoUrls.isNotEmpty) ...[
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: experience.photoUrls.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          experience.photoUrls[index],
                          width: 180,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 180,
                                height: 180,
                                color: colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
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
              const SizedBox(height: 20),
              InkWell(
                onTap: () => _openEditSheet(context, experience),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.control_camera,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Re-locate this meal',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              'File it under a different food card',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
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

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
