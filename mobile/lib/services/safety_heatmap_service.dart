import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/safety_zone.dart';

class SafetyHeatmapService {
  SafetyHeatmapService({http.Client? client, String? apiBaseUrl})
    : _client = client ?? http.Client(),
      _apiBaseUrl =
          apiBaseUrl ??
          const String.fromEnvironment(
            'ROUTING_API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8000/api/v1',
          );

  final http.Client _client;
  final String _apiBaseUrl;

  static const Duration _timeout = Duration(seconds: 10);
  static const String _zonesCacheKey = 'walksafe_safety_zones_cache';
  static const String _versionCacheKey = 'walksafe_safety_zones_version';

  Future<List<SafetyZone>> loadSafetyZones({bool refresh = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<SafetyZone> cachedZones = _loadCachedZones(prefs);
    final String? cachedVersion = prefs.getString(_versionCacheKey);

    final Uri uri = Uri.parse('$_apiBaseUrl/safety-zones').replace(
      queryParameters: <String, String>{
        if (cachedVersion != null && cachedVersion.isNotEmpty)
          'version': cachedVersion,
        if (refresh) 'refresh': 'true',
      },
    );

    try {
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic>? payload = _parseJsonMap(response.body);
        if (payload != null) {
          final bool notModified = payload['not_modified'] == true;
          if (notModified && cachedZones.isNotEmpty) {
            return cachedZones;
          }

          final List<SafetyZone> zones = _parseZones(payload['zones']);
          if (zones.isNotEmpty) {
            await _cacheZones(
              prefs,
              zones: zones,
              datasetVersion: payload['dataset_version']?.toString(),
            );
            return zones;
          }
        }
      }
    } catch (_) {
      // Fall through to cache/mock data.
    }

    if (cachedZones.isNotEmpty) {
      return cachedZones;
    }
    return getMockSafetyZones();
  }

  List<SafetyZone> getMockSafetyZones() {
    return const <SafetyZone>[
      SafetyZone(
        id: 'zone_1',
        latitude: 18.5246,
        longitude: 73.8664,
        safetyScore: 25,
        classification: 'RISKY',
      ),
      SafetyZone(
        id: 'zone_2',
        latitude: 18.5175,
        longitude: 73.8502,
        safetyScore: 35,
        classification: 'RISKY',
      ),
      SafetyZone(
        id: 'zone_3',
        latitude: 18.5311,
        longitude: 73.8597,
        safetyScore: 58,
        classification: 'CAUTIOUS',
      ),
      SafetyZone(
        id: 'zone_4',
        latitude: 18.5131,
        longitude: 73.8717,
        safetyScore: 66,
        classification: 'CAUTIOUS',
      ),
      SafetyZone(
        id: 'zone_5',
        latitude: 18.5272,
        longitude: 73.8429,
        safetyScore: 82,
        classification: 'SAFE',
      ),
      SafetyZone(
        id: 'zone_6',
        latitude: 18.5067,
        longitude: 73.8563,
        safetyScore: 91,
        classification: 'SAFE',
      ),
    ];
  }

  Future<void> _cacheZones(
    SharedPreferences prefs, {
    required List<SafetyZone> zones,
    String? datasetVersion,
  }) async {
    final List<Map<String, dynamic>> serialized = zones
        .map((SafetyZone zone) => zone.toJson())
        .toList(growable: false);
    await prefs.setString(_zonesCacheKey, jsonEncode(serialized));
    if (datasetVersion != null && datasetVersion.isNotEmpty) {
      await prefs.setString(_versionCacheKey, datasetVersion);
    }
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

  List<SafetyZone> _parseZones(Object? rawZones) {
    if (rawZones is! List) {
      return <SafetyZone>[];
    }

    final List<SafetyZone> zones = <SafetyZone>[];
    for (final dynamic item in rawZones) {
      if (item is Map<String, dynamic>) {
        zones.add(SafetyZone.fromJson(item));
      } else if (item is Map) {
        zones.add(
          SafetyZone.fromJson(
            item.map(
              (dynamic key, dynamic value) => MapEntry(key.toString(), value),
            ),
          ),
        );
      }
    }
    return zones;
  }
}
