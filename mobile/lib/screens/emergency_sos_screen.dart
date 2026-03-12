import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/sos_service.dart';

class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() => _EmergencySosScreenState();
}

class _EmergencySosScreenState extends State<EmergencySosScreen> {
  static const double _fallbackLat = 18.5204;
  static const double _fallbackLon = 73.8567;

  final SosService _sosService = SosService();
  final LocationService _locationService = LocationService();
  bool _sending = false;

  Future<void> _sendEmergencyAlert() async {
    setState(() {
      _sending = true;
    });

    final location = await _locationService.getCurrentLocation();
    final bool sent = await _sosService.sendEmergencyAlert(
      latitude: location?.latitude ?? _fallbackLat,
      longitude: location?.longitude ?? _fallbackLon,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _sending = false;
    });

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(sent ? 'Alert Sent' : 'Alert Failed'),
          content: Text(
            sent
                ? 'Emergency alert has been sent to backend.'
                : 'Could not reach backend. Call local emergency services immediately.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: 100,
              color: Colors.red.shade700,
            ),
            const SizedBox(height: 20),
            const Text(
              'Press the button below to notify your emergency contacts.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _sending ? null : _sendEmergencyAlert,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Send SOS Alert',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
