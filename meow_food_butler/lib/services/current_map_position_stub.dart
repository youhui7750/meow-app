class CurrentMapPosition {
  final double latitude;
  final double longitude;

  const CurrentMapPosition({required this.latitude, required this.longitude});
}

Future<CurrentMapPosition?> getCurrentMapPosition() async {
  return null;
}
