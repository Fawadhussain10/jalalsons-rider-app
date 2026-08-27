// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import 'proof_of_delivery_screen.dart';

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

  final String _routeSourceId = 'route_source_jsr';
  final String _routeLineLayerId = 'route_line_jsr';
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
    final zoom = 18.5 - (sp / 20.0) * 3.5; // 18.5 (slow) -> 15.0 (fast)
    final pitch = 45.0 + (sp / 20.0) * 25.0; // 45 (slow) -> 70 (fast)
    
    return CameraOptions(
      center: center, 
      bearing: bearing, 
      zoom: zoom, 
      pitch: pitch,
    );
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
            final auth = context.read<AuthProvider>();
            final rider = auth.currentRider;
            if (rider != null) {
              try {
                await FirebaseService.saveRiderData(
                  riderId: rider.id,
                  name: rider.name,
                  email: rider.email,
                  phone: rider.phone,
                  vehicleNumber: rider.vehicleNumber,
                  vehicleType: rider.vehicleType,
                  preferences: {
                    'liveLocation': {
                      'lat': pos.latitude,
                      'lng': pos.longitude,
                      'updatedAt': now.toIso8601String(),
                      'orderId': widget.order.id,
                      'bearing': pos.heading,
                      'speed': pos.speed,
                    },
                  },
                );
                _lastLocationShareAt = now;
                _lastSharedPosition = pos;
              } catch (_) {}
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

  Future<bool> _showLocationDisclosureDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Deny',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Accept',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _permissionDenied = true);
      return false;
    }
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      final accepted = await _showLocationDisclosureDialog();
      if (!accepted) {
        setState(() => _permissionDenied = true);
        return false;
      }
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
          zoom: 18.0,
          pitch: 60.0,
          bearing: pos.heading,
        ),
        MapAnimationOptions(duration: 800),
      );
      return;
    }

    // Optimization: If route was pre-fetched, show it instantly
    setState(() {
      _isNavigating = true;
      _followRider = true;
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Navigation started!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchAndShowRouteForPosition(geo.Position startPos, {bool isPrefetch = false}) async {
    final start = '${startPos.longitude},${startPos.latitude}';
    final end = '${widget.order.deliveryLongitude},${widget.order.deliveryLatitude}';

    final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/$start;$end?geometries=geojson&overview=simplified&alternatives=false&steps=true&access_token=${AppConfig.mapboxAccessToken}');

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
        if (legs != null && legs.isNotEmpty) {
          final steps = legs.first['steps'] as List?;
          if (steps != null && steps.isNotEmpty) {
            _nextStepInstruction = (steps.first['maneuver']?['instruction'] as String?) ?? 'Proceed';
          }
        }
      } catch (_) {}

      final featureCollection = {
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
            zoom: 18.0,
            pitch: 65.0,
            bearing: startPos.heading,
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

      if (!await _mapController.style.styleLayerExists(_routeLineLayerId)) {
        var layer = {
          "id": _routeLineLayerId,
          "type": "line",
          "source": _routeSourceId,
          "layout": {
            "line-join": "round",
            "line-cap": "round"
          },
          "paint": {
            "line-color": "#007AFF",
            "line-width": 6.0,
            "line-opacity": 0.9
          }
        };
        await _mapController.style.addStyleLayer(json.encode(layer), null);
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
      await orderProvider.updateOrderStatus(widget.order.id.toString(), OrderStatus.delivered);
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          MapWidget(
            key: ValueKey("mapWidget"),
            styleUri: MapboxStyles.MAPBOX_STREETS,
            cameraOptions: CameraOptions(
              center: _hasValidDeliveryLocation 
                  ? _customerPosition 
                  : (_currentPosition != null 
                      ? Point(coordinates: Position(_currentPosition!.longitude, _currentPosition!.latitude))
                      : Point(coordinates: Position(55.2708, 25.2048))), // Dubai fallback
              zoom: _hasValidDeliveryLocation ? 15.0 : 12.0,
              bearing: 0.0,
              pitch: 0.0,
            ),
            onMapCreated: _onMapCreated,
          ),


          // Permission denied banner
          if (_permissionDenied)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_off, color: Colors.red[600]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                            'Location permission is required for navigation.',
                            style: TextStyle(fontWeight: FontWeight.w500)
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Customer info card
          if (_isMapReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 32,
              left: 16,
              right: 16,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildCustomerInfoCard(),
              ),
            ),

          // Floating circular buttons panel - bottom left
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 186,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildFloatingCircularButtons(),
            ),
          ),

          // Navigation controls (main action buttons)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildNavigationControls(),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildCustomerInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Navigation info (only when navigating)
          if (_isNavigating && (_navDistanceMeters != null || _navDurationSeconds != null)) ...[
            Row(
              children: [
                Icon(Icons.route, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 6),
                if (_navDistanceMeters != null)
                  Text(_formatDistance(_navDistanceMeters!),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                if (_navDurationSeconds != null) ...[
                  const SizedBox(width: 6),
                  Text(_formatDuration(_navDurationSeconds!),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
                if (_nextStepInstruction != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _nextStepInstruction!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],

          // Main customer info
          Row(
            children: [
              // Status icon
              Icon(
                _canDeliver ? Icons.location_on : Icons.navigation,
                color: _canDeliver ? Colors.green[600] : Colors.orange[600],
                size: 18,
              ),
              const SizedBox(width: 8),

              // Customer details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.order.customerName ?? 'Customer',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Order #${widget.order.id}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (widget.order.deliveryAddress != null)
                      Text(
                        widget.order.deliveryAddress!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // Distance badge
              if (_distanceMeters != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _canDeliver ? Colors.green[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDistance(_distanceMeters!),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _canDeliver ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // _buildRouteAlternatives removed

  Widget _buildFloatingCircularButtons() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Follow toggle button
          _buildCircularButton(
            onTap: () => setState(() => _followRider = !_followRider),
            icon: _followRider ? Icons.gps_fixed : Icons.gps_off,
            color: _followRider ? Colors.blue : Colors.grey,
            tooltip: _followRider ? 'Following' : 'Free',
          ),
          const SizedBox(height: 8),
          // Compass button
          _buildCircularButton(
            onTap: () async {
              try {
                final pos = await geo.Geolocator.getCurrentPosition();
                _followRider = true;
                await _mapController.setCamera(CameraOptions(
                  center: Point(coordinates: Position(pos.longitude, pos.latitude)),
                  bearing: 0.0,
                ));
                setState(() {});
              } catch (_) {}
            },
            icon: Icons.explore,
            color: Colors.grey[700]!,
            tooltip: 'Reset North',
          ),
          const SizedBox(height: 8),
          // Style switcher button
          _buildCircularButton(
            onTap: () async {
              setState(() => _selectedStyleIndex = (_selectedStyleIndex + 1) % 4);
              try {
                await _mapController.loadStyleURI((_selectedStyleIndex == 0) ? MapboxStyles.MAPBOX_STREETS : (_selectedStyleIndex == 1) ? MapboxStyles.LIGHT : (_selectedStyleIndex == 2) ? MapboxStyles.DARK : MapboxStyles.SATELLITE_STREETS);
                await _ensureRouteSourceAndLayersExist();
              } catch (_) {}
            },
            icon: Icons.layers,
            color: Colors.grey[700]!,
            tooltip: 'Change Map Style',
          ),
          const SizedBox(height: 8),
          // Google Maps redirect button
          _buildCircularButton(
            onTap: _onOpenInGoogleMaps,
            imagePath: 'assets/icons/Google_map_icon.png',
            color: Colors.red[600]!,
            tooltip: 'Open in Google Maps',
          ),
        ],
      ),
    );
  }

  Widget _buildCircularButton({
    required VoidCallback onTap,
    IconData? icon,
    String? imagePath,
    required Color color,
    required String tooltip,
  }) {
    return Material(
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: imagePath != null 
            ? Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.asset(imagePath, fit: BoxFit.contain),
              )
            : Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildFloatingPillButton(
                onPressed: _onNavigate,
                icon: _isNavigating ? Icons.my_location : Icons.navigation,
                label: _isNavigating ? "Re-center" : "Navigate",
                color: _isNavigating ? Colors.orange : Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFloatingPillButton(
                onPressed: _onCallCustomer,
                icon: Icons.phone,
                label: "Call",
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFloatingPillButton(
                onPressed: _canDeliver ? _onDelivered : null,
                icon: Icons.camera_alt,
                label: "Delivered",
                color: _canDeliver ? Colors.red : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingPillButton({required VoidCallback? onPressed, required IconData icon, required String label, required Color color}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}