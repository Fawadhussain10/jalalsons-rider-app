// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import 'proof_of_delivery_screen.dart';
import '../utils/app_colors.dart';
import '../widgets/ui_kit.dart';
import '../utils/time_utils.dart';

/// One turn of the route, from the Mapbox Directions `steps`.
class _NavStep {
  final String instruction;
  final String type;
  final String modifier;
  final double lat;
  final double lng;
  const _NavStep(this.instruction, this.type, this.modifier, this.lat, this.lng);
}

/// Map styles the rider can cycle through: navigation day/night are tuned for
/// driving (clear roads, calm colours), then satellite.
const List<(String, String)> _kMapStyles = [
  ('mapbox://styles/mapbox/navigation-day-v1', 'Navigation'),
  ('mapbox://styles/mapbox/navigation-night-v1', 'Night'),
  (MapboxStyles.MAPBOX_STREETS, 'Streets'),
  (MapboxStyles.SATELLITE_STREETS, 'Satellite'),
];

class MapScreen extends StatefulWidget {
  final dynamic order;
  const MapScreen({super.key, required this.order});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late MapboxMap _mapController;
  PointAnnotationManager? _annotationManager;
  PointAnnotation? _customerMarker;
  PointAnnotation? _riderMarker; // no longer used when default puck is enabled
  Uint8List? _customerIconBytes;
  Uint8List? _riderIconBytes; // no longer used
  StreamSubscription<geo.Position>? _positionStreamSub;
  geo.Position? _currentPosition;

  bool _permissionDenied = false;
  double? _distanceMeters;
  bool _isNavigating = false;
  bool _isLocationSharing = true;
  bool _isMapReady = false;
  bool _followRider = false;
  bool _showBatteryNotice = false;
  int _selectedStyleIndex = 0;
  final List<String> _styleUris = <String>[
    MapboxStyles.MAPBOX_STREETS,
    MapboxStyles.LIGHT,
    MapboxStyles.DARK,
    MapboxStyles.SATELLITE_STREETS,
  ];
  DateTime? _lastCameraUpdateAt;
  final Duration _cameraUpdateDebounce = Duration(milliseconds: 100);
  final List<double> _headingBuffer = <double>[];
  final int _headingBufferMax = 8; // Increased for ultra-smooth rotation

  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  List<Point> _routePoints = [];
  // Removed alternate routes support
  DateTime? _lastRouteFetchAt;
  geo.Position? _lastRouteFetchPosition;
  // Removed duplicate declarations below

  // Navigation progress
  double? _navDistanceMeters;
  double? _navDurationSeconds;
  String? _nextStepInstruction;
  List<_NavStep> _steps = const [];
  int _stepIndex = 1;
  double? _distanceToManeuver;
  Map<String, dynamic>? _lastRouteFeatureCollection;
  // Trip panel: open before the ride, folded into a corner pill while navigating.
  bool _panelExpanded = true;

  final String _routeSourceId = 'route_source_jsr';
  final String _routeLineLayerId = 'route_line_jsr';
  final String _routeCasingLayerId = 'route_casing_jsr';
  // Removed alternate routes support
  bool _hasCustomerIcon = false;
  bool _hasRiderIcon = false;
  bool? _kmsPushOnce;
  Map<String, dynamic>? _prefetchedRouteData; // To store route for instant navigation

  final double _rerouteDistanceThresholdMeters = 15.0; // More sensitive rerouting
  final Duration _rerouteMinInterval = Duration(seconds: 10);
  final Duration _locationUpdateInterval = Duration(seconds: 1); // Realtime tracking

  // Live share cadence trackers
  DateTime? _lastLocationShareAt;
  geo.Position? _lastSharedPosition;

  bool get _canDeliver => _distanceMeters != null && _distanceMeters! <= 400.0;
  bool get _hasValidDeliveryLocation => widget.order.deliveryLatitude != 0.0 && widget.order.deliveryLongitude != 0.0;

  Point get _customerPosition =>
      Point(coordinates: Position(widget.order.deliveryLongitude, widget.order.deliveryLatitude));

  double _smoothHeading(double headingDeg) {
    _headingBuffer.add(headingDeg);
    if (_headingBuffer.length > _headingBufferMax) {
      _headingBuffer.removeAt(0);
    }
    double x = 0, y = 0;
    for (final h in _headingBuffer) {
      final rad = h * math.pi / 180.0;
      x += math.cos(rad);
      y += math.sin(rad);
    }
    final avg = math.atan2(y, x) * 180.0 / math.pi;
    return (avg + 360.0) % 360.0;
  }

  CameraOptions _cameraForSpeed(double speedMps, Point center, double bearing) {
    // Premium dynamic camera: 
    // Higher speed -> Lower zoom (see more), Higher pitch (see further ahead)
    // Lower speed -> Higher zoom (detail), Medium pitch (comfortable view)
    final sp = speedMps.clamp(0.0, 20.0); // max 72km/h for scaling
    final zoom = 17.2 - (sp / 20.0) * 1.8; // 17.2 (slow) -> 15.4 (fast): streets, not rooftops
    final pitch = 50.0 + (sp / 20.0) * 10.0; // 50 (slow) -> 60 (fast)

    return CameraOptions(
      center: center,
      bearing: bearing,
      zoom: zoom,
      pitch: pitch,
      padding: _navCameraPadding,
    );
  }

