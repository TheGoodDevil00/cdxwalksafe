import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

    final Map<String, dynamic>? scorePayload = await _fetchRouteSafety(start, end);
    final double? safetyScore = _asDouble(scorePayload?['safety_score']);
    if (safetyScore == null) {
      return null;
    }

    final double totalDistanceMeters =
        (_asDouble(scorePayload?['distance_km']) ?? 0) > 0
        ? (_asDouble(scorePayload?['distance_km']) ?? 0) * 1000
        : _polylineDistanceMeters(routePoints);

    return ScoredRoute(
      points: routePoints,
      segments: const [],
      totalDistanceMeters: totalDistanceMeters,
      averageSafetyScore: safetyScore,
      totalRisk: 100 - safetyScore,
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
