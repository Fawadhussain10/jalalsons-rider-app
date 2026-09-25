import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../utils/time_utils.dart';

enum OrderStatus {
  pending,
  accepted,
  pickedUp,
  delivered,
  cancelled,
}

enum OrderPriority {
  low,
  medium,
  high,
  urgent,
}

class Order {
  final String id;
  final String reference;
  final String tossdownSequence;
  final String customerName;
  final String customerPhone;
  final String pickupAddress;
  final String deliveryAddress;
  final double pickupLatitude;
  final double pickupLongitude;
  final double deliveryLatitude;
  final double deliveryLongitude;
  final double amount;
  final String currency;
  final OrderStatus status;
  final OrderPriority priority;
  final DateTime createdAt;
  final DateTime? estimatedDeliveryTime;
  final String? notes;
  final String? riderId;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final List<String> items;
  final Map<String, dynamic>? stateTrail;
  final String paymentMethod;
  final String paymentMode;
  final bool isPaid;
  final bool isCancelledOrRefunded;
  final bool liveOnApp;
  final String orderType;
  final String channel;
  final int? branchId;
  final String branchName;
  final double deliveryKms;
  final int? acceptedBy;
  final int? deliveredBy;

  Order({
    required this.id,
    required this.reference,
    this.tossdownSequence = '',
    required this.customerName,
    required this.customerPhone,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.amount,
    this.currency = 'PKR',
    this.status = OrderStatus.pending,
    this.priority = OrderPriority.medium,
    required this.createdAt,
    this.estimatedDeliveryTime,
    this.notes,
    this.riderId,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.items = const [],
    this.stateTrail,
    this.paymentMethod = 'cash',
    this.paymentMode = 'cod',
    this.isPaid = false,
    this.isCancelledOrRefunded = false,
    this.liveOnApp = false,
    this.orderType = 'delivery',
    this.channel = '',
    this.branchId,
    this.branchName = '',
    this.deliveryKms = 0.0,
    this.acceptedBy,
    this.deliveredBy,
  });

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static DateTime? _trailAt(Map<String, dynamic>? trail, String state) {
    final entry = trail?[state];
    return entry is Map ? TimeUtils.parseServerTime(entry['at']) : null;
  }

  static int? _trailBy(Map<String, dynamic>? trail, String state) {
    final entry = trail?[state];
    return entry is Map ? _toInt(entry['by']) : null;
  }

