import 'package:latlong2/latlong.dart';

import '../models/incident_report.dart';
import '../models/route_segment_safety.dart';
import 'incident_storage_service.dart';

class SafetyScoreService {
  SafetyScoreService({IncidentStorageService? incidentStorageService})
    : _incidentStorageService =
          incidentStorageService ?? IncidentStorageService();

  static const double _incidentRadiusMeters = 180;

  // Factor weights for the final safety penalty.
  static const double _incidentWeight = 0.45;
  static const double _timeWeight = 0.20;
  static const double _lightingWeight = 0.20;
  static const double _crowdWeight = 0.15;

  final IncidentStorageService _incidentStorageService;
  final Distance _distance = const Distance();

  Future<List<IncidentReport>> loadIncidentReports() async {
    try {
      return await _incidentStorageService.getReports();
    } catch (_) {
      // Fallback to an empty list if local report storage cannot be read.
      return <IncidentReport>[];
    }
  }

  Future<List<RouteSegmentSafety>> scoreRouteSegments(
    List<LatLng> routePoints, {
    List<IncidentReport>? reports,
    DateTime? evaluationTime,
  }) async {
    if (routePoints.length < 2) {
      return <RouteSegmentSafety>[];
    }

    final List<IncidentReport> incidentReports =
        reports ?? await loadIncidentReports();
    final DateTime now = evaluationTime ?? DateTime.now();

    // Score each edge between two consecutive route coordinates.
    final List<RouteSegmentSafety> segments = <RouteSegmentSafety>[];
    for (int i = 0; i < routePoints.length - 1; i++) {
      final LatLng start = routePoints[i];
      final LatLng end = routePoints[i + 1];

      final double distanceMeters = _distance(start, end);
      if (distanceMeters <= 0) {
        continue;
      }

      final LatLng midpoint = _midpoint(start, end);
      final double incidentRisk = _estimateIncidentRisk(
        midpoint,
        incidentReports,
        now,
      );
      final double timeOfDayRisk = _estimateTimeOfDayRisk(now.hour);
      final double lightingLevel = _estimateLightingLevel(
        midpoint,
        incidentReports,
        now.hour,
      );
      final double crowdDensity = _estimateCrowdDensity(
        midpoint,
        incidentReports,
        now.hour,
      );

      final double lightingRisk = (100 - lightingLevel) / 100;
      final double crowdRisk = (100 - crowdDensity) / 100;

      // Combine all factors to derive a segment safety score (0-100).
      final double combinedPenalty = _clamp01(
        (_incidentWeight * incidentRisk) +
            (_timeWeight * timeOfDayRisk) +
            (_lightingWeight * lightingRisk) +
            (_crowdWeight * crowdRisk),
      );

      final double safetyScore = _clampScore((1 - combinedPenalty) * 100);

      // Requested risk function: risk = distance_weight + safety_penalty
      final double distanceWeight = distanceMeters / 1000;
      final double safetyPenalty = (100 - safetyScore) / 100;
      final double risk = distanceWeight + safetyPenalty;

      segments.add(
        RouteSegmentSafety(
          start: start,
          end: end,
          distanceMeters: distanceMeters,
          safetyScore: safetyScore,
          incidentRisk: incidentRisk,
          timeOfDayRisk: timeOfDayRisk,
          lightingLevel: lightingLevel,
          crowdDensity: crowdDensity,
          distanceWeight: distanceWeight,
          safetyPenalty: safetyPenalty,
          risk: risk,
        ),
      );
    }

    return segments;
  }

  double calculateRouteRisk(List<RouteSegmentSafety> segments) {
    return segments.fold<double>(
      0,
      (double sum, RouteSegmentSafety segment) => sum + segment.risk,
    );
  }

  double calculateAverageSafetyScore(List<RouteSegmentSafety> segments) {
    if (segments.isEmpty) {
      return 0;
    }

    final double totalDistance = segments.fold<double>(
      0,
      (double sum, RouteSegmentSafety segment) => sum + segment.distanceMeters,
    );
    if (totalDistance <= 0) {
      final double mean =
          segments.fold<double>(
            0,
            (double sum, RouteSegmentSafety segment) =>
                sum + segment.safetyScore,
          ) /
          segments.length;
      return _clampScore(mean);
    }

    final double weightedSafety = segments.fold<double>(
      0,
      (double sum, RouteSegmentSafety segment) =>
          sum + (segment.safetyScore * segment.distanceMeters),
    );
    return _clampScore(weightedSafety / totalDistance);
  }

