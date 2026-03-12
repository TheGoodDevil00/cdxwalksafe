import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/incident_report.dart';
import '../services/incident_storage_service.dart';
import '../services/reporting_api_service.dart';
import '../widgets/walksafe_map_view.dart';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key, required this.initialLocation});

  final LatLng initialLocation;

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  static const List<String> _incidentTypes = <String>[
    'Harassment',
    'Poor lighting',
    'Suspicious activity',
    'Stalking',
    'Unsafe infrastructure',
  ];

  final IncidentStorageService _storageService = IncidentStorageService();
  final ReportingApiService _reportingApiService = ReportingApiService();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedIncidentType = _incidentTypes.first;
  LatLng? _selectedLocation;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final LatLng? location = _selectedLocation;
    if (location == null) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final IncidentReport report = IncidentReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      incidentType: _selectedIncidentType,
      latitude: location.latitude,
      longitude: location.longitude,
      description: _descriptionController.text.trim(),
      createdAtIso: DateTime.now().toIso8601String(),
    );

    final int severity = _severityForType(_selectedIncidentType);
    final String userHash =
        'mobile-${DateTime.now().millisecondsSinceEpoch.toString()}';
    final Map<String, dynamic>? remoteResponse = await _reportingApiService
        .submitIncidentReport(
          userHash: userHash,
          incidentType: report.incidentType,
          severity: severity,
          latitude: report.latitude,
          longitude: report.longitude,
          description: report.description,
        );

    await _storageService.saveReport(report);
    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          remoteResponse == null
              ? 'Saved locally. Backend unavailable; will still affect offline safety scoring.'
              : 'Incident report submitted and synced to backend.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  int _severityForType(String incidentType) {
    final String normalized = incidentType.toLowerCase();
    if (normalized.contains('stalking') || normalized.contains('harassment')) {
      return 5;
    }
    if (normalized.contains('suspicious')) {
      return 4;
    }
    if (normalized.contains('lighting')) {
      return 3;
    }
    if (normalized.contains('infrastructure')) {
      return 3;
    }
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final LatLng mapCenter = _selectedLocation ?? widget.initialLocation;
    final bool canSubmit = _selectedLocation != null && !_submitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Report Incident')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Drop a pin to mark the unsafe location.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: WalkSafeMapView(
                initialCenter: mapCenter,
                initialZoom: 15,
                markers: _selectedLocation == null
                    ? <Marker>[]
                    : <Marker>[
                        Marker(
                          point: _selectedLocation!,
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                onTap: (LatLng position) {
                  setState(() {
                    _selectedLocation = position;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedIncidentType,
            decoration: const InputDecoration(
              labelText: 'Incident Type',
              border: OutlineInputBorder(),
            ),
            items: _incidentTypes
                .map(
                  (String type) =>
                      DropdownMenuItem<String>(value: type, child: Text(type)),
                )
                .toList(growable: false),
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedIncidentType = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              border: OutlineInputBorder(),
              hintText: 'Describe what happened or what feels unsafe.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canSubmit ? _submitReport : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_submitting ? 'Submitting...' : 'Submit Report'),
          ),
        ],
      ),
    );
  }
}