  /// Builds an order from the Firestore document Odoo maintains.
  factory Order.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] is Map ? Map<String, dynamic>.from(json['customer']) : null;
    final address = customer?['address'] is Map ? customer!['address'] as Map : null;
    final location = customer?['location'] is Map ? customer!['location'] as Map : null;
    final branch = json['branch'] is Map ? json['branch'] as Map : null;
    final trail = json['stateTrail'] is Map ? Map<String, dynamic>.from(json['stateTrail']) : null;
    final paymentMode = (json['paymentMode'] ?? 'cod').toString();
    final state = (json['status'] ?? '').toString();

    final deliveryAddress = [address?['street'], address?['street2'], address?['city']]
        .where((p) => p != null && p.toString().trim().isNotEmpty && p != false)
        .join(', ');

    final acceptedAt = _trailAt(trail, 'accepted');
    final pickedUpAt = _trailAt(trail, 'dispatched');
    final deliveredAt = _trailAt(trail, 'delivered');

    OrderStatus status;
    if (state == 'cancelled' || state == 'refund' || json['is_cancelled_or_refunded'] == true) {
      status = OrderStatus.cancelled;
    } else if (deliveredAt != null || state == 'delivered') {
      status = OrderStatus.delivered;
    } else if (pickedUpAt != null || state == 'dispatch') {
      status = OrderStatus.pickedUp;
    } else if (acceptedAt != null || state == 'accepted') {
      status = OrderStatus.accepted;
    } else {
      status = OrderStatus.pending;
    }

    return Order(
      id: json['id']?.toString() ?? '',
      reference: (json['reference'] ?? '').toString(),
      tossdownSequence: (json['tossdownSequence'] ?? '').toString(),
      customerName: (customer?['name'] ?? '').toString(),
      customerPhone: (customer?['phone'] ?? '').toString(),
      pickupAddress: (branch?['name'] ?? '').toString(),
      deliveryAddress: deliveryAddress,
      pickupLatitude: _toDouble(json['pickupLatitude']),
      pickupLongitude: _toDouble(json['pickupLongitude']),
      deliveryLatitude: _toDouble(location?['latitude']),
      deliveryLongitude: _toDouble(location?['longitude']),
      amount: _toDouble(json['amount']),
      currency: (json['currency'] ?? 'PKR').toString(),
      status: status,
      createdAt: TimeUtils.parseServerTime(json['createdAt']) ?? DateTime.now(),
      estimatedDeliveryTime: TimeUtils.parseServerTime(json['estimatedDeliveryTime']),
      notes: json['notes']?.toString(),
      riderId: (json['rider'] is Map ? json['rider']['riderID'] : null)?.toString(),
      acceptedAt: acceptedAt,
      pickedUpAt: pickedUpAt,
      deliveredAt: deliveredAt,
      items: _extractItems(json),
      stateTrail: trail,
      paymentMethod: paymentMode == 'cod' ? 'cash' : paymentMode,
      paymentMode: paymentMode,
      isCancelledOrRefunded: status == OrderStatus.cancelled,
      liveOnApp: json['live_on_app'] == true,
      orderType: (json['orderType'] ?? 'delivery').toString().toLowerCase(),
      channel: (json['channel'] ?? '').toString(),
      branchId: _toInt(branch?['id']),
      branchName: (branch?['name'] ?? '').toString(),
      deliveryKms: _toDouble(json['delivery_kms']),
      acceptedBy: _trailBy(trail, 'accepted'),
      deliveredBy: _trailBy(trail, 'delivered'),
    );
  }

  static List<String> _extractItems(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>?;
    if (items == null) return [];
    return items.map((item) {
      if (item is Map) {
        final name = item['name']?.toString() ?? '';
        final qty = item['qty'];
        final q = qty is num && qty == qty.roundToDouble() ? qty.toInt().toString() : '${qty ?? 0}';
        return '$name ($q x)';
      }
      return item.toString();
    }).toList();
  }

  bool get isCashOnDelivery => paymentMode == 'cod';
  bool get isDispatched => pickedUpAt != null;
  bool get isDelivered => status == OrderStatus.delivered;

  String get paymentLabel {
    switch (paymentMode) {
      case 'cod':
        return 'Cash on Delivery';
      case 'online':
        return 'Paid Online';
      case 'card':
        return 'Card';
      case 'wallet':
        return 'Wallet';
      case 'bank_transfer':
        return 'Bank Transfer';
      default:
        return paymentMode;
    }
  }

  /// Lower-cased text the search box matches against.
  late final String searchText = [
    reference,
    tossdownSequence,
    id,
    customerName,
    customerPhone,
    customerPhone.replaceAll(RegExp(r'[^0-9]'), ''),
    deliveryAddress,
  ].join(' ').toLowerCase();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference': reference,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'deliveryAddress': deliveryAddress,
      'amount': amount,
      'currency': currency,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'paymentMode': paymentMode,
    };
  }
}

/// Supplies the three order tabs from a single Firestore listener.
///
/// Visibility rule (agreed with operations):
/// * orders placed since local midnight are shown;
/// * orders from the previous day stay only while they are not delivered
///   (so an order placed at 11:50 PM can still be finished after midnight);
/// * once delivered, a previous-day order disappears.
class OrderProvider extends ChangeNotifier {
  List<Order> _availableOrders = [];
  List<Order> _acceptedOrders = [];
  List<Order> _completedOrders = [];
  List<Order> _deliveredToday = [];
  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  String? _error;
  String? _currentUserId;
  String _query = '';
  final Set<String> _busyOrderIds = {};
  List<Map<String, dynamic>> _lastSnapshot = const [];

  StreamSubscription<List<Map<String, dynamic>>>? _ordersSub;
  Timer? _midnightTimer;

  // Branch IDs this rider is allowed to see orders for.
  // null  = field absent on rider doc → no restriction.
  // []    = field present but empty  → block ALL orders.
  // [..] = filter to these branch IDs.
  List<int>? _allowedBranchIds;

  List<Order> get availableOrders => _filter(_availableOrders);
  List<Order> get acceptedOrders => _filter(_acceptedOrders);
  List<Order> get completedOrders => _filter(_completedOrders);
  int get availableCount => _availableOrders.length;
  int get acceptedCount => _acceptedOrders.length;
  int get completedCount => _completedOrders.length;
  bool get isLoading => _isLoading;
  bool get hasLoadedOnce => _hasLoadedOnce;
  String? get error => _error;
  String get query => _query;
  bool isBusy(String orderId) => _busyOrderIds.contains(orderId);

  /// Deliveries this rider completed since local midnight.
  List<Order> get deliveredToday => _deliveredToday;

  /// Cash-on-delivery orders delivered today (money the rider is holding).
  List<Order> get codOrders => _deliveredToday.where((o) => o.isCashOnDelivery).toList();

