import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';
import 'package:meow_food_butler/repositories/restaurant_repository.dart';
import 'package:meow_food_butler/services/business_hours_service.dart';
import 'package:meow_food_butler/services/restaurant_lookup_service.dart';
import 'package:meow_food_butler/views/saved/food_card_detail.dart';
import 'package:meow_food_butler/views/saved/widgets/experience_photo.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';

enum MapSheetMode { imported, myPlaces }

enum MyPlacesSortMode { distance, recent, openNow }

class RestaurantListSheet extends StatefulWidget {
  static const double minSize = 0.11;
  static const double middleSize = 0.36;
  static const double initialSize = minSize;
  static const double maxSize = 0.92;
  static const List<double> snapSizes = [minSize, middleSize, maxSize];

  final DraggableScrollableController controller;
  final List<ExperienceCard> experiences;
  final MapSheetMode mode;
  final MyPlacesSortMode myPlacesSortMode;
  final int importedCount;
  final int myPlacesCount;
  final String? selectedExperienceId;
  final String Function(ExperienceCard experience) markerIdFor;
  final String? Function(ExperienceCard experience) distanceLabelFor;
  final BusinessHoursStatus? Function(ExperienceCard experience) hoursStatusFor;
  final ValueChanged<MapSheetMode> onModeChanged;
  final ValueChanged<MyPlacesSortMode> onSortModeChanged;
  final ValueChanged<ExperienceCard> onExperienceSelected;
  final ValueChanged<ExperienceCard> onExperienceDetailRequested;
  final ValueChanged<String> onVisitsTapped;
  final ValueChanged<ExperienceCard> onImportedDelete;

  const RestaurantListSheet({
    super.key,
    required this.controller,
    required this.experiences,
    required this.mode,
    required this.myPlacesSortMode,
    required this.importedCount,
    required this.myPlacesCount,
    required this.selectedExperienceId,
    required this.markerIdFor,
    required this.distanceLabelFor,
    required this.hoursStatusFor,
    required this.onModeChanged,
    required this.onSortModeChanged,
    required this.onExperienceSelected,
    required this.onExperienceDetailRequested,
    required this.onVisitsTapped,
    required this.onImportedDelete,
  });

  @override
  State<RestaurantListSheet> createState() => _RestaurantListSheetState();
}

class _RestaurantListSheetState extends State<RestaurantListSheet> {
  static const double _estimatedCardExtent = 126;

  ScrollController? _scrollController;
  String? _lastAutoScrolledId;

