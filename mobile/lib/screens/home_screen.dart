import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place_suggestion.dart';
import '../models/route_segment_safety.dart';
import '../models/scored_route.dart';
import '../models/safety_zone.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../services/routing_service.dart';
import '../services/safety_heatmap_service.dart';
import '../services/sos_service.dart';
import '../widgets/route_info_card.dart';
import '../widgets/safety_zone_overlay.dart';
import '../widgets/walksafe_map_view.dart';
import 'destination_search_screen.dart';
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
  List<SafetyZone> _safetyZones = <SafetyZone>[];
  List<Marker> _markers = <Marker>[];
  List<Polyline> _routePolylines = <Polyline>[];
  ScoredRoute? _selectedRoute;
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;
  bool _showSafetyZones = true;
  bool _isRouteActive = false;

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
    final LatLng? userLocation = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }

    final LatLng center = userLocation ?? _defaultCenter;
    final List<SafetyZone> zones = await _heatmapService
        .loadSafetyZonesForPoints(<LatLng>[center], refresh: true);
    if (!mounted) {
      return;
    }

    setState(() {
      _safetyZones = zones;
      _isLoadingLocation = false;
      _cameraTarget = center;
      _startPoint = center;
      _markers = _buildNavigationMarkers(start: center);
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _destinationPoint = null;
      _destinationLabel = null;
      _isRouteActive = false;
    });

    _mapController.move(center, 15.2);
  }

  Future<void> _selectDestinationAndRoute(
    LatLng destination, {
    String? label,
  }) async {
    if (_isLoadingLocation || _isLoadingRoute) {
      return;
    }

    setState(() {
      _destinationPoint = destination;
      _destinationLabel = label ?? 'Pinned destination';
      _isLoadingRoute = true;
      _isRouteActive = false;
      _markers = _buildNavigationMarkers(
        start: _startPoint,
        destination: destination,
      );
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
    });

    _mapController.move(destination, 15.8);

    try {
      final ScoredRoute? safestRoute = await _routingService.getSafestRoute(
        _startPoint,
        destination,
      );
      if (!mounted) {
        return;
      }

      final List<LatLng> routePoints = safestRoute?.points ?? <LatLng>[];
      final List<SafetyZone> nearbyZones = await _heatmapService
          .loadSafetyZonesForPoints(
            routePoints.isNotEmpty
                ? <LatLng>[_startPoint, destination, ...routePoints]
                : <LatLng>[_startPoint, destination],
            refresh: true,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedRoute = safestRoute;
        if (nearbyZones.isNotEmpty) {
          _safetyZones = nearbyZones;
        }
        _routePolylines = routePoints.isEmpty
            ? <Polyline>[]
            : _buildRoutePolylines(safestRoute!);
      });

      if (routePoints.isEmpty) {
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

  Future<void> _refreshNearbySafetyZones() async {
    final List<SafetyZone> zones = await _heatmapService
        .loadSafetyZonesForPoints(<LatLng>[_startPoint], refresh: true);
    if (!mounted || zones.isEmpty) {
      return;
    }
    setState(() {
      _safetyZones = zones;
    });
  }

  List<Polyline> _buildRoutePolylines(ScoredRoute route) {
    final List<LatLng> routePoints = route.points;
    if (routePoints.isEmpty) {
      return <Polyline>[];
    }

    final List<RouteSegmentSafety> scoredSegments = route.segments
        .where((RouteSegmentSafety segment) => segment.safetyLevel != 'UNKNOWN')
        .toList(growable: false);
    final List<Polyline> polylines = <Polyline>[
      Polyline(
        points: routePoints,
        strokeWidth: 16,
        color: Colors.white.withValues(alpha: 0.84),
      ),
      Polyline(
        points: routePoints,
        strokeWidth: 11,
        color: const Color(0xFF2F6EF6).withValues(alpha: 0.14),
      ),
    ];

    if (scoredSegments.isEmpty) {
      polylines.add(
        Polyline(
          points: routePoints,
          strokeWidth: 8,
          color: const Color(0xFF30C56A),
          borderStrokeWidth: 4.4,
          borderColor: Colors.white.withValues(alpha: 0.96),
        ),
      );
      return polylines;
    }

    for (final RouteSegmentSafety segment in scoredSegments) {
      polylines.add(
        Polyline(
          points: <LatLng>[segment.start, segment.end],
          strokeWidth: 8.2,
          color: _routeSegmentColor(segment),
          borderStrokeWidth: 2.8,
          borderColor: Colors.white.withValues(alpha: 0.90),
        ),
      );
    }
    return polylines;
  }

  Color _routeSegmentColor(RouteSegmentSafety segment) {
    if (segment.safetyPenalty >= 8 || segment.incidentRisk >= 0.6) {
      return const Color(0xFFE24A3B);
    }
    if (segment.safetyScore >= 75) {
      return const Color(0xFF30C56A);
    }
    if (segment.safetyScore >= 55) {
      return const Color(0xFFF2A53B);
    }
    return const Color(0xFFD7644F);
  }

  Future<void> _openDestinationSearch() async {
    final PlaceSuggestion? suggestion = await Navigator.of(context)
        .push<PlaceSuggestion>(
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

    await _selectDestinationAndRoute(suggestion.point, label: suggestion.title);
  }

  void _clearRoute() {
    setState(() {
      _destinationPoint = null;
      _destinationLabel = null;
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _markers = _buildNavigationMarkers(start: _startPoint);
      _isRouteActive = false;
    });
    unawaited(_refreshNearbySafetyZones());
    _mapController.move(_startPoint, 15.2);
  }

  void _recenterOnUser() {
    _mapController.move(_startPoint, 15.2);
  }

  void _toggleSafetyZones() {
    setState(() {
      _showSafetyZones = !_showSafetyZones;
    });
  }

  void _startRoute() {
    if (_selectedRoute == null) {
      return;
    }

    setState(() {
      _isRouteActive = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Route started. Follow the highlighted path and keep an eye on nearby danger zones.',
        ),
      ),
    );
  }

  List<Marker> _buildNavigationMarkers({
    required LatLng start,
    LatLng? destination,
  }) {
    final List<Marker> markers = <Marker>[
      _buildMapMarker(
        point: start,
        label: 'Your location',
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF34B3FF), Color(0xFF2E7CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF2E7CF6).withValues(alpha: 0.26),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    ];

    if (destination != null) {
      markers.add(
        _buildMapMarker(
          point: destination,
          label: _destinationLabel ?? 'Destination',
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFF2E7CF6), width: 5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7CF6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Marker _buildMapMarker({
    required LatLng point,
    required String label,
    required Widget child,
  }) {
    return Marker(
      point: point,
      width: 64,
      height: 64,
      child: Tooltip(
        message: label,
        child: Center(child: child),
      ),
    );
  }

  Future<void> _openIncidentReport() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close incident report',
      barrierColor: Colors.black.withValues(alpha: 0.30),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return ReportIncidentScreen(
              initialLocation: _destinationPoint ?? _cameraTarget,
            );
          },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final Animation<double> curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );

            return FadeTransition(
              opacity: curvedAnimation,
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: 0.96,
                  end: 1,
                ).animate(curvedAnimation),
                child: child,
              ),
            );
          },
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
    final bool showRouteCard = _selectedRoute != null || _isLoadingRoute;
    final double actionBottomOffset = showRouteCard ? 288 : 28;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          WalkSafeMapView(
            mapController: _mapController,
            initialCenter: _cameraTarget,
            initialZoom: 14.8,
            overlayLayers: <Widget>[
              SafetyZoneOverlay(
                zones: _safetyZones,
                isVisible: _showSafetyZones,
              ),
            ],
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
                    colors: <Color>[
                      Color(0x66FFFFFF),
                      Color(0x18FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SizedBox(height: 180, width: double.infinity),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _MapCircleButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Recenter',
                        onPressed: _recenterOnUser,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SearchPanel(
                          destinationLabel: _destinationLabel,
                          isLoadingRoute: _isLoadingRoute,
                          onTap: _openDestinationSearch,
                          onClear: _destinationLabel == null || _isLoadingRoute
                              ? null
                              : _clearRoute,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MapCircleButton(
                        icon: Icons.person_outline_rounded,
                        tooltip: 'Profile',
                        onPressed: _openSettingsScreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _MapToggleChip(
                        label: 'Show Safety Zones',
                        icon: _showSafetyZones
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        isSelected: _showSafetyZones,
                        onTap: _toggleSafetyZones,
                      ),
                      if (_selectedRoute == null && !_isLoadingRoute)
                        const _HintChip(
                          icon: Icons.touch_app_rounded,
                          label: 'Tap anywhere to preview a safe route',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: actionBottomOffset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MapCircleButton(
                  icon: Icons.report_gmailerrorred_rounded,
                  tooltip: 'Report incident',
                  onPressed: _openIncidentReport,
                ),
                const SizedBox(height: 12),
                _EmergencyButton(onPressed: _triggerSos),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                final Animation<Offset> offsetAnimation = Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: showRouteCard
                  ? Align(
                      key: ValueKey<String>(
                        'route-card-${_destinationLabel ?? 'none'}-${_isLoadingRoute ? 'loading' : 'ready'}-${_isRouteActive ? 'active' : 'idle'}',
                      ),
                      alignment: Alignment.bottomCenter,
                      child: RouteInfoCard(
                        route: _selectedRoute,
                        isLoading: _isLoadingRoute,
                        destinationLabel: _destinationLabel,
                        buttonLabel: _isRouteActive
                            ? 'ROUTE ACTIVE'
                            : 'START ROUTE',
                        onPrimaryPressed:
                            _isLoadingRoute || _selectedRoute == null
                            ? null
                            : _startRoute,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey<String>('empty')),
            ),
          ),
          if (_isLoadingLocation)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66FFFFFF),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF2E7CF6)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.destinationLabel,
    required this.isLoadingRoute,
    required this.onTap,
    required this.onClear,
  });

  final String? destinationLabel;
  final bool isLoadingRoute;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: 24,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x142F6EF6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF2F6EF6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      destinationLabel ?? 'Where are you walking to?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF111C2A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoadingRoute
                          ? 'Building your safest route...'
                          : 'Search or tap anywhere on the map',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6A7789),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLoadingRoute)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFF2F6EF6),
                  ),
                )
              else if (onClear != null)
                IconButton(
                  tooltip: 'Clear route',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF4E5E73),
                )
              else
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF4E5E73),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, required this.borderRadius});

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.70)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.84),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, color: const Color(0xFF162133)),
            style: IconButton.styleFrom(
              minimumSize: const Size(56, 56),
              shape: const CircleBorder(),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.60)),
              shadowColor: Colors.black.withValues(alpha: 0.10),
              elevation: 6,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapToggleChip extends StatelessWidget {
  const _MapToggleChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? const Color(0x332F6EF6)
              : Colors.white.withValues(alpha: 0.68),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? const Color(0xFF2F6EF6)
                      : const Color(0xFF54657A),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF162133),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: const Color(0xFF617286)),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF617286),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFE3424B), Color(0xFFD52A37)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFE3424B).withValues(alpha: 0.26),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.sos_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
