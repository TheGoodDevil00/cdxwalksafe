import 'dart:convert';

import 'package:http/http.dart' as http;

class ReportingApiService {
  ReportingApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'ROUTING_API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8000/api/v1',
          );

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, dynamic>?> submitIncidentReport({
    required String userHash,
    required String incidentType,
    required int severity,
    required double latitude,
    required double longitude,
    String? description,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl/report');
    final Map<String, dynamic> payload = <String, dynamic>{
      'user_hash': userHash,
      'incident_type': incidentType,
      'severity': severity,
      'lat': latitude,
      'lon': longitude,
      'description': description ?? '',
      'metadata': <String, dynamic>{'source': 'mobile_app'},
    };

    return _postJson(uri, payload);
  }

  Future<Map<String, dynamic>?> submitEmergencyAlert({
    required String userHash,
    required double latitude,
    required double longitude,
    String? message,
    int contactsNotified = 0,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl/report/emergency');
    final Map<String, dynamic> payload = <String, dynamic>{
      'user_hash': userHash,
      'lat': latitude,
      'lon': longitude,
      'message': message,
      'contacts_notified': contactsNotified,
      'metadata': <String, dynamic>{'source': 'mobile_app'},
    };
    return _postJson(uri, payload);
  }

  Future<Map<String, dynamic>?> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final dynamic parsed = jsonDecode(response.body);
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
}
