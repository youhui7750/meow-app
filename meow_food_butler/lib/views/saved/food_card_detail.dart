import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/food_card.dart';
import '../../models/experience_card.dart';
import '../../view_models/saved_view_model.dart';

import 'widgets/experience_photo.dart';

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
  int _heroPageIndex = 0;
  final PageController _heroPageController = PageController();

  @override
  void dispose() {
    _heroPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allExperiences = context.watch<SavedViewModel>().experiences;

    final relatedExperiences = allExperiences.where((e) {
      final key1 = e.foodCardId ?? e.placeId ?? e.placeTitle;
      final key2 = widget.foodCard.id ?? widget.foodCard.primaryTitle;
      return key1 == key2;
    }).toList();

    final currentExperiences = <ExperienceCard>[];
    for (final exp in [...widget.experiences, ...relatedExperiences]) {
      final duplicate = currentExperiences.any((item) {
        if (item.id != null && exp.id != null) return item.id == exp.id;
        return item.placeTitle == exp.placeTitle &&
            item.createdTime == exp.createdTime;
      });
      if (!duplicate) currentExperiences.add(exp);
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
      body: Column(
        children: [
          _buildHeroImage(colorScheme, widget.experiences, currentExperiences),
          _buildHeader(colorScheme, currentExperiences),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 32),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showOnlineInfoTab) 
                    _buildOnlineInfoSection(colorScheme),
                  _buildSourceLinkSection(colorScheme, currentExperiences),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage(
    ColorScheme colorScheme,
    List<ExperienceCard> priorityExperiences,
    List<ExperienceCard> currentExperiences,
  ) {
    ExperienceCard? heroExperience;
    for (final experience in [...priorityExperiences, ...currentExperiences]) {
      if (experience.photoUrls.isNotEmpty || experience.photoPaths.isNotEmpty) {
        heroExperience = experience;
        break;
      }
    }

    final photoPages = widget.foodCard.photoUrls
        .take(5)
        .map((url) => _buildRestaurantPhotoUrlPage(
              colorScheme,
              url,
              heroExperience,
            ))
        .toList();

    final pages = <Widget>[
      if (photoPages.isNotEmpty)
        ...photoPages
      else
        _buildRestaurantPhotoPage(colorScheme, heroExperience),
      if (widget.foodCard.menuLink?.isNotEmpty == true)
        _buildMenuPreviewPage(colorScheme),
    ];

    return Stack(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: PageView(
            controller: _heroPageController,
            onPageChanged: (index) => setState(() => _heroPageIndex = index),
            children: pages,
          ),
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
          right: 16,
          bottom: 12,
          child: Row(
            children: List.generate(
              pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: _heroPageIndex == index ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.only(left: 5),
                decoration: BoxDecoration(
                  color: _heroPageIndex == index
                      ? colorScheme.primary
                      : colorScheme.surface.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
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

  Widget _buildRestaurantPhotoPage(
    ColorScheme colorScheme,
    ExperienceCard? heroExperience,
  ) {
    if (heroExperience != null) {
      return ExperiencePhoto(
        experience: heroExperience,
        width: MediaQuery.sizeOf(context).width,
        height: 220,
        borderRadius: 0,
      );
    }

    return _buildPhotoFallback(colorScheme);
  }

  Widget _buildRestaurantPhotoUrlPage(
    ColorScheme colorScheme,
    String url,
    ExperienceCard? heroExperience,
  ) {
    return Image.network(
      key: ValueKey(url),
      url,
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stackTrace) {
        if (heroExperience != null) {
          return ExperiencePhoto(
            experience: heroExperience,
            width: MediaQuery.sizeOf(context).width,
            height: 220,
            borderRadius: 0,
          );
        }
        return _buildPhotoFallback(colorScheme);
      },
    );
  }

  Widget _buildPhotoFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.restaurant,
          size: 48,
          color: colorScheme.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildMenuPreviewPage(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final menuLink = widget.foodCard.menuLink;

    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Menu preview',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (menuLink != null)
            InkWell(
              onTap: () async {
                final uri = Uri.parse(menuLink);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        menuLink,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.open_in_new, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, List<ExperienceCard> currentExperiences) {
    final textTheme = Theme.of(context).textTheme;
    final rating = widget.foodCard.rating;

    final visitCount = currentExperiences.length;
    final avgRating = visitCount > 0 
        ? currentExperiences.fold(0.0, (sum, exp) => sum + exp.personalRating) / visitCount 
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.foodCard.primaryTitle,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate(
                            5,
                            (index) => Icon(
                              Icons.star,
                              size: 16,
                              color: index < rating.round()
                                  ? Colors.amber.shade700
                                  : colorScheme.outlineVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            rating.toStringAsFixed(1),
                            style: textTheme.labelLarge?.copyWith(
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (widget.foodCard.reviews != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${widget.foodCard.reviews})',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: visitCount > 0 ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "My Avg",
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: visitCount > 0 ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star, 
                            size: 14, 
                            color: visitCount > 0 ? colorScheme.primary : colorScheme.outline
                          ),
                          const SizedBox(width: 2),
                          Text(
                            visitCount > 0 ? avgRating.toStringAsFixed(1) : "-",
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: visitCount > 0 ? colorScheme.primary : colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
            child: Icon(Icons.navigation, color: colorScheme.onPrimary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineInfoSection(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final facts = _headerFacts(colorScheme);
    final hasHours =
        widget.foodCard.workingHours != null || widget.foodCard.popularTimes != null;
    final hasDescription = widget.foodCard.description?.trim().isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.foodCard.formattedAddress?.isNotEmpty == true ||
            hasDescription) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront_outlined,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.foodCard.formattedAddress ??
                      widget.foodCard.description!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (facts.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  facts[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (hasHours) ...[
          _buildSectionTitle('Hours & crowd', Icons.schedule, colorScheme),
          const SizedBox(height: 12),
          _buildHoursCard(colorScheme),
          const SizedBox(height: 24),
        ],
        if (widget.foodCard.reviewSnippets.isNotEmpty) ...[
          _buildSectionTitle('Reviews', Icons.forum_outlined, colorScheme),
          const SizedBox(height: 12),
          ...widget.foodCard.reviewSnippets
              .take(3)
              .map((review) => _buildReviewCard(review, colorScheme)),
        ],
      ],
    );
  }

  List<Widget> _headerFacts(ColorScheme colorScheme) {
    final facts = <Widget>[];
    final todayHours = _todayHoursLabel();
    if (todayHours != null) {
      facts.add(_HeaderFact(
        icon: Icons.schedule,
        text: todayHours,
        colorScheme: colorScheme,
      ));
    }
    if (widget.foodCard.phone?.isNotEmpty == true) {
      facts.add(_HeaderFact(
        icon: Icons.phone,
        text: widget.foodCard.phone!,
        colorScheme: colorScheme,
      ));
    }
    if (widget.foodCard.priceRange?.isNotEmpty == true) {
      facts.add(_HeaderFact(
        icon: Icons.payments_outlined,
        text: widget.foodCard.priceRange!,
        colorScheme: colorScheme,
      ));
    }
    if (widget.foodCard.typicalTimeSpent?.isNotEmpty == true) {
      facts.add(_HeaderFact(
        icon: Icons.timer_outlined,
        text: widget.foodCard.typicalTimeSpent!,
        colorScheme: colorScheme,
      ));
    }
    return facts;
  }

  Widget _buildSourceLinkSection(ColorScheme colorScheme, List<ExperienceCard> currentExperiences) {
    String? url = widget.foodCard.originalURL;
    if (url == null || url.trim().isEmpty) {
      for (final exp in currentExperiences) {
        if (exp.originalURL != null && exp.originalURL!.trim().isNotEmpty) {
          url = exp.originalURL;
          break;
        }
      }
    }

    if (url == null || url.trim().isEmpty) return const SizedBox.shrink();

    final isIG = url.contains('instagram.com');

    return Padding(
      padding: EdgeInsets.only(top: widget.showOnlineInfoTab ? 24.0 : 0.0),
      child: InkWell(
        onTap: () async {
          final uri = Uri.parse(url!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication); 
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open the link.')),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isIG ? Icons.camera_alt : Icons.link,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIG ? 'View Instagram Post' : 'View Original Source',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.open_in_new,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildHoursCard(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final todayHours = _todayHoursLabel();
    final popularBars = _popularTimeBarsForToday();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (todayHours != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Hours',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    todayHours,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (popularBars.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Popular times',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _buildPopularTimeBars(popularBars, colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildPopularTimeBars(
    List<_PopularTimePoint> points,
    ColorScheme colorScheme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: points.map((point) {
        final percentage = point.percentage.clamp(0, 100).toDouble();
        final isPeak = percentage >= 80;

        return Expanded(
          child: Column(
            children: [
              Container(
                height: 54,
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 10 + (percentage / 100) * 44,
                  width: 18,
                  decoration: BoxDecoration(
                    color: isPeak
                        ? colorScheme.primary
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                point.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReviewCard(
    Map<String, dynamic> review,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final rating = (review['rating'] as num?)?.toDouble();
    final text = (review['text'] as String?)?.trim();
    final author = (review['author'] as String?)?.trim();

    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (rating != null) ...[
                ...List.generate(
                  5,
                  (index) => Icon(
                    Icons.star,
                    size: 14,
                    color: index < rating.round()
                        ? Colors.amber.shade700
                        : colorScheme.outlineVariant,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                author == null || author.isEmpty ? 'Google Maps' : author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  String? _todayHoursLabel() {
    final hours = widget.foodCard.workingHours;
    if (hours == null || hours.isEmpty) return null;

    const keys = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    for (final key in keys) {
      final value = hours[key];
      if (value == null) continue;
      if (value is String && value.trim().isNotEmpty) return '$key $value';
      if (value is List && value.isNotEmpty) return '$key ${value.join(", ")}';
    }

    return hours.entries
        .take(2)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(' · ');
  }

  List<_PopularTimePoint> _popularTimeBarsForToday() {
    final popular = widget.foodCard.popularTimes;
    if (popular == null) return const [];

    if (popular is List) {
      final selectedDay = _selectPopularTimeDay(popular);
      if (selectedDay == null) return const [];

      final rawPoints = selectedDay['popular_times'];
      if (rawPoints is! List) return const [];

      final points = rawPoints
          .whereType<Map>()
          .map((item) {
            final percentage = (item['percentage'] as num?)?.toInt() ?? 0;
            final hour = (item['hour'] as num?)?.toInt();
            final label = (item['time'] as String?) ??
                (hour == null ? '' : hour.toString());
            return _PopularTimePoint(label: label, percentage: percentage);
          })
          .where((point) => point.percentage > 0)
          .toList();

      if (points.length <= 8) return points;

      final step = (points.length / 8).ceil();
      return [
        for (var i = 0; i < points.length; i += step) points[i],
      ].take(8).toList();
    }

    if (popular is Map) {
      return popular.entries.take(8).map((entry) {
        final value = entry.value;
        final percentage = value is Map
            ? (value['percentage'] as num?)?.toInt() ?? 0
            : (value is num ? value.toInt() : 0);
        return _PopularTimePoint(
          label: entry.key.toString(),
          percentage: percentage,
        );
      }).where((point) => point.percentage > 0).toList();
    }

    return const [];
  }

  Map<String, dynamic>? _selectPopularTimeDay(List<dynamic> days) {
    if (days.isEmpty) return null;
    final weekday = DateTime.now().weekday;
    final googleDay = weekday == 7 ? 7 : weekday;

    for (final item in days.whereType<Map>()) {
      if ((item['day'] as num?)?.toInt() == googleDay) {
        return Map<String, dynamic>.from(item);
      }
    }

    for (final item in days.whereType<Map>()) {
      return Map<String, dynamic>.from(item);
    }
    return null;
  }
}

class _PopularTimePoint {
  final String label;
  final int percentage;

  const _PopularTimePoint({
    required this.label,
    required this.percentage,
  });
}

class _HeaderFact extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme colorScheme;

  const _HeaderFact({
    required this.icon,
    required this.text,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
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

class _SmallInfoPill extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _SmallInfoPill({
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
