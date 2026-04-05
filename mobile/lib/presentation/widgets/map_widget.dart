import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_config.dart';

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
      children: <Widget>[
        TileLayer(
          urlTemplate:
              'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png'
              '?key=${AppConfig.maptilerApiKey}',
          userAgentPackageName: 'com.safewalk.mobile',
          tileDimension: 256,
        ),
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: <Polyline>[
              Polyline(
                points: routePoints,
                strokeWidth: 4.0,
                color: routeColor,
              ),
            ],
          ),
        RichAttributionWidget(
          attributions: <SourceAttribution>[
            TextSourceAttribution('MapTiler'),
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
