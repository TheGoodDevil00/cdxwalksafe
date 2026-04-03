import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/route_segment_safety.dart';
import '../models/scored_route.dart';

class RoutingService {
  RoutingService({http.Client? client, String? apiBaseUrl})
    : _client = client ?? http.Client(),
      _apiBaseUrl = apiBaseUrl ?? _baseUrl;

  static const String _baseUrl = String.fromEnvironment('API_BASE_URL');
  static const Duration _requestTimeout = Duration(seconds: 12);

  final http.Client _client;
  final String _apiBaseUrl;
  final Distance _distance = const Distance();

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    return _fetchRoutePoints(start, end);
  }

  Future<ScoredRoute?> getSafestRoute(LatLng start, LatLng end) async {
    final List<LatLng> routePoints = await _fetchRoutePoints(start, end);
    if (routePoints.length < 2) {
      return null;
    }

    final Map<String, dynamic>? scorePayload =
        await _fetchRouteRisk(routePoints) ??
        await _fetchRouteSafety(start, end);
    final double? safetyScore = _asDouble(scorePayload?['safety_score']);
    if (safetyScore == null) {
      return null;
    }

    final double totalDistanceMeters =
        (_asDouble(scorePayload?['distance_km']) ?? 0) > 0
        ? (_asDouble(scorePayload?['distance_km']) ?? 0) * 1000
        : _polylineDistanceMeters(routePoints);
    final List<RouteSegmentSafety> segments = _parseRouteSegments(
      scorePayload?['segments'],
      fallbackSafetyScore: safetyScore,
    );

    return ScoredRoute(
      points: routePoints,
      segments: segments,
      totalDistanceMeters: totalDistanceMeters,
      averageSafetyScore: safetyScore,
      totalRisk: 100 - safetyScore,
      warning: scorePayload?['warning']?.toString(),
    );
  }

  Future<List<LatLng>> _fetchRoutePoints(LatLng start, LatLng end) async {
    final Uri uri = Uri.parse('$_apiBaseUrl/route').replace(
      queryParameters: <String, String>{
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': end.latitude.toString(),
        'end_lon': end.longitude.toString(),
      },
    );

    final http.Response? response = await _safeGet(uri);
    if (response == null || response.statusCode != 200) {
      return <LatLng>[];
    }

    final Map<String, dynamic>? payload = _tryParseJsonMap(response.body);
    if (payload == null) {
      return <LatLng>[];
    }

    final Object? safest = payload['safest'];
    if (safest is! List) {
      return <LatLng>[];
    }

    final List<LatLng> points = <LatLng>[];
    for (final dynamic item in safest) {
      final Map<String, dynamic>? point = _coerceMap(item);
      if (point == null) {
        continue;
      }
      final double? lat = _asDouble(point['lat']);
      final double? lon = _asDouble(point['lon']);
      if (lat == null || lon == null) {
        continue;
      }
      points.add(LatLng(lat, lon));
    }
    return points;
  }

  Future<Map<String, dynamic>?> _fetchRouteSafety(
    LatLng start,
    LatLng end,
  ) async {
    final Uri uri = Uri.parse('$_apiBaseUrl/route-safe').replace(
      queryParameters: <String, String>{
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': end.latitude.toString(),
        'end_lon': end.longitude.toString(),
      },
    );

    final http.Response? response = await _safeGet(uri);
    if (response == null || response.statusCode != 200) {
      return null;
    }
    return _tryParseJsonMap(response.body);
  }

  Future<Map<String, dynamic>?> _fetchRouteRisk(
    List<LatLng> coordinates,
  ) async {
    final Uri uri = Uri.parse('$_apiBaseUrl/route/risk');

    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'coordinates': coordinates
                  .map(
                    (LatLng point) => <String, double>{
                      'lat': point.latitude,
                      'lon': point.longitude,
                    },
                  )
                  .toList(growable: false),
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      return _tryParseJsonMap(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_requestTimeout);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _tryParseJsonMap(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      return _coerceMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _coerceMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((dynamic key, dynamic v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  List<RouteSegmentSafety> _parseRouteSegments(
    Object? rawSegments, {
    required double fallbackSafetyScore,
  }) {
    if (rawSegments is! List) {
      return const <RouteSegmentSafety>[];
    }

    final List<RouteSegmentSafety> segments = <RouteSegmentSafety>[];
    for (final dynamic item in rawSegments) {
      final Map<String, dynamic>? segment = _coerceMap(item);
      final Map<String, dynamic>? start = _coerceMap(segment?['start']);
      final Map<String, dynamic>? end = _coerceMap(segment?['end']);
      if (segment == null || start == null || end == null) {
        continue;
      }

      final double? startLat = _asDouble(start['lat']);
      final double? startLon = _asDouble(start['lon']);
      final double? endLat = _asDouble(end['lat']);
      final double? endLon = _asDouble(end['lon']);
      if (startLat == null ||
          startLon == null ||
          endLat == null ||
          endLon == null) {
        continue;
      }

      final bool matched = _asBool(segment['matched']);
      final Map<String, dynamic>? zone = _coerceMap(segment['zone']);
      final double? baseSafetyScore = _asDouble(segment['base_safety_score']);
      final double safetyScore =
          _asDouble(segment['safety_score']) ??
          baseSafetyScore ??
          fallbackSafetyScore;
      final double incidentWeight = _asDouble(segment['incident_weight']) ?? 0;
      final double incidentPenalty =
          _asDouble(segment['incident_penalty']) ?? 0;
      final double? zoneRiskScore = _asDouble(zone?['risk_score']);
      final double lightingHeuristic = _parseLightingHeuristic(
        segment['lighting'],
      );

      segments.add(
        RouteSegmentSafety(
          start: LatLng(startLat, startLon),
          end: LatLng(endLat, endLon),
          distanceMeters: _asDouble(segment['length_m']) ?? 0,
          safetyScore: safetyScore,
          incidentRisk: incidentWeight,
          timeOfDayRisk: 0,
          lightingLevel: lightingHeuristic,
          crowdDensity: zoneRiskScore ?? 0,
          distanceWeight: _asDouble(segment['match_distance_m']) ?? 0,
          safetyPenalty: incidentPenalty,
          risk: (100 - safetyScore).clamp(0, 100).toDouble(),
          segmentId: segment['road_segment_id']?.toString(),
          safetyLevel: _deriveSafetyLevel(
            safetyScore: safetyScore,
            zoneRiskLevel: zone?['risk_level']?.toString(),
            matched: matched,
          ),
          baseSafetyScore: baseSafetyScore,
          incidentDensity: _asDouble(segment['incident_count']),
          lightingHeuristic: lightingHeuristic,
          distanceToQuery: _asDouble(segment['match_distance_m']),
        ),
      );
    }

    return segments;
  }

  double _parseLightingHeuristic(Object? value) {
    final double? numericValue = _asDouble(value);
    if (numericValue != null) {
      return numericValue;
    }
    if (value is! String) {
      return 0;
    }

    switch (value.trim().toLowerCase()) {
      case 'good':
      case 'bright':
      case 'well_lit':
      case 'well-lit':
        return 1;
      case 'moderate':
      case 'fair':
        return 0.6;
      case 'poor':
      case 'dim':
      case 'low':
        return 0.25;
      default:
        return 0;
    }
  }

  String _deriveSafetyLevel({
    required double safetyScore,
    required bool matched,
    String? zoneRiskLevel,
  }) {
    if (!matched) {
      return 'UNKNOWN';
    }

    final String normalizedZoneLevel = (zoneRiskLevel ?? '')
        .trim()
        .toUpperCase();
    if (normalizedZoneLevel == 'SAFE' ||
        normalizedZoneLevel == 'CAUTIOUS' ||
        normalizedZoneLevel == 'RISKY') {
      return normalizedZoneLevel;
    }

    if (safetyScore < 40) {
      return 'RISKY';
    }
    if (safetyScore < 70) {
      return 'CAUTIOUS';
    }
    return 'SAFE';
  }

  double _polylineDistanceMeters(List<LatLng> points) {
    if (points.length < 2) {
      return 0;
    }

    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _distance(points[i], points[i + 1]);
    }
    return total;
  }
}
