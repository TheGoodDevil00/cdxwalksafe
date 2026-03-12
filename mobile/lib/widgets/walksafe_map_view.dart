import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class WalkSafeMapView extends StatelessWidget {
  const WalkSafeMapView({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
    this.mapController,
    this.markers = const <Marker>[],
    this.safetyOverlays = const <CircleMarker>[],
    this.routePolylines = const <Polyline>[],
    this.onTap,
    this.onPositionChanged,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final MapController? mapController;
  final List<Marker> markers;
  final List<CircleMarker> safetyOverlays;
  final List<Polyline> routePolylines;
  final void Function(LatLng point)? onTap;
  final void Function(LatLng center)? onPositionChanged;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        onTap: (_, LatLng point) => onTap?.call(point),
        onPositionChanged: (MapCamera camera, bool hasGesture) {
          onPositionChanged?.call(camera.center);
        },
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.safewalk.mobile',
        ),
        if (safetyOverlays.isNotEmpty) CircleLayer(circles: safetyOverlays),
        if (routePolylines.isNotEmpty) PolylineLayer(polylines: routePolylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}
