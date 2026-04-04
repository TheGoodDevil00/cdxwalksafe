import 'package:flutter/material.dart';

import 'trusted_contacts_screen.dart';

class SettingsProfileScreen extends StatefulWidget {
  const SettingsProfileScreen({super.key});

  @override
  State<SettingsProfileScreen> createState() => _SettingsProfileScreenState();
}

class _SettingsProfileScreenState extends State<SettingsProfileScreen> {
  bool _liveLocationSharing = true;
  bool _incidentNotifications = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Profile')),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 12),
          const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Safety Settings'),
            subtitle: Text('Control your demo preferences and emergency setup'),
          ),
          const Divider(),
          SwitchListTile(
            value: _liveLocationSharing,
            title: const Text('Live Location Sharing'),
            subtitle: const Text('Share location with trusted contacts'),
            onChanged: (bool value) {
              setState(() {
                _liveLocationSharing = value;
              });
            },
          ),
          SwitchListTile(
            value: _incidentNotifications,
            title: const Text('Incident Notifications'),
            subtitle: const Text('Receive nearby safety updates'),
            onChanged: (bool value) {
              setState(() {
                _incidentNotifications = value;
              });
            },
          ),
          ListTile(
            leading: Icon(Icons.contact_phone_outlined),
            title: const Text('Trusted contacts'),
            subtitle: const Text('People notified when you use SOS'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const TrustedContactsScreen(),
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacy Preferences'),
            subtitle: Text('Control data sharing and retention'),
            trailing: Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