  double get totalCashToCollect => codOrders.fold(0.0, (sum, o) => sum + o.amount);

  double get kmsToday => _deliveredToday.fold(0.0, (sum, o) => sum + o.deliveryKms);

  Order? get currentOrder => _acceptedOrders.isNotEmpty ? _acceptedOrders.first : null;

  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  void setSearchQuery(String value) {
    final q = value.trim().toLowerCase();
    if (q == _query) return;
    _query = q;
    notifyListeners();
  }

  List<Order> _filter(List<Order> orders) {
    if (_query.isEmpty) return orders;
    final digits = _query.replaceAll(RegExp(r'[^0-9]'), '');
    return orders.where((o) {
      if (o.searchText.contains(_query)) return true;
      // "0300 1234567" should match "+923001234567"
      return digits.length >= 4 && o.searchText.contains(digits);
    }).toList();
  }

  /// Starts (or restarts) the live order feed.
  Future<void> initializeOrders() async {
    if (_currentUserId == null) {
      _error = 'User not authenticated';
      notifyListeners();
      return;
    }
    _setLoading(true);
    _error = null;
    try {
      _allowedBranchIds = await FirebaseService.getRiderAllowedBranchIds(_currentUserId!);
      _subscribe();
    } catch (e) {
      _error = 'Failed to load orders: $e';
      _setLoading(false);
    }
  }

  void _subscribe() {
    _ordersSub?.cancel();
    _midnightTimer?.cancel();

    final since = TimeUtils.carryOverStart();
    _ordersSub = FirebaseService.streamOrdersPlacedSince(since).listen(
      (docs) {
        _lastSnapshot = docs;
        _rebuild();
        _hasLoadedOnce = true;
        _error = null;
        _setLoading(false);
      },
      onError: (Object e) {
        _error = 'Could not load orders. Pull down to retry.';
        if (kDebugMode) print('Order stream error: $e');
        _setLoading(false);
      },
    );

    // At midnight yesterday's delivered orders must disappear and the query
    // window moves forward a day.
    _midnightTimer = Timer(TimeUtils.untilNextMidnight() + const Duration(seconds: 2), _subscribe);
  }

  void _rebuild() {
    final buckets = bucketOrders(
      _lastSnapshot,
      riderId: int.tryParse(_currentUserId ?? ''),
      allowedBranchIds: _allowedBranchIds,
    );
    _availableOrders = buckets.available;
    _acceptedOrders = buckets.accepted;
    _completedOrders = buckets.completed;
    _deliveredToday = buckets.deliveredToday;
    notifyListeners();
  }

