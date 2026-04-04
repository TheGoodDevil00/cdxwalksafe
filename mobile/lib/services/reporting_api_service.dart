import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ReportSubmissionException implements Exception {
  final String message;

  const ReportSubmissionException(this.message);

  @override
  String toString() => message;
}

class ReportingApiService {
  ReportingApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _envBaseUrl;

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> submitIncidentReport({
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
        throw const ReportSubmissionException(
          'Report could not be submitted. Please try again.',
        );
      }

      final Map<String, dynamic>? parsed = _parseJsonMap(response.body);
      if (parsed == null) {
        throw const ReportSubmissionException(
          'Report could not be submitted. Please try again.',
        );
      }
      return parsed;
    } on SocketException catch (_) {
      throw const ReportSubmissionException(
        'No internet connection. Please check your network and try again.',
      );
    } on TimeoutException catch (_) {
      throw const ReportSubmissionException(
        'The server took too long to respond. Please try again.',
      );
    } on ReportSubmissionException {
      rethrow;
    } catch (_) {
      throw const ReportSubmissionException(
        'Report could not be submitted. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>?> submitEmergencyAlert({
    required String userHash,
    required double latitude,
    required double longitude,
    String? message,
    List<Map<String, String>> trustedContacts = const <Map<String, String>>[],
    int contactsNotified = 0,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl/report/emergency');
    final Map<String, dynamic> payload = <String, dynamic>{
      'user_hash': userHash,
      'lat': latitude,
      'lon': longitude,
      'message': message,
      'trusted_contacts': trustedContacts,
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

      return _parseJsonMap(response.body);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJsonMap(String responseBody) {
    final dynamic parsed = jsonDecode(responseBody);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      return parsed.map(
        (dynamic key, dynamic value) => MapEntry(key.toString(), value),
      );
    }
    return null;
  }
}
