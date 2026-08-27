import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../utils/error_logger.dart';
import 'order_provider.dart';
import '../models/shift_model.dart';
import '../models/attendance_model.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';

class Rider {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String vehicleNumber;
  final String vehicleType;
  final bool isOnline;
  final String? profileImage;
  final int totalOrders;
  final int completedOrders;
  final int todayCompletedOrders;
  final double rating;
  final int totalEarnings;
  final double totalKms;
  final DateTime? lastActiveAt;
  final DateTime? joinedAt;
  final String? status; // active, inactive, suspended
  final Map<String, dynamic>? preferences;
  final Map<String, dynamic>? analytics;

  Rider({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicleNumber,
    required this.vehicleType,
    this.isOnline = false,
    this.profileImage,
    this.totalOrders = 0,
    this.completedOrders = 0,
    this.todayCompletedOrders = 0,
    this.rating = 0.0,
    this.totalEarnings = 0,
    this.totalKms = 0.0,
    this.lastActiveAt,
    this.joinedAt,
    this.status = 'active',
    this.preferences,
    this.analytics,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    return Rider(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      vehicleNumber: json['vehicleNumber'] ?? '',
      vehicleType: json['vehicleType'] ?? '',
      isOnline: json['isOnline'] ?? false,
      profileImage: json['profileImage'],
      totalOrders: json['totalOrders'] ?? 0,
      completedOrders: json['completedOrders'] ?? 0,
      todayCompletedOrders: json['todayCompletedOrders'] ?? 0,
      rating: (json['rating'] ?? 0.0).toDouble(),
      totalEarnings: json['totalEarnings'] ?? 0,
      totalKms: (json['totalKms'] ?? 0.0).toDouble(),
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.parse(json['lastActiveAt'])
          : null,
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : null,
      status: json['status'] ?? 'active',
      preferences: json['preferences'] as Map<String, dynamic>?,
      analytics: json['analytics'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      'isOnline': isOnline,
      'profileImage': profileImage,
      'totalOrders': totalOrders,
      'completedOrders': completedOrders,
      'todayCompletedOrders': todayCompletedOrders,
      'rating': rating,
      'totalEarnings': totalEarnings,
      'totalKms': totalKms,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'joinedAt': joinedAt?.toIso8601String(),
      'status': status,
      'preferences': preferences,
      'analytics': analytics,
    };
  }

  Rider copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? vehicleNumber,
    String? vehicleType,
    bool? isOnline,
    String? profileImage,
    int? totalOrders,
    int? completedOrders,
    int? todayCompletedOrders,
    double? rating,
    int? totalEarnings,
    double? totalKms,
    DateTime? lastActiveAt,
    DateTime? joinedAt,
    String? status,
    Map<String, dynamic>? preferences,
    Map<String, dynamic>? analytics,
  }) {
    return Rider(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      isOnline: isOnline ?? this.isOnline,
      profileImage: profileImage ?? this.profileImage,
      totalOrders: totalOrders ?? this.totalOrders,
      completedOrders: completedOrders ?? this.completedOrders,
      todayCompletedOrders: todayCompletedOrders ?? this.todayCompletedOrders,
      rating: rating ?? this.rating,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      totalKms: totalKms ?? this.totalKms,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      joinedAt: joinedAt ?? this.joinedAt,
      status: status ?? this.status,
      preferences: preferences ?? this.preferences,
      analytics: analytics ?? this.analytics,
    );
  }
}

class AuthSession {
  final String sessionId;
  final String riderId;
  final DateTime createdAt;
  final DateTime? expiresAt;

  AuthSession({
    required this.sessionId,
    required this.riderId,
    required this.createdAt,
    this.expiresAt,
  });
}

class AuthProvider extends ChangeNotifier {
  Rider? _rider;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;
  AuthSession? _session;
  OrderProvider? _orderProvider;

  bool _isClockedIn = false;
  DateTime? _clockInTime;
  String? _activeAttendanceId;
  List<AttendanceModel> _attendanceHistory = [];
  bool _isBatteryOptimizationIgnored = false;

  // Getters
  Rider? get rider => _rider;
  Rider? get currentRider => _rider;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isClockedIn => _isClockedIn;
  DateTime? get clockInTime => _clockInTime;
  String? get activeAttendanceId => _activeAttendanceId;
  String? get error => _error;
  String? get sessionId => _session?.sessionId;
  List<AttendanceModel> get attendanceHistory => _attendanceHistory;
  bool get isBatteryOptimizationIgnored => _isBatteryOptimizationIgnored;