  /// Splits Firestore order documents into the three tabs (pure; unit-tested).
  @visibleForTesting
  static ({
    List<Order> available,
    List<Order> accepted,
    List<Order> completed,
    List<Order> deliveredToday,
  }) bucketOrders(
    List<Map<String, dynamic>> docs, {
    required int? riderId,
    List<int>? allowedBranchIds,
    DateTime? now,
  }) {
    final todayStart = TimeUtils.startOfToday(now);
    final carryOverStart = TimeUtils.carryOverStart(now);
    final available = <Order>[];
    final accepted = <Order>[];
    final completed = <Order>[];
    final deliveredToday = <Order>[];

    for (final json in docs) {
      if (json['live_on_app'] != true) continue;
      if ((json['orderType'] ?? '').toString().toLowerCase() == 'pick') continue;
      if (!_branchAllowed(json, allowedBranchIds)) continue;

      final Order order;
      try {
        order = Order.fromJson(json);
      } catch (e) {
        if (kDebugMode) print('Skipping malformed order ${json['id']}: $e');
        continue;
      }
      if (order.status == OrderStatus.cancelled) continue;
      if (order.createdAt.isBefore(carryOverStart)) continue;

      final placedToday = !order.createdAt.isBefore(todayStart);

      if (order.isDelivered) {
        if (order.deliveredBy == riderId || (order.deliveredBy == null && order.acceptedBy == riderId)) {
          // Previous-day orders disappear once delivered.
          if (placedToday) completed.add(order);
          if (order.deliveredAt != null && !order.deliveredAt!.isBefore(todayStart)) {
            deliveredToday.add(order);
          }
        }
      } else if (order.acceptedAt != null) {
        if (order.acceptedBy == riderId) accepted.add(order);
      } else if (order.stateTrail?['draft'] is Map) {
        available.add(order);
      }
    }

    int newestFirst(DateTime? a, DateTime? b) => (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    available.sort((a, b) => newestFirst(a.createdAt, b.createdAt));
    accepted.sort((a, b) => newestFirst(a.acceptedAt, b.acceptedAt));
    completed.sort((a, b) => newestFirst(a.deliveredAt, b.deliveredAt));
    deliveredToday.sort((a, b) => newestFirst(a.deliveredAt, b.deliveredAt));

    return (
      available: available,
      accepted: accepted,
      completed: completed,
      deliveredToday: deliveredToday,
    );
  }

  /// Accept: Odoo first (it assigns the rider), then the Firestore trail.
  Future<bool> acceptOrder(String orderId, [String? _]) async {
    if (_currentUserId == null) {
      _error = 'User not authenticated';
      return false;
    }
    if (!_busyOrderIds.add(orderId)) return false;
    notifyListeners();
    try {
      final ok = await ApiService.updateOrderState(int.parse(orderId), 'accepted');
      if (!ok) {
        _error = 'Could not accept the order. It may already be taken.';
        return false;
      }
      await FirebaseService.updateOrderStateTrail(orderId, 'accepted', _currentUserId!);
      return true;
    } catch (e) {
      _error = 'Failed to accept order';
      return false;
    } finally {
      _busyOrderIds.remove(orderId);
      notifyListeners();
    }
  }

  /// Stores the route estimate (for on-time analytics). The official KMs are
  /// the road distance Odoo computes, so nothing is written to Odoo here.
  Future<bool> updateDeliveryKmsOnce(String orderId, double kms, {double? estimatedSeconds}) async {
    try {
      if (estimatedSeconds == null || estimatedSeconds <= 0) return true;
      final existing = await FirebaseService.getOrderById(orderId);
      if (existing?['estimatedDeliveryTime'] != null) return true;
      await FirebaseService.updateOrderFields(orderId, {
        'estimatedDeliveryTime':
            DateTime.now().toUtc().add(Duration(seconds: estimatedSeconds.round())).toIso8601String(),
        'route_duration_seconds': estimatedSeconds,
        'rider_route_kms': kms,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// [backendAlreadyUpdated]: the proof-of-delivery upload already set the
  /// state in Odoo, so only the Firestore trail needs writing.
  Future<bool> updateOrderStatus(
    String orderId,
    OrderStatus newStatus, {
    bool backendAlreadyUpdated = false,
  }) async {
    if (_currentUserId == null) {
      _error = 'User not authenticated';
      return false;
    }

    String stateTrailState;
    String? odooState;
    switch (newStatus) {
      case OrderStatus.pickedUp:
        // Rider starts the ride; the office handles accepted → dispatch in Odoo.
        stateTrailState = 'dispatched';
        odooState = null;
        break;
      case OrderStatus.delivered:
        stateTrailState = 'delivered';
        odooState = backendAlreadyUpdated ? null : 'delivered';
        break;
      case OrderStatus.cancelled:
        stateTrailState = 'cancelled';
        odooState = 'cancelled';
        break;
      default:
        _error = 'Invalid status for update';
        return false;
    }

    try {
      if (odooState != null) {
        final ok = await ApiService.updateOrderState(int.parse(orderId), odooState);
        if (!ok) {
          _error = 'Failed to update order state in backend';
          return false;
        }
      }
      await FirebaseService.updateOrderStateTrail(orderId, stateTrailState, _currentUserId!);
      if (newStatus == OrderStatus.cancelled) {
        await FirebaseService.updateOrderFields(orderId, {'is_cancelled_or_refunded': true});
      }
      return true;
    } catch (e) {
      _error = 'Failed to update order status';
      return false;
    }
  }

  static bool _branchAllowed(Map<String, dynamic> json, List<int>? allowed) {
    if (allowed == null) return true;
    if (allowed.isEmpty) return false;
    final branchMap = json['branch'];
    if (branchMap is! Map) return false;
    final rawId = branchMap['id'];
    final branchId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? -1;
    return allowed.contains(branchId);
  }

  /// Stops listening (logout).
  void reset() {
    _ordersSub?.cancel();
    _ordersSub = null;
    _midnightTimer?.cancel();
    _availableOrders = [];
    _acceptedOrders = [];
    _completedOrders = [];
    _deliveredToday = [];
    _lastSnapshot = const [];
    _hasLoadedOnce = false;
    _currentUserId = null;
    _query = '';
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Order? getOrderById(String orderId) {
    for (final list in [_availableOrders, _acceptedOrders, _completedOrders]) {
      for (final order in list) {
        if (order.id == orderId) return order;
      }
    }
    return null;
  }

  Future<bool> acceptOrderSimple(String orderId) => acceptOrder(orderId);

  @override
  void dispose() {
    _ordersSub?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }
}
