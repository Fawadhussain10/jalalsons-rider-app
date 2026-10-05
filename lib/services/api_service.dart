import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';

/// Odoo answered with a JSON-RPC error (it still uses HTTP 200 for those).
class OdooRpcException implements Exception {
  final String message;
  final bool sessionExpired;
  OdooRpcException(this.message, {this.sessionExpired = false});
  @override
  String toString() => message;
}

/// Result of a login attempt. Only [wrongCredentials] means the saved password
/// is bad; the others are temporary (weak signal, server busy) and must never
/// log the rider out.
enum AuthOutcome { success, wrongCredentials, tooManyAttempts, offline }

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
  static http.Client _client = http.Client();

  @visibleForTesting
  static set httpClient(http.Client client) => _client = client;

  @visibleForTesting
  static void resetSession() {
    _sessionId = null;
    _userId = null;
    _userName = null;
    _userEmail = null;
  }

  static String? _sessionId;
  static String? _userId;
  static String? _userName;
  static String? _userEmail;

  /// Set by AuthProvider: logs in again with the saved credentials when Odoo's
  /// session is missing or expired. Returns true once a new session exists.
  static Future<bool> Function()? onSessionExpired;
  static Future<bool>? _reauthInFlight;

  static String? get userName => _userName;
  static String? get userEmail => _userEmail;
  static String? get sessionId => _sessionId;
  static String? get userId => _userId;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
      };

  /// Makes sure an Odoo session exists, logging in again if needed. Concurrent
  /// callers share one login attempt.
  static Future<bool> _ensureSession() async {
    if (_sessionId != null && _userId != null) return true;
    return _reauthenticate();
  }

  static Future<bool> _reauthenticate() {
    final hook = onSessionExpired;
    if (hook == null) return Future.value(false);
    return _reauthInFlight ??= hook().whenComplete(() => _reauthInFlight = null);
  }

  /// POSTs a JSON-RPC call and returns `result`, throwing on transport or Odoo
  /// errors. An expired session is renewed once and the call retried.
  static Future<dynamic> _jsonRpc(
    String path,
    Map<String, dynamic> params, {
    Duration timeout = AppConfig.networkTimeout,
  }) async {
    if (!await _ensureSession()) {
      throw OdooRpcException('Not connected to the server. Please check your internet.');
    }
    try {
      return await _jsonRpcOnce(path, params, timeout: timeout);
    } on OdooRpcException catch (e) {
      if (!e.sessionExpired) rethrow;
      _sessionId = null;
      if (!await _reauthenticate()) rethrow;
      return _jsonRpcOnce(path, params, timeout: timeout);
    }
  }

  static Future<dynamic> _jsonRpcOnce(
    String path,
    Map<String, dynamic> params, {
    required Duration timeout,
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
      final errData = err is Map ? err['data'] : null;
      final name = errData is Map ? (errData['name'] ?? '').toString() : '';
      throw OdooRpcException(msg, sessionExpired: name.contains('SessionExpired'));
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
  static Future<bool> authenticate(String email, String password) async =>
      await login(email, password) == AuthOutcome.success;

  /// Logs in to Odoo and says *why* it failed, so callers can tell a wrong
  /// password from a weak signal or Odoo's temporary login lock.
  static Future<AuthOutcome> login(String email, String password) async {
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

      if (response.statusCode != 200) {
        ErrorLogger.auth('Login failed - HTTP ${response.statusCode}');
        return AuthOutcome.offline; // proxy/server trouble, not the password
      }
      final data = jsonDecode(response.body);
      if (data is Map && data['result'] != null) {
        _sessionId = _extractSessionId(response.headers);
        _userId = data['result']['uid'].toString();
        _userName = data['result']['name'] ?? 'Rider';
        _userEmail = email;
        ErrorLogger.auth('Login successful for user: $email');
        return AuthOutcome.success;
      }
      final err = data is Map ? data['error'] : null;
      final errData = err is Map ? err['data'] : null;
      final name = errData is Map ? (errData['name'] ?? '').toString() : '';
      final message = errData is Map ? (errData['message'] ?? '').toString() : '';
      if (message.contains('Too many login failures')) {
        ErrorLogger.auth('Login refused - too many attempts');
        return AuthOutcome.tooManyAttempts;
      }
      if (name.contains('AccessDenied')) {
        ErrorLogger.auth('Login failed - wrong credentials');
        return AuthOutcome.wrongCredentials;
      }
      ErrorLogger.auth('Login failed - server error: $name');
      return AuthOutcome.offline;
    } catch (e, stackTrace) {
      // No signal, DNS failure, timeout...
      ErrorLogger.auth('Authentication error', error: e, stackTrace: stackTrace);
      return AuthOutcome.offline;
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
    if (!await _ensureSession()) {
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
    if (!await _ensureSession()) return false;
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
    if (!await _ensureSession()) {
      return const PasswordChangeResult(false, 'Not connected to the server. Please check your internet.');
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
    if (_sessionId == null) return false; // also called during logout: never re-login here
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
    if (!await _ensureSession()) return null;
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
    if (!await _ensureSession()) return null;
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
