import 'package:flutter/material.dart';
import '../../models/food_card.dart';
import '../../models/experience_card.dart';
import 'experience_entry_sheet.dart'; 

class FoodCardDetail extends StatefulWidget {
  final FoodCard foodCard;
  final List<ExperienceCard> experiences;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback onToggleSave;
  final VoidCallback onAddExperience;

  const FoodCardDetail({
    super.key,
    required this.foodCard,
    required this.experiences,
    required this.isSaved,
    required this.onClose,
    required this.onToggleSave,
    required this.onAddExperience,
  });

  @override
  State<FoodCardDetail> createState() => _FoodCardDetailState();
}

class _FoodCardDetailState extends State<FoodCardDetail> {
  int _currentTabIndex = 0; // 0 = Online Info, 1 = Yours
  final TextEditingController _tagController = TextEditingController();
  
  final List<String> _mockPros = ['Clean', 'Fast service', 'Fresh food', 'Large portions'];
  final List<String> _mockCons = ['Hard to park', 'Long queue'];
  final List<String> _suggestedTags = ['Go-to spot', 'Weekend vibe', 'Cheap eats', 'Group friendly', 'Great value'];

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _openExperienceEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,        
      backgroundColor: Colors.transparent, 
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ExperienceEntrySheet(
            initialExperience: ExperienceCard(
              foodCardId: widget.foodCard.id,
              placeTitle: widget.foodCard.primaryTitle,
              placeAddress: widget.foodCard.formattedAddress,
              latitude: widget.foodCard.location?.latitude,
              longitude: widget.foodCard.location?.longitude,
              personalTags: const [],
              personalRating: 0.0,
            ),
            onSave: (newExperience, photos) async {
              debugPrint('Preparing to save new experience: ${newExperience.placeTitle}');
              debugPrint('Selected ${photos.length} photos');
              
              // Simulate network delay
              await Future.delayed(const Duration(seconds: 1));
              
              if (context.mounted) {
                Navigator.of(context).pop();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeroImage(),
              _buildHeader(),
              _buildTabs(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _currentTabIndex == 0 
                        ? _buildOnlineTab() 
                        : _buildYoursTab(),
                  ),
                ),
              ),
            ],
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return Stack(
      children: [
        Container(
          height: 220,
          width: double.infinity,
          color: Colors.grey[100],
          child: widget.foodCard.originalURL != null
              ? Image.network(widget.foodCard.originalURL!, fit: BoxFit.cover)
              : const Center(child: Icon(Icons.restaurant, size: 48, color: Colors.grey)),
        ),
        Container(
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.25), Colors.transparent],
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
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.black87, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text("Nearby • ", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Icon(Icons.phone, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text("No phone available", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Icon(Icons.assignment_outlined, color: Colors.black54, size: 18),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Expanded(child: _buildTabButton("Online Info", 0)),
            Expanded(child: _buildTabButton("My Rating", 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isActive = _currentTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive ? const [BoxShadow(color: Colors.black12, blurRadius: 2)] : [],
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.black87 : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineTab() {
    return Column(
      key: const ValueKey('online'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
              child: const Text("Restaurant", style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.orange, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    widget.foodCard.rating?.toStringAsFixed(1) ?? "4.5",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
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
            ..._mockPros.map((tag) => _buildStatusTag(tag, true)),
            ..._mockCons.map((tag) => _buildStatusTag(tag, false)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Colors.deepOrange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.foodCard.formattedAddress ?? "This is a highly popular restaurant offering a variety of specialty dishes. Highly recommended.",
                style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusTag(String text, bool isPro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPro ? Colors.green[50] : Colors.red[50],
        border: Border.all(color: isPro ? Colors.green[100]! : Colors.red[100]!),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isPro ? Colors.green[700] : Colors.red[700]),
      ),
    );
  }

  Widget _buildYoursTab() {
    final visitCount = widget.experiences.length;
    final avgRating = visitCount > 0 
        ? widget.experiences.fold(0.0, (sum, exp) => sum + exp.personalRating) / visitCount 
        : 0.0;

    return Column(
      key: const ValueKey('yours'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.amber[50]!, Colors.orange[50]!]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange[100]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("YOUR AVERAGE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
              visitCount > 0 ? Row(
                children: [
                  Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                  const SizedBox(width: 8),
                  Text("$visitCount visits", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                ],
              ) : const Text("No ratings yet", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("YOUR MEALS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            GestureDetector(
              onTap: _openExperienceEntrySheet, 
              child: Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            )
          ],
        ),
        const SizedBox(height: 12),
        if (visitCount == 0)
          GestureDetector(
            onTap: _openExperienceEntrySheet, 
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.add_circle_outline, size: 28, color: Colors.deepOrange),
                  const SizedBox(height: 8),
                  Text("Log your first meal", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text("Record the dishes you tried and your thoughts!", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...widget.experiences.map((exp) => _buildExperienceItem(exp)),
        const SizedBox(height: 24),
        const Text("YOUR TAGS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              const Text("#", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: const InputDecoration(border: InputBorder.none, hintText: "Add your own tag", hintStyle: TextStyle(fontSize: 13)),
                  onSubmitted: (val) => _handleAddNewTag(),
                ),
              ),
              GestureDetector(
                onTap: _handleAddNewTag,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward, color: Colors.white, size: 12),
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
                color: Colors.white,
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text("+ #$tag", style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildExperienceItem(ExperienceCard exp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
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
                  color: i < exp.personalRating ? Colors.orange : Colors.grey[300]
                )),
              ),
              Text(
                _formatRelative(exp.createdTime.toDate()),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          if (exp.personalNote != null && exp.personalNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(exp.personalNote!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ]
        ],
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

  Widget _buildBottomActionBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[100]!)),
        ),
        child: GestureDetector(
          onTap: widget.onToggleSave,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: widget.isSaved ? Colors.orange[50] : Colors.deepOrange,
              borderRadius: BorderRadius.circular(24),
              border: widget.isSaved ? Border.all(color: Colors.orange[200]!) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: widget.isSaved ? Colors.deepOrange : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isSaved ? "Saved to your map" : "Save this spot",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.isSaved ? Colors.deepOrange : Colors.white,
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