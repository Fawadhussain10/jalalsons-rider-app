import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';

class ApiService {
  static String get _baseUrl => AppConfig.apiBaseUrl;
  static String get db => AppConfig.dbName;

  static String? _sessionId;
  static String? _userId;
  static String? _userName;
  static String? _userEmail;

  static String? get userName => _userName;
  static String? get userEmail => _userEmail;

  // Authentication
  static Future<bool> authenticate(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/web/session/authenticate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {
                'db': db,
                'login': email,
                'password': password,
                'url': _baseUrl,
              },
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
        } else {
          ErrorLogger.auth('Login failed - invalid response', error: data);
        }
      } else {
        ErrorLogger.auth(
          'Login failed - HTTP ${response.statusCode}',
          error: response.body,
        );
      }
      return false;
    } catch (e, stackTrace) {
      ErrorLogger.auth(
        'Authentication error',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static String? _extractSessionId(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie != null) {
      final sessionMatch = RegExp(r'session_id=([^;]+)').firstMatch(setCookie);
      return sessionMatch?.group(1);
    }
    return null;
  }

  // Get available orders from Odoo
  static Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    try {
      // Validate session before making API call
      if (!await _validateSession()) {
        throw Exception('Session expired or invalid');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.order',
            'method': 'search_read',
            'args': [],
            'kwargs': {
              'domain': [
                ['state', '=', 'draft'],
                ['tossdown_status', '=', 'Confirm'],
              ],
              'fields': [
                'id',
                'reference',
                'tossdown_sequence',
                'customer_id',
                'order_type',
                'create_date',
                'write_date',
                'grand_total',
                'payment_mode',
                'branch',
              ],
              'limit': AppConfig.orderSearchLimit,
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          return List<Map<String, dynamic>>.from(data['result']);
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching orders: $e');
      }
      return [];
    }
  }

  // Fetch partner (customer) details by ID with location
  static Future<Map<String, dynamic>?> getPartnerById(int partnerId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/web/dataset/call_kw'),
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {
                'model': 'res.partner',
                'method': 'search_read',
                'args': [],
                'kwargs': {
                  'domain': [
                    ['id', '=', partnerId],
                  ],
                  'limit': 1,
                  'fields': [
                    'id',
                    'name',
                    'email',
                    'phone',
                    'mobile',
                    'street',
                    'street2',
                    'city',
                    'zip',
                    'partner_latitude',
                    'partner_longitude',
                  ],
                },
              },
            }),
          )
          .timeout(AppConfig.networkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['result'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          return Map<String, dynamic>.from(results.first as Map);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching partner by id: $e');
      }
      return null;
    }
  }

  // Get order details with line items
  static Future<Map<String, dynamic>?> getOrderDetails(int orderId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.order',
            'method': 'read',
            'args': [orderId],
            'kwargs': {
              'fields': [
                'id',
                'reference',
                'tossdown_sequence',
                'customer_id',
                'order_type',
                'order_placed_at',
                'branch',
                'payment_mode',
                'state',
                'tossdown_status',
                'line_ids',
                'total_qty',
                'total',
                'discount',
                'delivery_charges',
                'tax_amount',
                'service_charges',
                'grand_total',
                'create_date',
                'write_date',
              ],
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result'].isNotEmpty) {
          return data['result'][0];
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching order details: $e');
      }
      return null;
    }
  }

  // Get order line items
  static Future<List<Map<String, dynamic>>> getOrderLineItems(
    List<int> lineIds,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.order.line',
            'method': 'search_read',
            'args': [],
            'kwargs': {
              "domain": [
                ["id", "in", lineIds],
              ],
              // 'fields': [
              //   'id',
              //   'product_id',
              //   'name',
              //   'product_uom_qty',
              //   'price_unit',
              //   'price_subtotal',
              // ],
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          return List<Map<String, dynamic>>.from(data['result']);
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching order line items: $e');
      }
      return [];
    }
  }

  // Accept order (update status)
  static Future<bool> acceptOrder(int orderId, String riderId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.order',
            'method': 'write',
            'args': [
              [orderId],
              {
                'state': 'confirmed',
                'tossdown_status': 'Accepted',
                'rider_id': riderId,
                'accepted_at': DateTime.now().toIso8601String(),
              },
            ],
          },
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error accepting order: $e');
      }
      return false;
    }
  }

  // Update order status
  static Future<bool> updateOrderStatus(
    int orderId,
    String status, {
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final updateData = {
        'tossdown_status': status,
        'updated_at': DateTime.now().toIso8601String(),
        ...?additionalData,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.order',
            'method': 'write',
            'args': [
              [orderId],
              updateData,
            ],
          },
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating order status: $e');
      }
      return false;
    }
  }

  // Update order state in Odoo backend
  // static Future<bool> updateOrderState(int orderId, String state) async {
  //   try {
  //     if (_sessionId == null || _userId == null) {
  //       if (kDebugMode) {
  //         print('No active session for order state update');
  //       }
  //       return false;
  //     }
  //
  //     final response = await http.post(
  //       Uri.parse('$_baseUrl/web/dataset/call_kw'),
  //       headers: {
  //         'Content-Type': 'application/json',
  //         'Cookie': 'session_id=$_sessionId',
  //       },
  //       body: jsonEncode({
  //         'jsonrpc': '2.0',
  //         'method': 'call',
  //         'params': {
  //           'args': [
  //             [orderId],
  //             {
  //               'state': state,
  //               'rider_id':_userId,
  //             }
  //           ],
  //           'model': 'tossdown.order',
  //           'method': 'write',
  //           'kwargs': {
  //             'context': {
  //               'uid': _userId,
  //             }
  //           }
  //         },
  //       }),
  //     );
  //
  //     if (response.statusCode == 200) {
  //       final data = jsonDecode(response.body);
  //       if (kDebugMode) {
  //         print('Order state updated successfully: $state for order $orderId');
  //       }
  //       return true;
  //     } else {
  //       if (kDebugMode) {
  //         print('Failed to update order state: ${response.statusCode} - ${response.body}');
  //       }
  //       return false;
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       print('Error updating order state: $e');
  //     }
  //     ErrorLogger.error('updateOrderState'+ e.toString());
  //     return false;
  //   }
  // }

  static Future<bool> updateOrderState(int orderId, String state) async {
    try {
      if (_sessionId == null || _userId == null) {
        ErrorLogger.error('No active session for order state update');
        return false;
      }

      final url = Uri.parse('$_baseUrl/web/dataset/call_kw');
      final headers = {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=$_sessionId',
      };
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'args': [
            [orderId],
            {'state': state, 'rider_id': int.parse(_userId!)},
          ],
          'model': 'tossdown.order',
          'method': 'write',
          'kwargs': {
            'context': {'uid': _userId},
          },
        },
      };

      // Log API call details before sending request
      ErrorLogger.info('--- API CALL: updateOrderState ---');
      ErrorLogger.info('URL: $url');
      ErrorLogger.info('Headers: $headers');
      ErrorLogger.info('Body: ${jsonEncode(body)}');
      ErrorLogger.info('-----------------------------------');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        ErrorLogger.info(
          'Order state updated successfully: $state for order $orderId',
        );
        return true;
      } else {
        ErrorLogger.error(
          'Failed to update order state: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      ErrorLogger.error('Error updating order state: $e');
      return false;
    }
  }

  // Update arbitrary fields on order in Odoo (e.g., delivery_kms)
  static Future<bool> updateOrderFields(
    int orderId,
    Map<String, dynamic> fields,
  ) async {
    try {
      if (_sessionId == null) {
        ErrorLogger.error('No active session for updateOrderFields');
        return false;
      }

      final url = Uri.parse('$_baseUrl/web/dataset/call_kw');
      final headers = {
        'Content-Type': 'application/json',
        if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
      };
      final body = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'tossdown.order',
          'method': 'write',
          'args': [
            [orderId],
            fields,
          ],
        },
      };

      ErrorLogger.info('--- API CALL: updateOrderFields ---');
      ErrorLogger.info('URL: $url');
      ErrorLogger.info('Headers: $headers');
      ErrorLogger.info('Body: ${jsonEncode(body)}');
      ErrorLogger.info('-----------------------------------');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        ErrorLogger.info('Order fields updated for $orderId: $fields');
        return true;
      } else {
        ErrorLogger.error(
          'Failed to update order fields: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      ErrorLogger.error('Error updating order fields: $e');
      return false;
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      await http.get(
        Uri.parse('$_baseUrl/web/session/logout'),
        headers: {if (_sessionId != null) 'Cookie': 'session_id=$_sessionId'},
      );
    } catch (e) {
      if (kDebugMode) {
        print('Logout error: $e');
      }
    } finally {
      _sessionId = null;
      _userId = null;
      _userName = null;
      _userEmail = null;
    }
  }

  // Initialize session from stored data
  static Future<bool> initializeSession({
    required String sessionId,
    String? userEmail,
  }) async {
    try {
      if (sessionId.isEmpty) return false;
      _sessionId = sessionId;
      _userEmail = userEmail;

      // Validate cookie session by calling an allowed authenticated endpoint
      // Using search_count on res.partner (from Postman collection)
      final response = await http
          .post(
            Uri.parse('$_baseUrl/web/dataset/call_kw'),
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {
                'model': 'res.partner',
                'method': 'search_count',
                'args': [],
                'kwargs': {'domain': []},
              },
            }),
          )
          .timeout(AppConfig.shortNetworkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] is int) {
          // Session cookie is valid; keep current _userId/_userName if known
          return true;
        }
      }
      return false;
    } catch (e, stackTrace) {
      ErrorLogger.api(
        'Initialize session error',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  // Validate session before API calls
  static Future<bool> _validateSession() async {
    try {
      if (_sessionId == null) return false;

      // Simple session validation - just check if session ID exists
      // More complex validation is handled by FirebaseService
      return _sessionId != null && _userId != null;
    } catch (e) {
      if (kDebugMode) {
        print('Session validation error: $e');
      }
      return false;
    }
  }

  // Change user password
  static Future<bool> changePassword({required String newPassword}) async {
    try {
      // Validate session before making API call
      if (!await _validateSession()) {
        throw Exception('Session expired or invalid');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/reset/password'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({'password': newPassword}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] != null && data['result']['status'] == 'success';
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Password change error: $e');
      }
      return false;
    }
  }

  // Get user profile data
  static Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      // Validate session before making API call
      if (!await _validateSession()) {
        throw Exception('Session expired or invalid');
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/web/dataset/call_kw'),
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {
                'model': 'res.users',
                'method': 'read',
                'args': [
                  [int.parse(_userId ?? '0')],
                ],
                'kwargs': {
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
                    'on_time_delivery',
                    'average_delivery_time',
                  ],
                },
              },
            }),
          )
          .timeout(AppConfig.networkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'];
        if (result is List && result.isNotEmpty) {
          print('Get user profile success' + result[0].toString());
          return Map<String, dynamic>.from(result[0] as Map);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Get user profile error: $e');
      }
      return null;
    }
  }

  // Get additional user info (like allowed_branch_ids)
  static Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      if (!await _validateSession()) {
        throw Exception('Session expired or invalid');
      }

      final urlStr = '$_baseUrl/api/user/info?user_id=$_userId';
      final url = Uri.parse(urlStr);
      ErrorLogger.info('--- API CALL: getUserInfo ---');
      ErrorLogger.info('URL: $url');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
          )
          .timeout(AppConfig.networkTimeout);

      ErrorLogger.info('Response Status: ${response.statusCode}');
      ErrorLogger.info('Response Body: ${response.body}');
      ErrorLogger.info('-----------------------------');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Get user info error: $e');
      }
      return null;
    }
  }

  // Get session info
  static String? get sessionId => _sessionId;
  static String? get userId => _userId;
  // Clock In
  static Future<bool> clockIn(String riderId, double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.rider.shift', // Assumed model name
            'method': 'clock_in',
            'args': [riderId, lat, lng],
          },
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      ErrorLogger.error('Clock in error: $e');
      return false;
    }
  }

  // Clock Out
  static Future<bool> clockOut(String riderId, double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.rider.shift', // Assumed model name
            'method': 'clock_out',
            'args': [riderId, lat, lng],
          },
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      ErrorLogger.error('Clock out error: $e');
      return false;
    }
  }

  // Get Shifts
  static Future<List<Map<String, dynamic>>> getShifts(
    String riderId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.rider.shift', // Assumed model name
            'method': 'search_read',
            'args': [],
            'kwargs': {
              'domain': [
                ['rider_id', '=', int.parse(riderId)],
                if (start != null)
                  ['start_time', '>=', start.toIso8601String()],
                if (end != null) ['end_time', '<=', end.toIso8601String()],
              ],
              'order': 'start_time desc',
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          return List<Map<String, dynamic>>.from(data['result']);
        }
      }
      return [];
    } catch (e) {
      ErrorLogger.error('Get shifts error: $e');
      return [];
    }
  }

  // Get Earnings
  static Future<Map<String, dynamic>> getEarnings(
    String riderId,
    String period,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'tossdown.rider.earnings', // Assumed model name
            'method': 'get_earnings',
            'args': [riderId, period],
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          return data['result'];
        }
      }
      return {};
    } catch (e) {
      ErrorLogger.error('Get earnings error: $e');
      return {};
    }
  }

  // Get Today Stats
  static Future<Map<String, dynamic>> getTodayStats() async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/rider/today-stats/'),
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
            body: jsonEncode({}),
          )
          .timeout(AppConfig.networkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) {
          print('--- TODAY STATS RESPONSE ---');
          print(response.body);
          print('----------------------------');
        }
        return Map<String, dynamic>.from(data);
      } else {
        ErrorLogger.api('Failed to fetch today stats: ${response.statusCode}');
        return {};
      }
    } catch (e, stackTrace) {
      ErrorLogger.api(
        'Error fetching today stats',
        error: e,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  // Submit Proof of Delivery
  static Future<bool> submitPOD(String orderId, String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final String base64Image = base64Encode(await imageFile.readAsBytes());

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
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
            'kwargs': {
              'context': {'uid': _userId},
            },
          },
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      ErrorLogger.error('Submit POD error: $e');
      return false;
    }
  }
}
