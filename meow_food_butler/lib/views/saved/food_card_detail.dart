import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/food_card.dart';
import '../../models/experience_card.dart';
import '../../view_models/saved_view_model.dart';

import 'experience_entry_sheet.dart'; 
import 'experience_detail_screen.dart';

class FoodCardDetail extends StatefulWidget {
  final FoodCard foodCard;
  final List<ExperienceCard> experiences;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback onToggleSave;
  final VoidCallback onAddExperience;
  final bool showOnlineInfoTab;

  const FoodCardDetail({
    super.key,
    required this.foodCard,
    required this.experiences,
    required this.isSaved,
    required this.onClose,
    required this.onToggleSave,
    required this.onAddExperience,
    this.showOnlineInfoTab = true, 
  });

  @override
  State<FoodCardDetail> createState() => _FoodCardDetailState();
}

class _FoodCardDetailState extends State<FoodCardDetail> {
  int _currentTabIndex = 0; 
  final TextEditingController _tagController = TextEditingController();
  
  final List<String> _mockPros = ['Clean', 'Fast service', 'Fresh food', 'Large portions'];
  final List<String> _mockCons = ['Hard to park', 'Long queue'];
  final List<String> _suggestedTags = ['Go-to spot', 'Weekend vibe', 'Cheap eats', 'Group friendly', 'Great value'];

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _openExperienceEntrySheet({ExperienceCard? experienceToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,        
      backgroundColor: Colors.transparent, 
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ExperienceEntrySheet(
            initialExperience: experienceToEdit ?? ExperienceCard(
              foodCardId: widget.foodCard.id,
              placeTitle: widget.foodCard.primaryTitle,
              placeAddress: widget.foodCard.formattedAddress,
              latitude: widget.foodCard.location?.latitude,
              longitude: widget.foodCard.location?.longitude,
              personalTags: const [],
              personalRating: 0.0,
            ),
            onSave: (savedExperience, photos) async {
              if (experienceToEdit == null) {
                await context.read<SavedViewModel>().addExperience(savedExperience, photos: photos);
              } else {
                await context.read<SavedViewModel>().updateExperience(savedExperience, newPhotos: photos);
              }
              
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
                widget.onAddExperience(); 
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final allExperiences = context.watch<SavedViewModel>().experiences;
    
    var currentExperiences = allExperiences.where((e) {
      final key1 = e.foodCardId ?? e.placeId ?? e.placeTitle;
      final key2 = widget.foodCard.id ?? widget.foodCard.primaryTitle;
      return key1 == key2;
    }).toList();

    if (currentExperiences.isEmpty) {
      currentExperiences = List.from(widget.experiences);
    }

    currentExperiences.sort((a, b) {
      if (a.createdTime == null && b.createdTime == null) return 0;
      if (a.createdTime == null) return 1;
      if (b.createdTime == null) return -1;
      return b.createdTime!.compareTo(a.createdTime!); 
    });

    if (!widget.showOnlineInfoTab && currentExperiences.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeroImage(colorScheme),
              _buildHeader(colorScheme),
              
              if (widget.showOnlineInfoTab) _buildTabs(colorScheme),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
                  child: widget.showOnlineInfoTab 
                    ? AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _currentTabIndex == 0 
                            ? _buildOnlineTab(colorScheme) 
                            : _buildYoursTab(colorScheme, currentExperiences),
                      )
                    : _buildYoursTab(colorScheme, currentExperiences),
                ),
              ),
            ],
          ),
          _buildBottomActionBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeroImage(ColorScheme colorScheme) {
    return Stack(
      children: [
        Container(
          height: 220,
          width: double.infinity,
          color: colorScheme.surfaceContainerHighest,
          child: widget.foodCard.originalURL != null
              ? Image.network(widget.foodCard.originalURL!, fit: BoxFit.cover)
              : Center(child: Icon(Icons.restaurant, size: 48, color: colorScheme.outlineVariant)),
        ),
        Container(
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.4), Colors.transparent],
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: colorScheme.onSurface, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.foodCard.primaryTitle,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text("Nearby • ", style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    Icon(Icons.phone, size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text("No phone available", style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Icon(Icons.assignment_outlined, color: colorScheme.onSurfaceVariant, size: 18),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
            child: Icon(Icons.navigation, color: colorScheme.onPrimary, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Expanded(child: _buildTabButton("Online Info", 0, colorScheme)),
            Expanded(child: _buildTabButton("My Rating", 1, colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, int index, ColorScheme colorScheme) {
    final isActive = _currentTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive ? [BoxShadow(color: colorScheme.shadow.withOpacity(0.1), blurRadius: 2)] : [],
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineTab(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('online'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
              child: Text("Restaurant", style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurface)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.star, color: colorScheme.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    widget.foodCard.rating?.toStringAsFixed(1) ?? "4.5",
                    style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ..._mockPros.map((tag) => _buildStatusTag(tag, true, colorScheme)),
            ..._mockCons.map((tag) => _buildStatusTag(tag, false, colorScheme)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.foodCard.formattedAddress ?? "This is a highly popular restaurant offering a variety of specialty dishes. Highly recommended.",
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusTag(String text, bool isPro, ColorScheme colorScheme) {
    final bgColor = isPro ? colorScheme.tertiaryContainer : colorScheme.errorContainer;
    final textColor = isPro ? colorScheme.onTertiaryContainer : colorScheme.onErrorContainer;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  Widget _buildYoursTab(ColorScheme colorScheme, List<ExperienceCard> currentExperiences) {
    final textTheme = Theme.of(context).textTheme;
    final visitCount = currentExperiences.length;
    final avgRating = visitCount > 0 
        ? currentExperiences.fold(0.0, (sum, exp) => sum + exp.personalRating) / visitCount 
        : 0.0;

    return Column(
      key: const ValueKey('yours'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("YOUR AVERAGE", style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
              visitCount > 0 ? Row(
                children: [
                  Text(avgRating.toStringAsFixed(1), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                  const SizedBox(width: 8),
                  Text("$visitCount visits", style: textTheme.labelMedium?.copyWith(color: colorScheme.onPrimaryContainer)),
                ],
              ) : Text("No ratings yet", style: textTheme.labelMedium?.copyWith(fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("YOUR MEALS", style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.outline)),
            GestureDetector(
              onTap: () => _openExperienceEntrySheet(), 
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                child: Icon(Icons.add, color: colorScheme.onPrimary, size: 18),
              ),
            )
          ],
        ),
        const SizedBox(height: 12),
        if (visitCount == 0)
          GestureDetector(
            onTap: () => _openExperienceEntrySheet(), 
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline, size: 28, color: colorScheme.primary),
                  const SizedBox(height: 8),
                  Text("Log your first meal", style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  Text("Record the dishes you tried and your thoughts!", style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else
          ...currentExperiences.map((exp) => _buildExperienceItem(exp, colorScheme)),
        
        const SizedBox(height: 24),
        Text("YOUR TAGS", style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.outline)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              Text("#", style: TextStyle(color: colorScheme.outline, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tagController,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    border: InputBorder.none, 
                    hintText: "Add your own tag", 
                    hintStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.outline)
                  ),
                  onSubmitted: (val) => _handleAddNewTag(),
                ),
              ),
              GestureDetector(
                onTap: _handleAddNewTag,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_upward, color: colorScheme.onPrimary, size: 12),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _suggestedTags.map((tag) => GestureDetector(
            onTap: () {
              setState(() {
                if (!_suggestedTags.contains(tag)) _suggestedTags.add(tag);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text("+ #$tag", style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildExperienceItem(ExperienceCard exp, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (exp.id == null) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ExperienceDetailScreen(experienceId: exp.id!),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: List.generate(5, (i) => Icon(
                        Icons.star, 
                        size: 14, 
                        color: i < exp.personalRating ? colorScheme.primary : colorScheme.surfaceContainerHigh
                      )),
                    ),
                    Row(
                      children: [
                        Text(
                          _formatRelative(exp.createdTime?.toDate() ?? DateTime.now()),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert, size: 16, color: colorScheme.onSurfaceVariant),
                            onSelected: (value) async {
                              if (value == 'edit') {
                                _openExperienceEntrySheet(experienceToEdit: exp);
                              } else if (value == 'delete') {
                                if (exp.id != null) {
                                  await context.read<SavedViewModel>().removeExperience(exp.id!);
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
                if (exp.personalNote != null && exp.personalNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(exp.personalNote!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleAddNewTag() {
    if (_tagController.text.trim().isNotEmpty) {
      setState(() {
        _suggestedTags.insert(0, _tagController.text.trim());
        _tagController.clear();
      });
    }
  }

  String _formatRelative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return "Just now";
    if (diff.inHours == 1) return "1 hr ago";
    if (diff.inHours < 24) return "${diff.inHours} hrs ago";
    if (diff.inDays == 1) return "1 day ago";
    return "${diff.inDays} days ago";
  }

  Widget _buildBottomActionBar(ColorScheme colorScheme) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: GestureDetector(
          onTap: () => widget.showOnlineInfoTab ? widget.onToggleSave() : _openExperienceEntrySheet(),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: (widget.showOnlineInfoTab && widget.isSaved) ? colorScheme.primaryContainer : colorScheme.primary,
              borderRadius: BorderRadius.circular(24),
              border: (widget.showOnlineInfoTab && widget.isSaved) ? Border.all(color: colorScheme.outlineVariant) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.showOnlineInfoTab 
                      ? (widget.isSaved ? Icons.bookmark : Icons.bookmark_border)
                      : Icons.add,
                  color: (widget.showOnlineInfoTab && widget.isSaved) ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.showOnlineInfoTab 
                      ? (widget.isSaved ? "Saved to your map" : "Save this spot")
                      : "Log another meal here",
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: (widget.showOnlineInfoTab && widget.isSaved) ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}