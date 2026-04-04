import 'reporting_api_service.dart';
import 'trusted_contacts_service.dart';

class SosService {
  SosService({ReportingApiService? reportingApiService})
    : _reportingApiService = reportingApiService ?? ReportingApiService();

  final ReportingApiService _reportingApiService;

  Future<bool> sendEmergencyAlert({
    required double latitude,
    required double longitude,
    String? message,
    List<TrustedContact>? trustedContacts,
  }) async {
    final List<TrustedContact> resolvedContacts = await _resolveTrustedContacts(
      trustedContacts,
    );
    final String userHash = 'mobile-sos-${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic>? response = await _reportingApiService
        .submitEmergencyAlert(
          userHash: userHash,
          latitude: latitude,
          longitude: longitude,
          message: message ?? 'Emergency trigger from mobile app',
          trustedContacts: resolvedContacts
              .map(
                (TrustedContact contact) => <String, String>{
                  'name': contact.name.trim(),
                  'phone': contact.phone.trim(),
                },
              )
              .toList(growable: false),
          contactsNotified: resolvedContacts.length,
        );
    final int contactsNotified =
        (response?['contacts_notified'] as num?)?.toInt() ?? 0;
    return response != null && contactsNotified >= resolvedContacts.length;
  }

  Future<List<TrustedContact>> _resolveTrustedContacts(
    List<TrustedContact>? trustedContacts,
  ) async {
    final List<TrustedContact> sourceContacts =
        trustedContacts == null || trustedContacts.isEmpty
        ? await TrustedContactsService.load()
        : trustedContacts;
    final List<TrustedContact> normalizedContacts = <TrustedContact>[];
    final Set<String> seenContacts = <String>{};
    for (final TrustedContact contact in sourceContacts) {
      final String trimmedName = contact.name.trim();
      final String trimmedPhone = contact.phone.trim();
      if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
        continue;
      }
      final String normalizedKey =
          '${trimmedName.toLowerCase()}|${trimmedPhone.toLowerCase()}';
      if (!seenContacts.add(normalizedKey)) {
        continue;
      }
      normalizedContacts.add(
        TrustedContact(name: trimmedName, phone: trimmedPhone),
      );
    }
    return normalizedContacts;
  }
}
