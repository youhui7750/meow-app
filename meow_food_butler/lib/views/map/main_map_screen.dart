import 'package:flutter/material.dart';

/// Please use the command `flutter pub add google_maps_flutter`
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  GoogleMapController? mapController;

  // Placeholder for Taipei, Taiwan (Da'an District)
  static const LatLng _defaultCenter = LatLng(25.032969, 121.542598);
  LatLng _center = _defaultCenter;
  bool _canUseLocation = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final target = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _center = target;
        _canUseLocation = true;
      });

      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // We use a Stack to place the Draggable Sheet OVER the map
      body: Stack(
        children: [
          // 1. The Background Google Map Layer
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: _center, zoom: 15.0),
            myLocationEnabled: _canUseLocation,
            myLocationButtonEnabled:
                false, // We'll build a custom FAB for this later
            zoomControlsEnabled: false, // Keeps the UI clean
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'map-current-location',
              onPressed: _isLocating ? null : _moveToCurrentLocation,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          // 2. The Draggable Bottom Sheet Layer
          DraggableScrollableSheet(
            initialChildSize: 0.3, // Starts at 30% of screen height
            minChildSize: 0.1, // Can be dragged down to 10% (just a top bar)
            maxChildSize:
                0.85, // Can be dragged up to 85% to view comments/photos
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ListView.builder(
                  controller:
                      scrollController, // Crucial: binds scrolling to dragging
                  itemCount: 5, // Placeholder count
                  itemBuilder: (BuildContext context, int index) {
                    // Top drag indicator handle for the first item
                    if (index == 0) {
                      return Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            height: 5,
                            width: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }

                    // Placeholder for your FoodCard populated by Outscraper data
                    return _buildMockFoodCard(context, index);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // A temporary UI widget to visualize where the Outscraper API data will go
  Widget _buildMockFoodCard(BuildContext context, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ramen Spot $index',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Icon(
                  Icons.navigation,
                  color: Colors.blue,
                ), // Your requested Maps nav link
              ],
            ),
            const SizedBox(height: 8),
            // Placeholder for Outscraper Photos
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                itemBuilder: (context, picIndex) => Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.image, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Placeholder for Outscraper Reviews
            Text(
              '⭐⭐⭐⭐⭐ "Best ramen in Da\'an!"',
              style: TextStyle(
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
