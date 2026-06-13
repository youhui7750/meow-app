import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/experience_card.dart';
import '../../models/food_card.dart';
import '../../view_models/saved_view_model.dart';
import '../explore/widgets/restaurant_card.dart';
import 'experience_entry_sheet.dart';
import 'food_card_detail.dart';

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
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ExperienceEntrySheet(
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
      ),
    );
  }

  void _showRestaurantDetail(
    BuildContext context, 
    ExperienceCard latestExp, 
    List<ExperienceCard> allExperiences,
  ) {
    final relatedFoodCard = FoodCard(
      id: latestExp.foodCardId,
      originalURL: latestExp.photoUrls.isNotEmpty 
          ? latestExp.photoUrls.first 
          : latestExp.originalURL,
      formattedAddress: latestExp.placeAddress,
      rating: latestExp.personalRating,
      displayNames: [
        DisplayName(
          title: latestExp.placeTitle ?? 'Unnamed restaurant',
          languageCode: 'en',
        )
      ],
      location: latestExp.latitude != null && latestExp.longitude != null
          ? LocationCoordinate(
              latitude: latestExp.latitude!, 
              longitude: latestExp.longitude!
            )
          : null,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95, 
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: FoodCardDetail(
                foodCard: relatedFoodCard,
                experiences: allExperiences,
                isSaved: true,
                showOnlineInfoTab: false, 
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Spots', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExperienceSheet(context),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        icon: const Icon(Icons.add),
        label: const Text('Log meal', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Consumer<SavedViewModel>(
        builder: (context, viewModel, child) {
          final groupedData = viewModel.groupedExperiences;

          if (groupedData.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 64,
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No meals logged yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
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
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            itemCount: groupedData.length,
            separatorBuilder: (context, index) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              final restaurantExperiences = groupedData[index];
              final latestExp = restaurantExperiences.first;

              return Stack(
                children: [
                  GestureDetector(
                    onTap: () => _showRestaurantDetail(context, latestExp, restaurantExperiences),
                    child: RestaurantCard(
                      experience: latestExp,
                      onNavTap: () {
                        debugPrint('Navigate to: ${latestExp.placeTitle}');
                      },
                    ),
                  ),
                  
                  if (restaurantExperiences.length > 1)
                    Positioned(
                      top: 16,
                      right: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ]
                        ),
                        child: Text(
                          '${restaurantExperiences.length} visits',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}