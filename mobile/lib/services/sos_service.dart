import 'reporting_api_service.dart';

class SosService {
  static const List<String> _defaultTrustedContacts = <String>[
    'sister@walksafe.local',
    'roommate@walksafe.local',
  ];

  SosService({ReportingApiService? reportingApiService})
    : _reportingApiService = reportingApiService ?? ReportingApiService();

  final ReportingApiService _reportingApiService;

  Future<bool> sendEmergencyAlert({
    required double latitude,
    required double longitude,
    String? message,
    List<String>? trustedContacts,
  }) async {
    final List<String> resolvedContacts = _resolveTrustedContacts(
      trustedContacts,
    );
    final String userHash = 'mobile-sos-${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic>? response = await _reportingApiService
        .submitEmergencyAlert(
          userHash: userHash,
          latitude: latitude,
          longitude: longitude,
          message: message ?? 'Emergency trigger from mobile app',
          trustedContacts: resolvedContacts,
          contactsNotified: resolvedContacts.length,
        );
    final int contactsNotified =
        (response?['contacts_notified'] as num?)?.toInt() ?? 0;
    return response != null && contactsNotified >= resolvedContacts.length;
  }

  List<String> _resolveTrustedContacts(List<String>? trustedContacts) {
    final List<String> sourceContacts =
        trustedContacts == null || trustedContacts.isEmpty
        ? _defaultTrustedContacts
        : trustedContacts;
    final List<String> normalizedContacts = <String>[];
    final Set<String> seenContacts = <String>{};
    for (final String contact in sourceContacts) {
      final String trimmedContact = contact.trim();
      if (trimmedContact.isEmpty) {
        continue;
      }
      final String normalizedKey = trimmedContact.toLowerCase();
      if (!seenContacts.add(normalizedKey)) {
        continue;
      }
      normalizedContacts.add(trimmedContact);
    }
    return normalizedContacts;
  }
}