  LatLng _midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  double _estimateIncidentRisk(
    LatLng midpoint,
    List<IncidentReport> reports,
    DateTime now,
  ) {
    double weightedIncidents = 0;

    for (final IncidentReport report in reports) {
      final LatLng reportPoint = LatLng(report.latitude, report.longitude);
      final double distanceMeters = _distance(midpoint, reportPoint);
      if (distanceMeters > _incidentRadiusMeters) {
        continue;
      }

      final double distanceFactor =
          1 - (distanceMeters / _incidentRadiusMeters);
      final double severityFactor = _incidentSeverity(report.incidentType);
      final double recencyFactor = _recencyWeight(report.createdAtIso, now);

      weightedIncidents += distanceFactor * severityFactor * recencyFactor;
    }

    return _clamp01(weightedIncidents / 3);
  }

  double _estimateTimeOfDayRisk(int hour) {
    if (hour >= 22 || hour <= 4) {
      return 0.95;
    }
    if (hour == 5 || hour == 6) {
      return 0.65;
    }
    if (hour >= 19 && hour <= 21) {
      return 0.55;
    }
    return 0.20;
  }

  double _estimateLightingLevel(
    LatLng midpoint,
    List<IncidentReport> reports,
    int hour,
  ) {
    double baseLighting;
    if (hour >= 7 && hour <= 17) {
      baseLighting = 90;
    } else if (hour == 6 || hour == 18) {
      baseLighting = 70;
    } else if (hour >= 19 && hour <= 21) {
      baseLighting = 50;
    } else {
      baseLighting = 35;
    }

    final int poorLightingReports = _countNearbyIncidents(
      midpoint,
      reports,
      radiusMeters: 220,
      incidentFilter: (IncidentReport report) =>
          report.incidentType.toLowerCase().contains('lighting'),
    );

    final int nearbyIncidents = _countNearbyIncidents(
      midpoint,
      reports,
      radiusMeters: _incidentRadiusMeters,
    );

    final double lightingPenalty =
        (poorLightingReports * 12) + (nearbyIncidents * 2);
    return _clampScore(baseLighting - lightingPenalty);
  }

  double _estimateCrowdDensity(
    LatLng midpoint,
    List<IncidentReport> reports,
    int hour,
  ) {
    double baseDensity;
    if ((hour >= 7 && hour <= 10) || (hour >= 17 && hour <= 20)) {
      baseDensity = 78;
    } else if (hour >= 11 && hour <= 16) {
      baseDensity = 65;
    } else if (hour >= 21 && hour <= 23) {
      baseDensity = 45;
    } else {
      baseDensity = 24;
    }

    final int nearbyIncidents = _countNearbyIncidents(
      midpoint,
      reports,
      radiusMeters: _incidentRadiusMeters,
    );

    final double incidentPenalty = (nearbyIncidents * 6).toDouble();
    return _clampScore(baseDensity - incidentPenalty);
  }

  int _countNearbyIncidents(
    LatLng midpoint,
    List<IncidentReport> reports, {
    required double radiusMeters,
    bool Function(IncidentReport report)? incidentFilter,
  }) {
    int count = 0;
    for (final IncidentReport report in reports) {
      if (incidentFilter != null && !incidentFilter(report)) {
        continue;
      }

      final double distanceMeters = _distance(
        midpoint,
        LatLng(report.latitude, report.longitude),
      );
      if (distanceMeters <= radiusMeters) {
        count++;
      }
    }
    return count;
  }

  double _incidentSeverity(String incidentType) {
    final String normalized = incidentType.toLowerCase();
    if (normalized.contains('stalking') || normalized.contains('harassment')) {
      return 1.0;
    }
    if (normalized.contains('suspicious')) {
      return 0.85;
    }
    if (normalized.contains('infrastructure')) {
      return 0.70;
    }
    if (normalized.contains('lighting')) {
      return 0.65;
    }
    return 0.75;
  }

  double _recencyWeight(String createdAtIso, DateTime now) {
    final DateTime? createdAt = DateTime.tryParse(createdAtIso);
    if (createdAt == null) {
      return 0.50;
    }

    final double daysAgo = now.difference(createdAt).inHours / 24;
    final double normalizedDays = daysAgo < 0 ? 0 : daysAgo;
    if (normalizedDays <= 1) {
      return 1.0;
    }
    if (normalizedDays <= 7) {
      return 0.85;
    }
    if (normalizedDays <= 30) {
      return 0.65;
    }
    if (normalizedDays <= 90) {
      return 0.45;
    }
    return 0.25;
  }

  double _clamp01(double value) {
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  double _clampScore(double value) {
    if (value < 0) {
      return 0;
    }
    if (value > 100) {
      return 100;
    }
    return value;
  }
}
