import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/safety_zone.dart';

class SafetyHeatmapService {
  SafetyHeatmapService({http.Client? client, String? apiBaseUrl})
    : _client = client ?? http.Client(),
      _apiBaseUrl = apiBaseUrl ?? _baseUrl;

  static const String _baseUrl = String.fromEnvironment('API_BASE_URL');
  static const Duration _timeout = Duration(seconds: 10);
  static const String _zonesCacheKey = 'walksafe_safety_zones_cache';

  final http.Client _client;
  final String _apiBaseUrl;

  Future<List<SafetyZone>> loadSafetyZones({bool refresh = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<SafetyZone> cachedZones = _loadCachedZones(prefs);

    final Uri uri = Uri.parse('$_apiBaseUrl/safety-zones').replace(
      queryParameters: <String, String>{
        if (refresh) 'refresh': 'true',
      },
    );

    try {
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic>? payload = _parseJsonMap(response.body);
        if (payload != null) {
          final List<SafetyZone> zones = _parseZones(payload['features']);
          if (zones.isNotEmpty) {
            await _cacheZones(prefs, zones: zones);
            return zones;
          }
        }
      }
    } catch (_) {
      // Fall through to cache.
    }

    return cachedZones;
  }

  Future<void> _cacheZones(
    SharedPreferences prefs, {
    required List<SafetyZone> zones,
  }) async {
    final List<Map<String, dynamic>> serialized = zones
        .map((SafetyZone zone) => zone.toJson())
        .toList(growable: false);
    await prefs.setString(_zonesCacheKey, jsonEncode(serialized));
  }

  List<SafetyZone> _loadCachedZones(SharedPreferences prefs) {
    final String? raw = prefs.getString(_zonesCacheKey);
    if (raw == null || raw.isEmpty) {
      return <SafetyZone>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <SafetyZone>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (Map item) => SafetyZone.fromJson(
              item.map(
                (dynamic key, dynamic value) =>
                    MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return <SafetyZone>[];
    }
  }

  Map<String, dynamic>? _parseJsonMap(String body) {
    try {
      final dynamic parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      if (parsed is Map) {
        return parsed.map(
          (dynamic key, dynamic value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<SafetyZone> _parseZones(Object? rawFeatures) {
    if (rawFeatures is! List) {
      return <SafetyZone>[];
    }

    final List<SafetyZone> zones = <SafetyZone>[];
    for (final dynamic item in rawFeatures) {
      final Map<String, dynamic>? feature = _coerceMap(item);
      final Map<String, dynamic>? properties = _coerceMap(feature?['properties']);
      final Map<String, dynamic>? geometry = _coerceMap(feature?['geometry']);
      if (properties == null || geometry == null) {
        continue;
      }

      final List<double>? centroid = _polygonCentroid(geometry['coordinates']);
      if (centroid == null) {
        continue;
      }

      final double riskScore = _asDouble(properties['risk_score']) ?? 0;
      zones.add(
        SafetyZone(
          id: properties['zone_id']?.toString() ?? '',
          latitude: centroid[0],
          longitude: centroid[1],
          safetyScore: (1 - riskScore) * 100,
          classification: properties['risk_level']?.toString().toUpperCase(),
        ),
      );
    }
    return zones;
  }

  Map<String, dynamic>? _coerceMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((dynamic key, dynamic val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  List<double>? _polygonCentroid(Object? coordinates) {
    if (coordinates is! List || coordinates.isEmpty) {
      return null;
    }

    final Object? firstRingRaw = coordinates.first;
    if (firstRingRaw is! List || firstRingRaw.isEmpty) {
      return null;
    }

    double totalLat = 0;
    double totalLon = 0;
    int count = 0;
    for (final dynamic point in firstRingRaw) {
      if (point is! List || point.length < 2) {
        continue;
      }
      final double? lon = _asDouble(point[0]);
      final double? lat = _asDouble(point[1]);
      if (lat == null || lon == null) {
        continue;
      }
      totalLat += lat;
      totalLon += lon;
      count += 1;
    }

    if (count == 0) {
      return null;
    }
    return <double>[totalLat / count, totalLon / count];
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
}
