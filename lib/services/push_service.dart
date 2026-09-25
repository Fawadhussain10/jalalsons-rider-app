import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'firebase_service.dart';

/// Push notifications for riders.
///
/// Odoo sends pushes for new orders, dispatches, cancellations and campaigns.
/// While the app is open Android/iOS do not display them on their own, so they
/// are re-shown here through a high-importance local notification channel.
class PushService {
  PushService._();

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // must match Odoo + AndroidManifest
    'Orders & alerts',
    description: 'New orders, dispatch updates and important alerts',
    importance: Importance.max,
  );

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static final StreamController<Map<String, dynamic>> _taps = StreamController.broadcast();
  static StreamSubscription<String>? _tokenRefreshSub;
  static bool _initialized = false;

  /// Data payload of notifications the rider tapped (for in-app navigation).
  static Stream<Map<String, dynamic>> get onNotificationTap => _taps.stream;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          _taps.add({'payload': response.payload});
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // iOS shows banners itself when the app is open.
      await messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(m.data));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _taps.add(initial.data);
    } catch (e) {
      if (kDebugMode) print('PushService.initialize failed: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null || !Platform.isAndroid) return; // iOS already presents it
    await _local.show(
      id: message.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          color: const Color(0xFFE51A1A),
          styleInformation: BigTextStyleInformation(n.body ?? ''),
        ),
      ),
      payload: message.data['order_id']?.toString(),
    );
  }

  /// Ties this phone's token to [riderId] in Odoo (used for automatic pushes)
  /// and Firestore (used by older campaign code), and keeps it fresh.
  static Future<void> registerForRider(String riderId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _store(riderId, token);
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((t) => _store(riderId, t));
    } catch (e) {
      if (kDebugMode) print('PushService.registerForRider failed: $e');
    }
  }

  static Future<void> _store(String riderId, String token) async {
    await Future.wait([
      ApiService.registerFcmToken(token),
      FirebaseService.setRiderFcmToken(riderId, token),
    ]);
  }

  /// Stop pushes to this phone after logout.
  static Future<void> unregister(String? riderId) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      await Future.wait([
        ApiService.registerFcmToken(''),
        if (riderId != null) FirebaseService.setRiderFcmToken(riderId, null),
      ]);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) print('PushService.unregister failed: $e');
    }
  }
}
