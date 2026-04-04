import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A trusted contact that the user has manually saved.
/// Sent with SOS alerts so the backend knows who to notify.
class TrustedContact {
  final String name;
  final String phone;

  const TrustedContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'phone': phone,
  };

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
    name: json['name'] as String,
    phone: json['phone'] as String,
  );

  /// A contact is valid if both name and phone are non-empty.
  bool get isValid => name.trim().isNotEmpty && phone.trim().isNotEmpty;
}

class TrustedContactsService {
  static const String _key = 'trusted_contacts_v1';
  static const int maxContacts = 3;

  /// Load saved trusted contacts from local storage.
  /// Returns an empty list if none have been saved yet.
  static Future<List<TrustedContact>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null) {
      return <TrustedContact>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (dynamic entry) =>
                TrustedContact.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return <TrustedContact>[];
    }
  }

  /// Save the given list of trusted contacts to local storage.
  /// Trims the list to maxContacts before saving.
  static Future<void> save(List<TrustedContact> contacts) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<TrustedContact> trimmed = contacts.take(maxContacts).toList();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((TrustedContact c) => c.toJson()).toList()),
    );
  }

  /// True if at least one valid contact has been saved.
  static Future<bool> hasContacts() async {
    final List<TrustedContact> contacts = await load();
    return contacts.any((TrustedContact c) => c.isValid);
  }
}