  @override
  void didUpdateWidget(covariant RestaurantListSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedExperienceId != oldWidget.selectedExperienceId) {
      _scheduleScrollToSelected();
    }
  }

  void _scheduleScrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSelectedExperience();
    });
  }

  Future<void> _scrollToSelectedExperience() async {
    final selectedId = widget.selectedExperienceId;
    if (selectedId == null || selectedId == _lastAutoScrolledId) return;

    final selectedIndex = widget.experiences.indexWhere(
      (experience) => widget.markerIdFor(experience) == selectedId,
    );
    if (selectedIndex < 0) return;

    _lastAutoScrolledId = selectedId;

    if (widget.controller.isAttached &&
        widget.controller.size < RestaurantListSheet.middleSize) {
      await widget.controller.animateTo(
        RestaurantListSheet.middleSize,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) return;

    final maxScroll = scrollController.position.maxScrollExtent;
    final target = (selectedIndex * _estimatedCardExtent).clamp(0.0, maxScroll);

    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showRestaurantDetail(
    BuildContext context,
    ExperienceCard experience,
  ) async {
    final relatedFoodCard = await _foodCardForExperience(experience);

    if (!mounted || !context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          builder: (_, controller) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
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

  Future<FoodCard> _foodCardForExperience(ExperienceCard experience) async {
    try {
      final repository = RestaurantRepository();
      final restaurant =
          await repository.findForExperience(experience);
      if (restaurant != null) {
        // Found in Firestore — use the stored card directly, no Outscraper call.
        return _mergeRestaurantWithExperience(restaurant, experience);
      }

      // Not in Firestore — fall back to Outscraper ONCE: persist the restaurant
      // and link it back to the experience so the next open is a Firestore read,
      // never another Outscraper call.
      final fetchedRestaurant = await _fetchRestaurantForExperience(experience);
      if (fetchedRestaurant != null) {
        final savedId = await repository.saveRestaurant(fetchedRestaurant);
        await _linkExperienceToRestaurant(experience, savedId);
        return _mergeRestaurantWithExperience(fetchedRestaurant, experience);
      }
    } catch (_) {
      // Fall back to the experience-only card when Firestore lookup fails.
    }
    return _foodCardFromExperience(experience);
  }

  /// Persist the experience→restaurant link, but only for a real saved
  /// experience doc that isn't linked yet. Transient import candidates (no id)
  /// and synthetic restaurant-derived cards ('restaurant-…', already carrying a
  /// foodCardId) are skipped — they resolve via the restaurants stream instead.
  Future<void> _linkExperienceToRestaurant(
    ExperienceCard experience,
    String foodCardId,
  ) async {
    final id = experience.id;
    if (id == null || id.isEmpty || id.startsWith('restaurant-')) return;
    if (experience.foodCardId != null && experience.foodCardId!.isNotEmpty) return;
    if (foodCardId.isEmpty) return;
    try {
      await ExperienceRepository().linkFoodCard(id, foodCardId);
    } catch (_) {
      // Non-fatal: the card still renders; we may just refetch next time.
    }
  }

  Future<FoodCard?> _fetchRestaurantForExperience(
    ExperienceCard experience,
  ) async {
    final placeId = _usablePlaceId(experience.placeId);
    final mapsUrl = experience.googleMapsUrl?.trim();

    // Only call Outscraper when we have a precise identifier.
    // A text-only query (name + address) is too unreliable: it can match
    // unrelated restaurants, especially when tags are sent as context.
    if (placeId != null && placeId.isNotEmpty) {
      return RestaurantLookupService().fetch(
        placeId: placeId,
        query: experience.placeTitle?.trim(),
        originalURL: experience.originalURL,
        tags: experience.personalTags,
        visited: experience.isDone,
      );
    }

    if (mapsUrl != null && mapsUrl.isNotEmpty) {
      return RestaurantLookupService().fetch(
        placeId: mapsUrl,
        query: experience.placeTitle?.trim(),
        originalURL: experience.originalURL,
        tags: experience.personalTags,
        visited: experience.isDone,
      );
    }

    return null;
  }

  String? _usablePlaceId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('__') && trimmed.endsWith('__')) return null;
    return trimmed;
  }

  FoodCard _foodCardFromExperience(ExperienceCard experience) {
    return FoodCard(
      id: experience.foodCardId ?? experience.placeId,
      originalURL: experience.originalURL,
      googleMapsUrl: experience.googleMapsUrl,
      formattedAddress: experience.placeAddress,
      rating: experience.personalRating > 0 ? experience.personalRating : null,
      tags: experience.personalTags,
      photoPaths: experience.photoPaths,
      photoUrls: experience.photoUrls,
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
  }

  FoodCard _mergeRestaurantWithExperience(
    FoodCard restaurant,
    ExperienceCard experience,
  ) {
    final fallback = _foodCardFromExperience(experience);

    return FoodCard(
      id: restaurant.id ?? fallback.id,
      originalURL: restaurant.originalURL ?? fallback.originalURL,
      googleMapsUrl: restaurant.googleMapsUrl ?? fallback.googleMapsUrl,
      formattedAddress: restaurant.formattedAddress ?? fallback.formattedAddress,
      rating: restaurant.rating ?? fallback.rating,
      reviews: restaurant.reviews,
      phone: restaurant.phone,
      website: restaurant.website,
      priceRange: restaurant.priceRange,
      category: restaurant.category,
      subtypes: restaurant.subtypes,
      description: restaurant.description,
      workingHours: restaurant.workingHours,
      popularTimes: restaurant.popularTimes,
      reviewSnippets: restaurant.reviewSnippets,
      typicalTimeSpent: restaurant.typicalTimeSpent,
      menuLink: restaurant.menuLink,
      bookingLink: restaurant.bookingLink,
      verified: restaurant.verified,
      visited: restaurant.visited,
      tags: restaurant.tags.isNotEmpty ? restaurant.tags : fallback.tags,
      photoPaths: fallback.photoPaths.isNotEmpty
          ? fallback.photoPaths
          : restaurant.photoPaths,
      photoUrls:
          restaurant.photoUrls.isNotEmpty ? restaurant.photoUrls : fallback.photoUrls,
      displayNames:
          restaurant.displayNames.isNotEmpty ? restaurant.displayNames : fallback.displayNames,
      location: restaurant.location ?? fallback.location,
      createdTime: restaurant.createdTime,
      updatedTime: restaurant.updatedTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: PointerInterceptor(
        child: DraggableScrollableSheet(
          controller: widget.controller,
          expand: false,
          snap: true,
          snapSizes: RestaurantListSheet.snapSizes,
          initialChildSize: RestaurantListSheet.initialSize,
          minChildSize: RestaurantListSheet.minSize,
          maxChildSize: RestaurantListSheet.maxSize,
          builder: (context, scrollController) {
            _scrollController = scrollController;
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
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SheetHeaderDelegate(
                        count: widget.experiences.length,
                        mode: widget.mode,
                        myPlacesSortMode: widget.myPlacesSortMode,
                        importedCount: widget.importedCount,
                        myPlacesCount: widget.myPlacesCount,
                        onModeChanged: widget.onModeChanged,
                        onSortModeChanged: widget.onSortModeChanged,
                        controller: widget.controller,
                        backgroundColor: colorScheme.surface,
                      ),
                    ),
                    if (widget.experiences.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyMapSheetContent(mode: widget.mode),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        sliver: SliverList.separated(
                          itemCount: widget.experiences.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final experience = widget.experiences[index];
                            final selected = widget.markerIdFor(experience) ==
                                widget.selectedExperienceId;

                            return _MapRestaurantCard(
                              key: ValueKey(widget.markerIdFor(experience)),
                              experience: experience,
                              selected: selected,
                              mode: widget.mode,
                              distanceLabel: widget.distanceLabelFor(experience),
                              hoursStatus: widget.hoursStatusFor(experience),
                              onTap: () {
                                widget.onExperienceDetailRequested(experience);
                                _showRestaurantDetail(context, experience);
                              },
                              onLocate: () =>
                                  widget.onExperienceSelected(experience),
                              onVisitsTapped: () => widget.onVisitsTapped(
                                experience.placeTitle ?? '',
                              ),
                              onDeleteImported: () =>
                                  widget.onImportedDelete(experience),
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

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int count;
  final MapSheetMode mode;
  final MyPlacesSortMode myPlacesSortMode;
  final int importedCount;
  final int myPlacesCount;
  final ValueChanged<MapSheetMode> onModeChanged;
  final ValueChanged<MyPlacesSortMode> onSortModeChanged;
  final DraggableScrollableController controller;
  final Color backgroundColor;

  const _SheetHeaderDelegate({
    required this.count,
    required this.mode,
    required this.myPlacesSortMode,
    required this.importedCount,
    required this.myPlacesCount,
    required this.onModeChanged,
    required this.onSortModeChanged,
    required this.controller,
    required this.backgroundColor,
  });

  static const double _height = 144;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: _SheetHeader(
        count: count,
        mode: mode,
        myPlacesSortMode: myPlacesSortMode,
        importedCount: importedCount,
        myPlacesCount: myPlacesCount,
        onModeChanged: onModeChanged,
        onSortModeChanged: onSortModeChanged,
        controller: controller,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SheetHeaderDelegate oldDelegate) {
    return count != oldDelegate.count ||
        mode != oldDelegate.mode ||
        myPlacesSortMode != oldDelegate.myPlacesSortMode ||
        importedCount != oldDelegate.importedCount ||
        myPlacesCount != oldDelegate.myPlacesCount ||
        onModeChanged != oldDelegate.onModeChanged ||
        onSortModeChanged != oldDelegate.onSortModeChanged ||
        controller != oldDelegate.controller ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

class _SheetHeader extends StatelessWidget {
  final int count;
  final MapSheetMode mode;
  final MyPlacesSortMode myPlacesSortMode;
  final int importedCount;
  final int myPlacesCount;
  final ValueChanged<MapSheetMode> onModeChanged;
  final ValueChanged<MyPlacesSortMode> onSortModeChanged;
  final DraggableScrollableController controller;

  const _SheetHeader({
    required this.count,
    required this.mode,
    required this.myPlacesSortMode,
    required this.importedCount,
    required this.myPlacesCount,
    required this.onModeChanged,
    required this.onSortModeChanged,
    required this.controller,
  });

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

  void _expandSheet() {
    if (!controller.isAttached) return;
    final atMax =
        (controller.size - RestaurantListSheet.maxSize).abs() < 0.02;
    controller.animateTo(
      atMax ? RestaurantListSheet.minSize : RestaurantListSheet.maxSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = mode == MapSheetMode.imported
        ? '$count imported place${count == 1 ? '' : 's'}'
        : '$count place${count == 1 ? '' : 's'} on your food map';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => _dragSheet(context, details),
      onVerticalDragEnd: (_) => _snapSheet(),
      onDoubleTap: _expandSheet,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  mode == MapSheetMode.imported
                      ? Icons.auto_awesome
                      : Icons.place,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            _MapSheetSegmentedControl(
              mode: mode,
              importedCount: importedCount,
              myPlacesCount: myPlacesCount,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: 5),
            _MyPlacesSortControl(
              mode: myPlacesSortMode,
              onChanged: onSortModeChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapSheetSegmentedControl extends StatelessWidget {
  final MapSheetMode mode;
  final int importedCount;
  final int myPlacesCount;
  final ValueChanged<MapSheetMode> onChanged;

  const _MapSheetSegmentedControl({
    required this.mode,
    required this.importedCount,
    required this.myPlacesCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Imported',
            count: importedCount,
            selected: mode == MapSheetMode.imported,
            onTap: () => onChanged(MapSheetMode.imported),
          ),
          _SegmentButton(
            label: 'My Places',
            count: myPlacesCount,
            selected: mode == MapSheetMode.myPlaces,
            onTap: () => onChanged(MapSheetMode.myPlaces),
          ),
        ],
      ),
    );
  }
}

class _MyPlacesSortControl extends StatelessWidget {
  final MyPlacesSortMode mode;
  final ValueChanged<MyPlacesSortMode> onChanged;

  const _MyPlacesSortControl({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          _SortButton(
            icon: Icons.near_me,
            label: 'Distance',
            selected: mode == MyPlacesSortMode.distance,
            onTap: () => onChanged(MyPlacesSortMode.distance),
          ),
          const SizedBox(width: 8),
          _SortButton(
            icon: Icons.schedule,
            label: 'Recent',
            selected: mode == MyPlacesSortMode.recent,
            onTap: () => onChanged(MyPlacesSortMode.recent),
          ),
          const SizedBox(width: 8),
          _SortButton(
            icon: Icons.storefront,
            label: 'Open',
            selected: mode == MyPlacesSortMode.openNow,
            onTap: () => onChanged(MyPlacesSortMode.openNow),
          ),
          const Spacer(),
          Text(
            'Sort',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: selected ? null : onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : colorScheme.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label  $count',
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapRestaurantCard extends StatelessWidget {
  final ExperienceCard experience;
  final bool selected;
  final MapSheetMode mode;
  final String? distanceLabel;
  final BusinessHoursStatus? hoursStatus;
  final VoidCallback onTap;
  final VoidCallback onLocate;
  final VoidCallback onVisitsTapped;
  final VoidCallback onDeleteImported;

  const _MapRestaurantCard({
    super.key,
    required this.experience,
    required this.selected,
    required this.mode,
    required this.distanceLabel,
    required this.hoursStatus,
    required this.onTap,
    required this.onLocate,
    required this.onVisitsTapped,
    required this.onDeleteImported,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl =
        experience.photoUrls.isEmpty ? null : experience.photoUrls.first;
    final isOpen = hoursStatus?.isOpen;
    final todayHours = hoursStatus?.todayLabel;
    final statusLabel =
        isOpen == null ? '時間未知' : (isOpen ? '營業中' : '休息中');
    final statusColor = isOpen == null
        ? colorScheme.onSurfaceVariant
        : (isOpen ? Colors.green.shade700 : Colors.red.shade700);
    final statusBackground = isOpen == null
        ? colorScheme.surfaceContainerHighest
        : (isOpen
            ? Colors.green.withOpacity(0.15)
            : Colors.red.withOpacity(0.15));

    final savedVM = context.watch<SavedViewModel>();
    final allExperiences = savedVM.experiences;
    final targetKey =
        experience.foodCardId ?? experience.placeId ?? experience.placeTitle;
    final visitCount = allExperiences
        .where((e) => (e.foodCardId ?? e.placeId ?? e.placeTitle) == targetKey)
        .length;
    final isNewlyImported = experience.foodCardId != null &&
        savedVM.recentlyImportedIds.contains(experience.foodCardId);

    return AnimatedScale(
      scale: selected ? 1.006 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: selected ? const Offset(0, -0.01) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : isNewlyImported
                          ? const Color(0xFFCC8844)
                          : colorScheme.outlineVariant,
                  width: selected
                      ? 2
                      : isNewlyImported
                          ? 2.5
                          : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : isNewlyImported
                        ? [
                            BoxShadow(
                              color: const Color(0x44CC8844),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _MapCardThumbnail(
                            key: ValueKey(_thumbnailKeyFor(experience, imageUrl)),
                            experience: experience,
                            mode: mode,
                            imageUrl: imageUrl,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (todayHours != null) ...[
                        SizedBox(
                          width: 66,
                          child: Text(
                            todayHours,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 9,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusBackground,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              experience.placeTitle ?? 'Unnamed restaurant',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  (mode == MapSheetMode.imported &&
                                          experience.personalRating <= 0)
                                      ? Icons.link
                                      : Icons.star,
                                  size: 16,
                                  color: (mode == MapSheetMode.imported &&
                                          experience.personalRating <= 0)
                                      ? colorScheme.primary
                                      : Colors.amber.shade700,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  (mode == MapSheetMode.imported &&
                                          experience.personalRating <= 0)
                                      ? 'From import'
                                      : experience.personalRating
                                            .toStringAsFixed(1),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: (mode == MapSheetMode.imported &&
                                            experience.personalRating <= 0)
                                        ? colorScheme.primary
                                        : Colors.amber.shade800,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (distanceLabel != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.near_me,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    distanceLabel!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
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
                            if (experience.placeAddress?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 3),
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
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children:
                                    experience.personalTags.take(2).map((tag) {
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
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
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
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: onLocate,
                          icon: Icon(
                            Icons.near_me,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Show on map',
                        ),
                        if (mode == MapSheetMode.imported) ...[
                          const SizedBox(height: 4),
                          IconButton(
                            onPressed: onDeleteImported,
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: colorScheme.error,
                            ),
                            tooltip: 'Remove imported place',
                          ),
                        ],
                        if (visitCount > 0) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: onVisitsTapped,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 12,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$visitCount',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _thumbnailKeyFor(ExperienceCard experience, String? imageUrl) {
    final photoKey = imageUrl ??
        (experience.photoPaths.isEmpty
            ? 'no-photo'
            : experience.photoPaths.first);
    return '${experience.id}-${experience.foodCardId}-$photoKey';
  }
}

class _MapCardThumbnail extends StatelessWidget {
  final ExperienceCard experience;
  final MapSheetMode mode;
  final String? imageUrl;

  const _MapCardThumbnail({
    super.key,
    required this.experience,
    required this.mode,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget fallback() {
      return Container(
        width: 58,
        height: 58,
        color: colorScheme.primary,
        child: Icon(
          Icons.restaurant,
          color: colorScheme.onPrimary,
        ),
      );
    }

    Widget storagePhoto() {
      if (experience.photoPaths.isEmpty) return fallback();
      return ExperiencePhoto(
        experience: experience,
        photoPath: experience.photoPaths.first,
        width: 58,
        height: 58,
        borderRadius: 12,
      );
    }

    if (imageUrl != null) {
      return Image.network(
        key: ValueKey(imageUrl),
        imageUrl!,
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) => storagePhoto(),
      );
    }

    return storagePhoto();
  }
}

class _EmptyMapSheetContent extends StatelessWidget {
  final MapSheetMode mode;

  const _EmptyMapSheetContent({required this.mode});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isImported = mode == MapSheetMode.imported;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isImported ? Icons.auto_awesome_outlined : Icons.map_outlined,
            size: 58,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            isImported
                ? 'No imported places yet'
                : 'No places on your food map yet',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isImported
                ? 'Paste an Instagram or food URL to turn mentioned restaurants into map cards.'
                : 'Log a meal with a place or save a restaurant to show it here.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
