import 'package:flutter/foundation.dart';
import 'offline_service.dart';

class DataSyncService {
  static final DataSyncService _instance = DataSyncService._internal();

  factory DataSyncService() {
    return _instance;
  }

  DataSyncService._internal();

  Future<void> init() async {
    if (kDebugMode) {
      print('DataSyncService initialized');
    }
    // Listen to network changes or periodically sync
    // For now, we rely on OfflineService's internal mechanisms
    // This service can be expanded for more complex background sync logic
  }

  Future<void> syncNow() async {
    await OfflineService.syncPendingRequests();
  }
}
