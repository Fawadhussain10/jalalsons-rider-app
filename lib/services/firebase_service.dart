import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/app_config.dart';

class FirebaseService {
  static FirebaseFirestore? _firestore;
  static FirebaseMessaging? _fcm;
  static String? _deviceId;

  static Future<void> initialize() async {
    try {
      _firestore = FirebaseFirestore.instance;

      // Enable offline persistence
      _firestore!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Initialize FCM
      await _setupFCM();

      // Get device ID for session isolation
      await _getDeviceId();

      if (kDebugMode) {
        print('Firebase initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Firebase initialization error: $e');
      }
      // Continue without Firebase if initialization fails
    }
  }

  // Setup FCM
  static Future<void> _setupFCM() async {
    try {
      _fcm = FirebaseMessaging.instance;

      // Request permissions (especially for iOS)
      NotificationSettings settings = await _fcm!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (kDebugMode) {
        print('User granted notification permission: ${settings.authorizationStatus}');
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Got a message whilst in the foreground!');
          print('Message data: ${message.data}');
        }

        if (message.notification != null) {
          if (kDebugMode) {
            print('Message also contained a notification: ${message.notification}');
          }
          // You could show a local notification here if needed
        }
      });

      // Handle notification clicks when app is in background but not terminated
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('A new onMessageOpenedApp event was published!');
        }
        // Navigate to specific screen based on message data if needed
      });

    } catch (e) {
      if (kDebugMode) {
        print('Error setting up FCM: $e');
      }
    }
  }

  // Get FCM Token
  static Future<String?> getFCMToken() async {
    try {
      if (_fcm == null) return null;
      String? token = await _fcm!.getToken();
      if (kDebugMode) {
        print('FCM Token: $token');
      }
      return token;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting FCM token: $e');
      }
      return null;
    }
  }

  // Update FCM Token for a rider
  static Future<void> updateRiderFCMToken(String riderId) async {
    try {
      if (_firestore == null) return;
      String? token = await getFCMToken();
      if (token != null) {
        await _firestore!.collection('riders').doc(riderId).update({
          'fcmToken': token,
          'lastTokenUpdate': DateTime.now().toIso8601String(),
        });
        if (kDebugMode) {
          print('FCM token updated for rider: $riderId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating FCM token: $e');
      }
    }
  }

  // Get unique device ID for session isolation
  static Future<void> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = 'ios_${iosInfo.identifierForVendor}';
      } else {
        // Fallback for other platforms
        _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      }

      if (kDebugMode) {
        print('Device ID: $_deviceId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting device ID: $e');
      }
      // Fallback device ID
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Save user session data to Firestore
  static Future<void> saveUserSession({
    required String sessionId,
    required String userId,
    required String userEmail,
    required String userName,
    required DateTime expiresAt,
    String? password, // Only if remember me is enabled
  }) async {
    try {
      if (_firestore == null) {
        if (kDebugMode) {
          print('Firestore not initialized, skipping session save');
        }
        return;
      }

      final sessionData = {
        'sessionId': sessionId,
        'userId': userId,
        'userEmail': userEmail,
        'userName': userName,
        'expiresAt': expiresAt.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'isActive': true,
        'deviceId': _deviceId ?? 'unknown',
        'deviceType': Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : 'unknown',
        if (password != null) 'password': password, // Only store if remember me
      };

      // FIRST: Logout user from ALL other devices (single-device login)
      await _logoutFromAllOtherDevices(userEmail);

      // Use email as document ID (single session per user)
      final documentId = userEmail
          .replaceAll('@', '_at_')
          .replaceAll('.', '_dot_');

      // Add timeout to prevent hanging
      await _firestore!
          .collection('user_sessions')
          .doc(documentId)
          .set(sessionData)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              if (kDebugMode) {
                print(
                  'Firestore session save timeout - continuing without save',
                );
              }
            },
          );

      if (kDebugMode) {
        print(
          'User session saved to Firestore: $documentId (email: $userEmail) - Single device login',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        if (e.toString().contains('PERMISSION_DENIED')) {
          print('Firestore permission denied - rules may not be deployed yet');
        } else {
          print('Error saving user session (continuing anyway): $e');
        }
      }
      // Don't throw error - app should continue working even if Firestore fails
    }
  }

  // Logout user from all other devices (single-device login enforcement)
  static Future<void> _logoutFromAllOtherDevices(String userEmail) async {
    try {
      if (_firestore == null || _deviceId == null) return;

      // Get all active sessions for this user
      final query = await _firestore!
          .collection('user_sessions')
          .where('userEmail', isEqualTo: userEmail)
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 5));

      // Logout from all other devices (not current device)
      for (final doc in query.docs) {
        final sessionData = doc.data();
        final sessionDeviceId = sessionData['deviceId'];

        // Only logout from OTHER devices, not current device
        if (sessionDeviceId != _deviceId) {
          await doc.reference.update({
            'isActive': false,
            'loggedOutByOtherDevice': true,
            'loggedOutAt': DateTime.now().toIso8601String(),
            'loggedOutDeviceId': _deviceId,
          });

          if (kDebugMode) {
            print(
              'Logged out user from device: $sessionDeviceId (current device: $_deviceId)',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error logging out from other devices: $e');
      }
    }
  }

  // Get user session from Firestore by sessionId field (not doc id)
  static Future<Map<String, dynamic>?> getUserSession(String sessionId) async {
    try {
      if (_firestore == null) return null;

      final query = await _firestore!
          .collection('user_sessions')
          .where('sessionId', isEqualTo: sessionId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user session (continuing anyway): $e');
      }
      return null;
    }
  }

  // Check if session is valid
  static Future<bool> isSessionValid(String sessionId) async {
    try {
      final sessionData = await getUserSession(sessionId);
      if (sessionData == null) return false;

      final expiresAt = DateTime.parse(sessionData['expiresAt']);
      final now = DateTime.now();

      // Check if session expires soon (using buffer time from config)
      final isExpired = now.isAfter(
        expiresAt.subtract(AppConfig.sessionRefreshBuffer),
      );

      if (kDebugMode) {
        print('Session valid: ${!isExpired}, expires at: $expiresAt');
      }

      return !isExpired;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking session validity: $e');
      }
      return false;
    }
  }

  // Get active session for the current device (without requiring password)
  static Future<Map<String, dynamic>?>
  getActiveSessionForCurrentDevice() async {
    try {
      if (_firestore == null || _deviceId == null) return null;

      final query = await _firestore!
          .collection('user_sessions')
          .where('deviceId', isEqualTo: _deviceId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print(
          'Error getting active session for device (continuing anyway): $e',
        );
      }
      return null;
    }
  }

  // Get saved credentials for auto-login (single-device login)
  static Future<Map<String, dynamic>?> getSavedCredentials() async {
    try {
      if (_firestore == null || _deviceId == null) return null;

      // Try to get all active sessions and filter locally (faster approach)
      final query = await _firestore!
          .collection('user_sessions')
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(
            const Duration(seconds: 10), // Increased timeout for emulator
          );

      // Filter for current device locally
      for (final doc in query.docs) {
        final sessionData = doc.data();
        if (sessionData['deviceId'] == _deviceId &&
            sessionData['password'] != null) {
          if (kDebugMode) {
            print(
              'Found saved credentials for device $_deviceId: ${sessionData['userEmail']}',
            );
          }
          return {
            'email': sessionData['userEmail'],
            'password': sessionData['password'],
            'sessionId': sessionData['sessionId'],
          };
        }
      }

      if (kDebugMode) {
        print('No saved credentials found for device: $_deviceId');
        print('Total sessions found: ${query.docs.length}');
        for (final doc in query.docs) {
          final data = doc.data();
          print(
            'Session deviceId: ${data['deviceId']}, email: ${data['userEmail']}, hasPassword: ${data['password'] != null}',
          );
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting saved credentials (continuing anyway): $e');
      }
      return null;
    }
  }

  // Clear user session (single-device login)
  static Future<void> clearUserSession(String userEmail) async {
    try {
      if (_firestore == null) return;

      // Use email as document ID (single session per user)
      final documentId = userEmail
          .replaceAll('@', '_at_')
          .replaceAll('.', '_dot_');

      await _firestore!.collection('user_sessions').doc(documentId).update({
        'isActive': false,
        'clearedAt': DateTime.now().toIso8601String(),
        // Remove stored password on manual logout
        'password': FieldValue.delete(),
      });

      if (kDebugMode) {
        print(
          'User session cleared: $documentId (email: $userEmail) - Single device logout',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing user session: $e');
      }
    }
  }

  // Clean up old sessions for a user (single-device login - no cleanup needed)
  static Future<void> cleanupOldSessions(String userEmail) async {
    try {
      // With single-device login, we don't need to clean up old sessions
      // The _logoutFromAllOtherDevices method already handles this
      if (kDebugMode) {
        print('Single-device login: No cleanup needed for $userEmail');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in cleanup (single-device login): $e');
      }
    }
  }

  // Check if user is already logged in on another device
  static Future<bool> isUserLoggedInElsewhere(String userEmail) async {
    try {
      if (_firestore == null || _deviceId == null) return false;

      // Get all active sessions for this user
      final query = await _firestore!
          .collection('user_sessions')
          .where('userEmail', isEqualTo: userEmail)
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 5));

      // Check if there are sessions on other devices
      for (final doc in query.docs) {
        final sessionData = doc.data();
        final sessionDeviceId = sessionData['deviceId'];

        if (sessionDeviceId != _deviceId) {
          if (kDebugMode) {
            print('User is logged in on another device: $sessionDeviceId');
          }
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking if user is logged in elsewhere: $e');
      }
      return false;
    }
  }

  // Save rider data to Firestore
  static Future<void> saveRiderData({
    required String riderId,
    required String name,
    required String email,
    String? phone,
    String? vehicleNumber,
    String? vehicleType,
    int? totalOrders,
    int? completedOrders,
    double? rating,
    int? totalEarnings,
    String? status,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      if (_firestore == null) {
        if (kDebugMode) {
          print('Firestore not initialized, skipping rider data save');
        }
        return;
      }

      final now = DateTime.now();
      final Map<String, dynamic> riderData = {
        'id': riderId,
        'name': name,
        'email': email,
        'isOnline': false,
        'totalOrders': totalOrders ?? 0,
        'completedOrders': completedOrders ?? 0,
        'rating': rating ?? 0.0,
        'totalEarnings': totalEarnings ?? 0,
        'status': status ?? 'active',
        'updatedAt': now.toIso8601String(),
        'lastActiveAt': now.toIso8601String(),
      };

      // Only include these if they are not null/empty to avoid overwriting existing data
      if (phone != null && phone.isNotEmpty && phone != 'false') {
        riderData['phone'] = phone;
      }
      if (vehicleNumber != null && vehicleNumber.isNotEmpty && vehicleNumber != 'false') {
        riderData['vehicleNumber'] = vehicleNumber;
      }
      if (vehicleType != null && vehicleType.isNotEmpty && vehicleType != 'false') {
        riderData['vehicleType'] = vehicleType;
      }
      if (preferences != null) {
        riderData['preferences'] = preferences;
      }

      // Use a batch or separate check for createdAt/joinedAt if needed, 
      // but for now let's just use FieldValue.serverTimestamp() for first time
      // or just don't overwrite if they exist in the map (which we won't if we don't add them)
      
      // We'll set these only if it's a new document by using merge: true 
      // and NOT including them in subsequent updates, but since we want to set them 
      // at least once, we can use a check or just assume if they are missing in Firestore 
      // they will be set. Actually, the best way in Firestore to "set if absent" 
      // without knowing if it exists is not possible with a single .set().
      // However, we can just remove them from this default map and only set them 
      // when we know it's a new rider. For now, let's just focus on the emptying issue.

      await _firestore!
          .collection('riders')
          .doc(riderId)
          .set(riderData, SetOptions(merge: true))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              if (kDebugMode) {
                print(
                  'Firestore rider data save timeout - continuing without save',
                );
              }
            },
          );

      if (kDebugMode) {
        print('Rider data saved to Firestore: $riderId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving rider data (continuing anyway): $e');
      }
      // Don't throw error - app should continue working even if Firestore fails
    }
  }

  // Upsert full order document to Firestore
  static Future<void> upsertOrder(Map<String, dynamic> orderJson) async {
    try {
      if (_firestore == null) return;
      final orderId = orderJson['id'].toString();
      await _firestore!
          .collection('orders')
          .doc(orderId)
          .set(orderJson, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        print('Order upserted to Firestore: $orderId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error upserting order: $e');
      }
    }
  }

  // Save additional user info to the riders collection
  static Future<void> saveUserData(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (_firestore == null) return;
      await _firestore!
          .collection('riders')
          .doc(userId)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        print('User data saved to riders collection: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving data to riders collection: $e');
      }
    }
  }

  // Stream orders from Firestore
  static Stream<List<Map<String, dynamic>>> streamOrders() {
    if (_firestore == null) {
      return const Stream.empty();
    }
    return _firestore!
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
  //
  // // Stream only draft orders (for upcoming tab)
  // static Stream<List<Map<String, dynamic>>> streamDraftOrders() {
  //   if (_firestore == null) {
  //     return const Stream.empty();
  //   }
  //   return _firestore!
  //       .collection('orders')
  //       .where('stateTrail.draft.at', isNull: false)
  //       .snapshots()
  //       .map((snap) => snap.docs.map((d) => d.data()).toList());
  // }
  //
  // // Stream orders accepted by specific user (for ongoing tab)
  // static Stream<List<Map<String, dynamic>>> streamAcceptedOrdersByUser(String userId) {
  //   if (_firestore == null) {
  //     return const Stream.empty();
  //   }
  //   return _firestore!
  //       .collection('orders')
  //       .where('stateTrail.accepted.by', isEqualTo: int.parse(userId))
  //       .snapshots()
  //       .map((snap) => snap.docs.map((d) => d.data()).toList());
  // }
  //
  // // Stream orders delivered by specific user (for completed tab)
  // static Stream<List<Map<String, dynamic>>> streamDeliveredOrdersByUser(String userId) {
  //   if (_firestore == null) {
  //     return const Stream.empty();
  //   }
  //   return _firestore!
  //       .collection('orders')
  //       .where('stateTrail.delivered.by', isEqualTo: int.parse(userId))
  //       .snapshots()
  //       .map((snap) => snap.docs.map((d) => d.data()).toList());
  // }

  // Stream only draft orders (for upcoming tab) - sorted by createdAt
  static Stream<List<Map<String, dynamic>>> streamDraftOrders() {
    if (_firestore == null) {
      return const Stream.empty();
    }
    return _firestore!
        .collection('orders')
        .where('stateTrail.draft.at', isNull: false)
        .orderBy(
          'createdAt',
          descending: true,
        ) // Sort by createdAt for available orders
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // Stream orders accepted by specific user (for ongoing tab) - sorted by accepted.at
  static Stream<List<Map<String, dynamic>>> streamAcceptedOrdersByUser(
    String userId,
  ) {
    if (_firestore == null) {
      return const Stream.empty();
    }
    return _firestore!
        .collection('orders')
        .where('stateTrail.accepted.by', isEqualTo: int.parse(userId))
        .orderBy(
          'stateTrail.accepted.at',
          descending: true,
        ) // Sort by accepted timestamp
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // Stream orders delivered by specific user (for completed tab) - sorted by delivered.at
  static Stream<List<Map<String, dynamic>>> streamDeliveredOrdersByUser(
    String userId,
  ) {
    if (_firestore == null) {
      return const Stream.empty();
    }
    return _firestore!
        .collection('orders')
        .where('stateTrail.delivered.by', isEqualTo: int.parse(userId))
        .orderBy(
          'stateTrail.delivered.at',
          descending: true,
        ) // Sort by delivered timestamp
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // Get order document by id (single read)
  static Future<Map<String, dynamic>?> getOrderById(String orderId) async {
    try {
      if (_firestore == null) return null;
      final doc = await _firestore!
          .collection('orders')
          .doc(orderId)
          .get()
          .timeout(const Duration(seconds: 10));
      return doc.data();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting order by id: $e');
      }
      return null;
    }
  }

  // Update arbitrary fields on an order document
  static Future<void> updateOrderFields(
    String orderId,
    Map<String, dynamic> fields,
  ) async {
    try {
      if (_firestore == null) return;
      await _firestore!
          .collection('orders')
          .doc(orderId)
          .update(fields)
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        print('Order $orderId updated with fields: $fields');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating order fields: $e');
      }
    }
  }

  // Update order state trail in Firestore
  static Future<void> updateOrderStateTrail(
    String orderId,
    String state,
    String userId,
  ) async {
    try {
      if (_firestore == null) return;

      final now = DateTime.now().toIso8601String();
      final userIdInt = int.parse(userId);

      await _firestore!
          .collection('orders')
          .doc(orderId)
          .update({
            'stateTrail.$state.at': now,
            'stateTrail.$state.by': userIdInt,
          })
          .timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('Order $orderId state updated: $state by user $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating order state: $e');
      }
    }
  }

  // Get the list of branch IDs this rider is allowed to see orders for.
  // Returns null  → field absent on rider doc (legacy rider, no filter applied).
  // Returns []    → field present but empty (rider has NO branch access, block all).
  // Returns [..] → filter orders to only these branch IDs.
  static Future<List<int>?> getRiderAllowedBranchIds(String riderId) async {
    try {
      if (_firestore == null) return null;
      final doc = await _firestore!
          .collection('riders')
          .doc(riderId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      // Field absent → null (no restriction for legacy riders)
      if (!data.containsKey('allowed_branch_ids')) return null;
      final rawList = data['allowed_branch_ids'] as List<dynamic>?;
      // Field present but null value → treat as empty (no access)
      if (rawList == null) return [];
      // Safely convert each element to int (Firestore stores numbers as int or double)
      return rawList
          .map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? -1)
          .where((e) => e >= 0)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting rider allowedBranchIds: $e');
      }
      return null; // On error, don't restrict (fail open)
    }
  }

  // Get rider data from Firestore
  static Future<Map<String, dynamic>?> getRiderData(String riderId) async {
    try {
      if (_firestore == null) return null;

      final doc = await _firestore!.collection('riders').doc(riderId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting rider data: $e');
      }
      return null;
    }
  }

  // Get rider statistics from Firestore
  static Future<Map<String, dynamic>> getRiderStatistics(String riderId) async {
    try {
      if (_firestore == null) {
        return {
          'totalOrders': 0,
          'completedOrders': 0,
          'rating': 0.0,
          'totalEarnings': 0,
          'on_time_delivery': 0.0,
          'average_delivery_time': 'N/A',
        };
      }

      int riderIdInt = int.tryParse(riderId) ?? 0;

      // Get current rider document to preserve existing rating/data
      final riderDoc = await _firestore!
          .collection('riders')
          .doc(riderId)
          .get();
      final riderDataStore = riderDoc.data() ?? {};
      final double currentRating = (riderDataStore['rating'] ?? 0.0).toDouble();

      // Get completed orders count for this rider
      final completedOrdersQuery = await _firestore!
          .collection('orders')
          .where('stateTrail.delivered.by', isEqualTo: riderIdInt)
          .get();

      final completedOrders = completedOrdersQuery.docs.length;

      // Get total orders count (accepted + completed)
      final totalOrdersQuery = await _firestore!
          .collection('orders')
          .where('stateTrail.accepted.by', isEqualTo: riderIdInt)
          .get();

      final totalOrders = totalOrdersQuery.docs.length;

      // Calculate total earnings, on-time delivery, and average delivery time
      double totalEarnings = 0;
      int onTimeCount = 0;
      int onTimeSamplePool = 0;
      int totalDeliveryTimeMinutes = 0;
      int deliveryWithTimeCount = 0;

      for (final doc in completedOrdersQuery.docs) {
        final orderData = doc.data();

        // Earnings
        final amount = orderData['amount'] as num? ?? 0.0;
        totalEarnings += amount.toDouble();

        // Timestamps extraction
        final stateTrail = orderData['stateTrail'] as Map<String, dynamic>?;
        final deliveredAtStr =
            stateTrail?['delivered']?['at'] as String? ??
            orderData['deliveredAt'] as String?;
        final dispatchedAtStr =
            stateTrail?['dispatched']?['at'] as String? ??
            orderData['pickedUpAt'] as String?;
        final acceptedAtStr =
            stateTrail?['accepted']?['at'] as String? ??
            orderData['acceptedAt'] as String?;
        final createdAtStr =
            orderData['create_date'] as String? ??
            orderData['createdAt']
                as String?; // Support both Odoo and Firestore keys
        final estimatedAtStr = orderData['estimatedDeliveryTime'] as String?;

        if (deliveredAtStr != null) {
          final deliveredAt = DateTime.tryParse(deliveredAtStr);
          if (deliveredAt != null) {
            // 1. On-Time Delivery Logic
            DateTime? estimatedAt;
            if (estimatedAtStr != null) {
              estimatedAt = DateTime.tryParse(estimatedAtStr);
            } else {
              // DYNAMIC SLA: Calculate based on distance, starting from DISPATCH
              final baseTimeStr =
                  dispatchedAtStr ?? acceptedAtStr ?? createdAtStr;
              if (baseTimeStr != null) {
                final baseTime = DateTime.tryParse(baseTimeStr);
                if (baseTime != null) {
                  // Get distance from order data (set by Mapbox during navigation)
                  final double kms = (orderData['delivery_kms'] as num? ?? 5.0)
                      .toDouble(); // Default to 5km if info missing for older orders

                  final int dynamicSlaMinutes =
                      (kms * AppConfig.slaMinutesPerKm).round() +
                      AppConfig.slaBaseMinutes;
                  estimatedAt = baseTime.add(
                    Duration(minutes: dynamicSlaMinutes),
                  );
                }
              }
            }

            if (estimatedAt != null) {
              onTimeSamplePool++;
              final deadline = estimatedAt.add(AppConfig.deliveryGracePeriod);
              final isOnTime = !deliveredAt.isAfter(deadline);

              if (isOnTime) {
                onTimeCount++;
              }
            }

            // 2. Average Delivery Time Logic (Dispatch -> Delivered)
            final startMarkerStr =
                dispatchedAtStr ?? acceptedAtStr ?? createdAtStr;
            if (startMarkerStr != null) {
              final startTime = DateTime.tryParse(startMarkerStr);
              if (startTime != null) {
                final diff = deliveredAt.difference(startTime).inMinutes;
                if (diff >= 0 && diff < AppConfig.maxRealisticDeliveryMinutes) {
                  // Keep within configurable limit for realism
                  totalDeliveryTimeMinutes += diff;
                  deliveryWithTimeCount++;
                }
              }
            }
          }
        }
      }

      final double onTimeRate = onTimeSamplePool > 0
          ? (onTimeCount / onTimeSamplePool)
          : 0.0;

      // Calculate average delivery time
      String avgDeliveryTime = 'N/A';
      if (deliveryWithTimeCount > 0) {
        final avgMinutes = (totalDeliveryTimeMinutes / deliveryWithTimeCount)
            .round();
        if (avgMinutes >= 60) {
          final hours = avgMinutes ~/ 60;
          final mins = avgMinutes % 60;
          avgDeliveryTime = mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
        } else {
          avgDeliveryTime = '$avgMinutes mins';
        }
      }

      return {
        'totalOrders': totalOrders,
        'completedOrders': completedOrders,
        'rating': currentRating > 0
            ? currentRating
            : AppConfig.defaultRiderRating,
        'totalEarnings': totalEarnings.toInt(),
        'on_time_delivery': onTimeRate,
        'average_delivery_time': avgDeliveryTime,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error getting rider statistics: $e');
      }
      return {
        'totalOrders': 0,
        'completedOrders': 0,
        'rating': 0.0,
        'totalEarnings': 0,
        'on_time_delivery': 0.0,
        'average_delivery_time': 'N/A',
      };
    }
  }

  // Update rider statistics in Firestore
  static Future<void> updateRiderStatistics(
    String riderId,
    Map<String, dynamic> stats,
  ) async {
    try {
      if (_firestore == null) return;

      await _firestore!.collection('riders').doc(riderId).update({
        'totalOrders': stats['totalOrders'] ?? 0,
        'completedOrders': stats['completedOrders'] ?? 0,
        'rating': stats['rating'] ?? 0.0,
        'totalEarnings': stats['totalEarnings'] ?? 0,
        'lastActiveAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (kDebugMode) {
        print('Rider statistics updated: $riderId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating rider statistics: $e');
      }
    }
  }

  // Update rider profile data
  static Future<void> updateRiderProfile({
    required String riderId,
    String? name,
    String? phone,
    String? vehicleNumber,
    String? vehicleType,
    String? profileImage,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      if (_firestore == null) return;

      final updateData = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (name != null) updateData['name'] = name;
      if (phone != null) updateData['phone'] = phone;
      if (vehicleNumber != null) updateData['vehicleNumber'] = vehicleNumber;
      if (vehicleType != null) updateData['vehicleType'] = vehicleType;
      if (profileImage != null) updateData['profileImage'] = profileImage;
      if (preferences != null) updateData['preferences'] = preferences;

      await _firestore!.collection('riders').doc(riderId).update(updateData);

      if (kDebugMode) {
        print('Rider profile updated: $riderId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating rider profile: $e');
      }
    }
  }

  // Update password in user session
  static Future<bool> updateUserPassword(
    String userEmail,
    String newPassword,
  ) async {
    try {
      if (_firestore == null) return false;

      // Find the user session document
      final querySnapshot = await _firestore!
          .collection('user_sessions')
          .where('userEmail', isEqualTo: userEmail)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;

        // Update the password in the session
        await _firestore!.collection('user_sessions').doc(docId).update({
          'password': newPassword,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        if (kDebugMode) {
          print('Password updated in Firestore for user: $userEmail');
        }
        return true;
      }

      if (kDebugMode) {
        print('No active session found for user: $userEmail');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating password in Firestore: $e');
      }
      return false;
    }
  }

  // Attendance logging
  static Future<String?> logAttendanceStart({
    required String riderId,
    required double lat,
    required double lng,
    String? companyId,
  }) async {
    try {
      if (_firestore == null) return null;

      final dateStr = _getCurrentDateString();
      final now = DateTime.now();

      // Use composite ID for unique record per rider per day
      final documentId = "${riderId}_$dateStr";
      final docRef = _firestore!.collection('attendance').doc(documentId);

      final doc = await docRef.get();

      if (!doc.exists) {
        // First clock in of the day
        final attendance = {
          'id': documentId,
          'rider_id': riderId, // Use consistent naming
          'user_id': riderId, // Keep for compatibility
          'company_id': companyId,
          'attendance_date': now.toIso8601String(),
          'clock_in': now.toIso8601String(),
          'clock_out': null,
          'type': '{"is_Late": "0"}',
          'last_type': '{"is_Early": "0"}',
          'is_pushed': 0,
          'is_updated_from_server': 0,
          'user_entered_at': now.toIso8601String(),
          'deviceId': _deviceId ?? 'unknown',
          'location_in': {'lat': lat, 'lng': lng},
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        };
        await docRef.set(attendance);
      } else {
        // Already clocked in today, update last activity
        await docRef.update({
          'last_clock_in': now.toIso8601String(),
          'is_updated_from_server': 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      return documentId;
    } catch (e) {
      if (kDebugMode)
        print('Error starting attendance session (doc update): $e');
      return null;
    }
  }

  static Future<bool> logAttendanceEnd({
    required String sessionId, // dateStr
    required String riderId,
    required double lat,
    required double lng,
  }) async {
    try {
      if (_firestore == null) return false;

      final now = DateTime.now();
      final docRef = _firestore!.collection('attendance').doc(sessionId);

      await docRef.update({
        'clock_out': now.toIso8601String(),
        'location_out': {'lat': lat, 'lng': lng},
        'updated_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) print('Error ending attendance session (doc update): $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getAttendanceHistory(
    String riderId, {
    int limit = 10,
  }) async {
    try {
      if (_firestore == null) return [];

      final query = await _firestore!
          .collection('attendance')
          .where('rider_id', isEqualTo: riderId)
          .orderBy('attendance_date', descending: true)
          .limit(limit)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching attendance history (doc read): $e');
      return [];
    }
  }

  static String _getCurrentDateString() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }
}
