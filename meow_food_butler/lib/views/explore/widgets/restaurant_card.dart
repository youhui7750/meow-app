import 'package:flutter/material.dart';
import '../../../models/experience_card.dart';

class RestaurantCard extends StatelessWidget {
  final ExperienceCard experience;
  final VoidCallback? onNavTap; 

  const RestaurantCard({
    super.key,
    required this.experience,
    this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          experience.placeTitle ?? 'Unnamed restaurant',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (experience.isDone) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle, color: colorScheme.tertiary, size: 18),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.navigation, color: colorScheme.primary),
                  onPressed: onNavTap,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 4),

            Text(
              experience.placeAddress ?? 'No address available',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: colorScheme.primary, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      experience.personalRating.toStringAsFixed(1),
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold, 
                        color: colorScheme.primary
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 12, color: colorScheme.outlineVariant),
                ...experience.personalTags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$tag',
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 100,
              child: experience.photoUrls.isEmpty
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_not_supported_outlined, color: colorScheme.outline, size: 20),
                            const SizedBox(width: 8),
                            Text('No photos yet', style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: experience.photoUrls.length,
                      itemBuilder: (context, picIndex) => Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: NetworkImage(experience.photoUrls[picIndex]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
            ),

            if (experience.personalNote != null && experience.personalNote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primaryContainer, width: 1),
                ),
                child: Text(
                  '“${experience.personalNote}”',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}