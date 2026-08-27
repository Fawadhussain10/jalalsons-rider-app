import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class OfflineService {
  static const String _queueKey = 'offline_queue';
  static final Connectivity _connectivity = Connectivity();

  // Queue an API call
  static Future<void> queueRequest(String method, String endpoint, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> queue = prefs.getStringList(_queueKey) ?? [];
    
    final request = {
      'method': method,
      'endpoint': endpoint,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    queue.add(jsonEncode(request));
    await prefs.setStringList(_queueKey, queue);
    
    if (kDebugMode) {
      print('Request queued: $method $endpoint');
    }
  }

  // Sync pending requests
  static Future<void> syncPendingRequests() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> queue = prefs.getStringList(_queueKey) ?? [];

    if (queue.isEmpty) return;

    if (kDebugMode) {
      print('Syncing ${queue.length} pending requests...');
    }

    final List<String> failedRequests = [];

    for (final requestJson in queue) {
      try {
        final request = jsonDecode(requestJson);
        final method = request['method'];
        final endpoint = request['endpoint'];
        final data = request['data'];

        bool success = false;
        
        // Dispatch based on method/endpoint - simplified dispatch logic
        // In a real app, this might need a more robust command pattern
        if (endpoint.contains('updateOrderState')) {
           // We might need to reconstruct the arguments from 'data'
           // This implies 'data' must contain all necessary args
           if (data['orderId'] != null && data['state'] != null) {
             success = await ApiService.updateOrderState(data['orderId'], data['state']);
           }
        } else if (endpoint.contains('updateOrderFields')) {
          if (data['orderId'] != null && data['fields'] != null) {
            success = await ApiService.updateOrderFields(data['orderId'], data['fields']);
          }
        } 
        
        // Add other handlers here
        
        if (!success) {
          failedRequests.add(requestJson);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error syncing request: $e');
        }
        failedRequests.add(requestJson);
      }
    }

    await prefs.setStringList(_queueKey, failedRequests);
    
    if (kDebugMode) {
      print('Sync complete. ${failedRequests.length} requests remaining.');
    }
  }

  // Monitor connectivity
  static void initialize() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (!result.contains(ConnectivityResult.none)) {
        syncPendingRequests();
      }
    });
  }
}
