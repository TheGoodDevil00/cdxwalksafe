import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SafeWalkMap extends StatelessWidget {
  final List<LatLng> routePoints;
  final Color routeColor;

  const SafeWalkMap({
    super.key,
    this.routePoints = const [],
    this.routeColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: const LatLng(51.509364, -0.128928),
        initialZoom: 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.safewalk.app',
        ),
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 4.0,
                color: routeColor,
              ),
            ],
          ),
      ],
    );
  }
}
