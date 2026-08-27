# JS Rider - Flutter Delivery App

A Flutter-based delivery rider application that integrates with Odoo ERP system for order management and uses Firebase Firestore for data storage.

## 🏗️ Architecture Overview

### Authentication Strategy
- **Primary Authentication**: Odoo ERP API (REST)
- **Data Storage**: Firebase Firestore (No Firebase Authentication)
- **Session Management**: Firestore-based session storage
- **Single-Device Login**: Users can only be logged in on ONE device at a time
- **Auto-login**: Always enabled - users stay logged in until manual logout or API failure
- **Remember Me**: Only saves credentials for future use (doesn't affect auto-login)

### Core Components
- **Frontend**: Flutter (Dart)
- **Backend Integration**: Odoo ERP REST API
- **Database**: Firebase Firestore
- **State Management**: Provider pattern
- **UI Framework**: Material Design 3

## 📱 Features

### ✅ Implemented Features
- **API-based Authentication** with Odoo ERP
- **Single-Device Login** (one user = one device at a time)
- **Session Management** with Firestore storage
- **Always-on Auto-login** (users stay logged in until logout)
- **Remember Me** for credential storage
- **Rider Profile Management**
- **Order Management** (View, Accept, Update Status)
- **Offline-first Architecture** (with API sync)
- **Modern UI/UX** with Material Design 3
- **Advanced Map Navigation** with Mapbox integration:
  - **Real-time Location Tracking** with rider and customer markers
  - **Route Visualization** with turn-by-turn directions
  - **Navigation Controls** (Navigate/Re-center functionality)
  - **Customer Information Display** (name, phone, address)
  - **Call Customer** functionality (opens phone dialer)
  - **Smart Delivery Detection** (100m radius proximity check)
  - **Live Distance Tracking** to delivery location
  - **Professional UI/UX** with modern Material Design 3
  - **Live Location Sharing** for customer tracking
  - **Animated Status Indicators** and smooth transitions
  - **Custom App Icon** implementation

### ❌ Removed Features (As Requested)
- ~~Real-time Location Tracking~~
- ~~Push Notifications (FCM)~~
- ~~Offline Capability~~
- ~~Multi-factor Authentication (Biometric, PIN, OTP)~~

## 🔧 Technical Requirements

### Dependencies
```yaml
dependencies:
  flutter: ^3.24.0
  provider: ^6.1.1
  firebase_core: ^4.1.1
  cloud_firestore: ^6.0.2
  http: ^1.1.2
  shared_preferences: ^2.2.2
  mapbox_maps_flutter: ^2.11.0
  geolocator: ^14.0.2
  url_launcher: ^6.2.4
  permission_handler: ^12.0.1
  connectivity_plus: ^7.0.0
```

### Firebase Configuration
- **Firebase Project**: Configured with `google-services.json`
- **Firestore Database**: Used for data storage only
- **Security Rules**: Open for development (restrict in production)
 - **Live Location**: Rider live location stored under `riders/{riderId}.preferences.liveLocation`

### API Integration
- **Base URL**: Configurable in `lib/config/app_config.dart`
- **Authentication**: Odoo ERP REST API
- **Session Management**: API-based with Firestore persistence
 - **Order State Updates**: Odoo `tossdown.order.write` used to update `state` on Accept (draft→accepted) and Delivered (dispatch→delivered). Manager handles accepted→dispatch in Odoo.

## 🗄️ Database Schema

### Firestore Collections

#### `user_sessions`
```json
{
  "sessionId": "string",
  "userId": "string", 
  "userEmail": "string",
  "userName": "string",
  "expiresAt": "ISO8601 string",
  "createdAt": "ISO8601 string",
  "isActive": "boolean",
  "password": "string (only if remember me)"
}
```

#### `riders`
```json
{
  "id": "string",
  "name": "string",
  "email": "string", 
  "phone": "string",
  "vehicleNumber": "string",
  "vehicleType": "string",
  "isOnline": "boolean",
  "createdAt": "ISO8601 string",
  "updatedAt": "ISO8601 string",
  "totalOrders": 0,
  "completedOrders": 0,
  "rating": 4.8,
  "totalEarnings": 0,
  "status": "active",
  "joinedAt": "ISO8601 string",
  "lastActiveAt": "ISO8601 string",
  "preferences": {
    "liveLocation": {
      "lat": 31.5204,
      "lng": 74.3587,
      "updatedAt": "ISO8601 string",
      "orderId": "string"
    }
  }
}
```

#### `orders`
```json
{
  "id": "string",
  "customerName": "string",
  "customerPhone": "string",
  "pickupAddress": "string",
  "deliveryAddress": "string",
  "status": "string",
  "riderId": "string",
  "createdAt": "ISO8601 string",
  "updatedAt": "ISO8601 string",
  "deliveryLatitude": 0.0,
  "deliveryLongitude": 0.0,
  "stateTrail": {
    "draft": { "at": "ISO8601", "by": null },
    "accepted": { "at": null, "by": null },
    "dispatched": { "at": null, "by": null },
    "delivered": { "at": null, "by": null }
  }
}
```

## 🔐 Authentication Flow

### 1. App Startup (Always Auto-login)
```
Splash Screen → Firebase Init → Check Saved Session → Auto-login (if valid) or Show Login
```

Auto-login (single-device only):
- Uses Firestore `user_sessions` for current `deviceId` (no Remember Me required)
- Initializes Odoo API session using stored `sessionId` (cookie)
- On success, refreshes session and updates Firestore

### 2. Login Process (Single-Device Login)
```
User Input → API Authentication → Logout from Other Devices → Create Session → Save to Firestore → Navigate to Main App
- "Remember Me" checkbox only saves credentials for autofill after manual logout (not required for auto-login)
- Session is always saved for auto-login
- Automatically logs out user from all other devices
- Only ONE device can be logged in per user at a time
```

Additional notes:
- Session documents are keyed by user email (sanitized). We query by `sessionId` or filter by `deviceId` for validity, not doc ID

### 3. Session Management (Single-Device)
```
Session Check → Validate with API → Auto-login if Valid → Stay Logged In Forever
- Users stay logged in until manual logout or API authentication fails
- Only ONE device can be logged in per user at a time
- Login on new device automatically logs out from previous device
- Enhanced security - lost device doesn't stay logged in
```

Implementation details:
- Firestore `user_sessions` includes `deviceId` and `isActive`. On login, we mark sessions on other devices inactive
- Validity checks use `expiresAt` with a 5-minute buffer; if expired, splash will redirect to login unless Firestore has valid credentials to re-authenticate

### 4. Logout Process
```
Manual Logout → Clear Session → Clear Firestore Data → Navigate to Login
- Only way to logout is manual logout button
- API failures will also trigger logout
```

On logout we clear the Firestore `user_sessions` record for the user.

### 5. Single-Device Login Benefits
- **Security**: Lost device doesn't stay logged in
- **Simplicity**: One user = one active session
- **Control**: Easy to manage user sessions
- **Analytics**: Track which devices users prefer
- **Clean Database**: No duplicate or conflicting sessions

## 🚀 Setup Instructions

### 1. Firebase Setup
1. Create Firebase project
2. Enable Firestore Database
3. Download `google-services.json` to `android/app/`
4. **Deploy Firestore security rules** (see `deploy_firestore_rules.md`)

### 2. API Configuration
1. Update `lib/config/app_config.dart` with your Odoo server details:
```dart
class AppConfig {
  static const String apiBaseUrl = 'https://your-odoo-server.com';
  static const String dbName = 'your_database_name';
  // Mapbox access token (required for maps)
  static const String mapboxAccessToken = 'YOUR_MAPBOX_PUBLIC_TOKEN';
}
```

### 3. Mapbox Setup
1. Obtain a Mapbox public access token
2. Set `AppConfig.mapboxAccessToken`
3. Android: Add ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION permissions
4. iOS: Add NSLocationWhenInUseUsageDescription to `Info.plist`

### 4. App Icon Setup
1. **Automatic Setup**: Icons are automatically generated from `assets/logos/JS_rider_logo.png`
2. **Android Icons**: All required densities (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi) are generated
3. **iOS Icons**: All required sizes are generated for iPhone and iPad
4. **Web Icons**: PWA-ready icons with proper theming
5. **Manual Setup**: Icons are already copied to appropriate directories

### 5. Live Location Tracking Setup
1. **Firestore Configuration**: Live location data is stored in `riders/{riderId}.preferences.liveLocation`
2. **Web Tracking**: Use the provided `web_tracking_example.html` for customer tracking
3. **Privacy Control**: Riders can toggle location sharing on/off
4. **Real-time Updates**: Location updates every 5 meters when sharing is enabled

### 3. Build and Run
```bash
flutter pub get
flutter run
```

### 4. Deploy Firestore Rules (Important!)
The app will show permission denied errors until you deploy the Firestore rules. See `deploy_firestore_rules.md` for instructions.

## 📋 API Endpoints

### Authentication
- `POST /web/session/authenticate` - User login
- `GET /web/session/logout` - User logout
- Session validation is done by calling an authenticated endpoint (e.g. `POST /web/dataset/call_kw` with `res.partner.search_count`) using the session cookie

### Orders
- Use Odoo model methods via `POST /web/dataset/call_kw` (see Postman collection)

## 🔧 Configuration Files

### `firestore.rules`
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Development rules - allow all access
    // Production rules should be more restrictive
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

### `pubspec.yaml`
- Core Flutter dependencies
- Firebase packages
- HTTP client for API calls
- Provider for state management
 - Mapbox GL for maps
 - Geolocator for GPS

## 🐛 Troubleshooting

### Common Issues

#### 1. Firestore Permission Denied Errors
- **Problem**: `PERMISSION_DENIED: Missing or insufficient permissions`
- **Solution**: Deploy Firestore security rules (see `deploy_firestore_rules.md`)
- **Temporary Fix**: Use Firebase Console to set rules to allow all access for testing

#### 2. Firebase Connection Issues
- **Problem**: "Unable to resolve host firestore.googleapis.com"
- **Solution**: Check internet connection, verify Firebase project configuration
- **Note**: App continues working in offline mode

#### 3. Empty Firestore Database
- **Problem**: Collections not created automatically
- **Solution**: Collections are created on first write operation
- **Note**: App works fine with empty database

#### 4. API Authentication Failures
- **Problem**: Login fails with API errors
- **Solution**: Verify Odoo server URL and credentials in `app_config.dart`

#### 5. Session Expiration
- **Problem**: Auto-login fails after session expires
- **Solution**: App will redirect to login screen, user needs to re-authenticate

#### 6. Google Play Services Errors
- **Problem**: Various Google Play Services warnings in logs
- **Solution**: These are normal in emulator environment, app works fine

#### 7. Map Screen Issues
- **Problem**: Map not loading or navigation not working
- **Solution**: Verify Mapbox access token in `app_config.dart`
- **Location Permission**: Ensure location permissions are granted
- **Route Errors**: Check internet connection for Mapbox Directions API

#### 8. App Icon Issues
- **Problem**: Flutter default icon still showing
- **Solution**: Icons are already implemented in all required directories
- **Android**: Check `android/app/src/main/res/mipmap-*/ic_launcher.png`
- **iOS**: Check `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- **Clean Build**: Try `flutter clean && flutter pub get` and rebuild

#### 9. Live Location Tracking Issues
- **Problem**: Customer can't see rider location
- **Solution**: Ensure Firestore rules allow read access to `riders` collection
- **Web Interface**: Use the provided `web_tracking_example.html` with proper Firebase config
- **Location Sharing**: Check if rider has enabled location sharing in the app

## 🗺️ Map Screen Features

### Professional Navigation System
The map screen provides a comprehensive, professional navigation experience for delivery riders with modern UI/UX design:

#### **🎨 Professional UI Design**
- **Modern Material Design 3** with smooth animations and transitions
- **Gradient Status Bar** with real-time distance tracking
- **Animated Proximity Indicators** with pulsing effects
- **Floating Action Cards** with shadow effects and rounded corners
- **Professional Color Scheme** with consistent branding
- **Responsive Layout** that adapts to different screen sizes

#### **📍 Customer Information Display**
- **Comprehensive Customer Card** with organized information layout
- **Real-time Distance Tracking** with animated status indicators
- **Visual Proximity Indicator** (green when within 100m, orange when en route)
- **Order Reference Display** for easy identification
- **Professional Typography** with clear hierarchy

#### **🎯 Three Main Action Buttons**

1. **Navigate Button**
   - **First Click**: Starts navigation with route visualization
   - **Subsequent Clicks**: Re-centers map on rider's current location
   - **Route Display**: Shows turn-by-turn directions using Mapbox Directions API
   - **Visual Feedback**: Button changes to "Re-center" with orange color
   - **Professional Styling**: Elevated button with shadow effects

2. **Call Customer Button**
   - Opens phone dialer with customer's number pre-filled
   - Handles missing phone numbers gracefully with user feedback
   - Works with both `customerPhone` and `customer.phone` fields
   - **Green Color Scheme** for positive action indication

3. **Delivered Button**
   - **Smart Activation**: Only enabled when rider is within 100m of delivery location
   - **Confirmation Dialog**: Professional modal with rounded corners
   - **Status Update**: Updates order status to "delivered" in both Odoo and Firestore
   - **Red Color Scheme** for final action indication

#### **🔄 Real-time Features**
- **Live Location Tracking**: Rider's position updates every 5 meters
- **Distance Calculation**: Real-time distance to delivery location
- **Map Markers**: Professional customer (📍) and rider (🏍️) location markers
- **Auto-zoom**: Map automatically adjusts to show relevant areas
- **Location Sharing Toggle**: Enable/disable live location sharing for customers

#### **🌐 Live Location Sharing for Customers**
- **Real-time Tracking**: Rider location shared via Firestore
- **Web Interface**: Customers can track riders through web browser
- **Location Data**: Includes lat, lng, updatedAt, and orderId
- **Privacy Control**: Toggle location sharing on/off
- **Customer Web App**: Example HTML interface provided

#### **⚙️ Technical Implementation**
- **Mapbox Integration**: Uses Mapbox Maps Flutter SDK v2.11.0
- **Route Visualization**: GeoJSON-based route rendering with blue route lines
- **Location Services**: Geolocator for GPS tracking with best accuracy
- **Permission Handling**: Automatic location permission requests with user feedback
- **Error Handling**: Comprehensive error handling with user-friendly messages
- **Animation Controllers**: Smooth animations for status indicators and UI transitions
- **State Management**: Proper state management for navigation and location sharing

## 📱 App Structure

```
lib/
├── config/           # App configuration
├── models/           # Data models
├── providers/        # State management
├── screens/          # UI screens
│   └── map_screen.dart  # Professional navigation interface with live tracking
├── services/         # API and Firebase services
├── utils/            # Utilities and helpers
├── widgets/          # Reusable UI components
├── main.dart         # App entry point
└── web_tracking_example.html  # Customer tracking web interface
```

## 🌐 Customer Live Tracking

### Web Interface
A complete web interface is provided for customers to track their delivery rider in real-time:

#### **Features**
- **Real-time Location Updates**: Live tracking of rider position
- **Professional UI**: Clean, responsive design
- **Rider Information**: Name, vehicle details, and order information
- **Map Integration**: Mapbox-powered interactive map
- **Status Indicators**: Online/offline status with visual indicators
- **Last Updated**: Timestamp of last location update

#### **Usage**
1. Deploy `web_tracking_example.html` to your web server
2. Configure Firebase and Mapbox credentials
3. Access via URL: `https://yoursite.com/tracking.html?riderId=RIDER_ID&lat=CUSTOMER_LAT&lng=CUSTOMER_LNG`
4. Customers can track their rider's live location

#### **Data Structure**
The live location data is stored in Firestore under:
```json
{
  "riders": {
    "RIDER_ID": {
      "preferences": {
        "liveLocation": {
          "lat": 31.5204,
          "lng": 74.3587,
          "updatedAt": "2024-01-01T12:00:00.000Z",
          "orderId": "ORDER_123"
        }
      }
    }
  }
}
```

## 📦 Orders - Firestore-first Implementation

- **Source of truth**: Firestore collection `orders`.
- **Sync**: On app startup, the app performs a one-time sync from Odoo via `web/dataset/call_kw` and writes fully-composed orders into Firestore. After that, the rider app only reads from Firestore streams.
- **Realtime**: The app subscribes to `orders` via `FirebaseService.streamOrders()`; lists update automatically.
- **No direct API calls in rider UI**: After the initial sync step, orders and details are read exclusively from Firestore (temporary approach until Odoo→Firestore direct feed is enabled).

### Order JSON (Single Document)
Each order is stored as one complete JSON document in `orders/{id}`:

```json
{
  "id": "25",
  "reference": "JS00008",
  "tossdownSequence": "TD-123",
  "status": "pending", // one of: pending, accepted, pickedUp, delivered, cancelled
  "createdAt": "ISO8601",
  "writeDate": "ISO8601",
  "orderType": "delivery",
  "paymentMode": "cod",
  "amount": 1400,
  "currency": "AED",
  "branch": { "id": 2, "name": "Jalal Sons Model Town Link Road" },
  "customer": {
    "id": 8,
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "+123456789",
    "address": {
      "street": "123 Main Street",
      "street2": "Building A",
      "city": "Dubai",
      "zip": "12345"
    },
    "location": {
      "latitude": 25.2048,
      "longitude": 55.2708
    }
  },
  "items": [
    { "id": 17, "name": "Item A", "brand": "Brand X", "qty": 2, "price": 500, "total": 1000 },
    { "id": 18, "name": "Item B", "brand": "Brand Y", "qty": 1, "price": 300, "total": 300 }
  ],
  "stateTrail": {
    "draft": { "at": "ISO8601", "by": null },
    "accepted": { "at": null, "by": null },
    "dispatched": { "at": null, "by": null },
    "delivered": { "at": null, "by": null }
  }
}
```

Notes:
- `status` maps Odoo `tossdown_status` to app statuses: Confirm→pending, Accepted→accepted, Picked Up→pickedUp, Delivered→delivered.
- `stateTrail` sub-objects capture when and by whom each transition happened. On initial sync, only `draft` is populated; subsequent actions should update `accepted/ dispatched/ delivered` with `{ at, by }` and the top-level `status`.

### Flow
- App boot → One-time Odoo sync → Upsert full orders into Firestore (`orders/{id}`)
- UI subscribes to Firestore `orders` and categorizes into lists (pending/accepted/completed) in `OrderProvider`.
- Future: Odoo will write orders directly to Firestore, and the app will skip the initial sync step.

State transitions (source of truth):
- Accept (Rider): Odoo state draft → accepted, Firestore `stateTrail.accepted`
- Dispatch (Manager): Odoo state accepted → dispatch
- Delivered (Rider): Odoo state dispatch → delivered, Firestore `stateTrail.delivered`

## 🔄 Development Workflow

### Adding New Features
1. Create models in `lib/models/`
2. Add API endpoints in `lib/services/api_service.dart`
3. Update providers for state management
4. Create UI screens in `lib/screens/`
5. Update Firestore schema if needed

### Testing
- Use Android emulator for testing
- Verify API connectivity
- Test offline scenarios
- Validate session management

## 📝 Notes

- **Firebase Authentication**: Not used - API authentication only
- **Firestore**: Used purely for data storage and session management
- **Security**: Development rules are open - implement proper security for production
- **Offline Support**: Basic offline support with API sync when online
- **Session Persistence**: Sessions stored in Firestore with expiration handling

## 🚨 Production Considerations

1. **Security Rules**: Implement proper Firestore security rules
2. **API Security**: Use HTTPS and proper authentication tokens
3. **Error Handling**: Implement comprehensive error handling
4. **Logging**: Add proper logging for debugging
5. **Performance**: Optimize for production performance
6. **Testing**: Implement comprehensive testing suite

---

**Last Updated**: December 2024
**Version**: 1.0.0
**Flutter Version**: 3.24.0+