  // Set OrderProvider reference
  void setOrderProvider(OrderProvider orderProvider) {
    _orderProvider = orderProvider;
  }

  // Initialize auth state
  Future<void> initializeAuth() async {
    _setLoading(true);
    try {
      await checkBatteryOptimizationStatus();
      if (!_isBatteryOptimizationIgnored) {
        // Automatically request it for the "extreme experience"
        await requestIgnoreBatteryOptimization();
      }
      
      if (kDebugMode) {
        print('Starting auth initialization...');
      }

      // Try to get saved credentials for this device from Firestore
      final sessionInfo = await FirebaseService.getSavedCredentials();

      if (sessionInfo != null) {
        if (kDebugMode) {
          print('Found saved credentials, attempting silent login...');
        }

        // Always start a new session silently using email + password
        final authSuccess = await ApiService.authenticate(
          sessionInfo['email'],
          sessionInfo['password'],
        );

        if (authSuccess) {
          if (kDebugMode) {
            print('Auto-login successful!');
          }

          // Create rider from API session data
          _rider = Rider(
            id:
                ApiService.userId ??
                'rider_${DateTime.now().millisecondsSinceEpoch}',
            name: ApiService.userName ?? 'Rider',
            email: ApiService.userEmail ?? sessionInfo['email'],
            phone: '', // Should be fetched from API
            vehicleNumber: '', // Should be fetched from API
            vehicleType: '', // Should be fetched from API
            isOnline: false,
          );

          _isAuthenticated = true;

          // Set user ID in OrderProvider for filtering
          if (_orderProvider != null) {
            _orderProvider!.setCurrentUserId(_rider!.id);
          }

          // Fetch and update rider statistics
          await fetchRiderStatistics();

          // Fetch user info for branch ids and save to users collection
          await _fetchAndSaveUserInfo();

          // Save rider data to Firebase with all fields
          await FirebaseService.saveRiderData(
            riderId: _rider!.id,
            name: _rider!.name,
            email: _rider!.email,
            phone: _rider!.phone,
            vehicleNumber: _rider!.vehicleNumber,
            vehicleType: _rider!.vehicleType,
            totalOrders: _rider!.totalOrders,
            completedOrders: _rider!.completedOrders,
            rating: _rider!.rating,
            totalEarnings: _rider!.totalEarnings,
            status: _rider!.status,
            preferences: {
              ...?_rider!.preferences,
              'liveLocation': {
                'lat': null,
                'lng': null,
                'updatedAt': null,
                'orderId': null,
              },
            },
          );

          // Update FCM Token for push notifications
          await FirebaseService.updateRiderFCMToken(_rider!.id);

          // Create session record
          _session = AuthSession(
            sessionId: ApiService.sessionId ?? '',
            riderId: _rider!.id,
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(AppConfig.sessionTimeout),
          );

          // Update session in Firebase (always save session for auto-login)
          FirebaseService.saveUserSession(
            sessionId: _session!.sessionId,
            userId: _rider!.id,
            userEmail: _rider!.email,
            userName: _rider!.name,
            expiresAt: _session!.expiresAt!,
            password: sessionInfo['password'],
          );

          // No local fallback caching (Firestore only as requested)

          if (kDebugMode) {
            print('Auto-login successful: ${_rider!.name}');
          }
        } else {
          if (kDebugMode) {
            print('Auto-login failed - API authentication unsuccessful');
          }
          // Authentication failed, clear saved credentials
          _isAuthenticated = false;
          _rider = null;
          _session = null;
        }
      } else {
        if (kDebugMode) {
          print('No saved credentials found - user needs to login');
        }
        // No saved credentials
        _isAuthenticated = false;
        _rider = null;
        _session = null;
      }
    } catch (e) {
      _error = 'Failed to initialize authentication';
      _isAuthenticated = false;
      _rider = null;
      _session = null;

      if (kDebugMode) {
        print('Auth initialization error (continuing anyway): $e');
      }
      // Don't throw error - app should continue working even if auto-login fails
    } finally {
      // Load clock in status from local storage
      try {
        final prefs = await SharedPreferences.getInstance();
        _isClockedIn = prefs.getBool('isClockedIn') ?? false;
        _activeAttendanceId = prefs.getString('activeAttendanceId');
        final clockInTimeStr = prefs.getString('clockInTime');
        if (clockInTimeStr != null) {
          _clockInTime = DateTime.parse(clockInTimeStr);
        }
      } catch (e) {
        if (kDebugMode) print('Error loading clock-in state: $e');
      }

      _setLoading(false);
      
      // Check battery optimization status
      await checkBatteryOptimizationStatus();
      
      notifyListeners();
    }
  }

