import 'reporting_api_service.dart';

class SosService {
  SosService({ReportingApiService? reportingApiService})
    : _reportingApiService = reportingApiService ?? ReportingApiService();

  final ReportingApiService _reportingApiService;

  Future<bool> sendEmergencyAlert({
    required double latitude,
    required double longitude,
  }) async {
    final String userHash = 'mobile-sos-${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic>? response = await _reportingApiService
        .submitEmergencyAlert(
          userHash: userHash,
          latitude: latitude,
          longitude: longitude,
          message: 'Emergency trigger from mobile app',
        );
    return response != null;
  }
}
