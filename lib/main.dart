import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'screens/splash_screen.dart';
import 'screens/main_navigation.dart';
import 'providers/auth_provider.dart';
import 'providers/order_provider.dart';
import 'utils/app_theme.dart';
import 'services/firebase_service.dart';
import 'services/data_sync_service.dart';
import 'services/offline_service.dart';
import 'config/app_config.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();
  if (kDebugMode) {
    print("Handling a background message: ${message.messageId}");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using google-services.json
  try {
    await Firebase.initializeApp();
    await FirebaseService.initialize();
    
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Initialize Offline Service
    OfflineService.initialize();
    
    // Initialize Data Sync Service
    await DataSyncService().init();

  } catch (e) {
    if (kDebugMode) {
      print('Firebase initialization error: $e');
    }
    // Continue without Firebase for now
  }
  // Initialize Mapbox Access Token
  MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);

  runApp(const JSRiderApp());
}

class JSRiderApp extends StatelessWidget {
  const JSRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return Consumer<OrderProvider>(
            builder: (context, orderProvider, child) {
              // Set OrderProvider reference in AuthProvider
              WidgetsBinding.instance.addPostFrameCallback((_) {
                authProvider.setOrderProvider(orderProvider);
              });
              
              return MaterialApp(
                title: 'JS Rider',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: ThemeMode.light,
                home: const _LocationPermissionGate(),
                routes: {
                  '/main': (context) => const MainNavigation(),
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _LocationPermissionGate extends StatefulWidget {
  const _LocationPermissionGate();

  @override
  State<_LocationPermissionGate> createState() => _LocationPermissionGateState();
}

class _LocationPermissionGateState extends State<_LocationPermissionGate> {
  bool _checking = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePermissions();
    });
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

  Future<void> _ensurePermissions() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _checking = false;
          _message = 'Location services are disabled. Please enable and try again.';
        });
        return;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        await _showLocationDisclosureDialog();
        // Always proceed to the real system permission prompt after the
        // explanation screen — Apple guideline 5.1.1(iv): a custom pre-prompt
        // must not itself grant or deny; only "Continue" to the OS dialog.
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
        setState(() {
          _checking = false;
          _message = 'Location permission is required to continue.';
        });
        return;
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _checking = false;
        _message = 'Failed to check permissions. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, size: 48, color: Colors.red[400]),
              const SizedBox(height: 12),
              Text(_message ?? 'Permission required', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await geo.Geolocator.openLocationSettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _ensurePermissions,
                    child: const Text('Retry'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
