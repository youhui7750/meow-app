import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  
  final List<_DemoMenuItem> _demoMenuItems = const [
    _DemoMenuItem('招牌健康餐盒', '舒肥雞胸、季節蔬菜、紫米飯', 'NT\$ 165'),
    _DemoMenuItem('炙燒牛五花餐盒', '微辣醬汁、溫泉蛋、青花菜', 'NT\$ 210'),
    _DemoMenuItem('低醣鮭魚餐盒', '烤鮭魚、花椰菜米、胡麻沙拉', 'NT\$ 240'),
  ];
  final List<_DemoReview> _demoReviews = const [
    _DemoReview('份量剛好，雞胸不乾，午餐尖峰要提早訂。', 5),
    _DemoReview('菜色清爽，價格偏中上，但外送包裝很穩。', 4),
  ];

  @override
  void dispose() {
    _heroPageController.dispose();
    super.dispose();
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
      body: Column(
        children: [
          _buildHeroImage(colorScheme, currentExperiences),
          _buildHeader(colorScheme, currentExperiences),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 32),
              physics: const BouncingScrollPhysics(),
              child: widget.showOnlineInfoTab 
                  ? _buildOnlineInfoSection(colorScheme)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage(
    ColorScheme colorScheme,
    List<ExperienceCard> currentExperiences,
  ) {
    ExperienceCard? heroExperience;
    for (final experience in currentExperiences) {
      if (experience.photoUrls.isNotEmpty || experience.photoPaths.isNotEmpty) {
        heroExperience = experience;
        break;
      }
    }

    final pages = <Widget>[
      _buildRestaurantPhotoPage(colorScheme, heroExperience),
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

    if (widget.foodCard.originalURL != null) {
      return Image.network(
        widget.foodCard.originalURL!,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) =>
            _buildPhotoFallback(colorScheme),
      );
    }

    return _buildPhotoFallback(colorScheme);
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
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _demoMenuItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _demoMenuItems[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.price,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, List<ExperienceCard> currentExperiences) {
    final textTheme = Theme.of(context).textTheme;
    final rating = widget.foodCard.rating ?? 4.5;

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
                    // Google Stars
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
                        const SizedBox(width: 6),
                        Text(
                          '(426)',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '•',
                      style: TextStyle(
                        color: colorScheme.outlineVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // My Avg Badge
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storefront_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.foodCard.formattedAddress ?? "This is a highly popular restaurant offering a variety of specialty dishes. Highly recommended.",
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _HeaderFact(
                icon: Icons.schedule,
                text: 'Open now · until 20:30',
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _HeaderFact(
                icon: Icons.phone,
                text: '03-555-1295',
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _HeaderFact(
                icon: Icons.payments_outlined,
                text: '\$\$ · NT\$160-280',
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _HeaderFact(
                icon: Icons.timer_outlined,
                text: '35-50 min',
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Hours & crowd', Icons.schedule, colorScheme),
        const SizedBox(height: 12),
        _buildHoursCard(colorScheme),
        const SizedBox(height: 24),
        _buildSectionTitle('Reviews', Icons.forum_outlined, colorScheme),
        const SizedBox(height: 12),
        ..._demoReviews.map((review) => _buildReviewCard(review, colorScheme)),
      ],
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Open now',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mon-Sun 10:30-20:30',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Popular times today',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _buildPeakBars(colorScheme),
        ],
      ),
    );
  }

  Widget _buildPeakBars(ColorScheme colorScheme) {
    const values = [0.25, 0.48, 0.88, 0.72, 0.38, 0.56];
    const labels = ['10', '11', '12', '13', '14', '18'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        final isPeak = values[index] > 0.8;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 54,
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 12 + values[index] * 42,
                  width: 18,
                  decoration: BoxDecoration(
                    color:
                        isPeak ? colorScheme.primary : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                labels[index],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildReviewCard(_DemoReview review, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;

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
              ...List.generate(
                5,
                (index) => Icon(
                  Icons.star,
                  size: 14,
                  color: index < review.rating
                      ? Colors.amber.shade700
                      : colorScheme.outlineVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Google Maps',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.text,
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DemoMenuItem {
  final String name;
  final String description;
  final String price;

  const _DemoMenuItem(this.name, this.description, this.price);
}

class _DemoReview {
  final String text;
  final int rating;

  const _DemoReview(this.text, this.rating);
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