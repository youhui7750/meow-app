import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/models/food_card.dart';
import 'package:meow_food_butler/repositories/experience_repository.dart';
import 'package:meow_food_butler/repositories/restaurant_repository.dart';
import 'package:meow_food_butler/services/business_hours_service.dart';
import 'package:meow_food_butler/services/current_map_position.dart';
import 'package:meow_food_butler/services/distance_service.dart';
import 'package:meow_food_butler/services/shared_url_notifier.dart';
import 'dart:async';

import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/map/widgets/import_dialog.dart';
import 'package:meow_food_butler/views/map/widgets/restaurant_list_sheet.dart';
import 'package:meow_food_butler/views/map/settings_screen.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  static const LatLng _defaultCenter = LatLng(25.032969, 121.542598);
  static const double _locationZoom = 17;

  static const String _mapStyle = '''
[
  {
    "featureType": "administrative",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#444444"
      }
    ]
  },
  {
    "featureType": "landscape",
    "elementType": "all",
    "stylers": [
      {
        "color": "#e9e6de"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "simplified"
      }
    ]
  },
  {
    "featureType": "poi.attraction",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.business",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.government",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.medical",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#f5f5f2"
      },
      {
        "visibility": "on"
      },
      {
        "saturation": -35
      },
      {
        "lightness": -10
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.place_of_worship",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.school",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.sports_complex",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "all",
    "stylers": [
      {
        "saturation": -100
      },
      {
        "lightness": 45
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "simplified"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "simplified"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "simplified"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "all",
    "stylers": [
      {
        "color": "#7ddde6"
      },
      {
        "visibility": "on"
      }
    ]
  }
]
''';

  GoogleMapController? _mapController;
  BitmapDescriptor? _blackSpotIcon;
  BitmapDescriptor? _redSpotIcon;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  final List<ExperienceCard> _importedCandidates = [];

  LatLng _center = _defaultCenter;
  LatLng? _currentLocation;

  String? _selectedExperienceId;
  MapSheetMode _sheetMode = MapSheetMode.myPlaces;
  MyPlacesSortMode _myPlacesSortMode = MyPlacesSortMode.distance;

  bool _canUseLocation = false;
  bool _isLocating = false;
  SharedUrlNotifier? _sharedUrlNotifier;
  StreamSubscription<RestaurantImportEvent>? _importEventSub;

  @override
  void initState() {
    super.initState();
    _loadSpotIcons();
    _moveToCurrentLocation(showErrors: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = Provider.of<SharedUrlNotifier>(context, listen: false);
      _sharedUrlNotifier = notifier;
      notifier.addListener(_onSharedUrlChanged);
      _handleSharedUrlIfPresent();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to import events so URL-imported restaurants land in the sheet.
    _importEventSub?.cancel();
    _importEventSub = context
        .read<SavedViewModel>()
        .importEvents
        .listen(_onImportEvent);
  }

  void _onImportEvent(RestaurantImportEvent event) {
    if (!mounted || !event.isCompleted) return;
    final experience = event.linkedExperience;
    if (experience == null) return;
    setState(() {
      _sheetMode = MapSheetMode.imported;
      _importedCandidates.removeWhere(
        (c) => c.originalURL != null && c.originalURL == experience.originalURL,
      );
      _importedCandidates.insert(0, experience);
    });
    _selectExperience(experience);
  }

  void _onSharedUrlChanged() {
    _handleSharedUrlIfPresent();
  }

  @override
  void dispose() {
    _importEventSub?.cancel();
    _sharedUrlNotifier?.removeListener(_onSharedUrlChanged);
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _handleSharedUrlIfPresent() async {
    final notifier = Provider.of<SharedUrlNotifier>(context, listen: false);
    final sharedUrl = notifier.sharedUrl;
    if (sharedUrl == null || sharedUrl.trim().isEmpty) return;

    notifier.clearSharedUrl();
    await _openImportDialog(initialUrl: sharedUrl);
  }

  Future<void> _openImportDialog({String? initialUrl}) async {
    // Dialog closes immediately — import runs in background via SavedViewModel.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ImportInstagramDialog(initialUrl: initialUrl),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    if (_currentLocation != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation!, zoom: _locationZoom),
        ),
      );
    }
  }

  Future<void> _loadSpotIcons() async {
    final blackIcon = await _buildPinIcon(
      fillColor: const Color(0xFF3F3F46),
      size: 28,
      active: false,
    );

    final redIcon = await _buildPinIcon(
      fillColor: const Color(0xFFEF4444),
      size: 28,
      active: true,
    );

    if (!mounted) return;

    setState(() {
      _blackSpotIcon = blackIcon;
      _redSpotIcon = redIcon;
    });
  }

  Future<BitmapDescriptor> _buildPinIcon({
    required Color fillColor,
    required int size,
    required bool active,
  }) async {
    final int canvasSize = active ? 72 : 56;
    final double scale = size / 24.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final Offset canvasCenter = Offset(canvasSize / 2, canvasSize / 2);
    final Offset origin = Offset(
      canvasCenter.dx - size / 2,
      canvasCenter.dy - size / 2,
    );

    if (active) {
      final pulsePaint = Paint()
        ..color = const Color(0xFFEF4444).withOpacity(0.22)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        canvasCenter,
        size * 0.58,
        pulsePaint,
      );
    }

    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final pinPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final whiteDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final innerDotPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    Path pinPath() {
      return Path()
        ..moveTo(20 * scale, 10 * scale)
        ..cubicTo(
          20 * scale,
          14.993 * scale,
          14.461 * scale,
          20.193 * scale,
          12.601 * scale,
          21.799 * scale,
        )
        ..cubicTo(
          12.239 * scale,
          22.112 * scale,
          11.761 * scale,
          22.112 * scale,
          11.399 * scale,
          21.799 * scale,
        )
        ..cubicTo(
          9.539 * scale,
          20.193 * scale,
          4 * scale,
          14.993 * scale,
          4 * scale,
          10 * scale,
        )
        ..cubicTo(
          4 * scale,
          5.582 * scale,
          7.582 * scale,
          2 * scale,
          12 * scale,
          2 * scale,
        )
        ..cubicTo(
          16.418 * scale,
          2 * scale,
          20 * scale,
          5.582 * scale,
          20 * scale,
          10 * scale,
        )
        ..close();
    }

    final path = pinPath();
    canvas.drawPath(path.shift(Offset(0, 2 * scale)), shadowPaint);
    canvas.drawPath(path, pinPaint);
    canvas.drawPath(path, strokePaint);

    canvas.drawCircle(
      Offset(12 * scale, 10 * scale),
      3 * scale,
      whiteDotPaint,
    );

    canvas.drawCircle(
      Offset(12 * scale, 10 * scale),
      1.35 * scale,
      innerDotPaint,
    );

    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize, canvasSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  List<ExperienceCard> _mapExperiences(List<ExperienceCard> experiences) {
    final deduped = <String, ExperienceCard>{};

    for (final experience in experiences) {
      if (experience.latitude == null || experience.longitude == null) {
        continue;
      }

      final coordinateKey =
          '${experience.placeTitle ?? 'unknown'}-${experience.latitude}-${experience.longitude}';
      final key = experience.placeId ?? experience.foodCardId ?? coordinateKey;

      final current = deduped[key];

      if (current == null ||
          experience.createdTime.compareTo(current.createdTime) > 0) {
        deduped[key] = experience;
      }
    }

    return deduped.values.toList()
      ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
  }

  bool _isImportedExperience(ExperienceCard experience) {
    return experience.originalURL?.trim().isNotEmpty == true;
  }

  ExperienceCard _experienceFromRestaurant(FoodCard restaurant) {
    return ExperienceCard(
      id: 'restaurant-${restaurant.id ?? restaurant.primaryTitle}',
      foodCardId: restaurant.id,
      placeId: restaurant.id,
      placeTitle: restaurant.primaryTitle,
      placeAddress: restaurant.formattedAddress,
      latitude: restaurant.location?.latitude,
      longitude: restaurant.location?.longitude,
      originalURL: restaurant.originalURL,
      googleMapsUrl: restaurant.googleMapsUrl,
      photoPaths: restaurant.photoPaths,
      photoUrls: restaurant.photoUrls,
      personalTags: restaurant.tags,
      personalRating: restaurant.rating ?? 0,
      personalNote: restaurant.description,
      isDone: restaurant.visited,
      createdTime: restaurant.updatedTime ?? restaurant.createdTime,
    );
  }

  FoodCard? _restaurantForExperience(
    ExperienceCard experience,
    List<FoodCard> restaurants,
  ) {
    final candidates = <String?>[
      experience.foodCardId,
      experience.placeId,
      if (experience.id?.startsWith('restaurant-') == true)
        experience.id!.replaceFirst('restaurant-', ''),
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    for (final restaurant in restaurants) {
      final restaurantId = restaurant.id?.trim();
      if (restaurantId != null && candidates.contains(restaurantId)) {
        return restaurant;
      }
    }

    final title = experience.placeTitle?.trim();
    if (title == null || title.isEmpty) return null;
    for (final restaurant in restaurants) {
      final restaurantTitle = restaurant.primaryTitle.trim();
      if (restaurantTitle == title ||
          restaurantTitle.contains(title) ||
          title.contains(restaurantTitle)) {
        return restaurant;
      }
    }

    return null;
  }

  BusinessHoursStatus? _hoursStatusFor(
    ExperienceCard experience,
    List<FoodCard> restaurants,
  ) {
    final restaurant = _restaurantForExperience(experience, restaurants);
    final status = BusinessHoursService.status(restaurant?.workingHours);
    return status.hasData ? status : null;
  }

  double? _distanceMetersTo(ExperienceCard experience) {
    final currentLocation = _currentLocation;
    final latitude = experience.latitude;
    final longitude = experience.longitude;

    if (currentLocation == null || latitude == null || longitude == null) {
      return null;
    }

    return DistanceService.metersBetween(
      fromLatitude: currentLocation.latitude,
      fromLongitude: currentLocation.longitude,
      toLatitude: latitude,
      toLongitude: longitude,
    );
  }

  String? _distanceLabelFor(ExperienceCard experience) {
    return DistanceService.formatMeters(_distanceMetersTo(experience));
  }

  List<ExperienceCard> _sortMyPlaces(
    List<ExperienceCard> experiences,
    List<FoodCard> restaurants,
  ) {
    final items = List<ExperienceCard>.from(experiences);

    if (_myPlacesSortMode == MyPlacesSortMode.recent) {
      return items..sort((a, b) => b.createdTime.compareTo(a.createdTime));
    }

    if (_myPlacesSortMode == MyPlacesSortMode.openNow) {
      return items
        ..sort((a, b) {
          final aRank = _openSortRank(_hoursStatusFor(a, restaurants));
          final bRank = _openSortRank(_hoursStatusFor(b, restaurants));
          if (aRank != bRank) return aRank.compareTo(bRank);

          final distanceCompare = _compareDistance(a, b);
          if (distanceCompare != 0) return distanceCompare;
          return b.createdTime.compareTo(a.createdTime);
        });
    }

    if (_currentLocation == null) {
      return items..sort((a, b) => b.createdTime.compareTo(a.createdTime));
    }

    return items
      ..sort((a, b) {
        final distanceCompare = _compareDistance(a, b);
        if (distanceCompare != 0) return distanceCompare;
        return b.createdTime.compareTo(a.createdTime);
      });
  }

  int _openSortRank(BusinessHoursStatus? status) {
    final isOpen = status?.isOpen;
    if (isOpen == true) return 0;
    if (isOpen == false) return 1;
    return 2;
  }

  int _compareDistance(ExperienceCard a, ExperienceCard b) {
    final aDistance = _distanceMetersTo(a);
    final bDistance = _distanceMetersTo(b);

    if (aDistance == null && bDistance == null) return 0;
    if (aDistance == null) return 1;
    if (bDistance == null) return -1;
    return aDistance.compareTo(bDistance);
  }

  Set<Marker> _markersFor(List<ExperienceCard> experiences) {
    return experiences.map((experience) {
      final markerId = _markerIdFor(experience);
      final selected = markerId == _selectedExperienceId;
      final position = LatLng(experience.latitude!, experience.longitude!);

      return Marker(
        markerId: MarkerId(selected ? '$markerId-selected' : markerId),
        position: position,
        zIndexInt: selected ? 100 : 0,
        icon: selected
            ? (_redSpotIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed))
            : (_blackSpotIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet)),
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: experience.placeTitle ?? 'Unnamed restaurant',
          snippet: experience.placeAddress,
        ),
        onTap: () => _selectExperience(experience, showInfoWindow: false),
      );
    }).toSet();
  }

  Set<Circle> _circlesFor(List<ExperienceCard> experiences) {
    final circles = <Circle>{};

    final currentLocation = _currentLocation;

    if (currentLocation != null) {
      circles.addAll({
        Circle(
          circleId: const CircleId('current-location-range'),
          center: currentLocation,
          radius: 45,
          fillColor: Colors.blueAccent.withOpacity(0.18),
          strokeColor: Colors.blueAccent.withOpacity(0.35),
          strokeWidth: 1,
          zIndex: 99,
        ),
        Circle(
          circleId: const CircleId('current-location-dot'),
          center: currentLocation,
          radius: 12,
          fillColor: Colors.blueAccent.withOpacity(0.95),
          strokeColor: Colors.white,
          strokeWidth: 4,
          zIndex: 100,
        ),
      });
    }

    return circles;
  }

  String _markerIdFor(ExperienceCard experience) {
    return experience.id ??
        experience.originalURL ??
        experience.placeId ??
        '${experience.placeTitle}-${experience.latitude}-${experience.longitude}';
  }

  Future<void> _selectExperience(
    ExperienceCard experience, {
    bool showInfoWindow = true,
  }) async {
    final latitude = experience.latitude;
    final longitude = experience.longitude;

    if (latitude == null || longitude == null) return;

    final markerId = _markerIdFor(experience);

    setState(() {
      _selectedExperienceId = markerId;
    });

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(latitude, longitude), zoom: _locationZoom),
      ),
    );

    if (showInfoWindow) {
      await _mapController?.showMarkerInfoWindow(
        MarkerId('$markerId-selected'),
      );
    }
  }

  Future<void> _deleteImportedExperience(
    ExperienceCard experience,
    List<FoodCard> restaurants,
  ) async {
    setState(() {
      _importedCandidates.removeWhere(
        (candidate) =>
            _markerIdFor(candidate) == _markerIdFor(experience) ||
            (candidate.originalURL != null &&
                candidate.originalURL == experience.originalURL) ||
            (candidate.placeTitle != null &&
                candidate.placeTitle == experience.placeTitle),
      );
      if (_selectedExperienceId == _markerIdFor(experience)) {
        _selectedExperienceId = null;
      }
    });

    final restaurant = _restaurantForExperience(experience, restaurants);
    final restaurantId = restaurant?.id ?? experience.foodCardId;

    try {
      if (restaurantId != null && restaurantId.trim().isNotEmpty) {
        await RestaurantRepository().deleteRestaurant(restaurantId);
      }
      final experienceId = experience.id;
      if (_isImportedExperience(experience) &&
          experienceId != null &&
          experienceId.isNotEmpty &&
          !experienceId.startsWith('restaurant-')) {
        await ExperienceRepository().deleteExperience(experience);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported place removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove imported place: $error')),
      );
    }
  }

  Future<void> _moveToCurrentLocation({bool showErrors = true}) async {
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
    });

    try {
      final position = await getCurrentMapPosition();

      if (position == null) {
        if (!mounted) return;
        if (showErrors) {
          _showMapSnackBar(
            'Could not get current location. Check browser location permission for this localhost port.',
          );
        }
        return;
      }

      final target = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _center = target;
        _currentLocation = target;
        _canUseLocation = true;
      });

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: _locationZoom),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      if (showErrors) {
        _showMapSnackBar('Could not get current location: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _showMapSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedExperiences = context.watch<SavedViewModel>().experiences;
    return StreamBuilder<List<FoodCard>>(
      stream: RestaurantRepository().watchRestaurants(),
      builder: (context, snapshot) {
        return _buildMapScaffold(
          context,
          savedExperiences,
          snapshot.data ?? const <FoodCard>[],
        );
      },
    );
  }

  Widget _buildMapScaffold(
    BuildContext context,
    List<ExperienceCard> savedExperiences,
    List<FoodCard> restaurants,
  ) {
    final restaurantExperiences = restaurants
        .map(_experienceFromRestaurant)
        .where(
          (experience) =>
              experience.latitude != null && experience.longitude != null,
        )
        .toList();
    final importedExperiences = _mapExperiences(
      [
        ..._importedCandidates,
        ...restaurantExperiences.where((experience) => !experience.isDone),
      ],
    );
    final myPlaceExperiences = _sortMyPlaces(
      _mapExperiences([
        ...restaurantExperiences.where((experience) => experience.isDone),
      ]),
      restaurants,
    );
    final mapExperiences = _sheetMode == MapSheetMode.imported
        ? importedExperiences
        : myPlaceExperiences;

    final markers = _markersFor(mapExperiences);
    final circles = _circlesFor(mapExperiences);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: _locationZoom,
                ),
                myLocationEnabled: _canUseLocation,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: markers,
                circles: circles,
                style: _mapStyle,
                webGestureHandling: WebGestureHandling.greedy,
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: PointerInterceptor(
                  child: FloatingActionButton.small(
                    heroTag: 'map-settings',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: const Icon(Icons.settings_outlined),
                  ),
                ),
              ),
              RestaurantListSheet(
                controller: _sheetController,
                experiences: mapExperiences,
                mode: _sheetMode,
                myPlacesSortMode: _myPlacesSortMode,
                importedCount: importedExperiences.length,
                myPlacesCount: myPlaceExperiences.length,
                selectedExperienceId: _selectedExperienceId,
                markerIdFor: _markerIdFor,
                distanceLabelFor: _distanceLabelFor,
                hoursStatusFor: (experience) =>
                    _hoursStatusFor(experience, restaurants),
                onModeChanged: (mode) {
                  setState(() {
                    _sheetMode = mode;
                    _selectedExperienceId = null;
                  });
                },
                onSortModeChanged: (mode) {
                  setState(() {
                    _myPlacesSortMode = mode;
                    _selectedExperienceId = null;
                  });
                },
                onExperienceSelected: (experience) {
                  _selectExperience(experience, showInfoWindow: false);
                },
                onExperienceDetailRequested: (experience) {
                  // Opening the card detail should not move the map.
                },
                onVisitsTapped: (placeTitle) {
                  final query = Uri.encodeComponent(placeTitle);
                  context.go('/saved?q=$query');
                },
                onImportedDelete: (experience) =>
                    _deleteImportedExperience(experience, restaurants),
              ),
              AnimatedBuilder(
                animation: _sheetController,
                builder: (context, child) {
                  final sheetSize = _sheetController.isAttached
                      ? _sheetController.size
                      : RestaurantListSheet.initialSize;

                  final bottom =
                      constraints.maxHeight * sheetSize +
                      MediaQuery.of(context).padding.bottom +
                      16;

                  return Positioned(right: 16, bottom: bottom, child: child!);
                },
                child: PointerInterceptor(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'map-current-location',
                        onPressed: _isLocating ? null : _moveToCurrentLocation,
                        child: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton.small(
                        heroTag: 'map-import',
                        onPressed: _openImportDialog,
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
