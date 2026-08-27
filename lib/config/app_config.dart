import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class AppConfig {
  // Environment configuration
  static const String environment = String.fromEnvironment('ENV', defaultValue: 'development');
  
  // API Configuration
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL', 
    defaultValue: 'https://jsesale.com'
  );
  
  static const String databaseName = String.fromEnvironment(
    'DB_NAME', 
    defaultValue: 'test'
  );
  
  // App Configuration
  static const String appName = 'JS Rider';
  static const String appVersion = '1.0.0';
  
  // Session Configuration
  static const Duration sessionTimeout = Duration(hours: 24);
  static const Duration sessionRefreshBuffer = Duration(minutes: 5);
  static const Duration networkTimeout = Duration(seconds: 15);
  static const Duration shortNetworkTimeout = Duration(seconds: 10);
  
  // Security Configuration
  static const bool enableBiometricAuth = false; // TODO: Implement biometric auth
  static const bool enableRememberMe = true;
  
  // Debug Configuration
  static const bool enableDebugLogs = true;
  static const bool showDemoCredentials = false; // Never show in production
  
  // Firebase Configuration
  static const bool enableFirebase = true;
  static const bool enablePushNotifications = true;
  static const bool isAttendanceEnabled = false;
  
  // Performance Analytics Rules
  static const int slaBaseMinutes = 15;
  static const int slaMinutesPerKm = 5;
  static const Duration deliveryGracePeriod = Duration(minutes: 5);
  static const double defaultRiderRating = 5.0;
  
  // Data Fetching Rules
  static const int orderSearchLimit = 50;
  static const int maxRealisticDeliveryMinutes = 1440; // 24 hours

  // Mapbox Configuration
  // Public (pk.) token — safe to ship in the client. Used for the Maps SDK and
  // the Directions API. Overridable at build time with --dart-define=MAPBOX_TOKEN=.
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: 'pk.eyJ1IjoianNkZXZlbG9wZXJzIiwiYSI6ImNtdGI5ejllbTAyeG0yeXI2bXFoMWJnajcifQ.z-DiTLEU5nu-7PrZIuWaLA',
  );
  
  // Development/Demo Configuration
  static const Map<String, String> demoCredentials = {
    'email': 'test',
    'password': '123',
  };
  
  // Helper methods
  static bool get isDevelopment => environment == 'development';
  static bool get isProduction => environment == 'production';
  static bool get isStaging => environment == 'staging';
  
  static String get apiBaseUrl => baseUrl;
  static String get dbName => databaseName;
  
  // Validation
  static bool get isValidConfig {
    return baseUrl.isNotEmpty && 
           databaseName.isNotEmpty && 
           appName.isNotEmpty;
  }

  static String get mapBoxStyle =>  MapboxStyles.MAPBOX_STREETS;
}
