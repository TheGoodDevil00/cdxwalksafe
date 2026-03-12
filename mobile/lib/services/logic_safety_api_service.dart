import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/logic_safety_score.dart';

class LogicSafetyApiService {
  LogicSafetyApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'LOGIC_API_BASE_URL',
            defaultValue: 'http://127.0.0.1:9123',
          );

  final http.Client _client;
  final String _baseUrl;

  String get baseUrl => _baseUrl;

  Future<LogicSafetyScore> getNearestSafetyScore(LatLng point) async {
    // Step 1: Build query URI for nearest-segment safety lookup.
    final Uri uri = Uri.parse('$_baseUrl/safety-score').replace(
      queryParameters: <String, String>{
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      },
    );

    // Step 2: Call backend and parse response payload.
    final http.Response response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Logic API request failed with status ${response.statusCode}.',
      );
    }

    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    return LogicSafetyScore.fromJson(payload);
  }
}
