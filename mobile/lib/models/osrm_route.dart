class OsrmRoute {
  const OsrmRoute({required this.geometry, required this.distanceMeters});

  final String geometry;
  final double distanceMeters;

  // Parses geometry and route distance from OSRM response.
  factory OsrmRoute.fromJson(Map<String, dynamic> json) {
    final Object? geometry = json['geometry'];
    if (geometry is! String || geometry.isEmpty) {
      throw const FormatException('Missing route geometry in OSRM response.');
    }

    final Object? distance = json['distance'];
    return OsrmRoute(
      geometry: geometry,
      distanceMeters: distance is num ? distance.toDouble() : 0,
    );
  }
}
