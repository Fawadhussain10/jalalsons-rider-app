import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';

/// Odoo answered with a JSON-RPC error (it still uses HTTP 200 for those).
class OdooRpcException implements Exception {
  final String message;
  OdooRpcException(this.message);
  @override
  String toString() => message;
}

/// Outcome of a password change, with a message fit to show the rider.
class PasswordChangeResult {
  final bool success;
  final String? code;
  final String message;
  const PasswordChangeResult(this.success, this.message, {this.code});
}

class ApiService {
  static String get _baseUrl => AppConfig.apiBaseUrl;
  static String get db => AppConfig.dbName;

  // One keep-alive connection for every request instead of a new socket each time.
  static final http.Client _client = http.Client();

  static String? _sessionId;
  static String? _userId;
  static String? _userName;
  static String? _userEmail;

  static String? get userName => _userName;
  static String? get userEmail => _userEmail;
  static String? get sessionId => _sessionId;
  static String? get userId => _userId;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
      };

  /// POSTs a JSON-RPC call and returns `result`, throwing on transport or Odoo errors.
  static Future<dynamic> _jsonRpc(
    String path,
    Map<String, dynamic> params, {
    Duration timeout = AppConfig.networkTimeout,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': params}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw OdooRpcException('Server error (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['error'] != null) {
      final err = data['error'];
      final msg = (err is Map ? (err['data']?['message'] ?? err['message']) : err).toString();
      throw OdooRpcException(msg);
    }
    return data is Map ? data['result'] : null;
  }

  static Future<dynamic> _callKw(
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) {
    return _jsonRpc('/web/dataset/call_kw', {
      'model': model,
      'method': method,
      'args': args,
      'kwargs': kwargs,
    });
  }

  // Authentication
  static Future<bool> authenticate(String email, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/web/session/authenticate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {'db': db, 'login': email, 'password': password},
            }),
          )
          .timeout(AppConfig.networkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          _sessionId = _extractSessionId(response.headers);
          _userId = data['result']['uid'].toString();
          _userName = data['result']['name'] ?? 'Rider';
          _userEmail = email;
          ErrorLogger.auth('Login successful for user: $email');
          return true;
        }
        ErrorLogger.auth('Login failed - invalid credentials');
      } else {
        ErrorLogger.auth('Login failed - HTTP ${response.statusCode}');
      }
      return false;
    } catch (e, stackTrace) {
      ErrorLogger.auth('Authentication error', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  static String? _extractSessionId(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie != null) {
      return RegExp(r'session_id=([^;]+)').firstMatch(setCookie)?.group(1);
    }
    return null;
  }

  /// Writes the order state in Odoo; true only if Odoo really accepted it.
  static Future<bool> updateOrderState(int orderId, String state) async {
    if (_sessionId == null || _userId == null) {
      ErrorLogger.error('No active session for order state update');
      return false;
    }
    try {
      await _callKw('tossdown.order', 'write', [
        [orderId],
        {'state': state, 'rider_id': int.parse(_userId!)},
      ]);
      ErrorLogger.info('Order $orderId -> $state');
      return true;
    } catch (e) {
      ErrorLogger.error('Failed to update order $orderId to $state: $e');
      return false;
    }
  }

  static Future<bool> updateOrderFields(int orderId, Map<String, dynamic> fields) async {
    if (_sessionId == null) return false;
    try {
      await _callKw('tossdown.order', 'write', [
        [orderId],
        fields,
      ]);
      return true;
    } catch (e) {
      ErrorLogger.error('Failed to update order fields for $orderId: $e');
      return false;
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      await _client
          .get(Uri.parse('$_baseUrl/web/session/logout'), headers: _headers)
          .timeout(AppConfig.shortNetworkTimeout);
    } catch (e) {
      if (kDebugMode) print('Logout error: $e');
    } finally {
      _sessionId = null;
      _userId = null;
      _userName = null;
      _userEmail = null;
    }
  }

  /// Changes the password; Odoo verifies [oldPassword] before changing anything.
  static Future<PasswordChangeResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_sessionId == null) {
      return const PasswordChangeResult(false, 'Your session expired. Please log in again.');
    }
    try {
      final result = await _jsonRpc('/api/reset/password', {
        'old_password': oldPassword,
        'password': newPassword,
      });
      if (result is Map && result['status'] == 'success') {
        return PasswordChangeResult(true, result['message']?.toString() ?? 'Password changed');
      }
      return PasswordChangeResult(
        false,
        (result is Map ? result['message'] : null)?.toString() ?? 'Could not change password.',
        code: result is Map ? result['code']?.toString() : null,
      );
    } catch (e) {
      return const PasswordChangeResult(false, 'Could not reach the server. Check your internet.');
    }
  }

  /// Registers this phone's push token with Odoo (empty string clears it).
  static Future<bool> registerFcmToken(String? token) async {
    if (_sessionId == null) return false;
    try {
      await _jsonRpc('/api/rider/fcm-token', {'token': token ?? ''},
          timeout: AppConfig.shortNetworkTimeout);
      return true;
    } catch (e) {
      ErrorLogger.error('FCM token registration failed: $e');
      return false;
    }
  }

  // Get user profile data
  static Future<Map<String, dynamic>?> getUserProfile() async {
    if (_sessionId == null || _userId == null) return null;
    try {
      final result = await _callKw('res.users', 'read', [
        [int.parse(_userId!)],
      ], {
        'fields': [
          'id',
          'name',
          'email',
          'phone',
          'mobile',
          'partner_id',
          'vehicle_number',
          'vehicle_type',
          'average_rating',
          'total_delivered_orders',
          'allowed_branch_ids',
        ],
      });
      if (result is List && result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first as Map);
      }
    } catch (e) {
      if (kDebugMode) print('Get user profile error: $e');
    }
    return null;
  }

  // Get additional user info (like allowed_branch_ids)
  static Future<Map<String, dynamic>?> getUserInfo() async {
    if (_sessionId == null || _userId == null) return null;
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/user/info?user_id=$_userId'), headers: _headers)
          .timeout(AppConfig.networkTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (e) {
      if (kDebugMode) print('Get user info error: $e');
    }
    return null;
  }

  // Clock In
  static Future<bool> clockIn(String riderId, double lat, double lng) async {
    try {
      await _callKw('tossdown.rider.shift', 'clock_in', [riderId, lat, lng]);
      return true;
    } catch (e) {
      ErrorLogger.error('Clock in error: $e');
      return false;
    }
  }

  // Clock Out
  static Future<bool> clockOut(String riderId, double lat, double lng) async {
    try {
      await _callKw('tossdown.rider.shift', 'clock_out', [riderId, lat, lng]);
      return true;
    } catch (e) {
      ErrorLogger.error('Clock out error: $e');
      return false;
    }
  }

  // Get Earnings
  static Future<Map<String, dynamic>> getEarnings(String riderId, String period) async {
    try {
      final result = await _callKw('tossdown.rider.earnings', 'get_earnings', [riderId, period]);
      if (result is Map<String, dynamic>) return result;
    } catch (e) {
      ErrorLogger.error('Get earnings error: $e');
    }
    return {};
  }

  /// Today's figures for the logged-in rider (see /api/rider/today-stats).
  static Future<Map<String, dynamic>> getTodayStats() async {
    try {
      final result = await _jsonRpc('/api/rider/today-stats', {});
      if (result is Map) return Map<String, dynamic>.from(result);
    } catch (e, stackTrace) {
      ErrorLogger.api('Error fetching today stats', error: e, stackTrace: stackTrace);
    }
    return {};
  }

  /// Uploads the delivery photo and marks the order delivered in Odoo.
  static Future<bool> submitPOD(String orderId, String imagePath) async {
    try {
      final base64Image = base64Encode(await File(imagePath).readAsBytes());
      await _jsonRpc(
        '/web/dataset/call_kw',
        {
          'model': 'tossdown.order',
          'method': 'write',
          'args': [
            [int.parse(orderId)],
            {
              'delivery_photo': base64Image,
              'tossdown_status': 'Delivered',
              'state': 'delivered',
            },
          ],
          'kwargs': {},
        },
        timeout: const Duration(seconds: 45),
      );
      return true;
    } catch (e) {
      ErrorLogger.error('Submit POD error: $e');
      return false;
    }
  }
}
