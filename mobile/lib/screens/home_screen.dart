import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/logic_safety_score.dart';
import '../models/scored_route.dart';
import '../models/safety_zone.dart';
import '../services/logic_safety_api_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../services/safety_heatmap_service.dart';
import '../services/sos_service.dart';
import '../widgets/safety_legend_card.dart';
import '../widgets/walksafe_map_view.dart';
import 'emergency_sos_screen.dart';
import 'report_incident_screen.dart';
import 'settings_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final LatLng _defaultCenter = LatLng(18.5204, 73.8567);

  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final RoutingService _routingService = RoutingService();
  final LogicSafetyApiService _logicSafetyApiService = LogicSafetyApiService();
  final SafetyHeatmapService _heatmapService = SafetyHeatmapService();
  final SosService _sosService = SosService();

  LatLng _cameraTarget = _defaultCenter;
  LatLng _startPoint = _defaultCenter;
  List<CircleMarker> _heatmapCircles = <CircleMarker>[];
  List<Marker> _markers = <Marker>[];
  List<Polyline> _routePolylines = <Polyline>[];
  ScoredRoute? _selectedRoute;
  LogicSafetyScore? _logicSafetyScore;
  String _logicApiStatus = 'Not queried yet';
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;
  bool _showSafetyZones = true;

  @override
  void initState() {
    super.initState();
    _loadHomeMap();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadHomeMap() async {
    // Step 1: Load safety overlays from backend (with offline cache fallback).
    final List<SafetyZone> zones = await _heatmapService.loadSafetyZones();
    final List<CircleMarker> circles = zones.map(_mapZoneToCircle).toList();

    // Step 2: Resolve the user's location. Fallback to the default city center.
    final LatLng? userLocation = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }

    final LatLng center = userLocation ?? _defaultCenter;

    // Step 3: Initialize the map with only the start marker.
    setState(() {
      _heatmapCircles = circles;
      _isLoadingLocation = false;
      _cameraTarget = center;
      _startPoint = center;
      _markers = _buildNavigationMarkers(start: center);
      _selectedRoute = null;
      _logicSafetyScore = null;
      _logicApiStatus = 'Not queried yet';
      _routePolylines = <Polyline>[];
    });

    // Step 4: Focus the camera on the start position.
    _mapController.move(center, 15);
  }

  Future<void> _onMapTapped(LatLng destination) async {
    if (_isLoadingLocation || _isLoadingRoute) {
      return;
    }

    // Step 1: Optimistically show destination marker for immediate feedback.
    setState(() {
      _isLoadingRoute = true;
      _markers = _buildNavigationMarkers(
        start: _startPoint,
        destination: destination,
      );
      _logicSafetyScore = null;
      _logicApiStatus = 'Querying logic safety API...';
    });

    try {
      // Step 2: Request alternative routes and pick minimum-risk candidate.
      final ScoredRoute? safestRoute = await _routingService.getSafestRoute(
        _startPoint,
        destination,
      );
      if (!mounted) {
        return;
      }

      // Step 3: Query backend safety score for the tapped destination.
      LogicSafetyScore? logicSafetyScore;
      String logicApiStatus;
      try {
        logicSafetyScore = await _logicSafetyApiService.getNearestSafetyScore(
          destination,
        );
        logicApiStatus = 'Connected (${_logicSafetyApiService.baseUrl})';
      } catch (_) {
        logicApiStatus =
            'Unavailable (${_logicSafetyApiService.baseUrl}) - check uvicorn';
      }

      final List<LatLng> route = safestRoute?.points ?? <LatLng>[];

      // Step 4: Draw the route polyline once points are available.
      setState(() {
        _selectedRoute = safestRoute;
        _logicSafetyScore = logicSafetyScore;
        _logicApiStatus = logicApiStatus;
        _routePolylines = route.isEmpty
            ? <Polyline>[]
            : <Polyline>[
                Polyline(
                  points: route,
                  strokeWidth: 6,
                  color: _routeColorForSafety(
                    logicSafetyScore?.safetyScore ??
                        safestRoute?.averageSafetyScore ??
                        0,
                  ),
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white,
                ),
              ];
      });

      if (route.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No walking route found for the selected point.'),
          ),
        );
      }
      if (logicSafetyScore == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Logic API not reachable. Route rendered without backend score.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      // Step 4: Clear stale route data if request fails.
      setState(() {
        _routePolylines = <Polyline>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to fetch route. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  Color _routeColorForSafety(double safetyScore) {
    if (safetyScore >= 75) {
      return Colors.green.shade700;
    }
    if (safetyScore >= 55) {
      return Colors.orange.shade700;
    }
    return Colors.red.shade700;
  }

  List<Marker> _buildNavigationMarkers({
    required LatLng start,
    LatLng? destination,
  }) {
    final List<Marker> markers = <Marker>[
      _buildMapMarker(
        point: start,
        icon: Icons.my_location,
        color: Colors.blue.shade700,
        label: 'Start position',
      ),
    ];

    if (destination != null) {
      markers.add(
        _buildMapMarker(
          point: destination,
          icon: Icons.flag_rounded,
          color: Colors.deepPurple,
          label: 'Destination',
        ),
      );
    }

    return markers;
  }

  Marker _buildMapMarker({
    required LatLng point,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Marker(
      point: point,
      width: 50,
      height: 50,
      child: Tooltip(
        message: label,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                blurRadius: 6,
                spreadRadius: 1,
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  CircleMarker _mapZoneToCircle(SafetyZone zone) {
    final Color baseColor = switch (zone.safetyLevel) {
      SafetyLevel.risky => Colors.red,
      SafetyLevel.cautious => Colors.yellow.shade700,
      SafetyLevel.safe => Colors.green,
    };

    return CircleMarker(
      point: LatLng(zone.latitude, zone.longitude),
      radius: zone.radiusMeters,
      useRadiusInMeter: true,
      color: baseColor.withValues(alpha: 0.35),
      borderColor: baseColor,
      borderStrokeWidth: 2,
    );
  }

  Future<void> _openIncidentReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportIncidentScreen(initialLocation: _cameraTarget),
      ),
    );
  }

  Future<void> _triggerSos() async {
    final bool sent = await _sosService.sendEmergencyAlert(
      latitude: _cameraTarget.latitude,
      longitude: _cameraTarget.longitude,
    );
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(sent ? 'SOS Alert Sent' : 'SOS Offline Fallback'),
          content: Text(
            sent
                ? 'Emergency alert has been recorded by backend.'
                : 'Could not reach backend. Please call local emergency services directly.',
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

  void _openEmergencyScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const EmergencySosScreen()));
  }

  void _openSettingsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalkSafe'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Emergency',
            onPressed: _openEmergencyScreen,
            icon: const Icon(Icons.warning_amber_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: _openSettingsScreen,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          WalkSafeMapView(
            mapController: _mapController,
            initialCenter: _cameraTarget,
            initialZoom: 14,
            safetyOverlays: _showSafetyZones ? _heatmapCircles : <CircleMarker>[],
            routePolylines: _routePolylines,
            markers: _markers,
            onTap: _onMapTapped,
            onPositionChanged: (LatLng center) {
              _cameraTarget = center;
            },
          ),
          const Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: SafetyLegendCard(),
          ),
          Positioned(
            top: 68,
            left: 14,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Safety Zones'),
                    Switch(
                      value: _showSafetyZones,
                      onChanged: (bool value) {
                        setState(() {
                          _showSafetyZones = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectedRoute != null)
            Positioned(
              top: 126,
              left: 14,
              right: 14,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Risk-Optimized Route',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Safety: ${_selectedRoute!.averageSafetyScore.toStringAsFixed(1)}/100',
                      ),
                      Text('Logic API: $_logicApiStatus'),
                      if (_logicSafetyScore != null)
                        Text(
                          'Backend segment score: ${_logicSafetyScore!.safetyScore.toStringAsFixed(1)}/100',
                        ),
                      if (_logicSafetyScore != null)
                        Text(
                          'Nearest segment: ${_logicSafetyScore!.segmentId} (${_logicSafetyScore!.distanceToQueryMeters.toStringAsFixed(1)}m away)',
                        ),
                      Text(
                        'Risk: ${_selectedRoute!.totalRisk.toStringAsFixed(2)} = distance_weight + safety_penalty',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoadingLocation || _isLoadingRoute)
            const Positioned(
              top: 170,
              right: 14,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 90,
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _triggerSos,
                icon: const Icon(Icons.sos_outlined),
                label: const Text(
                  'SOS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openIncidentReport,
        icon: const Icon(Icons.report_problem_outlined),
        label: const Text('Report Unsafe Area'),
      ),
    );
  }
}
