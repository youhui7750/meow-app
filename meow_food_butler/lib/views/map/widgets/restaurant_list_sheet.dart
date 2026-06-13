import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/views/saved/food_card_detail.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class RestaurantListSheet extends StatelessWidget {
  static const double minSize = 0.07;
  static const double initialSize = 0.42;
  static const double maxSize = 0.86;
  static const List<double> snapSizes = [minSize, initialSize, maxSize];

  final DraggableScrollableController controller;
  final List<ExperienceCard> experiences;
  final String? selectedExperienceId;
  final String Function(ExperienceCard experience) markerIdFor;
  final ValueChanged<ExperienceCard> onExperienceSelected;

  const RestaurantListSheet({
    super.key,
    required this.controller,
    required this.experiences,
    required this.selectedExperienceId,
    required this.markerIdFor,
    required this.onExperienceSelected,
  });

  void _showRestaurantDetail(BuildContext context, ExperienceCard experience) {
    final relatedFoodCard = FoodCard(
      id: experience.foodCardId,
      originalURL: experience.photoUrls.isNotEmpty
          ? experience.photoUrls.first
          : experience.originalURL,
      formattedAddress: experience.placeAddress,
      rating: experience.personalRating,
      displayNames: [
        DisplayName(
          title: experience.placeTitle ?? 'Unnamed restaurant',
          languageCode: 'en',
        ),
      ],
      location: experience.latitude != null && experience.longitude != null
          ? LocationCoordinate(
              latitude: experience.latitude,
              longitude: experience.longitude,
            )
          : null,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: FoodCardDetail(
                foodCard: relatedFoodCard,
                experiences: [experience],
                isSaved: experience.isDone,
                onClose: () => Navigator.pop(context),
                onToggleSave: () {},
                onAddExperience: () {},
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: PointerInterceptor(
        child: DraggableScrollableSheet(
          controller: controller,
          expand: false,
          snap: true,
          snapSizes: snapSizes,
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          builder: (context, scrollController) {
            return ScrollConfiguration(
              behavior: const _MapSheetScrollBehavior(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 22,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: experiences.isEmpty
                    ? _EmptyMapSheet(scrollController: scrollController)
                    : CustomScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          SliverToBoxAdapter(
                            child: _SheetHeader(
                              count: experiences.length,
                              controller: controller,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            sliver: SliverList.separated(
                              itemCount: experiences.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final experience = experiences[index];
                                final selected =
                                    markerIdFor(experience) ==
                                    selectedExperienceId;

                                return _MapRestaurantCard(
                                  experience: experience,
                                  selected: selected,
                                  onTap: () {
                                    onExperienceSelected(experience);
                                    _showRestaurantDetail(context, experience);
                                  },
                                  onLocate: () =>
                                      onExperienceSelected(experience),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MapSheetScrollBehavior extends MaterialScrollBehavior {
  const _MapSheetScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _SheetHeader extends StatelessWidget {
  final int count;
  final DraggableScrollableController controller;

  const _SheetHeader({required this.count, required this.controller});

  void _dragSheet(BuildContext context, DragUpdateDetails details) {
    if (!controller.isAttached) return;
    final height = MediaQuery.sizeOf(context).height;
    final delta = details.primaryDelta ?? 0;
    final nextSize = (controller.size - delta / height).clamp(
      RestaurantListSheet.minSize,
      RestaurantListSheet.maxSize,
    );
    controller.jumpTo(nextSize);
  }

  void _snapSheet() {
    if (!controller.isAttached) return;
    final current = controller.size;
    final target = RestaurantListSheet.snapSizes.reduce((a, b) {
      return (current - a).abs() < (current - b).abs() ? a : b;
    });
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => _dragSheet(context, details),
      onVerticalDragEnd: (_) => _snapSheet(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.place, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count saved place${count == 1 ? '' : 's'} on your map',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapRestaurantCard extends StatelessWidget {
  final ExperienceCard experience;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLocate;

  const _MapRestaurantCard({
    required this.experience,
    required this.selected,
    required this.onTap,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = experience.photoUrls.isEmpty
        ? null
        : experience.photoUrls.first;

    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl == null
                    ? Container(
                        width: 70,
                        height: 70,
                        color: colorScheme.primary,
                        child: Icon(
                          Icons.restaurant,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Image.network(
                        imageUrl,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 70,
                          height: 70,
                          color: colorScheme.primary,
                          child: Icon(
                            Icons.restaurant,
                            color: colorScheme.onPrimary,
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
                      experience.placeTitle ?? 'Unnamed restaurant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          experience.personalRating.toStringAsFixed(1),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (experience.region?.isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          Text(
                            experience.region!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (experience.placeAddress?.isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        experience.placeAddress!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (experience.personalTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: experience.personalTags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              '#$tag',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onLocate,
                icon: const Icon(Icons.near_me),
                tooltip: 'Show on map',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMapSheet extends StatelessWidget {
  final ScrollController scrollController;

  const _EmptyMapSheet({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
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
        const SizedBox(height: 40),
        Icon(Icons.map_outlined, size: 58, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'No saved restaurants on the map yet',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Save a meal with a selected place or current location to show it here.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
