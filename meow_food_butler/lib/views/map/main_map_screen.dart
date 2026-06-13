import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:meow_food_butler/models/experience_card.dart';
import 'package:meow_food_butler/services/current_map_position.dart';
import 'package:meow_food_butler/view_models/instagram_import_vm.dart';
import 'package:meow_food_butler/view_models/saved_view_model.dart';
import 'package:meow_food_butler/views/map/widgets/import_dialog.dart';
import 'package:meow_food_butler/views/map/widgets/restaurant_list_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  static const LatLng _defaultCenter = LatLng(25.032969, 121.542598);
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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  LatLng _center = _defaultCenter;
  LatLng? _currentLocation;
  String? _selectedExperienceId;
  bool _canUseLocation = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  List<ExperienceCard> _mapExperiences(List<ExperienceCard> experiences) {
    final deduped = <String, ExperienceCard>{};

    for (final experience in experiences) {
      if (experience.latitude == null || experience.longitude == null) {
        continue;
      }

      final key =
          experience.placeId ??
          experience.foodCardId ??
          '${experience.placeTitle ?? 'unknown'}-${experience.latitude}-${experience.longitude}';
      final current = deduped[key];
      if (current == null ||
          experience.createdTime.compareTo(current.createdTime) > 0) {
        deduped[key] = experience;
      }
    }

    return deduped.values.toList()
      ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
  }

  // NOTE: 為了避免 async 產生 marker/icon 造成結構複雜，
  // 目前先把自製圓點方法整段註解掉。
  // Future<BitmapDescriptor> _buildCurrentLocationDescriptor() async {
  //   // Web/CPU rendering path: generate a bitmap with a blue dot + ring.
  //   // If it fails for any reason, fall back to default hue marker.
  //   try {
  //     const int size = 96;
  //     final ui.PictureRecorder recorder = ui.PictureRecorder();
  //     final Canvas canvas = Canvas(recorder);
  //
  //     final double radius = size * 0.16;
  //     final Offset center = Offset(size / 2.0, size / 2.0);
  //
  //     final ringPaint = Paint()
  //       ..color = Colors.lightBlueAccent.withOpacity(0.35)
  //       ..style = PaintingStyle.stroke
  //       ..strokeWidth = 10;
  //     canvas.drawCircle(center, radius + 10, ringPaint);
  //
  //     final glowPaint = Paint()
  //       ..color = Colors.lightBlue.withOpacity(0.35)
  //       ..style = PaintingStyle.fill;
  //     canvas.drawCircle(center, radius + 6, glowPaint);
  //
  //     final dotPaint = Paint()..color = Colors.blueAccent;
  //     canvas.drawCircle(center, radius, dotPaint);
  //
  //     final picture = recorder.endRecording();
  //     final img = await picture.toImage(size, size);
  //     final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  //     final pngBytes = byteData!.buffer.asUint8List();
  //     return BitmapDescriptor.fromBytes(pngBytes);
  //   } catch (_) {
  //     return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  //   }
  // }

  Future<Set<Marker>> _markersForAsync(List<ExperienceCard> experiences) async {
    final markers = <Marker>{};

    for (final experience in experiences) {
      final markerId = _markerIdFor(experience);
      final selected = markerId == _selectedExperienceId;
      final position = LatLng(experience.latitude!, experience.longitude!);

      markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          zIndexInt: selected ? 10 : 0,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            selected ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: experience.placeTitle ?? 'Unnamed restaurant',
            snippet: experience.placeAddress,
          ),
          onTap: () => _selectExperience(experience, showInfoWindow: false),
        ),
      );
    }

    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      // 自製 icon 方法目前已註解，暫時先用預設藍色 marker。
      final icon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
      markers.add(
        Marker(
          markerId: const MarkerId('current-location'),
          position: currentLocation,
          zIndexInt: 50,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          draggable: false,
          visible: true,
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    }

    return markers;
  }

  Set<Marker> _markersFor(List<ExperienceCard> experiences) {
    final markers = experiences.map((experience) {
      final markerId = _markerIdFor(experience);
      final selected = markerId == _selectedExperienceId;
      final position = LatLng(experience.latitude!, experience.longitude!);

      return Marker(
        markerId: MarkerId(markerId),
        position: position,
        zIndexInt: selected ? 10 : 0,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          selected ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(
          title: experience.placeTitle ?? 'Unnamed restaurant',
          snippet: experience.placeAddress,
        ),
        onTap: () => _selectExperience(experience, showInfoWindow: false),
      );
    }).toSet();

    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current-location'),
          position: currentLocation,
          zIndexInt: 50,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          anchor: const Offset(0.5, 0.5),
          draggable: false,
          visible: true,
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    }

    return markers;
  }

  String _markerIdFor(ExperienceCard experience) {
    return experience.id ??
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
    setState(() => _selectedExperienceId = markerId);

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(latitude, longitude), zoom: 16),
      ),
    );

    if (showInfoWindow) {
      await _mapController?.showMarkerInfoWindow(MarkerId(markerId));
    }
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isLocating) return;

    setState(() => _isLocating = true);

    try {
      final position = await getCurrentMapPosition();
      if (position == null) return;
      final target = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _center = target;
        _currentLocation = target;
        _canUseLocation = true;
      });

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get current location: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _openImportDialog() async {
    final newExperience = await showDialog<ExperienceCard>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangeNotifierProvider(
        create: (_) => InstagramImportViewModel(),
        child: const ImportInstagramDialog(),
      ),
    );

    if (newExperience != null && mounted) {
      await _selectExperience(newExperience);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedExperiences = context.watch<SavedViewModel>().experiences;
    final mapExperiences = _mapExperiences(savedExperiences);
    final markers = _markersFor(mapExperiences);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: 15,
                ),
                myLocationEnabled: _canUseLocation,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: markers,
                style: _mapStyle,
                webGestureHandling: WebGestureHandling.greedy,
              ),
              RestaurantListSheet(
                controller: _sheetController,
                experiences: mapExperiences,
                selectedExperienceId: _selectedExperienceId,
                markerIdFor: _markerIdFor,
                onExperienceSelected: _selectExperience,
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
