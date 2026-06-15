/// Builds Google Maps **directions** deep links (the navigation page), not just
/// a place pin. The starting point is intentionally left unset: when `origin` is
/// omitted, Google Maps defaults the route's start to the user's current
/// location — exactly the "navigate from where I am now" behaviour we want.
///
/// Mirrors the URL the backend `searchSpots` skill emits for nearby spots, so
/// tapping a card or an in-chat link both land on the same navigation page.
library;

/// A `https://www.google.com/maps/dir/` directions URL to [title] / [placeId] /
/// coordinates / [address]. Returns null when there's nothing to route to.
///
/// `destination_place_id` is added only for a real Google Place ID (`ChIJ…`),
/// which pins the exact place; otherwise Maps resolves the `destination` text.
Uri? googleMapsDirectionsUri({
  String? placeId,
  String? title,
  double? latitude,
  double? longitude,
  String? address,
  String travelMode = 'walking',
}) {
  final name = title?.trim();
  final addr = address?.trim();
  final destination = (name != null && name.isNotEmpty)
      ? name
      : (latitude != null && longitude != null)
          ? '$latitude,$longitude'
          : (addr != null && addr.isNotEmpty)
              ? addr
              : null;
  if (destination == null) return null;

  final params = <String, String>{
    'api': '1',
    'destination': destination,
    'travelmode': travelMode,
  };
  final id = placeId?.trim();
  if (id != null && id.startsWith('ChIJ')) {
    params['destination_place_id'] = id;
  }
  return Uri.https('www.google.com', '/maps/dir/', params);
}
