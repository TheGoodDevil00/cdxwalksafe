import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/safety_zone.dart';

class SafetyZoneOverlay extends StatelessWidget {
  const SafetyZoneOverlay({
    super.key,
    required this.zones,
    this.isVisible = true,
  });

  final List<SafetyZone> zones;
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    final List<SafetyZone> dangerZones = zones
        .where((SafetyZone zone) => zone.safetyLevel != SafetyLevel.safe)
        .toList(growable: false);
    if (dangerZones.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Polygon> polygons = dangerZones
        .map(_buildPolygon)
        .toList(growable: false);
    final List<Marker> markers = _buildLabels(dangerZones);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: isVisible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: SizedBox.expand(
          child: Stack(
            children: <Widget>[
              PolygonLayer(polygons: polygons),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),
        ),
      ),
    );
  }

  Polygon _buildPolygon(SafetyZone zone) {
    final bool isRisky = zone.safetyLevel == SafetyLevel.risky;
    final Color fillColor = isRisky
        ? const Color(0xFFCF2C3A).withValues(alpha: 0.34)
        : const Color(0xFFE25A45).withValues(alpha: 0.20);
    final Color borderColor = isRisky
        ? const Color(0xFFC01C2F).withValues(alpha: 0.80)
        : const Color(0xFFD54D3C).withValues(alpha: 0.56);

    return Polygon(
      points: _buildZonePoints(zone),
      color: fillColor,
      borderColor: borderColor,
      borderStrokeWidth: isRisky ? 2.4 : 1.8,
    );
  }

  List<Marker> _buildLabels(List<SafetyZone> zones) {
    final List<SafetyZone> labels = zones
        .where((SafetyZone zone) => zone.safetyLevel == SafetyLevel.risky)
        .take(2)
        .toList(growable: false);
    if (labels.isEmpty && zones.isNotEmpty) {
      return <Marker>[_buildLabelMarker(zones.first)];
    }

    return labels.map(_buildLabelMarker).toList(growable: false);
  }

  Marker _buildLabelMarker(SafetyZone zone) {
    return Marker(
      point: LatLng(zone.latitude, zone.longitude),
      width: 110,
      height: 60,
      child: IgnorePointer(
        child: Center(
          child: Text(
            'DANGER\nZONES',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              height: 1.05,
              shadows: <Shadow>[
                Shadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<LatLng> _buildZonePoints(SafetyZone zone) {
    final bool isRisky = zone.safetyLevel == SafetyLevel.risky;
    final List<double> multipliers = isRisky
        ? const <double>[1.28, 0.98, 1.16, 0.90, 1.22, 0.96]
        : const <double>[1.10, 0.86, 1.02, 0.88, 1.06, 0.84];
    final double angleStep = 360 / multipliers.length;
    final double baseRadius = zone.radiusMeters * (isRisky ? 1.48 : 1.26);
    final int seed = zone.id.runes.fold<int>(
      0,
      (int value, int rune) => value + rune,
    );
    final double startAngle = (seed % 360).toDouble();

    return List<LatLng>.generate(multipliers.length, (int index) {
      final double angle = startAngle + (angleStep * index);
      return _offsetPoint(
        zone.latitude,
        zone.longitude,
        baseRadius * multipliers[index],
        angle,
      );
    }, growable: false);
  }

  LatLng _offsetPoint(
    double latitude,
    double longitude,
    double distanceMeters,
    double bearingDegrees,
  ) {
    const double earthRadiusMeters = 6378137;
    final double angularDistance = distanceMeters / earthRadiusMeters;
    final double bearing = _degreesToRadians(bearingDegrees);
    final double lat1 = _degreesToRadians(latitude);
    final double lon1 = _degreesToRadians(longitude);

    final double lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final double lon2 =
        lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(_radiansToDegrees(lat2), _radiansToDegrees(lon2));
  }

  double _degreesToRadians(double value) => value * (math.pi / 180);

  double _radiansToDegrees(double value) => value * (180 / math.pi);
}
