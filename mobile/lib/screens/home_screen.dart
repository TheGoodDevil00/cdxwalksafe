import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/place_suggestion.dart';
import '../models/route_segment_safety.dart';
import '../models/scored_route.dart';
import '../models/safety_zone.dart';
import '../services/location_service.dart';
import '../services/navigation_math.dart';
import '../services/place_search_service.dart';
import '../services/routing_service.dart';
import '../services/safety_heatmap_service.dart';
import '../services/sos_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/route_info_card.dart';
import '../widgets/safety_zone_overlay.dart';
import '../widgets/walksafe_map_view.dart';
import 'destination_search_screen.dart';
import 'report_incident_screen.dart';
import 'settings_profile_screen.dart';

enum NavigationState { idle, planning, active, arrived }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final LatLng _defaultCenter = LatLng(18.5204, 73.8567);
  static const double _minimumHeadingSpeedMps = 0.8;
  static const double _maximumReliableAccuracyMeters = 35;
  static const int _offRouteConfirmationSamples = 3;
  static const Duration _rerouteCooldown = Duration(seconds: 15);

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
  NavigationState _navState = NavigationState.idle;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Position? _currentPosition;
  Position? _previousPosition;
  DateTime? _lastRerouteTime;
  double? _deviceHeading;
  double _currentHeading = 0.0;
  bool _headingUpMode = false;
  bool _cardExpanded = false;
  bool _mapReady = false;
  bool _isRerouting = false;
  int _offRouteSampleCount = 0;

  LatLng get _liveUserPoint => _currentPosition == null
      ? _startPoint
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  bool get _showCompassReset => _headingUpMode && _hasHeading;

  bool get _hasHeading =>
      _deviceHeading != null ||
      (_currentPosition != null &&
          _travelHeadingFromPosition(_currentPosition!) != null);

  @override
  void initState() {
    super.initState();
    _loadHomeMap();
    _startCompassTracking();
    _startPositionTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _syncMarkers() {
    _markers = _buildNavigationMarkers(
      start: _liveUserPoint,
      destination: _destinationPoint,
    );
  }

  void _resetMapBearing() {
    if (_mapReady) {
      _mapController.rotate(0);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _headingUpMode = false;
      _syncMarkers();
    });
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
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _destinationPoint = null;
      _destinationLabel = null;
      _navState = NavigationState.idle;
      _cardExpanded = false;
      _lastRerouteTime = null;
      _isRerouting = false;
      _offRouteSampleCount = 0;
      _syncMarkers();
    });

    _mapController.move(center, 15.2);
  }

  Future<void> _loadRoute({
    required LatLng start,
    required LatLng destination,
    String? label,
    bool moveCamera = true,
    bool preserveVisibleRoute = false,
  }) async {
    if (_isLoadingLocation || _isLoadingRoute) {
      return;
    }

    final bool keepActive = _navState == NavigationState.active;
    final bool preserveExistingRoute =
        keepActive && preserveVisibleRoute && _selectedRoute != null;

    setState(() {
      _startPoint = start;
      _destinationPoint = destination;
      _destinationLabel = label ?? _destinationLabel ?? 'Pinned destination';
      _isLoadingRoute = true;
      if (!preserveExistingRoute) {
        _selectedRoute = null;
        _routePolylines = <Polyline>[];
      }
      if (!keepActive) {
        _navState = NavigationState.idle;
        _cardExpanded = false;
      }
      _syncMarkers();
    });

    if (moveCamera) {
      _mapController.move(destination, 15.8);
    }

    try {
      final ScoredRoute? safestRoute = await _routingService.getSafestRoute(
        start,
        destination,
      );
      if (!mounted) {
        return;
      }

      final List<LatLng> routePoints = safestRoute?.points ?? <LatLng>[];
      if (routePoints.isEmpty) {
        if (!preserveExistingRoute) {
          setState(() {
            _selectedRoute = null;
            _routePolylines = <Polyline>[];
            _navState = NavigationState.idle;
            _syncMarkers();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No walking route found. Try another nearby point.',
              ),
            ),
          );
        }
        return;
      }

      final List<SafetyZone> nearbyZones = await _heatmapService
          .loadSafetyZonesForPoints(<LatLng>[
            start,
            destination,
            ...routePoints,
          ], refresh: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedRoute = safestRoute;
        if (nearbyZones.isNotEmpty) {
          _safetyZones = nearbyZones;
        }
        _routePolylines = _buildRoutePolylines(safestRoute!);
        _navState = keepActive
            ? NavigationState.active
            : NavigationState.planning;
        _offRouteSampleCount = 0;
        _syncMarkers();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (!preserveExistingRoute) {
        setState(() {
          _selectedRoute = null;
          _routePolylines = <Polyline>[];
          _navState = NavigationState.idle;
          _syncMarkers();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find a route right now. Try another destination.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  Future<void> _selectDestinationAndRoute(
    LatLng destination, {
    String? label,
  }) async {
    await _loadRoute(
      start: _liveUserPoint,
      destination: destination,
      label: label,
    );
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

  void _startCompassTracking() {
    _compassSubscription?.cancel();

    final Stream<CompassEvent>? headingStream = FlutterCompass.events;
    if (headingStream == null) {
      debugPrint('Compass stream unavailable on this device.');
      return;
    }

    _compassSubscription = headingStream.listen(
      (CompassEvent event) {
        final double? heading = NavigationMath.normalizeHeading(event.heading);
        if (!mounted || heading == null) {
          return;
        }

        final double resolvedHeading = _deviceHeading == null
            ? heading
            : NavigationMath.blendHeading(_deviceHeading!, heading);
        final bool headingChanged =
            _deviceHeading == null ||
            NavigationMath.headingDeltaDegrees(
                  _currentHeading,
                  resolvedHeading,
                ).abs() >=
                1.2;

        if (!headingChanged &&
            !(_navState == NavigationState.active &&
                _headingUpMode &&
                _mapReady)) {
          return;
        }

        setState(() {
          _deviceHeading = resolvedHeading;
          _currentHeading = resolvedHeading;
          _syncMarkers();
        });

        if (_headingUpMode) {
          _syncMapToHeading(heading: resolvedHeading);
        }
      },
      onError: (Object error) {
        debugPrint('Compass stream error: $error');
      },
    );
  }

  void _startPositionTracking() {
    _positionSubscription?.cancel();

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _onPositionUpdate,
          onError: (Object error) {
            debugPrint('Position stream error: $error');
          },
        );
  }

  double? _travelHeadingFromPosition(Position position) {
    if (position.speed < _minimumHeadingSpeedMps || position.heading < 0) {
      return null;
    }
    if (position.headingAccuracy > 0 && position.headingAccuracy > 45) {
      return null;
    }
    return NavigationMath.normalizeHeading(position.heading);
  }

  void _refreshDisplayedHeading(Position position) {
    final double? effectiveHeading =
        _deviceHeading ?? _travelHeadingFromPosition(position);
    if (effectiveHeading == null) {
      return;
    }

    if (NavigationMath.headingDeltaDegrees(
          _currentHeading,
          effectiveHeading,
        ).abs() >=
        1.2) {
      setState(() {
        _currentHeading = effectiveHeading;
        _syncMarkers();
      });
    }

    _syncMapToHeading(heading: effectiveHeading);
  }

  void _syncMapToHeading({double? heading, LatLng? userPoint}) {
    if (_navState != NavigationState.active || !_mapReady) {
      return;
    }

    final double zoom = _mapController.camera.zoom;
    final LatLng targetPoint = userPoint ?? _liveUserPoint;
    final double? effectiveHeading = heading != null
        ? NavigationMath.normalizeHeading(heading)
        : NavigationMath.normalizeHeading(_deviceHeading ?? _currentHeading);

    if (_headingUpMode && effectiveHeading != null) {
      _mapController.moveAndRotate(targetPoint, zoom, -effectiveHeading);
    } else {
      _mapController.move(targetPoint, zoom);
    }
  }

  bool _isLikelyMoving(Position position) {
    if (position.speed >= _minimumHeadingSpeedMps) {
      return true;
    }

    final Position? previousPosition = _previousPosition;
    if (previousPosition == null) {
      return false;
    }

    final double movedMeters = Geolocator.distanceBetween(
      previousPosition.latitude,
      previousPosition.longitude,
      position.latitude,
      position.longitude,
    );
    final double previousAccuracy = previousPosition.accuracy > 0
        ? previousPosition.accuracy
        : _maximumReliableAccuracyMeters;
    final double currentAccuracy = position.accuracy > 0
        ? position.accuracy
        : _maximumReliableAccuracyMeters;
    final double noiseBudget = math.max(
      10,
      math.min(25, (previousAccuracy + currentAccuracy) * 0.6),
    );
    return movedMeters > noiseBudget;
  }

  void _evaluateOffRoute(Position position, LatLng userPoint) {
    final ScoredRoute? route = _selectedRoute;
    if (route == null || route.points.isEmpty) {
      _offRouteSampleCount = 0;
      return;
    }

    final double distanceToRoute = NavigationMath.distanceToPolylineMeters(
      userPoint,
      route.points,
    );
    final bool reliableFix =
        position.accuracy > 0 &&
        position.accuracy <= _maximumReliableAccuracyMeters;
    final bool likelyMoving = _isLikelyMoving(position);
    final double rerouteThreshold = NavigationMath.rerouteThresholdMeters(
      position.accuracy,
    );

    if (reliableFix && likelyMoving && distanceToRoute > rerouteThreshold) {
      _offRouteSampleCount += 1;
    } else {
      _offRouteSampleCount = 0;
      return;
    }

    final DateTime now = DateTime.now();
    final bool cooldownExpired =
        _lastRerouteTime == null ||
        now.difference(_lastRerouteTime!) > _rerouteCooldown;

    if (_offRouteSampleCount >= _offRouteConfirmationSamples &&
        cooldownExpired &&
        !_isRerouting) {
      _lastRerouteTime = now;
      _offRouteSampleCount = 0;
      unawaited(_reroute(from: userPoint));
    }
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) {
      return;
    }

    final LatLng userPoint = LatLng(position.latitude, position.longitude);

    try {
      setState(() {
        _currentPosition = position;
        _startPoint = userPoint;
        _cameraTarget = userPoint;
        _syncMarkers();
      });

      _refreshDisplayedHeading(position);

      if (_navState != NavigationState.active) {
        return;
      }

      if (_destinationPoint != null) {
        final double distanceToDestination = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _destinationPoint!.latitude,
          _destinationPoint!.longitude,
        );

        if (distanceToDestination < 30) {
          _onArrived();
          return;
        }
      }

      _syncMapToHeading(
        heading: _deviceHeading ?? _travelHeadingFromPosition(position),
        userPoint: userPoint,
      );
      _evaluateOffRoute(position, userPoint);
    } finally {
      _previousPosition = position;
    }
  }

  void _onCompassResetPressed() {
    if (_mapReady) {
      _mapController.rotate(0);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _headingUpMode = false;
      _syncMarkers();
    });
  }

  void _onArrived() {
    if (!mounted) {
      return;
    }

    setState(() {
      _navState = NavigationState.arrived;
      _cardExpanded = true;
      _isRerouting = false;
      _lastRerouteTime = null;
      _offRouteSampleCount = 0;
    });

    _resetMapBearing();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have arrived at your destination.'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _reroute({required LatLng from}) async {
    if (_destinationPoint == null) {
      return;
    }

    setState(() {
      _isRerouting = true;
    });

    try {
      await _loadRoute(
        start: from,
        destination: _destinationPoint!,
        label: _destinationLabel,
        moveCamera: false,
        preserveVisibleRoute: true,
      );

      if (mounted &&
          _selectedRoute != null &&
          _selectedRoute!.points.isNotEmpty) {
        setState(() {
          _navState = NavigationState.active;
        });
      }
    } catch (error) {
      debugPrint('Reroute failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isRerouting = false;
        });
      }
    }
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
      _navState = NavigationState.idle;
      _cardExpanded = false;
      _lastRerouteTime = null;
      _isRerouting = false;
      _offRouteSampleCount = 0;
      _syncMarkers();
    });
    unawaited(_refreshNearbySafetyZones());
    _resetMapBearing();
    _mapController.move(_liveUserPoint, 15.2);
  }

  void _recenterOnUser() {
    if (_navState == NavigationState.active) {
      setState(() {
        _headingUpMode = _hasHeading;
      });
      _syncMapToHeading();
      return;
    }

    _mapController.move(_liveUserPoint, 15.2);
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
      _navState = NavigationState.active;
      _cardExpanded = false;
      _headingUpMode = _hasHeading;
      _offRouteSampleCount = 0;
    });

    _syncMapToHeading();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Route started. Follow the highlighted path and keep an eye on nearby danger zones.',
        ),
      ),
    );
  }

  void _stopNavigation() {
    setState(() {
      _navState = NavigationState.idle;
      _cardExpanded = false;
      _isRerouting = false;
      _lastRerouteTime = null;
      _offRouteSampleCount = 0;
      _selectedRoute = null;
      _routePolylines = <Polyline>[];
      _destinationPoint = null;
      _destinationLabel = null;
      _syncMarkers();
    });

    _resetMapBearing();
    unawaited(_refreshNearbySafetyZones());
  }

  int _routeEtaMinutes(ScoredRoute route) =>
      (route.totalDistanceMeters / 75).clamp(1, 180).round();

  int _routeSafetyPercent(ScoredRoute route) =>
      route.averageSafetyScore.round().clamp(0, 100).toInt();

  String _navigationAdvisoryText(ScoredRoute route) {
    final String? warning = route.warning?.trim();
    if (warning != null && warning.isNotEmpty) {
      return warning;
    }

    final int safetyScore = _routeSafetyPercent(route);
    if (safetyScore >= 75) {
      return 'This route is staying on calmer stretches right now.';
    }
    if (safetyScore >= 55) {
      return 'Stay alert near the highlighted sections as conditions change.';
    }
    return 'Keep to brighter, busier roads and reassess if conditions feel off.';
  }

  Widget _buildBottomCardShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(22, 22, 22, 22),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(32)),
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: borderRadius,
          border: Border.all(color: const Color(0xFFF0F4FA)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF12366E).withValues(alpha: 0.10),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  Widget _buildCollapsedNavigationStrip(ScoredRoute route) {
    final int etaMinutes = _routeEtaMinutes(route);
    final int safetyScore = _routeSafetyPercent(route);

    return _buildBottomCardShell(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('active-strip'),
          onTap: () {
            setState(() {
              _cardExpanded = true;
            });
          },
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 72,
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0x142F6EF6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Color(0xFF2F6EF6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Navigating',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF111C2A),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$etaMinutes min · $safetyScore% safe',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5E6D80),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Color(0xFF4E5E73),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedNavigationCard(ScoredRoute route) {
    final int etaMinutes = _routeEtaMinutes(route);
    final int safetyScore = _routeSafetyPercent(route);
    final ThemeData theme = Theme.of(context);

    return _buildBottomCardShell(
      child: Column(
        key: const ValueKey<String>('active-expanded-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Active navigation',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0E1B2A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _cardExpanded = false;
                  });
                },
                child: const Text('Collapse'),
              ),
            ],
          ),
          if (_destinationLabel != null &&
              _destinationLabel!.trim().isNotEmpty) ...<Widget>[
            Text(
              _destinationLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF66768D),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: _NavigationMetric(
                  label: 'Safety score',
                  value: '$safetyScore%',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _NavigationMetric(
                  label: 'ETA',
                  value: '$etaMinutes min',
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (_isRerouting) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x142F6EF6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF2F6EF6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Rerouting to keep you on the safest path...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF2F6EF6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _navigationAdvisoryText(route),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: route.warning == null
                  ? const Color(0xFF5E6D80)
                  : const Color(0xFF8B5A14),
              height: 1.35,
              fontWeight: route.warning == null
                  ? FontWeight.w500
                  : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          GradientButton(
            label: 'STOP NAVIGATION',
            onPressed: _stopNavigation,
            height: 62,
            borderRadius: 24,
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFE24A3B), Color(0xFFD7644F)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalCard() {
    final ThemeData theme = Theme.of(context);

    return _buildBottomCardShell(
      child: Column(
        key: const ValueKey<String>('arrival-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0x1730C56A),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF30C56A),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'You have arrived',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF0E1B2A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You are within walking distance of your destination.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6D80),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          GradientButton(
            label: 'DONE',
            onPressed: _stopNavigation,
            height: 62,
            borderRadius: 24,
            textStyle: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard() {
    if (_isLoadingRoute && _selectedRoute == null) {
      return Align(
        key: const ValueKey<String>('route-loading'),
        alignment: Alignment.bottomCenter,
        child: RouteInfoCard(
          route: _selectedRoute,
          isLoading: true,
          destinationLabel: _destinationLabel,
          buttonLabel: 'START NAVIGATION',
          onPrimaryPressed: null,
        ),
      );
    }

    if (_navState == NavigationState.planning && _selectedRoute != null) {
      return Align(
        key: const ValueKey<String>('route-planning'),
        alignment: Alignment.bottomCenter,
        child: RouteInfoCard(
          route: _selectedRoute,
          isLoading: false,
          destinationLabel: _destinationLabel,
          buttonLabel: 'START NAVIGATION',
          onPrimaryPressed: _startRoute,
        ),
      );
    }

    if (_navState == NavigationState.active && _selectedRoute != null) {
      final ScoredRoute route = _selectedRoute!;
      return Align(
        key: ValueKey<String>(
          _cardExpanded ? 'route-active-expanded' : 'route-active-collapsed',
        ),
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _cardExpanded
              ? _buildExpandedNavigationCard(route)
              : _buildCollapsedNavigationStrip(route),
        ),
      );
    }

    if (_navState == NavigationState.arrived) {
      return Align(
        key: const ValueKey<String>('route-arrived'),
        alignment: Alignment.bottomCenter,
        child: _buildArrivalCard(),
      );
    }

    return const SizedBox.shrink(key: ValueKey<String>('route-empty'));
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
          child: Transform.rotate(
            angle: _currentHeading * math.pi / 180,
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 24,
            ),
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
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      position = null;
    }

    if (position == null) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Location required for SOS'),
            content: const Text(
              'WalkSafe needs your GPS location to send an accurate SOS alert.\n\n'
              'Please enable location permissions in your phone settings, then try again.\n\n'
              'If you need immediate help, call 112.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openLocationSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final bool sent = await _sosService.sendEmergencyAlert(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(sent ? 'SOS Alert Sent' : 'SOS Alert Failed'),
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
    final bool showBottomCard =
        _isLoadingRoute ||
        _navState == NavigationState.planning ||
        _navState == NavigationState.active ||
        _navState == NavigationState.arrived;
    final double actionBottomOffset =
        _navState == NavigationState.active && !_cardExpanded
        ? 104
        : showBottomCard
        ? 288
        : 28;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          WalkSafeMapView(
            mapController: _mapController,
            initialCenter: _cameraTarget,
            initialZoom: 14.8,
            onMapReady: () {
              if (mounted) {
                setState(() {
                  _mapReady = true;
                });
              }
            },
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
                if (_showCompassReset) ...<Widget>[
                  _MapCircleButton(
                    icon: Icons.explore_rounded,
                    tooltip: 'Reset compass',
                    onPressed: _onCompassResetPressed,
                  ),
                  const SizedBox(height: 12),
                ],
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
              child: _buildBottomCard(),
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

class _NavigationMetric extends StatelessWidget {
  const _NavigationMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final CrossAxisAlignment alignment = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        Text(
          label,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF617286),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF0C1522),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
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
