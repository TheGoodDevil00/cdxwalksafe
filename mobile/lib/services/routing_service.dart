import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:polyline_codec/polyline_codec.dart';

import '../models/incident_report.dart';
import '../models/osrm_route.dart';
import '../models/route_segment_safety.dart';
import '../models/scored_route.dart';
import 'safety_score_service.dart';

class RoutingService {
  RoutingService({
    SafetyScoreService? safetyScoreService,
    http.Client? client,
    String? riskApiBaseUrl,
  }) : _safetyScoreService = safetyScoreService ?? SafetyScoreService(),
       _client = client ?? http.Client(),
       _riskApiBaseUrl =
           riskApiBaseUrl ??
           const String.fromEnvironment(
             'ROUTING_API_BASE_URL',
             defaultValue: 'http://127.0.0.1:8000/api/v1',
           );

  static const String _osrmBaseUrl = 'https://router.project-osrm.org';
  static const Duration _requestTimeout = Duration(seconds: 12);

  final SafetyScoreService _safetyScoreService;
  final http.Client _client;
  final String _riskApiBaseUrl;
  final Distance _distance = const Distance();

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final ScoredRoute? safestRoute = await getSafestRoute(start, end);
    return safestRoute?.points ?? <LatLng>[];
  }

  Future<ScoredRoute?> getSafestRoute(LatLng start, LatLng end) async {
    // Preferred path: backend orchestrates OSRM alternatives + risk ranking.
    final ScoredRoute? backendConsolidatedRoute = await _fetchRouteSafe(
      start,
      end,
    );
    if (backendConsolidatedRoute != null) {
      return backendConsolidatedRoute;
    }

    // Fallback path: mobile fetches OSRM alternatives and backend scores each.
    // Step 1: Build OSRM walking URL and request alternative candidates.
    final Uri uri = Uri.parse(
      '$_osrmBaseUrl/route/v1/foot/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=full&geometries=polyline&alternatives=true&steps=false',
    );

    // Step 2: Call the OSRM public API.
    final http.Response? response = await _safeGet(uri);
    if (response == null || response.statusCode != 200) {
      return null;
    }

    // Step 3: Parse candidate routes from the OSRM payload.
    final Map<String, dynamic>? payload = _tryParseJsonMap(response.body);
    if (payload == null) {
      return null;
    }

    final Object? code = payload['code'];
    if (code != 'Ok') {
      return null;
    }

    final List<dynamic>? routeObjects = payload['routes'] as List<dynamic>?;
    if (routeObjects == null || routeObjects.isEmpty) {
      return null;
    }

    // Step 4: Score each route with backend risk API. If unreachable, fallback.
    List<IncidentReport>? incidentReports;
    final DateTime evaluationTime = DateTime.now();
    final List<ScoredRoute> scoredRoutes = <ScoredRoute>[];

    for (final dynamic routeObject in routeObjects) {
      final Map<String, dynamic>? routeJson = _coerceMap(routeObject);
      if (routeJson == null) {
        continue;
      }

      final OsrmRoute route;
      try {
        route = OsrmRoute.fromJson(routeJson);
      } catch (_) {
        continue;
      }

      final List<LatLng> routePoints = _decodePolyline(route.geometry);
      if (routePoints.length < 2) {
        continue;
      }

      final double fallbackDistance = route.distanceMeters > 0
          ? route.distanceMeters
          : _polylineDistanceMeters(routePoints);

      ScoredRoute? scoredRoute = await _scoreRouteViaBackend(
        routePoints,
        fallbackDistanceMeters: fallbackDistance,
      );

      if (scoredRoute == null) {
        incidentReports ??= await _safeLoadIncidentReports();
        scoredRoute = await _scoreRouteViaFallback(
          routePoints,
          reports: incidentReports,
          evaluationTime: evaluationTime,
          fallbackDistanceMeters: fallbackDistance,
        );
      }

      if (scoredRoute != null) {
        scoredRoutes.add(scoredRoute);
      }
    }

    if (scoredRoutes.isEmpty) {
      return null;
    }

    // Step 5: Select the route with minimum risk (distance + safety penalty).
    scoredRoutes.sort((ScoredRoute a, ScoredRoute b) {
      final int riskOrder = a.totalRisk.compareTo(b.totalRisk);
      if (riskOrder != 0) {
        return riskOrder;
      }
      return a.totalDistanceMeters.compareTo(b.totalDistanceMeters);
    });

    return scoredRoutes.first;
  }

  Future<ScoredRoute?> _fetchRouteSafe(LatLng start, LatLng end) async {
    final Uri uri = Uri.parse('$_riskApiBaseUrl/route-safe').replace(
      queryParameters: <String, String>{
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': end.latitude.toString(),
        'end_lon': end.longitude.toString(),
        'alternatives': '3',
      },
    );

    final http.Response? response = await _safeGet(uri);
    if (response == null || response.statusCode != 200) {
      return null;
    }

    final Map<String, dynamic>? payload = _tryParseJsonMap(response.body);
    if (payload == null) {
      return null;
    }

    final Map<String, dynamic>? selectedRoute = _coerceMap(
      payload['selected_route'],
    );
    if (selectedRoute == null) {
      return null;
    }

    final List<LatLng> points = _parseCoordinateList(selectedRoute['coordinates']);
    if (points.length < 2) {
      return null;
    }

    final List<RouteSegmentSafety> segments = _parseBackendSegments(
      selectedRoute['segments'],
    );
    if (segments.isEmpty) {
      return null;
    }

    final Map<String, dynamic>? summary = _coerceMap(selectedRoute['summary']);
    return ScoredRoute(
      points: points,
      segments: segments,
      totalDistanceMeters:
          _asDouble(summary?['total_distance']) ?? _polylineDistanceMeters(points),
      averageSafetyScore:
          _asDouble(summary?['average_safety_score']) ??
          _safetyScoreService.calculateAverageSafetyScore(segments),
      totalRisk:
          _asDouble(summary?['total_risk']) ??
          _safetyScoreService.calculateRouteRisk(segments),
    );
  }

  Future<ScoredRoute?> _scoreRouteViaBackend(
    List<LatLng> routePoints, {
    required double fallbackDistanceMeters,
  }) async {
    final Uri uri = Uri.parse('$_riskApiBaseUrl/route/risk');

    final Map<String, Object> body = <String, Object>{
      'coordinates': routePoints
          .map(
            (LatLng point) => <String, double>{
              'lat': point.latitude,
              'lon': point.longitude,
            },
          )
          .toList(growable: false),
    };

    final http.Response? response = await _safePost(uri, body);
    if (response == null || response.statusCode != 200) {
      return null;
    }

    final Map<String, dynamic>? payload = _tryParseJsonMap(response.body);
    if (payload == null) {
      return null;
    }

    final List<RouteSegmentSafety> segments = _parseBackendSegments(
      payload['segments'],
    );
    if (segments.isEmpty) {
      return null;
    }

    final Map<String, dynamic>? summary = _coerceMap(payload['summary']);
    final double totalRisk =
        _asDouble(summary?['total_risk']) ??
        _safetyScoreService.calculateRouteRisk(segments);
    final double totalDistanceMeters =
        _asDouble(summary?['total_distance']) ??
        (fallbackDistanceMeters > 0
            ? fallbackDistanceMeters
            : _segmentsDistanceMeters(segments));
    final double averageSafetyScore =
        _asDouble(summary?['average_safety_score']) ??
        _safetyScoreService.calculateAverageSafetyScore(segments);

    return ScoredRoute(
      points: routePoints,
      segments: segments,
      totalDistanceMeters: totalDistanceMeters,
      averageSafetyScore: averageSafetyScore,
      totalRisk: totalRisk,
    );
  }

  Future<ScoredRoute?> _scoreRouteViaFallback(
    List<LatLng> routePoints, {
    required List<IncidentReport>? reports,
    required DateTime evaluationTime,
    required double fallbackDistanceMeters,
  }) async {
    final List<RouteSegmentSafety> segments = await _safetyScoreService
        .scoreRouteSegments(
          routePoints,
          reports: reports,
          evaluationTime: evaluationTime,
        );
    if (segments.isEmpty) {
      return null;
    }

    final double totalDistanceMeters = fallbackDistanceMeters > 0
        ? fallbackDistanceMeters
        : _segmentsDistanceMeters(segments);

    return ScoredRoute(
      points: routePoints,
      segments: segments,
      totalDistanceMeters: totalDistanceMeters,
      averageSafetyScore: _safetyScoreService.calculateAverageSafetyScore(
        segments,
      ),
      totalRisk: _safetyScoreService.calculateRouteRisk(segments),
    );
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_requestTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> _safePost(Uri uri, Map<String, Object> body) async {
    try {
      return await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<List<IncidentReport>> _safeLoadIncidentReports() async {
    try {
      return await _safetyScoreService.loadIncidentReports();
    } catch (_) {
      return <IncidentReport>[];
    }
  }

  List<RouteSegmentSafety> _parseBackendSegments(Object? rawSegments) {
    if (rawSegments is! List) {
      return <RouteSegmentSafety>[];
    }

    final List<RouteSegmentSafety> segments = <RouteSegmentSafety>[];
    for (final dynamic rawSegment in rawSegments) {
      final Map<String, dynamic>? segment = _coerceMap(rawSegment);
      if (segment == null) {
        continue;
      }

      final LatLng? start = _parseCoordinate(segment['start']);
      final LatLng? end = _parseCoordinate(segment['end']);
      if (start == null || end == null) {
        continue;
      }

      final double distanceMeters =
          _asDouble(segment['distance']) ?? _distance(start, end);
      final double safetyScore = _clampScore(
        _asDouble(segment['safety_score']) ?? 0,
      );
      final double risk = _asDouble(segment['risk']) ?? 0;
      final double distanceWeight =
          _asDouble(segment['distance']) ?? distanceMeters;
      final double safetyPenalty = _clampScore(100 - safetyScore);
      final double incidentDensity =
          _asDouble(segment['incident_density']) ?? 0;
      final double timePenalty = _asDouble(segment['time_penalty']) ?? 0;

      segments.add(
        RouteSegmentSafety(
          start: start,
          end: end,
          distanceMeters: distanceMeters,
          safetyScore: safetyScore,
          incidentRisk: _clamp01(incidentDensity / 20),
          timeOfDayRisk: _clamp01(timePenalty / 20),
          lightingLevel: _clampScore(
            _asDouble(segment['lighting_heuristic']) ?? 0,
          ),
          crowdDensity: _clampScore(_asDouble(segment['crowd_density']) ?? 0),
          distanceWeight: distanceWeight,
          safetyPenalty: safetyPenalty,
          risk: risk,
          segmentId: segment['segment_id']?.toString(),
          safetyLevel: segment['safety_level']?.toString(),
          baseSafetyScore: _asDouble(segment['base_safety_score']),
          incidentDensity: _asDouble(segment['incident_density']),
          lightingHeuristic: _asDouble(segment['lighting_heuristic']),
          timePenalty: _asDouble(segment['time_penalty']),
          distanceToQuery: _asDouble(segment['distance_to_query']),
        ),
      );
    }
    return segments;
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

  LatLng? _parseCoordinate(Object? value) {
    final Map<String, dynamic>? coordinate = _coerceMap(value);
    if (coordinate == null) {
      return null;
    }

    final double? lat = _asDouble(coordinate['lat']);
    final double? lon = _asDouble(coordinate['lon']);
    if (lat == null || lon == null) {
      return null;
    }
    return LatLng(lat, lon);
  }

  List<LatLng> _parseCoordinateList(Object? value) {
    if (value is! List) {
      return <LatLng>[];
    }

    final List<LatLng> points = <LatLng>[];
    for (final dynamic item in value) {
      final LatLng? point = _parseCoordinate(item);
      if (point != null) {
        points.add(point);
      }
    }
    return points;
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

  double _segmentsDistanceMeters(List<RouteSegmentSafety> segments) {
    return segments.fold<double>(
      0,
      (double sum, RouteSegmentSafety segment) => sum + segment.distanceMeters,
    );
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

  List<LatLng> _decodePolyline(String geometry) {
    final List<List<num>> decodedPoints = PolylineCodec.decode(geometry);
    return decodedPoints
        .where((List<num> point) => point.length >= 2)
        .map(
          (List<num> point) => LatLng(point[0].toDouble(), point[1].toDouble()),
        )
        .toList(growable: false);
  }
}