  // Check if battery optimization is ignored
  Future<void> checkBatteryOptimizationStatus() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      _isBatteryOptimizationIgnored = status.isGranted;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error checking battery optimization: $e');
    }
  }

  // Request to ignore battery optimization
  Future<void> requestIgnoreBatteryOptimization() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      _isBatteryOptimizationIgnored = status.isGranted;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error requesting battery optimization: $e');
    }
  }

  // Login
  Future<bool> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      // Validate input
      if (email.isEmpty || password.isEmpty) {
        _error = 'Please enter both email and password';
        return false;
      }

      // Authenticate with Odoo API
      final authSuccess = await ApiService.authenticate(email, password);
      if (authSuccess) {
        // Create rider from API session data
        _rider = Rider(
          id:
              ApiService.userId ??
              'rider_${DateTime.now().millisecondsSinceEpoch}',
          name: ApiService.userName ?? 'Rider',
          email: ApiService.userEmail ?? email,
          phone: '', // Should be fetched from API
          vehicleNumber: '', // Should be fetched from API
          vehicleType: '', // Should be fetched from API
          isOnline: false,
        );

        _isAuthenticated = true;

        // Set user ID in OrderProvider for filtering
        if (_orderProvider != null) {
          _orderProvider!.setCurrentUserId(_rider!.id);
        }

        // Fetch and update rider statistics
        await fetchRiderStatistics();

        // Fetch user info for branch ids and save to users collection
        await _fetchAndSaveUserInfo();

        // Save rider data to Firebase with all fields
        await FirebaseService.saveRiderData(
          riderId: _rider!.id,
          name: _rider!.name,
          email: _rider!.email,
          phone: _rider!.phone,
          vehicleNumber: _rider!.vehicleNumber,
          vehicleType: _rider!.vehicleType,
          totalOrders: _rider!.totalOrders,
          completedOrders: _rider!.completedOrders,
          rating: _rider!.rating,
          totalEarnings: _rider!.totalEarnings,
          status: _rider!.status,
          preferences: {
            ...?_rider!.preferences,
            'liveLocation': {
              'lat': null,
              'lng': null,
              'updatedAt': null,
              'orderId': null,
            },
          },
        );

        // Update FCM Token for push notifications
        await FirebaseService.updateRiderFCMToken(_rider!.id);

        // Create session record
        _session = AuthSession(
          sessionId:
              ApiService.sessionId ??
              'sess_${DateTime.now().millisecondsSinceEpoch}',
          riderId: _rider!.id,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(AppConfig.sessionTimeout),
        );

        // Clean up old sessions first
        FirebaseService.cleanupOldSessions(_rider!.email);

        // Always save session to Firebase for auto-login (store password for silent login)
        FirebaseService.saveUserSession(
          sessionId: _session!.sessionId,
          userId: _rider!.id,
          userEmail: _rider!.email,
          userName: _rider!.name,
          expiresAt: _session!.expiresAt!,
          password: password,
        );

        // No local fallback caching (Firestore only as requested)

        ErrorLogger.auth(
          'Login successful: ${_rider!.name} (${_rider!.email})',
        );

        notifyListeners();
        return true;
      } else {
        _error = 'Invalid email or password. Please check your credentials.';
        return false;
      }
    } catch (e, stackTrace) {
      _error =
          'Login failed. Please check your internet connection and try again.';
      ErrorLogger.auth('Login error', error: e, stackTrace: stackTrace);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _fetchAndSaveUserInfo() async {
    try {
      if (_rider == null) return;
      final userInfo = await ApiService.getUserInfo();

      // Look for allowed_branch_ids in the response directly or inside 'result'
      List<dynamic>? branchIds;
      if (userInfo != null) {
        // Extract branch IDs
        if (userInfo.containsKey('allowed_branch_ids')) {
          branchIds = userInfo['allowed_branch_ids'] as List<dynamic>?;
        } else if (userInfo.containsKey('result') &&
            userInfo['result'] is Map &&
            (userInfo['result'] as Map).containsKey('allowed_branch_ids')) {
          branchIds =
              (userInfo['result'] as Map)['allowed_branch_ids']
                  as List<dynamic>?;
        }

        // Also extract phone and vehicle info if missing in current rider
        final phone = (userInfo['phone'] ?? '').toString();
        final vehicleNumber = (userInfo['vehicle_number'] ?? 
                              userInfo['vehicleNumber'] ?? '').toString();
        final vehicleType = (userInfo['vehicle_type'] ?? 
                            userInfo['vehicleType'] ?? '').toString();

        if (phone.isNotEmpty || vehicleNumber.isNotEmpty || vehicleType.isNotEmpty) {
          _rider = _rider!.copyWith(
            phone: (phone.isNotEmpty && phone != 'false') ? phone : _rider!.phone,
            vehicleNumber: (vehicleNumber.isNotEmpty && vehicleNumber != 'false') 
                ? vehicleNumber : _rider!.vehicleNumber,
            vehicleType: (vehicleType.isNotEmpty && vehicleType != 'false') 
                ? vehicleType : _rider!.vehicleType,
          );
        }

        // Save everything to Firestore
        final Map<String, dynamic> updateData = {};
        if (branchIds != null) updateData['allowed_branch_ids'] = branchIds;
        if (_rider!.phone.isNotEmpty) updateData['phone'] = _rider!.phone;
        if (_rider!.vehicleNumber.isNotEmpty) updateData['vehicleNumber'] = _rider!.vehicleNumber;
        if (_rider!.vehicleType.isNotEmpty) updateData['vehicleType'] = _rider!.vehicleType;

        if (updateData.isNotEmpty) {
          await FirebaseService.saveUserData(_rider!.id, updateData);
        }

        if (kDebugMode) {
          print('Saved user info from getUserInfo: $updateData');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching and saving user info: $e');
      }
    }
  }

  // Logout
  Future<void> logout() async {
    _setLoading(true);

    try {
      // Logout from API
      await ApiService.logout();

      // Clear session from Firebase
      if (_rider != null) {
        await FirebaseService.clearUserSession(_rider!.email);
      }

      // Clear local storage (no remembered creds clearing here; password kept in Firestore only)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('rider_data');
      // No local fallback to clear

      // Reset state
      _rider = null;
      _isAuthenticated = false;
      _error = null;
      _session = null;

      if (kDebugMode) {
        print('Logout successful');
      }

      notifyListeners();
    } catch (e) {
      _error = 'Logout failed';
      if (kDebugMode) {
        print('Logout error: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  // Update rider profile
  Future<bool> updateProfile({
    String? name,
    String? phone,
    String? vehicleNumber,
    String? vehicleType,
    String? profileImage,
  }) async {
    if (_rider == null) return false;

    try {
      _rider = _rider!.copyWith(
        name: name,
        phone: phone,
        vehicleNumber: vehicleNumber,
        vehicleType: vehicleType,
        profileImage: profileImage,
      );

      // Save updated rider data to Firebase
      await FirebaseService.updateRiderProfile(
        riderId: _rider!.id,
        name: name,
        phone: phone,
        vehicleNumber: vehicleNumber,
        vehicleType: vehicleType,
        profileImage: profileImage,
      );

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Profile update failed';
      if (kDebugMode) {
        print('Profile update error: $e');
      }
      return false;
    }
  }

  // Fetch rider profile/stats from Odoo (res.users)
  Future<void> fetchRiderStatistics() async {
    if (_rider == null) return;

    try {
      final profile = await ApiService.getUserProfile();
      if (profile != null) {
        // Handle Odoo returning 'false' for empty fields
        String phone = '';
        if (profile['phone'] != null && profile['phone'] != false) {
          phone = profile['phone'].toString();
        }

        String vehicleNumber = '';
        if (profile['vehicle_number'] != null &&
            profile['vehicle_number'] != false) {
          vehicleNumber = profile['vehicle_number'].toString();
        }

        String vehicleType = '';
        if (profile['vehicle_type'] != null &&
            profile['vehicle_type'] != false) {
          vehicleType = profile['vehicle_type'].toString();
        }

        final rating = (profile['average_rating'] ?? 0.0);
        final completed = (profile['total_delivered_orders'] ?? 0);

        _rider = _rider!.copyWith(
          phone: phone.isNotEmpty ? phone : _rider!.phone,
          vehicleNumber:
              vehicleNumber.isNotEmpty ? vehicleNumber : _rider!.vehicleNumber,
          vehicleType:
              vehicleType.isNotEmpty ? vehicleType : _rider!.vehicleType,
          rating: (rating is num) ? rating.toDouble() : _rider!.rating,
          completedOrders: (completed is num)
              ? completed.toInt()
              : _rider!.completedOrders,
          lastActiveAt: DateTime.now(),
        );

        // Optionally mirror to Firebase for web dashboard/live views
        await FirebaseService.saveRiderData(
          riderId: _rider!.id,
          name: _rider!.name,
          email: _rider!.email,
          phone: _rider!.phone,
          vehicleNumber: _rider!.vehicleNumber,
          vehicleType: _rider!.vehicleType,
          completedOrders: _rider!.completedOrders,
          rating: _rider!.rating,
        );

        // Automatically refresh analytics whenever statistics are fetched
        await fetchAnalytics();

        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rider profile from Odoo: $e');
      }
    }

    // Fetch today's stats and sync totalEarnings + totalKms + todayCompletedOrders into the rider model
    try {
      final statsData = await ApiService.getTodayStats();
      final resultData = statsData['result'] as Map<String, dynamic>? ?? {};
      final earning = resultData['totalEarnings'] ?? resultData['rider_earning'] ?? resultData['total_earnings'];
      final kms = resultData['totalKms'];
      final todayCount = resultData['today_delivered_orders_count'];
      if (_rider != null) {
        _rider = _rider!.copyWith(
          totalEarnings: (earning is num) ? earning.toInt() : _rider!.totalEarnings,
          totalKms: (kms is num) ? kms.toDouble() : _rider!.totalKms,
          todayCompletedOrders: (todayCount is num) ? todayCount.toInt() : _rider!.todayCompletedOrders,
        );
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching today stats for earnings: $e');
      }
    }
  }

  // Refresh rider data from Firestore
  Future<void> refreshRiderData() async {
    if (_rider == null) return;

    try {
      final riderData = await FirebaseService.getRiderData(_rider!.id);
      if (riderData != null) {
        _rider = Rider.fromJson(riderData);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error refreshing rider data: $e');
      }
    }
  }

  // Toggle online status
  Future<void> toggleOnlineStatus() async {
    if (_rider == null) return;

    try {
      _rider = _rider!.copyWith(
        isOnline: !_rider!.isOnline,
        lastActiveAt: DateTime.now(),
      );

      // Save updated rider data to Firebase
      await FirebaseService.updateRiderProfile(
        riderId: _rider!.id,
        preferences: {
          'isOnline': _rider!.isOnline,
          'lastActiveAt': _rider!.lastActiveAt?.toIso8601String(),
        },
      );

      if (kDebugMode) {
        print('Online status changed: ${_rider!.isOnline}');
      }

      notifyListeners();
    } catch (e) {
      _error = 'Failed to update online status';
      if (kDebugMode) {
        print('Online status error: $e');
      }
    }
  }

  // Check session validity and refresh if needed
  Future<bool> checkSessionValidity() async {
    try {
      if (_session == null) return false;

      final isValid = await FirebaseService.isSessionValid(_session!.sessionId);
      if (!isValid) {
        if (kDebugMode) {
          print('Session expired, attempting refresh...');
        }

        // Try to get saved credentials and re-authenticate
        final savedCredentials = await FirebaseService.getSavedCredentials();
        if (savedCredentials != null) {
          final authSuccess = await ApiService.authenticate(
            savedCredentials['email'],
            savedCredentials['password'],
          );

          if (authSuccess) {
            // Update session data
            _session = AuthSession(
              sessionId: ApiService.sessionId ?? _session!.sessionId,
              riderId: _rider?.id ?? _session!.riderId,
              createdAt: DateTime.now(),
              expiresAt: DateTime.now().add(const Duration(hours: 24)),
            );

            // Save updated session to Firebase
            await FirebaseService.saveUserSession(
              sessionId: _session!.sessionId,
              userId: _rider?.id ?? '',
              userEmail: _rider?.email ?? '',
              userName: _rider?.name ?? '',
              expiresAt: _session!.expiresAt!,
              password: savedCredentials['password'],
            );

            notifyListeners();
            return true;
          } else {
            // Session refresh failed, logout user
            await logout();
            return false;
          }
        } else {
          // No saved credentials, logout user
          await logout();
          return false;
        }
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Session validity check error: $e');
      }
      return false;
    }
  }

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Public method to set loading state
  void setLoading(bool loading) {
    _setLoading(loading);
  }

  // Start Shift (Clock In)
  Future<bool> startShift() async {
    if (_rider == null) return false;
    _setLoading(true);
    try {
      // Get current location (mocking for now, should use Geolocator)
      double lat = 0.0;
      double lng = 0.0;

      final success = await ApiService.clockIn(_rider!.id, lat, lng);
      if (success) {
        _isClockedIn = true;
        _clockInTime = DateTime.now();

        // Log to Firebase Attendance Sessions
        _activeAttendanceId = await FirebaseService.logAttendanceStart(
          riderId: _rider!.id,
          lat: lat,
          lng: lng,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isClockedIn', true);
        await prefs.setString('clockInTime', _clockInTime!.toIso8601String());
        if (_activeAttendanceId != null) {
          await prefs.setString('activeAttendanceId', _activeAttendanceId!);
        }

        // Log old style for backward compatibility if needed (skipping as requested "new table")

        // Automatically set online
        if (!_rider!.isOnline) {
          await toggleOnlineStatus();
        }

        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to start shift';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // End Shift (Clock Out)
  Future<bool> endShift() async {
    if (_rider == null) return false;
    _setLoading(true);
    try {
      // Get current location (mocking for now, should use Geolocator)
      double lat = 0.0;
      double lng = 0.0;

      final success = await ApiService.clockOut(_rider!.id, lat, lng);
      if (success) {
        _isClockedIn = false;
        _clockInTime = null;

        // Update Firebase Session
        if (_activeAttendanceId != null) {
          await FirebaseService.logAttendanceEnd(
            sessionId: _activeAttendanceId!,
            riderId: _rider!.id,
            lat: lat,
            lng: lng,
          );
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isClockedIn', false);
        await prefs.remove('clockInTime');
        await prefs.remove('activeAttendanceId');
        _activeAttendanceId = null;

        // Log old style for backward compatibility

        // Automatically set offline
        if (_rider!.isOnline) {
          await toggleOnlineStatus();
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to end shift';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Get Earnings
  Future<Map<String, dynamic>> getEarnings(String period) async {
    if (_rider == null) return {};
    try {
      return await ApiService.getEarnings(_rider!.id, period);
    } catch (e) {
      return {};
    }
  }

  // Get Today Stats
  Future<Map<String, dynamic>> getTodayStats() async {
    if (_rider == null) return {};
    try {
      return await ApiService.getTodayStats();
    } catch (e) {
      return {};
    }
  }

  // Fetch attendance history (past 7 days)
  Future<void> fetchAttendanceHistory() async {
    if (_rider == null) return;
    try {
      final historyData = await FirebaseService.getAttendanceHistory(
        _rider!.id,
      );
      _attendanceHistory = historyData
          .map((map) => AttendanceModel.fromMap(map))
          .toList();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching attendance history: $e');
      }
    }
  }

  // Submit POD
  Future<bool> submitPOD(String orderId, String imagePath) async {
    _setLoading(true);
    try {
      final success = await ApiService.submitPOD(orderId, imagePath);
      return success;
    } catch (e) {
      _error = 'Failed to submit POD';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Fetch Rider Analytics
  Future<void> fetchAnalytics() async {
    if (_rider == null) return;
    try {
      // 1. Try to get analytics from Odoo Profile
      final profile = await ApiService.getUserProfile();

      // 2. Get calculated analytics from Firestore
      final firestoreStats = await FirebaseService.getRiderStatistics(
        _rider!.id,
      );

      final Map<String, dynamic> analytics = {
        'on_time_delivery':
            (profile?['on_time_delivery'] != null &&
                profile!['on_time_delivery'] > 0)
            ? profile['on_time_delivery']
            : firestoreStats['on_time_delivery'] ?? 0.0,

        'average_delivery_time':
            (profile?['average_delivery_time'] != null &&
                profile!['average_delivery_time'] != 'N/A')
            ? profile['average_delivery_time']
            : firestoreStats['average_delivery_time'] ?? 'N/A',
      };

      _rider = _rider!.copyWith(
        analytics: analytics,
        completedOrders:
            profile?['total_delivered_orders'] ??
            firestoreStats['completedOrders'] ??
            _rider!.completedOrders,
        rating:
            profile?['average_rating']?.toDouble() ??
            firestoreStats['rating'] ??
            _rider!.rating,
      );

      notifyListeners();

      if (kDebugMode) {
        print('Analytics updated: $analytics');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching analytics: $e');
      }
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
