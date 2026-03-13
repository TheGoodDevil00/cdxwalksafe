import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place_suggestion.dart';
import '../models/scored_route.dart';
import '../models/safety_zone.dart';
import '../screens/destination_search_screen.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/routing_service.dart';
import '../services/safety_heatmap_service.dart';
import '../services/sos_service.dart';
import '../widgets/route_summary_panel.dart';
import '../widgets/safety_legend_card.dart';
import '../widgets/walksafe_map_view.dart';
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
  final SafetyHeatmapService _heatmapService = SafetyHeatmapService();
  final SosService _sosService = SosService();
  final PlaceSearchService _placeSearchService = PlaceSearchService();

  LatLng _cameraTarget = _defaultCenter;
  LatLng _startPoint = _defaultCenter;
  LatLng? _destinationPoint;
  String? _destinationLabel;
  List<CircleMarker> _heatmapCircles = <CircleMarker>[];
  List<Marker> _markers = <Marker>[];
  List<Polyline> _routePolylines = <Polyline>[];
  ScoredRoute? _selectedRoute;
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
    final List<SafetyZone> zones = await _heatmapService.loadSafetyZones();
    final List<CircleMarker> circles = zones.map(_mapZoneToCircle).toList();
    final LatLng? userLocation = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }

    final LatLng center = userLocation ?? _defaultCenter;

    setState(() {
      _heatmapCircles = circles;
      _isLoadingLocation = false;
      _cameraTarget = center;
      _startPoint = center;
      _markers = _buildNavigationMarkers(start: center);
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _destinationPoint = null;
      _destinationLabel = null;
    });

    _mapController.move(center, 15);
  }

  Future<void> _selectDestinationAndRoute(
    LatLng destination, {
    String? label,
  }) async {
    if (_isLoadingLocation || _isLoadingRoute) {
      return;
    }

    _mapController.move(destination, 15.8);

    setState(() {
      _destinationPoint = destination;
      _destinationLabel = label ?? 'Pinned destination';
      _isLoadingRoute = true;
      _markers = _buildNavigationMarkers(
        start: _startPoint,
        destination: destination,
      );
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
    });

    try {
      final ScoredRoute? safestRoute = await _routingService.getSafestRoute(
        _startPoint,
        destination,
      );
      if (!mounted) {
        return;
      }

      final List<LatLng> route = safestRoute?.points ?? <LatLng>[];
      setState(() {
        _selectedRoute = safestRoute;
        _routePolylines = route.isEmpty
            ? <Polyline>[]
            : <Polyline>[
                Polyline(
                  points: route,
                  strokeWidth: 7,
                  color: _routeColorForSafety(
                    safestRoute?.averageSafetyScore ?? 0,
                  ),
                  borderStrokeWidth: 2.4,
                  borderColor: Colors.white.withValues(alpha: 0.92),
                ),
              ];
      });

      if (route.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No walking route found. Try another nearby point.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedRoute = null;
        _routePolylines = <Polyline>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not find a route right now. Try another destination.',
          ),
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

  Future<void> _openDestinationSearch() async {
    final PlaceSuggestion? suggestion = await Navigator.of(context).push<PlaceSuggestion>(
      MaterialPageRoute<PlaceSuggestion>(
        builder: (_) => DestinationSearchScreen(
          placeSearchService: _placeSearchService,
          initialQuery: _destinationLabel,
        ),
      ),
    );

    if (!mounted || suggestion == null) {
      return;
    }

    await _selectDestinationAndRoute(
      suggestion.point,
      label: suggestion.title,
    );
  }

  void _clearRoute() {
    setState(() {
      _destinationPoint = null;
      _destinationLabel = null;
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _markers = _buildNavigationMarkers(start: _startPoint);
    });
    _mapController.move(_startPoint, 15);
  }

  void _recenterOnUser() {
    _mapController.move(_startPoint, 15.2);
  }

  Color _routeColorForSafety(double safetyScore) {
    if (safetyScore >= 75) {
      return const Color(0xFF2C8C63);
    }
    if (safetyScore >= 55) {
      return const Color(0xFFD09A20);
    }
    return const Color(0xFFBF4F41);
  }

  List<Marker> _buildNavigationMarkers({
    required LatLng start,
    LatLng? destination,
  }) {
    final List<Marker> markers = <Marker>[
      _buildMapMarker(
        point: start,
        icon: Icons.radio_button_checked_rounded,
        color: const Color(0xFF0F6B63),
        label: 'Start',
      ),
    ];

    if (destination != null) {
      markers.add(
        _buildMapMarker(
          point: destination,
          icon: Icons.flag_rounded,
          color: const Color(0xFF7C4DCC),
          label: _destinationLabel ?? 'Destination',
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
      width: 58,
      height: 58,
      child: Tooltip(
        message: label,
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                  color: Colors.black.withValues(alpha: 0.16),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  CircleMarker _mapZoneToCircle(SafetyZone zone) {
    final Color baseColor = switch (zone.safetyLevel) {
      SafetyLevel.risky => const Color(0xFFBF4F41),
      SafetyLevel.cautious => const Color(0xFFD09A20),
      SafetyLevel.safe => const Color(0xFF2C8C63),
    };

    return CircleMarker(
      point: LatLng(zone.latitude, zone.longitude),
      radius: zone.radiusMeters,
      useRadiusInMeter: true,
      color: baseColor.withValues(alpha: 0.22),
      borderColor: baseColor.withValues(alpha: 0.85),
      borderStrokeWidth: 2,
    );
  }

  Future<void> _openIncidentReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportIncidentScreen(
          initialLocation: _destinationPoint ?? _cameraTarget,
        ),
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
                ? 'Your emergency alert has been recorded. Move toward a brighter, busier area if you can.'
                : 'Could not reach the backend. Please call local emergency services directly.',
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

  void _openSettingsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          WalkSafeMapView(
            mapController: _mapController,
            initialCenter: _cameraTarget,
            initialZoom: 14,
            safetyOverlays: _showSafetyZones ? _heatmapCircles : <CircleMarker>[],
            routePolylines: _routePolylines,
            markers: _markers,
            onTap: (LatLng point) {
              _selectDestinationAndRoute(point, label: 'Pinned destination');
            },
            onPositionChanged: (LatLng center) {
              _cameraTarget = center;
            },
          ),
          const IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xCCF5F1E8), Color(0x00F5F1E8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SizedBox(height: 120, width: double.infinity),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TopPanel(
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE4F2ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFF0F6B63),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'WalkSafe',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: const Color(0xFF16312D),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _RoundMapButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Recenter',
                        onPressed: _recenterOnUser,
                      ),
                      const SizedBox(width: 8),
                      _RoundMapButton(
                        icon: Icons.person_outline_rounded,
                        tooltip: 'Profile',
                        onPressed: _openSettingsScreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _TopPanel(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _openDestinationSearch,
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4F2ED),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF0F6B63),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _destinationLabel ?? 'Search destination',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF16312D),
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isLoadingRoute
                                      ? 'Updating route...'
                                      : 'Search or tap anywhere on the map',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF61746F),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (_destinationLabel != null && !_isLoadingRoute)
                            IconButton(
                              tooltip: 'Clear route',
                              onPressed: _clearRoute,
                              icon: const Icon(Icons.close_rounded),
                            )
                          else if (_isLoadingRoute)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          else
                            const Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Expanded(child: SafetyLegendCard()),
                      const SizedBox(width: 10),
                      _TopPanel(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.layers_outlined,
                              size: 18,
                              color: Color(0xFF49635D),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Zones',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF49635D),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(width: 2),
                            Switch(
                              value: _showSafetyZones,
                              activeThumbColor: const Color(0xFF0F6B63),
                              activeTrackColor: const Color(0xFF9FD3C4),
                              onChanged: (bool value) {
                                setState(() {
                                  _showSafetyZones = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: _selectedRoute != null || _isLoadingRoute ? 220 : 112,
            child: _RoundMapButton(
              icon: Icons.my_location_rounded,
              tooltip: 'Recenter',
              onPressed: _recenterOnUser,
            ),
          ),
          if (_selectedRoute != null || _isLoadingRoute)
            Positioned(
              left: 16,
              right: 16,
              bottom: 118,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: RouteSummaryPanel(
                  key: ValueKey<String>(
                    '${_destinationLabel ?? 'none'}-${_selectedRoute?.totalRisk ?? -1}-${_isLoadingRoute ? 'loading' : 'idle'}',
                  ),
                  route: _selectedRoute,
                  isLoading: _isLoadingRoute,
                  destinationLabel: _destinationLabel,
                  onClearRoute: _clearRoute,
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD7372F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: _triggerSos,
                    icon: const Icon(Icons.sos_rounded),
                    label: const Text(
                      'SOS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE0F3EC),
                      foregroundColor: const Color(0xFF0F6B63),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    onPressed: _openIncidentReport,
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text(
                      'Report unsafe area',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingLocation)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66FFFFFF),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0F6B63),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F2A22),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFF16312D)),
      ),
    );
  }
}
