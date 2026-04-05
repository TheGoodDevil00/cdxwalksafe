import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class NavigationMath {
  NavigationMath._();

  static const double _earthRadiusMeters = 6371000;
  static const Distance _distance = Distance();

  static double? normalizeHeading(double? heading) {
    if (heading == null || !heading.isFinite) {
      return null;
    }

    final double normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double headingDeltaDegrees(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  static double blendHeading(
    double previous,
    double next, {
    double factor = 0.24,
  }) {
    final double normalizedPrevious = normalizeHeading(previous) ?? 0;
    final double normalizedNext = normalizeHeading(next) ?? normalizedPrevious;
    final double clampedFactor = factor.clamp(0.0, 1.0);
    final double delta = headingDeltaDegrees(
      normalizedPrevious,
      normalizedNext,
    );
    return normalizeHeading(normalizedPrevious + (delta * clampedFactor)) ??
        normalizedNext;
  }

  static double distanceToPolylineMeters(
    LatLng point,
    List<LatLng> routePoints,
  ) {
    if (routePoints.isEmpty) {
      return double.infinity;
    }

    if (routePoints.length == 1) {
      return _distance(point, routePoints.first);
    }

    double minDistance = double.infinity;
    for (int index = 0; index < routePoints.length - 1; index++) {
      final double segmentDistance = _distancePointToSegmentMeters(
        point,
        routePoints[index],
        routePoints[index + 1],
      );
      if (segmentDistance < minDistance) {
        minDistance = segmentDistance;
      }
    }

    return minDistance;
  }

  static double rerouteThresholdMeters(
    double accuracyMeters, {
    double minimum = 40,
    double maximum = 80,
  }) {
    final double safeAccuracy = accuracyMeters.isFinite && accuracyMeters > 0
        ? accuracyMeters
        : minimum;
    final double scaled = safeAccuracy * 2.2;
    return math.max(minimum, math.min(maximum, scaled));
  }

  static double _distancePointToSegmentMeters(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final _ProjectedPoint projectedStart = _projectRelativeTo(point, start);
    final _ProjectedPoint projectedEnd = _projectRelativeTo(point, end);
    final double dx = projectedEnd.x - projectedStart.x;
    final double dy = projectedEnd.y - projectedStart.y;
    final double segmentLengthSquared = (dx * dx) + (dy * dy);

    if (segmentLengthSquared <= 0) {
      return math.sqrt(
        (projectedStart.x * projectedStart.x) +
            (projectedStart.y * projectedStart.y),
      );
    }

    final double projection =
        -((projectedStart.x * dx) + (projectedStart.y * dy)) /
        segmentLengthSquared;
    final double t = projection.clamp(0.0, 1.0);
    final double closestX = projectedStart.x + (dx * t);
    final double closestY = projectedStart.y + (dy * t);
    return math.sqrt((closestX * closestX) + (closestY * closestY));
  }

  static _ProjectedPoint _projectRelativeTo(LatLng origin, LatLng point) {
    final double originLatitudeRadians = _degreesToRadians(origin.latitude);
    final double deltaLatitudeRadians = _degreesToRadians(
      point.latitude - origin.latitude,
    );
    final double deltaLongitudeRadians = _degreesToRadians(
      point.longitude - origin.longitude,
    );

    return _ProjectedPoint(
      x:
          deltaLongitudeRadians *
          math.cos(originLatitudeRadians) *
          _earthRadiusMeters,
      y: deltaLatitudeRadians * _earthRadiusMeters,
    );
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}

class _ProjectedPoint {
  const _ProjectedPoint({required this.x, required this.y});

  final double x;
  final double y;
}
