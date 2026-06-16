import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/saved/experience_detail_screen.dart';
import 'package:meow_food_butler/views/saved/experience_entry_sheet.dart';
import 'package:meow_food_butler/views/saved/widgets/experience_card_tile.dart';
import 'package:provider/provider.dart';

class SavedScreen extends StatefulWidget {
  final String? initialSearchQuery;
  final ValueListenable<int>? resetListenable;

  const SavedScreen({super.key, this.initialSearchQuery, this.resetListenable});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedRegion;
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!;
      _query = widget.initialSearchQuery!.toLowerCase();
    }
    
    _searchController.addListener(_handleSearchChanged);
    widget.resetListenable?.addListener(_resetFilters);
  }

  @override
  void didUpdateWidget(covariant SavedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetListenable != widget.resetListenable) {
      oldWidget.resetListenable?.removeListener(_resetFilters);
      widget.resetListenable?.addListener(_resetFilters);
    }
    if (widget.initialSearchQuery != oldWidget.initialSearchQuery &&
        widget.initialSearchQuery != null) {
      _searchController.text = widget.initialSearchQuery!;
      _query = widget.initialSearchQuery!.toLowerCase();
    }
  }

  @override
  void dispose() {
    widget.resetListenable?.removeListener(_resetFilters);
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (!mounted) return;
    setState(() => _query = _searchController.text.trim().toLowerCase());
  }

  void _resetFilters() {
    if (!mounted) return;
    _searchController.removeListener(_handleSearchChanged);
    _searchController.clear();
    _searchController.addListener(_handleSearchChanged);
    setState(() {
      _selectedRegion = null;
      _selectedTags.clear();
      _query = '';
    });
  }

  void _openExperienceSheet(
    BuildContext context, {
    ExperienceCard? experience,
  }) {
    final viewModel = context.read<SavedViewModel>();
    final placeSuggestions = viewModel.experiences;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ExperienceEntrySheet(
        initialExperience: experience,
        savedPlaceSuggestions: placeSuggestions,
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

  List<ExperienceCard> _filteredExperiences(List<ExperienceCard> experiences) {
    final filtered = experiences.where((experience) {
      final region = _regionForExperience(experience);
      if (_selectedRegion != null && region != _selectedRegion) {
        return false;
      }

      if (_selectedTags.isNotEmpty &&
          !_selectedTags.every(experience.personalTags.contains)) {
        return false;
      }

      if (_query.isEmpty) return true;

      final searchableText = [
        experience.placeTitle,
        experience.placeAddress,
        experience.region,
        region,
        experience.personalNote,
        experience.placeId,
        ...experience.personalTags,
      ].whereType<String>().join(' ').toLowerCase();

      return searchableText.contains(_query);
    }).toList();

    filtered.sort((a, b) => b.createdTime.compareTo(a.createdTime));

    return filtered;
  }

  List<String> _allTags(List<ExperienceCard> experiences) {
    final tags = <String>{};
    for (final experience in experiences) {
      tags.addAll(experience.personalTags);
    }
    final sortedTags = tags.toList()..sort();
    return sortedTags;
  }

  List<String> _allRegions(List<ExperienceCard> experiences) {
    final regions = <String>{};
    for (final experience in experiences) {
      final region = _regionForExperience(experience);
      if (region != null) regions.add(region);
    }
    final sortedRegions = regions.toList()..sort();
    return sortedRegions;
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
          final filteredExperiences = _filteredExperiences(experiences);
          final tags = _allTags(experiences);
          final regions = _allRegions(experiences);

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
            itemCount: filteredExperiences.isEmpty
                ? 2
                : filteredExperiences.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _ExperienceFilters(
                  controller: _searchController,
                  regions: regions,
                  selectedRegion: _selectedRegion,
                  tags: tags,
                  selectedTags: _selectedTags,
                  onRegionSelected: (region) {
                    setState(() => _selectedRegion = region);
                  },
                  onTagToggled: _toggleTag,
                  onClear: () {
                    setState(() {
                      _selectedRegion = null;
                      _selectedTags.clear();
                      _searchController.clear();
                    });
                  },
                );
              }

              if (filteredExperiences.isEmpty) {
                return _EmptyFilterResult(
                  onClear: () {
                    setState(() {
                      _selectedRegion = null;
                      _selectedTags.clear();
                      _searchController.clear();
                    });
                  },
                );
              }

              final experience = filteredExperiences[index - 1];
              return ExperienceCardTile(
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

  void _toggleTag(String tag, bool selected) {
    setState(() {
      if (selected) {
        _selectedTags.add(tag);
      } else {
        _selectedTags.remove(tag);
      }
    });
  }
}

class _ExperienceFilters extends StatefulWidget {
  final TextEditingController controller;
  final List<String> regions;
  final String? selectedRegion;
  final List<String> tags;
  final Set<String> selectedTags;
  final ValueChanged<String?> onRegionSelected;
  final void Function(String tag, bool selected) onTagToggled;
  final VoidCallback onClear;

  const _ExperienceFilters({
    required this.controller,
    required this.regions,
    required this.selectedRegion,
    required this.tags,
    required this.selectedTags,
    required this.onRegionSelected,
    required this.onTagToggled,
    required this.onClear,
  });

  @override
  State<_ExperienceFilters> createState() => _ExperienceFiltersState();
}

class _ExperienceFiltersState extends State<_ExperienceFilters> {
  static const int _collapsedTagCount = 4;
  bool _showAllTags = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilters =
        widget.controller.text.trim().isNotEmpty ||
        widget.selectedRegion != null ||
        widget.selectedTags.isNotEmpty;
    final visibleTags = _showAllTags
        ? widget.tags
        : widget.tags.take(_collapsedTagCount).toList();
    final canExpandTags = widget.tags.length > _collapsedTagCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search meals, places, notes, or tags',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: hasFilters
                ? IconButton(
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear filters',
                  )
                : null,
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
        if (widget.regions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.regions
                .map(
                  (region) => FilterChip(
                    avatar: const Icon(Icons.place_outlined, size: 18),
                    label: Text(region),
                    selected: widget.selectedRegion == region,
                    onSelected: (selected) =>
                        widget.onRegionSelected(selected ? region : null),
                  ),
                )
                .toList(),
          ),
        ],
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...visibleTags.map(
                (tag) => FilterChip(
                  label: Text('#$tag'),
                  selected: widget.selectedTags.contains(tag),
                  onSelected: (selected) => widget.onTagToggled(tag, selected),
                ),
              ),
              if (canExpandTags)
                ActionChip(
                  avatar: Icon(
                    _showAllTags
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                  label: Text(_showAllTags ? 'Less' : 'More'),
                  onPressed: () => setState(() => _showAllTags = !_showAllTags),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EmptyFilterResult extends StatelessWidget {
  final VoidCallback onClear;

  const _EmptyFilterResult({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 42, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'No matching meals',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Try another keyword or tag.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

String? _regionForExperience(ExperienceCard experience) {
  return experience.region ??
      _regionFromLocationText([experience.placeAddress, experience.placeTitle]);
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
