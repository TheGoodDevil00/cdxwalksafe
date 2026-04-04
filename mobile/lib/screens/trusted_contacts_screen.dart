import 'package:flutter/material.dart';

import '../services/trusted_contacts_service.dart';

/// Screen where the user adds or edits their trusted emergency contacts.
/// Accessible from Settings. Contacts are saved locally.
class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  List<TrustedContact> _contacts = <TrustedContact>[];
  bool _loading = true;
  bool _saving = false;

  final List<TextEditingController> _nameControllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _phoneControllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final List<TrustedContact> saved = await TrustedContactsService.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = saved;
      _loading = false;
    });

    for (int i = 0; i < saved.length && i < 3; i++) {
      _nameControllers[i].text = saved[i].name;
      _phoneControllers[i].text = saved[i].phone;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    final List<TrustedContact> contacts = <TrustedContact>[];
    for (int i = 0; i < 3; i++) {
      final String name = _nameControllers[i].text.trim();
      final String phone = _phoneControllers[i].text.trim();
      if (name.isNotEmpty || phone.isNotEmpty) {
        contacts.add(TrustedContact(name: name, phone: phone));
      }
    }

    await TrustedContactsService.save(contacts);
    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = contacts;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trusted contacts saved.')),
    );
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _nameControllers) {
      controller.dispose();
    }
    for (final TextEditingController controller in _phoneControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _contacts.isEmpty
                ? 'Add up to 3 trusted contacts. Their names and phone numbers will be sent to the backend when you trigger an SOS alert.'
                : 'You can update up to 3 trusted contacts here. These names and phone numbers are included with each SOS alert.',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < 3; i++) ...<Widget>[
            Text(
              'Contact ${i + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameControllers[i],
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneControllers[i],
              decoration: const InputDecoration(
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