  /// Puts the rider in the lower part of the screen (above the folded panel)
  /// so most of the view shows the road ahead.
  MbxEdgeInsets get _navCameraPadding {
    final h = MediaQuery.of(context).size.height;
    return MbxEdgeInsets(top: h * 0.42, left: 0, bottom: _panelExpanded ? h * 0.30 : 0, right: 0);
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startLocationStream();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(duration: const Duration(seconds: 3), vsync: this)
      ..repeat(reverse: true);
    _slideController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _fadeController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _mapController = map;
    _annotationManager = await _mapController.annotations.createPointAnnotationManager();

    // Configure location component with minimal settings to reduce frame events
    // Enable default location puck for rider (device) marker
    await _mapController.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: false,
        showAccuracyRing: false,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ),
    );

    // No distance scale over the navigation view.
    try {
      await _mapController.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    } catch (_) {}

    // Optimize map performance settings
    await _optimizeMapPerformance();

    await _ensureRouteSourceAndLayersExist();
    await _registerMarkerImages();
    await _addCustomerMarker();

    // Get initial position but don't immediately move camera
    try {
      final pos = await geo.Geolocator.getCurrentPosition();

      // Set a flag to prevent immediate camera movement
      // Let the location stream handle the first camera update
      _lastCameraUpdateAt = DateTime.now();

      // Only set initial camera if we're not following rider yet
      // This prevents the jump back to rider location
      if (!_followRider) {
        await _mapController.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(pos.longitude, pos.latitude)),
            bearing: pos.heading,
            zoom: 18.0,
            pitch: 45.0,
          ),
        );
      }
    } catch (_) {}

    setState(() {
      _isMapReady = true;
    });

    // Explicitly focus on customer position after map is ready
    await _mapController.flyTo(
      CameraOptions(
        center: _customerPosition,
        zoom: 15.5,
        pitch: 0,
        bearing: 0,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }
  Future<void> _registerMarkerImages() async {
    try {
      final customerBytes = await _tryLoadAsset('assets/markers/customer.png');
      if (customerBytes != null && customerBytes.isNotEmpty) {
        _customerIconBytes = customerBytes;
        _hasCustomerIcon = true;
      }
      final riderBytes = await _tryLoadAsset('assets/markers/bike.png');
      if (riderBytes != null && riderBytes.isNotEmpty) {
        _riderIconBytes = riderBytes;
        _hasRiderIcon = true;
      }
    } catch (_) {
      _hasCustomerIcon = false;
      _hasRiderIcon = false;
    }
  }

  // Removed MbxImage conversion; we attach PNG bytes directly to annotations

  Future<Uint8List?> _tryLoadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _optimizeMapPerformance() async {
    try {
      // Set style transition to reduce frame events
      await _mapController.style.setStyleTransition(
        TransitionOptions(
          delay: 0,
          duration: 0,
          enablePlacementTransitions: false,
        ),
      );

      // Disable unnecessary map features
      await _mapController.setCamera(
        CameraOptions(
          center: _customerPosition,
          zoom: 15.0,
          bearing: 0.0,
          pitch: 0.0,
        ),
      );
    } catch (e) {
      // Silent error handling
    }
  }


  Future<void> _addCustomerMarker() async {
    if (_annotationManager == null) return;
    try {
      // Remove existing customer marker if any
      if (_customerMarker != null) {
        await _annotationManager!.delete(_customerMarker!);
      }

      // Prefer custom icon if registered, else fallback to emoji text
      final hasCustom = _hasCustomerIcon;
      _customerMarker = await _annotationManager!.create(PointAnnotationOptions(
        geometry: _customerPosition,
        image: hasCustom ? _customerIconBytes : null,
        iconAnchor: IconAnchor.BOTTOM,
        iconSize: hasCustom ? 0.25 : null,
        textField: hasCustom ? null : '📍',
        textSize: hasCustom ? null : 12.0,
        textColor: hasCustom ? null : Colors.green.value,
        textAnchor: hasCustom ? null : TextAnchor.BOTTOM,
        textOffset: hasCustom ? null : [0.0, -2.0],
      ));

      // REMOVED: Don't automatically fly to customer location
      // This prevents the camera from jumping between rider and customer locations
      // The location stream will handle camera positioning based on rider location

    } catch (e) {
      // Silent error handling to reduce log spam
    }
  }
  Future<void> _addOrUpdateRiderMarker(geo.Position pos) async {
    if (_annotationManager == null) return;
    try {
      final riderPoint = Point(coordinates: Position(pos.longitude, pos.latitude));
      if (_riderMarker != null) {
        // Only update if position changed significantly to reduce frame events
        final currentPos = _riderMarker!.geometry?.coordinates;
        if (currentPos != null) {
          final distance = geo.Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            currentPos.lat.toDouble(),
            currentPos.lng.toDouble(),
          );
          if (distance < 5.0) return; // Skip update if less than 5 meters
        }

        _riderMarker!.geometry = riderPoint;
        // Rotate with device heading
        try {
          _riderMarker!.iconRotate = pos.heading;
        } catch (_) {}
        await _annotationManager!.update(_riderMarker!);
      } else {
        final hasCustom = _hasRiderIcon;
        _riderMarker = await _annotationManager!.create(PointAnnotationOptions(
          geometry: riderPoint,
          image: hasCustom ? _riderIconBytes : null,
          iconAnchor: IconAnchor.CENTER,
          iconSize: hasCustom ? 0.35 : null,
          iconRotate: 0.0,
          textField: hasCustom ? null : '🏍️',
          textSize: hasCustom ? null : 12.0,
          textColor: hasCustom ? null : Colors.blue.value,
          textAnchor: hasCustom ? null : TextAnchor.CENTER,
        ));
      }
    } catch (e) {
      // Silent error handling to reduce log spam
    }
  }

  Future<void> _startLocationStream() async {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    // Extreme performance settings: 0 meters distance filter and 1s interval
    final geo.LocationSettings settings = Platform.isAndroid
        ? geo.AndroidSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            forceLocationManager: false,
            foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
              notificationTitle: 'Extreme High Performance Active',
              notificationText: 'Optimizing tracking for best delivery speed.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : geo.AppleSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false,
            activityType: geo.ActivityType.fitness,
          );

    _positionStreamSub = geo.Geolocator.getPositionStream(locationSettings: settings).listen(
          (pos) async {
        // Only update if position is valid and significantly different
        if (pos.latitude == 0.0 && pos.longitude == 0.0) return;
        final now = DateTime.now();

        // For the first position update, wait a bit before moving camera
        // This gives the customer marker animation time to complete
        final isFirstUpdate = _lastCameraUpdateAt == null;

        // Smooth speed-adaptive camera with smoothed bearing
        if (_followRider) {
            // For the first position update, wait a bit before moving camera
            if (isFirstUpdate) {
              await Future.delayed(const Duration(milliseconds: 500));
            }

            _lastCameraUpdateAt = now;
            try {
              final center = Point(coordinates: Position(pos.longitude, pos.latitude));
              final bearing = _smoothHeading(pos.heading);
              final cam = _cameraForSpeed(pos.speed, center, bearing);
              
              // Match animation duration to GPS interval (1s) for continuous fluid movement
              // This eliminates the "stop-and-go" look of the camera
              await _mapController.easeTo(
                cam,
                MapAnimationOptions(duration: 1000),
              );
            } catch (_) {}
        } else if (_prefetchedRouteData == null && !isFirstUpdate) {
          // Pre-fetch route in background so it's ready when Navigate is clicked
          unawaited(_fetchAndShowRouteForPosition(pos, isPrefetch: true));
        }

        final d = geo.Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          widget.order.deliveryLatitude,
          widget.order.deliveryLongitude,
        );

        if (mounted) {
          setState(() {
            _distanceMeters = d;
            _currentPosition = pos;
            _advanceStep(pos);
          });
        }

        // Update live location sharing aggressively (time or distance or heading change)
        if (_isLocationSharing) {
          final movedMeters = _lastSharedPosition == null
              ? double.infinity
              : geo.Geolocator.distanceBetween(
                  pos.latitude,
                  pos.longitude,
                  _lastSharedPosition!.latitude,
                  _lastSharedPosition!.longitude,
                );

          final headingDelta = _lastSharedPosition == null
              ? 180.0
              : ((pos.heading - _lastSharedPosition!.heading).abs());

          final timeOk = _lastLocationShareAt == null || now.difference(_lastLocationShareAt!) >= _locationUpdateInterval;
          final distanceOk = movedMeters >= 5.0; // push if moved ≥ 5m
          final headingOk = headingDelta >= 10.0; // or heading changed significantly

          if (timeOk || distanceOk || headingOk) {
            final rider = context.read<AuthProvider>().currentRider;
            if (rider != null) {
              // Mark as sent before the write so a slow network can't queue duplicates.
              _lastLocationShareAt = now;
              _lastSharedPosition = pos;
              unawaited(FirebaseService.updateRiderLiveLocation(rider.id, {
                'lat': pos.latitude,
                'lng': pos.longitude,
                'updatedAt': now.toIso8601String(),
                'orderId': widget.order.id,
                'bearing': pos.heading,
                'speed': pos.speed,
                'accuracy': pos.accuracy.round(),
              }));
            }
          }
        }

        if (_isNavigating && _shouldReroute(pos)) {
          _lastRouteFetchAt = DateTime.now();
          _lastRouteFetchPosition = pos;
          unawaited(_fetchAndShowRouteForPosition(pos));
        }
      },
      onError: (error) {
        // Silent error handling to reduce log spam
      },
    );
  }


  /// Moves the turn banner on once the rider reaches the upcoming maneuver.
  void _advanceStep(geo.Position pos) {
    if (_steps.isEmpty) return;
    double distTo(int i) => geo.Geolocator.distanceBetween(pos.latitude, pos.longitude, _steps[i].lat, _steps[i].lng);
    while (_stepIndex < _steps.length - 1 && distTo(_stepIndex) < 18) {
      _stepIndex++;
    }
    _distanceToManeuver = distTo(_stepIndex);
    _nextStepInstruction = _steps[_stepIndex].instruction;
  }

  bool _shouldReroute(geo.Position pos) {
    if (_lastRouteFetchAt == null || _lastRouteFetchPosition == null) return true;
    final since = DateTime.now().difference(_lastRouteFetchAt!);
    if (since >= _rerouteMinInterval) return true;
    final moved = geo.Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      _lastRouteFetchPosition!.latitude,
      _lastRouteFetchPosition!.longitude,
    );
    // Further increased threshold to reduce rerouting frequency and frame events
    return moved >= _rerouteDistanceThresholdMeters * 3;
  }

  Future<void> _showLocationDisclosureDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue, size: 28),
              SizedBox(width: 8),
              Text(
                'Location Access',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'JS Rider collects location data to track and display active delivery routes to customers and dispatchers.',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'This data is collected in the background (even when the app is closed or not in use) while you are on an active delivery run.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _permissionDenied = true);
      return false;
    }
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      await _showLocationDisclosureDialog();
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        setState(() => _permissionDenied = true);
        return false;
      }
    }
    if (permission == geo.LocationPermission.deniedForever) {
      setState(() => _permissionDenied = true);
      return false;
    }
    return true;
  }

  Future<void> _onNavigate() async {
    if (!_hasValidDeliveryLocation) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Delivery address has no GPS coordinates')),
        );
      }
      return;
    }

    if (_isNavigating) {
      final pos = _currentPosition ?? await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 3),
      ).catchError((_) => geo.Geolocator.getLastKnownPosition());
      
      if (pos == null) return;
      
      _followRider = true;
      await _mapController.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 17.2,
          pitch: 55.0,
          bearing: pos.heading,
          padding: _navCameraPadding,
        ),
        MapAnimationOptions(duration: 800),
      );
      return;
    }

    // Optimization: If route was pre-fetched, show it instantly
    setState(() {
      _isNavigating = true;
      _followRider = true;
      _panelExpanded = false; // give the map the screen while riding
    });

    final pos = _currentPosition ?? await geo.Geolocator.getCurrentPosition(
      desiredAccuracy: geo.LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 3),
    ).catchError((_) => geo.Geolocator.getLastKnownPosition());

    if (pos == null) return;

    if (_prefetchedRouteData != null) {
      _showRouteFromData(_prefetchedRouteData!, pos);
    } else {
      unawaited(_fetchAndShowRouteForPosition(pos));
    }

  }

  Future<void> _fetchAndShowRouteForPosition(geo.Position startPos, {bool isPrefetch = false}) async {
    final start = '${startPos.longitude},${startPos.latitude}';
    final end = '${widget.order.deliveryLongitude},${widget.order.deliveryLatitude}';

    final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$start;$end?geometries=geojson&overview=full&alternatives=false&steps=true&access_token=${AppConfig.mapboxAccessToken}');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (isPrefetch) {
        _prefetchedRouteData = data;
        return;
      }

      _showRouteFromData(data, startPos);
    } catch (e) {
      debugPrint('Route fetch error: $e');
    }
  }

  Future<void> _showRouteFromData(Map<String, dynamic> data, geo.Position startPos) async {
    try {
      final routes = data['routes'] as List? ?? [];
      if (routes.isEmpty) return;
      
      final selectedRoute = routes.first;
      final geometry = selectedRoute['geometry'];
      final coords = (geometry?['coordinates'] as List?) ?? [];
      if (coords.isEmpty) return;

      _routePoints = coords
          .map((c) => Point(coordinates: Position((c[0] as num).toDouble(), (c[1] as num).toDouble())))
          .toList();

      _navDistanceMeters = (selectedRoute['distance'] as num?)?.toDouble();
      _navDurationSeconds = (selectedRoute['duration'] as num?)?.toDouble();

      _updateKmsInBackground();

      try {
        final legs = selectedRoute['legs'] as List?;
        final rawSteps = (legs != null && legs.isNotEmpty) ? (legs.first['steps'] as List? ?? []) : [];
        _steps = [
          for (final st in rawSteps)
            if (st is Map && st['maneuver'] is Map && (st['maneuver']['location'] as List?)?.length == 2)
              _NavStep(
                (st['maneuver']['instruction'] ?? '').toString(),
                (st['maneuver']['type'] ?? '').toString(),
                (st['maneuver']['modifier'] ?? '').toString(),
                ((st['maneuver']['location'] as List)[1] as num).toDouble(),
                ((st['maneuver']['location'] as List)[0] as num).toDouble(),
              ),
        ];
        // steps[0] is "depart" at the rider's position; the next turn is steps[1].
        _stepIndex = _steps.length > 1 ? 1 : 0;
        _nextStepInstruction = _steps.isNotEmpty ? _steps[_stepIndex].instruction : 'Proceed';
        _advanceStep(startPos);
      } catch (_) {}

      final featureCollection = <String, dynamic>{
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "duration": selectedRoute['duration'],
              "distance": selectedRoute['distance'],
            },
            "geometry": geometry
          }
        ],
      };

      _lastRouteFeatureCollection = featureCollection;
      if (await _mapController.style.styleSourceExists(_routeSourceId)) {
        await _mapController.style.setStyleSourceProperty(
          _routeSourceId,
          'data',
          jsonEncode(featureCollection),
        );
      } else {
        await _mapController.style.addStyleSource(
          _routeSourceId, 
          jsonEncode({"type": "geojson", "data": featureCollection})
        );
      }

      if (_routePoints.isNotEmpty && _followRider) {
        await _mapController.flyTo(
          CameraOptions(
            center: _routePoints.first,
            zoom: 17.2,
            pitch: 55.0,
            bearing: startPos.heading,
            padding: _navCameraPadding,
          ),
          MapAnimationOptions(duration: 1200),
        );
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Show route error: $e');
    }
  }

  void _updateKmsInBackground() async {
    try {
      if (_navDistanceMeters != null && (_kmsPushOnce ?? false) == false) {
        final kms = (_navDistanceMeters! / 1000.0);
        final ok = await context.read<OrderProvider>().updateDeliveryKmsOnce(
          widget.order.id.toString(), 
          kms,
          estimatedSeconds: _navDurationSeconds,
        );
        if (ok && mounted) {
          _kmsPushOnce = true;
        }
      }
    } catch (_) {}
  }

  // Alternate routes feature removed

  Future<void> _ensureRouteSourceAndLayersExist() async {
    try {
      // Main route source and layer
      if (!await _mapController.style.styleSourceExists(_routeSourceId)) {
        var source = {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}};
        await _mapController.style.addStyleSource(_routeSourceId, json.encode(source));
      }

      if (!await _mapController.style.styleLayerExists(_routeCasingLayerId)) {
        await _mapController.style.addStyleLayer(json.encode({
          "id": _routeCasingLayerId,
          "type": "line",
          "source": _routeSourceId,
          "layout": {"line-join": "round", "line-cap": "round"},
          "paint": {
            "line-color": "#FFFFFF",
            "line-width": ["interpolate", ["linear"], ["zoom"], 12, 7.0, 18, 16.0],
            "line-opacity": 0.95
          }
        }), null);
      }
      if (!await _mapController.style.styleLayerExists(_routeLineLayerId)) {
        await _mapController.style.addStyleLayer(json.encode({
          "id": _routeLineLayerId,
          "type": "line",
          "source": _routeSourceId,
          "layout": {"line-join": "round", "line-cap": "round"},
          "paint": {
            "line-color": "#E51A1A",
            "line-width": ["interpolate", ["linear"], ["zoom"], 12, 4.0, 18, 10.0],
            "line-opacity": 1.0
          }
        }), null);
      }
      // A style switch drops sources; put the current route back.
      if (_lastRouteFeatureCollection != null) {
        await _mapController.style.setStyleSourceProperty(
            _routeSourceId, 'data', jsonEncode(_lastRouteFeatureCollection));
      }

      // Route arrows layer removed to avoid missing 'arrow_icon' image errors
    } catch (e) {
      debugPrint('ensureRouteSourceAndLayersExist error: $e');
    }
  }

  // Convert international number to Pakistani local format (03...)
  String _formatPakistaniNumber(String number) {
    // Remove all non-digit characters except +
    String cleaned = number.replaceAll(RegExp(r'[^0-9+]+'), '');
    
    // If number already starts with 0, return as is (already in Pakistani format)
    if (cleaned.startsWith('0')) {
      return cleaned;
    }
    
    // If number starts with +92 (Pakistan country code)
    if (cleaned.startsWith('+92')) {
      // Remove +92 and add 0 at the beginning
      String withoutCountryCode = cleaned.substring(3); // Remove '+92'
      if (withoutCountryCode.length >= 10) {
        return '0$withoutCountryCode';
      }
    }
    
    // If number starts with other country codes (+1, +2, etc.), convert to Pakistani format
    if (cleaned.startsWith('+')) {
      // Remove the + and country code
      String digitsOnly = cleaned.substring(1); // Remove '+'
      
      // Pakistani mobile numbers are typically 11 digits (03XX XXXXXXX)
      // If we have 11 or more digits, try to extract Pakistani number pattern
      if (digitsOnly.length >= 11) {
        // Try to find Pakistani mobile pattern (starts with 3)
        // Take the last 11 digits and ensure it starts with 0
        String lastDigits = digitsOnly.substring(digitsOnly.length - 11);
        if (lastDigits.startsWith('3')) {
          return '0$lastDigits';
        }
        // If doesn't start with 3, still add 0 prefix for Pakistani format
        if (!lastDigits.startsWith('0')) {
          return '0$lastDigits';
        }
        return lastDigits;
      }
      
      // If less than 11 digits, try to format as Pakistani number
      if (digitsOnly.length == 10 && digitsOnly.startsWith('3')) {
        return '0$digitsOnly';
      }
    }
    
    // If number doesn't start with + or 0, try to format it
    String digitsOnly = cleaned.replaceAll('+', '');
    
    // If it's 10 digits and starts with 3, add 0 prefix
    if (digitsOnly.length == 10 && digitsOnly.startsWith('3')) {
      return '0$digitsOnly';
    }
    
    // If it's 11 digits and doesn't start with 0, check if it starts with 3
    if (digitsOnly.length == 11 && !digitsOnly.startsWith('0')) {
      if (digitsOnly.startsWith('3')) {
        return '0$digitsOnly';
      }
      // If it doesn't start with 3, it might be a different format, keep as is
    }
    
    // Return cleaned number as fallback
    return digitsOnly.isNotEmpty ? digitsOnly : cleaned;
  }

  Future<void> _onCallCustomer() async {
    final rawNumber = widget.order.customerPhone ?? widget.order.customer?.phone;
    if (rawNumber == null || rawNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Customer phone number not available'),
            backgroundColor: Colors.orange[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Format number for Pakistan (convert +92, +1, +2 etc. to 03... format)
    String formattedNumber = _formatPakistaniNumber(rawNumber);
    
    // Create tel: URI with formatted number
    final Uri telUri = Uri(scheme: 'tel', path: formattedNumber);
    
    try {
      // Try multiple launch modes to ensure compatibility across all devices
      bool launched = false;
      
      // First attempt: platformDefault (works on most Android devices)
      try {
        launched = await launchUrl(
          telUri,
          mode: LaunchMode.platformDefault,
        );
        if (launched) return;
      } catch (e) {
        debugPrint('PlatformDefault launch failed: $e');
      }
      
      // Second attempt: externalNonBrowserApplication (for devices that need explicit app selection)
      try {
        launched = await launchUrl(
          telUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        if (launched) return;
      } catch (e) {
        debugPrint('ExternalNonBrowserApplication launch failed: $e');
      }
      
      // Third attempt: externalApplication (fallback)
      try {
        launched = await launchUrl(
          telUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (e) {
        debugPrint('ExternalApplication launch failed: $e');
      }

      // If all attempts failed
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to open dialer. Please check if a dialer app is installed.'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to open dialer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open dialer: ${e.toString()}'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onDelivered() async {
    if (!_canDeliver) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Move closer to the delivery location (≤400m). Current: ${_distanceMeters?.toStringAsFixed(0) ?? '-'} m'), 
            backgroundColor: Colors.orange[600], 
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Direct navigation to ProofOfDeliveryScreen as requested
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProofOfDeliveryScreen(
          order: widget.order as Order,
        ),
      ),
    );

    if (result == true && mounted) {
      // POD submitted successfully, update local status
      final orderProvider = context.read<OrderProvider>();
      // The proof-of-delivery upload already marked it delivered in Odoo.
      await orderProvider.updateOrderStatus(
        widget.order.id.toString(),
        OrderStatus.delivered,
        backendAlreadyUpdated: true,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order marked as delivered'), 
            backgroundColor: Colors.green[600],
          ),
        );
        Navigator.pop(context); // Close MapScreen
      }
    }
  }

  Future<void> _onOpenInGoogleMaps() async {
    if (!_hasValidDeliveryLocation) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No GPS coordinates for this order')),
        );
      }
      return;
    }
    final lat = widget.order.deliveryLatitude;
    final lng = widget.order.deliveryLongitude;
    
    // Using universal link that works on both Android and iOS
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Google Maps app'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening Google Maps: $e');
    }
  }

  void _toggleLocationSharing() {
    setState(() => _isLocationSharing = !_isLocationSharing);
  }

  // Route selection UI removed

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.round());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '${meters.round()} m';
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────

  Order? get _typedOrder => widget.order is Order ? widget.order as Order : null;

  IconData _maneuverIcon(_NavStep? step) {
    if (step == null) return Icons.navigation_rounded;
    final m = step.modifier;
    if (step.type == 'arrive') return Icons.flag_rounded;
    if (step.type == 'roundabout' || step.type == 'rotary') return Icons.roundabout_right_rounded;
    if (m == 'uturn') return Icons.u_turn_left_rounded;
    if (m == 'sharp left') return Icons.turn_sharp_left_rounded;
    if (m == 'sharp right') return Icons.turn_sharp_right_rounded;
    if (m == 'slight left') return Icons.turn_slight_left_rounded;
    if (m == 'slight right') return Icons.turn_slight_right_rounded;
    if (m == 'left') return Icons.turn_left_rounded;
    if (m == 'right') return Icons.turn_right_rounded;
    return Icons.straight_rounded;
  }

  String get _etaClock {
    if (_navDurationSeconds == null) return '';
    return TimeUtils.timeOfDay(DateTime.now().add(Duration(seconds: _navDurationSeconds!.round())));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: Stack(
          // Fill the screen even before the map view has laid out.
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: const ValueKey("mapWidget"),
              styleUri: _kMapStyles.first.$1,
              cameraOptions: CameraOptions(
                center: _hasValidDeliveryLocation
                    ? _customerPosition
                    : (_currentPosition != null
                        ? Point(coordinates: Position(_currentPosition!.longitude, _currentPosition!.latitude))
                        : Point(coordinates: Position(74.3587, 31.5204))), // Lahore fallback
                zoom: _hasValidDeliveryLocation ? 15.0 : 12.0,
                bearing: 0.0,
                pitch: 0.0,
              ),
              onMapCreated: _onMapCreated,
            ),

            // Soft fade at the top so the status bar stays readable over any map.
            IgnorePointer(
              child: Container(
                height: pad.top + 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ),

            // Top: back button + turn-by-turn banner (or destination chip before starting)
            Positioned(
              top: pad.top + 10,
              left: 14,
              right: 14,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GlassButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _isNavigating ? _buildTurnBanner() : _buildDestinationChip()),
                  ],
                ),
              ),
            ),

            if (_permissionDenied)
              Positioned(
                top: pad.top + 84,
                left: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_off_rounded, color: AppColors.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Location permission is required for navigation.',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                      ),
                    ],
                  ),
                ),
              ),

            // Right: map controls
            Positioned(
              right: 14,
              top: pad.top + (_isNavigating ? 120 : 76),
              child: SlideTransition(position: _slideAnimation, child: _buildMapControls()),
            ),

            // Bottom: trip panel, or folded into a corner pill while riding.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                      alignment: Alignment.bottomLeft,
                      child: child,
                    ),
                  ),
                  child: _panelExpanded
                      ? KeyedSubtree(key: const ValueKey('panel'), child: _buildTripPanel(pad.bottom))
                      : KeyedSubtree(key: const ValueKey('folded'), child: _buildFoldedBar(pad.bottom)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          const IconBadge(icon: Icons.flag_rounded, color: AppColors.primary, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivering to #${_typedOrder?.reference ?? widget.order.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                Text(
                  (widget.order.deliveryAddress as String?)?.isNotEmpty == true
                      ? widget.order.deliveryAddress as String
                      : (widget.order.customerName ?? 'Customer').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnBanner() {
    final step = _steps.isNotEmpty ? _steps[_stepIndex] : null;
    final arriving = step?.type == 'arrive' || (_distanceMeters != null && _distanceMeters! < 60);
    final instruction = arriving
        ? 'You have arrived'
        : (_nextStepInstruction?.isNotEmpty == true ? _nextStepInstruction! : 'Follow the route');
    final dist = _distanceToManeuver;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: arriving ? AppColors.primaryGradient : AppColors.inkGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(arriving ? Icons.flag_rounded : _maneuverIcon(step), color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!arriving && dist != null)
                  Text(dist < 1000 ? 'In ${(dist / 10).round() * 10} m' : 'In ${(dist / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                Text(
                  instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: arriving || dist == null ? 1 : 0.8),
                    fontSize: arriving || dist == null ? 17 : 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: _followRider ? Icons.my_location_rounded : Icons.location_searching_rounded,
            color: _followRider ? AppColors.info : AppColors.textSecondary,
            active: _followRider,
            tooltip: _followRider ? 'Following you' : 'Follow me',
            onTap: () => setState(() => _followRider = !_followRider),
          ),
          _ControlButton(
            icon: Icons.explore_rounded,
            tooltip: 'North up',
            onTap: () async {
              try {
                final pos = _currentPosition ?? await geo.Geolocator.getCurrentPosition();
                await _mapController.flyTo(
                  CameraOptions(
                    center: Point(coordinates: Position(pos.longitude, pos.latitude)),
                    bearing: 0.0,
                    pitch: 0.0,
                  ),
                  MapAnimationOptions(duration: 600),
                );
              } catch (_) {}
            },
          ),
          _ControlButton(
            icon: Icons.layers_rounded,
            tooltip: 'Map style: ${_kMapStyles[_selectedStyleIndex].$2}',
            onTap: () async {
              setState(() => _selectedStyleIndex = (_selectedStyleIndex + 1) % _kMapStyles.length);
              try {
                await _mapController.loadStyleURI(_kMapStyles[_selectedStyleIndex].$1);
                await _ensureRouteSourceAndLayersExist();
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Map: ${_kMapStyles[_selectedStyleIndex].$2}'),
                  duration: const Duration(milliseconds: 900),
                ));
              }
            },
          ),
          _ControlButton(
            imagePath: 'assets/icons/Google_map_icon.png',
            tooltip: 'Open in Google Maps',
            onTap: _onOpenInGoogleMaps,
          ),
        ],
      ),
    );
  }

  /// Folded state: a pill in the bottom-left corner (tap or swipe up to open) and,
  /// once inside the 400 m zone, a Delivered button on the right.
  Widget _buildFoldedBar(double bottomInset) {
    final title = _navDurationSeconds != null
        ? _formatDuration(_navDurationSeconds!)
        : (_distanceMeters != null ? _formatDistance(_distanceMeters!) : 'Trip');
    final subtitle = _navDurationSeconds != null
        ? '${_navDistanceMeters != null ? _formatDistance(_navDistanceMeters!) : ''} · $_etaClock'
        : 'Tap for details';
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _FoldedPill(title: title, subtitle: subtitle, onTap: () => setState(() => _panelExpanded = true)),
          const Spacer(),
          if (_canDeliver)
            FilledButton.icon(
              onPressed: _onDelivered,
              style: FilledButton.styleFrom(
                minimumSize: const ui.Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const StadiumBorder(),
                elevation: 6,
              ),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Delivered'),
            ),
        ],
      ),
    );
  }

  Widget _buildTripPanel(double bottomInset) {
    final order = _typedOrder;
    final name = (widget.order.customerName ?? 'Customer').toString();
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    final cod = order?.isCashOnDelivery ?? true;
    final amount = order?.amount ?? 0.0;
    final away = _distanceMeters;
    // Proximity meter: full when inside the 400 m delivery zone.
    final progress = away == null ? 0.0 : (1 - ((away - 400) / 3000)).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.fromLTRB(18, 4, 18, bottomInset + 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 30, offset: Offset(0, -6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle + fold button; a downward swipe folds the panel too.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _panelExpanded = false),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 150) setState(() => _panelExpanded = false);
            },
            child: SizedBox(
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                  ),
                  const Positioned(
                    right: 0,
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 28),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Trip summary
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _navDurationSeconds != null ? _formatDuration(_navDurationSeconds!) : (away != null ? _formatDistance(away) : '—'),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.05),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _navDurationSeconds != null
                          ? '${_navDistanceMeters != null ? _formatDistance(_navDistanceMeters!) : ''} · arrive by $_etaClock'
                          : (away != null ? 'from the customer' : 'Locating you…'),
                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (_canDeliver)
                const StatusChip(label: 'IN DELIVERY ZONE', color: AppColors.success, icon: Icons.verified_rounded)
              else if (!_isNavigating)
                StatusChip(
                  label: away == null ? 'LOCATING' : '${_formatDistance(away)} AWAY',
                  color: AppColors.warning,
                  icon: Icons.near_me_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.canvas,
              valueColor: AlwaysStoppedAnimation(_canDeliver ? AppColors.success : AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),

          // Customer
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(16)),
                child: Text(initials.isEmpty ? '?' : initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      '#${order?.reference ?? widget.order.id}${(widget.order.deliveryAddress as String?)?.isNotEmpty == true ? ' · ${widget.order.deliveryAddress}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _RoundAction(icon: Icons.call_rounded, color: AppColors.success, tooltip: 'Call customer', onTap: _onCallCustomer),
            ],
          ),
          const SizedBox(height: 14),

          // Payment strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: cod ? AppColors.warningSoft : AppColors.successSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(cod ? Icons.payments_rounded : Icons.verified_rounded,
                    color: cod ? const Color(0xFFB45309) : AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(cod ? 'Collect cash from customer' : 'Already paid · nothing to collect',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cod ? const Color(0xFF92400E) : const Color(0xFF0B7A3B))),
                ),
                if (cod)
                  Text(formatRs(amount),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _onNavigate,
                  style: FilledButton.styleFrom(
                    minimumSize: const ui.Size.fromHeight(54),
                    backgroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(_isNavigating ? Icons.my_location_rounded : Icons.navigation_rounded),
                  label: Text(_isNavigating ? 'Re-center' : 'Navigate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _onDelivered, // explains the 400 m rule when still too far
                  style: FilledButton.styleFrom(
                    minimumSize: const ui.Size.fromHeight(54),
                    backgroundColor: _canDeliver ? AppColors.primary : const Color(0xFFE9EAEE),
                    foregroundColor: _canDeliver ? Colors.white : AppColors.textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(_canDeliver ? Icons.photo_camera_rounded : Icons.lock_clock_rounded),
                  label: const Text('Delivered'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FoldedPill extends StatelessWidget {
  const _FoldedPill({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -150) onTap(); // swipe up opens it
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        decoration: BoxDecoration(
          gradient: AppColors.inkGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.1)),
                Text(subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: AppColors.cardShadow),
            child: Icon(icon, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.imagePath,
    this.color = AppColors.textPrimary,
    this.active = false,
  });
  final IconData? icon;
  final String? imagePath;
  final Color color;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active ? AppColors.infoSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.all(imagePath != null ? 11 : 0),
          child: imagePath != null ? Image.asset(imagePath!, fit: BoxFit.contain) : Icon(icon, color: color, size: 23),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.color, required this.onTap, required this.tooltip});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 50, height: 50, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}
