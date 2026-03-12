import 'package:flutter/material.dart';

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
            title: Text('Walker Profile'),
            subtitle: Text('women.safety@walksafe.local'),
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
          const ListTile(
            leading: Icon(Icons.contact_phone_outlined),
            title: Text('Emergency Contacts'),
            subtitle: Text('Manage trusted contacts'),
            trailing: Icon(Icons.chevron_right),
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
