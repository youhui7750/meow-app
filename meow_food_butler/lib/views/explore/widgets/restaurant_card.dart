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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[200]!, width: 1),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (experience.isDone) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.navigation, color: Colors.blue),
                  onPressed: onNavTap,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 4),

            Text(
              experience.placeAddress ?? 'No address available',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
                    const Icon(Icons.star, color: Colors.orange, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      experience.personalRating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Container(width: 1, height: 12, color: Colors.grey[300]),
                ...experience.personalTags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
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
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[100]!),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_not_supported_outlined, color: Colors.grey[400], size: 20),
                            const SizedBox(width: 8),
                            Text('No photos yet', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
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
                  color: Colors.amber[50]?.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[100]!, width: 0.5),
                ),
                child: Text(
                  '“${experience.personalNote}”',
                  style: TextStyle(
                    color: Colors.amber[900],
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
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