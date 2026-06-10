import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/experience_card.dart';
import 'widgets/restaurant_list_sheet.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  GoogleMapController? mapController;

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
    final mockExperiences = [
      ExperienceCard(
        id: 'mock_1',
        placeTitle: '大安優質拉麵屋',
        placeAddress: '台北市大安區信義路四段XX號',
        personalRating: 4.8,
        personalTags: ['豚骨拉麵', '排隊美食'],
        personalNote: '濃郁的湯頭配上黃金比例的叉燒，簡直是人間美味！必點溏心蛋。',
        isDone: true,
        photoUrls: ['https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=400'],
      ),
      ExperienceCard(
        id: 'mock_2',
        placeTitle: '微風高空餐酒館',
        placeAddress: '台北市信義區忠孝東路五段XX號',
        personalRating: 4.2,
        personalTags: ['夜景', '微醺約會', '餐酒館'],
        isDone: false,
        photoUrls: [], 
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: _center, zoom: 15.0),
            myLocationEnabled: _canUseLocation,
            myLocationButtonEnabled: false, 
            zoomControlsEnabled: false, 
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

          RestaurantListSheet(experiences: mockExperiences),
        ],
      ),
    );
  }
}