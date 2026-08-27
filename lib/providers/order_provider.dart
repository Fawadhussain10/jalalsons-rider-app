import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../models/odoo_order.dart';

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
  final bool isPaid;
  final bool isCancelledOrRefunded;

  Order({
    required this.id,
    required this.reference,
    required this.customerName,
    required this.customerPhone,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.amount,
    this.currency = 'AED',
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
    this.isPaid = false,
    this.isCancelledOrRefunded = false,
  });


  factory Order.fromJson(Map<String, dynamic> json) {
    // Handle new Firestore JSON structure
    final customer = json['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] ?? '';
    final customerPhone = customer?['phone'] ?? '';
    final deliveryAddress = customer?['address'] != null 
        ? '${customer!['address']['street'] ?? ''} ${customer['address']['street2'] ?? ''} ${customer['address']['city'] ?? ''}'.trim()
        : '';
    
    return Order(
      id: json['id']?.toString() ?? '',
      reference: json['reference'] ?? '',
      customerName: customerName,
      customerPhone: customerPhone,
      pickupAddress: json['pickupAddress'] ?? '',
      deliveryAddress: deliveryAddress,
      pickupLatitude: json['pickupLatitude']?.toDouble() ?? 0.0,
      pickupLongitude: json['pickupLongitude']?.toDouble() ?? 0.0,
      deliveryLatitude: customer?['location']?['latitude']?.toDouble() ?? 0.0,
      deliveryLongitude: customer?['location']?['longitude']?.toDouble() ?? 0.0,
      amount: json['amount']?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'AED',
      status: OrderStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => OrderStatus.pending,
      ),
      priority: OrderPriority.values.firstWhere(
        (e) => e.toString().split('.').last == json['priority'],
        orElse: () => OrderPriority.medium,
      ),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      paymentMethod: json['paymentMethod'] ?? 'cash',
      isPaid: json['isPaid'] ?? false,
      isCancelledOrRefunded: json['is_cancelled_or_refunded'] ?? false,
      estimatedDeliveryTime: json['estimatedDeliveryTime'] != null
          ? DateTime.parse(json['estimatedDeliveryTime'])
          : null,
      notes: json['notes'],
      riderId: json['riderId']?.toString(),
      acceptedAt: json['acceptedAt'] != null
          ? DateTime.parse(json['acceptedAt'])
          : null,
      pickedUpAt: json['pickedUpAt'] != null
          ? DateTime.parse(json['pickedUpAt'])
          : null,
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'])
          : null,
      items: _extractItems(json),
      stateTrail: json['stateTrail'] as Map<String, dynamic>?,
    );
  }

  // Extract items from the new JSON structure
  static List<String> _extractItems(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>?;
    if (items == null) return [];
    
    return items.map((item) {
      if (item is Map<String, dynamic>) {
        final name = item['name']?.toString() ?? '';
        final qty = item['qty']?.toString() ?? '0';
        return '$name ($qty x)';
      }
      return item.toString();
    }).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference': reference,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'pickupAddress': pickupAddress,
      'deliveryAddress': deliveryAddress,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'deliveryLatitude': deliveryLatitude,
      'deliveryLongitude': deliveryLongitude,
      'amount': amount,
      'currency': currency,
      'status': status.toString().split('.').last,
      'priority': priority.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'estimatedDeliveryTime': estimatedDeliveryTime?.toIso8601String(),
      'notes': notes,
      'riderId': riderId,
      'acceptedAt': acceptedAt?.toIso8601String(),
      'pickedUpAt': pickedUpAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      // Note: items are handled separately in OrderDao
      'paymentMethod': paymentMethod,
      'isPaid': isPaid,
      'is_cancelled_or_refunded': isCancelledOrRefunded,
    };
  }

  Order copyWith({
    String? id,
    String? reference,
    String? customerName,
    String? customerPhone,
    String? pickupAddress,
    String? deliveryAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    double? deliveryLatitude,
    double? deliveryLongitude,
    double? amount,
    String? currency,
    OrderStatus? status,
    OrderPriority? priority,
    DateTime? createdAt,
    DateTime? estimatedDeliveryTime,
    String? notes,
    String? riderId,
    DateTime? acceptedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    List<String>? items,
    Map<String, dynamic>? stateTrail,
    String? paymentMethod,
    bool? isPaid,
    bool? isCancelledOrRefunded,
  }) {
    return Order(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      deliveryLatitude: deliveryLatitude ?? this.deliveryLatitude,
      deliveryLongitude: deliveryLongitude ?? this.deliveryLongitude,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      estimatedDeliveryTime: estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      notes: notes ?? this.notes,
      riderId: riderId ?? this.riderId,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      items: items ?? this.items,
      stateTrail: stateTrail ?? this.stateTrail,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaid: isPaid ?? this.isPaid,
      isCancelledOrRefunded: isCancelledOrRefunded ?? this.isCancelledOrRefunded,
    );
  }
}

class OrderProvider extends ChangeNotifier {
  List<Order> _availableOrders = [];
  List<Order> _acceptedOrders = [];
  List<Order> _completedOrders = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;
  // Branch IDs this rider is allowed to see orders for.
  // null  = field absent on rider doc → no restriction.
  // []    = field present but empty  → block ALL orders.
  // [..] = filter to these branch IDs.
  List<int>? _allowedBranchIds;

  // Getters
  List<Order> get availableOrders => _availableOrders;
  List<Order> get acceptedOrders => _acceptedOrders;
  List<Order> get completedOrders => _completedOrders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get Cash on Delivery (COD) orders
  List<Order> get codOrders {
    return _completedOrders.where((order) => 
      order.paymentMethod.toLowerCase() == 'cash' && !order.isPaid
    ).toList();
  }

  // Get Total Cash to Collect
  double get totalCashToCollect {
    return codOrders.fold(0.0, (sum, order) => sum + order.amount);
  }

  // Get current active order
  Order? get currentOrder {
    final activeOrders = _acceptedOrders.where(
      (order) => order.status == OrderStatus.accepted || 
                  order.status == OrderStatus.pickedUp
    ).toList();
    return activeOrders.isNotEmpty ? activeOrders.first : null;
  }

  // Set current user ID for filtering
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // Initialize orders with efficient queries
  // Future<void> initializeOrders() async {
  //   _setLoading(true);
  //   try {
  //     if (_currentUserId == null) {
  //       _error = 'User not authenticated';
  //       return;
  //     }
  //
  //     // One-time sync from API into Firestore (temporary)
  //     // await _syncOrdersFromAPIToFirestore();
  //
  //     // Listen to draft orders (upcoming tab)
  //     FirebaseService.streamDraftOrders().listen((orders) {
  //       _availableOrders.clear();
  //       for (final json in orders) {
  //         // Client-side filter: only show orders that are draft and not accepted
  //         final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
  //         if (stateTrail != null) {
  //           final draftState = stateTrail['draft'];
  //           final acceptedState = stateTrail['accepted'];
  //
  //           // Only show if draft exists and accepted does not exist
  //           if (draftState != null && draftState['at'] != null &&
  //               (acceptedState == null || acceptedState['at'] == null)) {
  //             final order = Order.fromJson(json);
  //             _availableOrders.add(order);
  //           }
  //         }
  //       }
  //       notifyListeners();
  //     });
  //
  //     // Listen to accepted orders by current user (ongoing tab)
  //     FirebaseService.streamAcceptedOrdersByUser(_currentUserId!).listen((orders) {
  //       _acceptedOrders.clear();
  //       for (final json in orders) {
  //         // Client-side filter: only show orders that are accepted but not delivered
  //         final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
  //         if (stateTrail != null) {
  //           final acceptedState = stateTrail['accepted'];
  //           final deliveredState = stateTrail['delivered'];
  //
  //           // Only show if accepted exists and delivered does not exist
  //           if (acceptedState != null && acceptedState['at'] != null &&
  //               (deliveredState == null || deliveredState['at'] == null)) {
  //             final order = Order.fromJson(json);
  //             _acceptedOrders.add(order);
  //           }
  //         }
  //       }
  //       notifyListeners();
  //     });
  //
  //     // Listen to delivered orders by current user (completed tab)
  //     FirebaseService.streamDeliveredOrdersByUser(_currentUserId!).listen((orders) {
  //       _completedOrders.clear();
  //       for (final json in orders) {
  //         // Client-side filter: only show orders that are delivered
  //         final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
  //         if (stateTrail != null) {
  //           final deliveredState = stateTrail['delivered'];
  //
  //           // Only show if delivered exists
  //           if (deliveredState != null && deliveredState['at'] != null) {
  //             final order = Order.fromJson(json);
  //             _completedOrders.add(order);
  //           }
  //         }
  //       }
  //       notifyListeners();
  //     });
  //
  //     notifyListeners();
  //   } catch (e) {
  //     _error = 'Failed to load orders';
  //   } finally {
  //     _setLoading(false);
  //   }
  // }

// Initialize orders with efficient queries and proper sorting
// Initialize orders with efficient queries and proper sorting
  Future<void> initializeOrders() async {
    _setLoading(true);
    try {
      if (_currentUserId == null) {
        _error = 'User not authenticated';
        return;
      }

      // Fetch this rider's allowed branch IDs before setting up streams.
      // If the field is absent the list will be empty → no branch filter applied.
      _allowedBranchIds =
          await FirebaseService.getRiderAllowedBranchIds(_currentUserId!);
      if (kDebugMode) {
        if (_allowedBranchIds == null) {
          print('Rider $_currentUserId allowedBranchIds: null (no restriction)');
        } else if (_allowedBranchIds!.isEmpty) {
          print('Rider $_currentUserId allowedBranchIds: [] (NO branch access — all orders blocked)');
        } else {
          print('Rider $_currentUserId allowedBranchIds: $_allowedBranchIds');
        }
      }

      // Listen to draft orders (upcoming tab) - sorted by createdAt
      FirebaseService.streamDraftOrders().listen((orders) {
        _availableOrders.clear();
        for (final json in orders) {
          // Only show orders that are live on app
          if (json['live_on_app'] != true) {
            continue;
          }
          // Filter by allowed branch IDs
          if (!_isBranchAllowed(json)) {
            continue;
          }
          // Hide pick orders from riders
          final orderType = (json['orderType'] ?? '').toString().toLowerCase();
          if (orderType == 'pick') {
            continue;
          }
          // Filter out cancelled or refunded orders
          if (json['is_cancelled_or_refunded'] == true) {
            continue;
          }

          final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
          if (stateTrail != null) {
            final draftState = stateTrail['draft'] as Map<String, dynamic>?;
            final acceptedState = stateTrail['accepted'] as Map<String, dynamic>?;

            if (draftState != null && draftState['at'] != null &&
                (acceptedState == null || acceptedState['at'] == null)) {
              final order = Order.fromJson(json);
              _availableOrders.add(order);
            }
          }
        }

        // Additional client-side sorting by createdAt (descending - newest first)
        _availableOrders.sort((a, b) {
          final aTime = a.createdAt.millisecondsSinceEpoch;
          final bTime = b.createdAt.millisecondsSinceEpoch;
          return bTime.compareTo(aTime); // Descending order
        });

        notifyListeners();
      });

      // Listen to accepted orders by current user (ongoing tab) - sorted by accepted.at
      FirebaseService.streamAcceptedOrdersByUser(_currentUserId!).listen((orders) {
        _acceptedOrders.clear();
        for (final json in orders) {
          // Only show orders that are live on app
          if (json['live_on_app'] != true) {
            continue;
          }
          // Filter by allowed branch IDs
          if (!_isBranchAllowed(json)) {
            continue;
          }
          // Hide pick orders from riders
          final orderType = (json['orderType'] ?? '').toString().toLowerCase();
          if (orderType == 'pick') {
            continue;
          }
          // Filter out cancelled or refunded orders
          if (json['is_cancelled_or_refunded'] == true) {
            continue;
          }

          final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
          if (stateTrail != null) {
            final acceptedState = stateTrail['accepted'] as Map<String, dynamic>?;
            final deliveredState = stateTrail['delivered'] as Map<String, dynamic>?;

            if (acceptedState != null && acceptedState['at'] != null &&
                (deliveredState == null || deliveredState['at'] == null)) {
              final order = Order.fromJson(json);
              _acceptedOrders.add(order);
            }
          }
        }

        // Additional client-side sorting by accepted.at (descending - newest first)
        _acceptedOrders.sort((a, b) {
          final aStateTrail = a.stateTrail;
          final bStateTrail = b.stateTrail;

          if (aStateTrail == null || bStateTrail == null) return 0;

          final aAccepted = aStateTrail['accepted'] as Map<String, dynamic>?;
          final bAccepted = bStateTrail['accepted'] as Map<String, dynamic>?;

          if (aAccepted == null || bAccepted == null) return 0;

          final aTimeStr = aAccepted['at'] as String?;
          final bTimeStr = bAccepted['at'] as String?;

          if (aTimeStr == null || bTimeStr == null) return 0;

          final aTime = DateTime.parse(aTimeStr).millisecondsSinceEpoch;
          final bTime = DateTime.parse(bTimeStr).millisecondsSinceEpoch;
          return bTime.compareTo(aTime); // Descending order
        });

        notifyListeners();
      });

      // Listen to delivered orders by current user (completed tab) - sorted by delivered.at
      FirebaseService.streamDeliveredOrdersByUser(_currentUserId!).listen((orders) {
        _completedOrders.clear();
        for (final json in orders) {
          // Only show orders that are live on app
          if (json['live_on_app'] != true) {
            continue;
          }
          // Filter by allowed branch IDs
          if (!_isBranchAllowed(json)) {
            continue;
          }
          // Hide pick orders from riders
          final orderType = (json['orderType'] ?? '').toString().toLowerCase();
          if (orderType == 'pick') {
            continue;
          }
          // Filter out cancelled or refunded orders
          if (json['is_cancelled_or_refunded'] == true) {
            continue;
          }

          final stateTrail = json['stateTrail'] as Map<String, dynamic>?;
          if (stateTrail != null) {
            final deliveredState = stateTrail['delivered'] as Map<String, dynamic>?;

            if (deliveredState != null && deliveredState['at'] != null) {
              final order = Order.fromJson(json);
              _completedOrders.add(order);
            }
          }
        }

        // Additional client-side sorting by delivered.at (descending - newest first)
        _completedOrders.sort((a, b) {
          final aStateTrail = a.stateTrail;
          final bStateTrail = b.stateTrail;

          if (aStateTrail == null || bStateTrail == null) return 0;

          final aDelivered = aStateTrail['delivered'] as Map<String, dynamic>?;
          final bDelivered = bStateTrail['delivered'] as Map<String, dynamic>?;

          if (aDelivered == null || bDelivered == null) return 0;

          final aTimeStr = aDelivered['at'] as String?;
          final bTimeStr = bDelivered['at'] as String?;

          if (aTimeStr == null || bTimeStr == null) return 0;

          final aTime = DateTime.parse(aTimeStr).millisecondsSinceEpoch;
          final bTime = DateTime.parse(bTimeStr).millisecondsSinceEpoch;
          return bTime.compareTo(aTime); // Descending order
        });

        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load orders: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Fetch from Odoo API and upsert into Firestore as a full order JSON
  Future<void> _syncOrdersFromAPIToFirestore() async {
    try {
      final apiOrders = await ApiService.getAvailableOrders();
      
      for (final orderData in apiOrders) {
        final odooOrder = OdooOrder.fromJson(orderData);
        
        // Get order line items
        final lineItems = await ApiService.getOrderLineItems(odooOrder.lineIds);
        final orderWithItems = odooOrder.copyWith(
          lineItems: lineItems.map((item) => OdooOrderLine.fromJson(item)).toList(),
        );
        
        // Build full, single JSON document with nested customer and line items and state trail
        final customerId = odooOrder.customerId.isNotEmpty ? (odooOrder.customerId.first as int? ?? 0) : 0;
        Map<String, dynamic>? customer;
        if (customerId > 0) {
          customer = await ApiService.getPartnerById(customerId);
        }

        final orderJson = {
          'id': odooOrder.id,
          'reference': odooOrder.reference,
          'tossdownSequence': odooOrder.tossdownSequence,
          'status': OrderStatus.pending.toString().split('.').last, // initial map from Confirm→pending already handled downstream
          'createdAt': odooOrder.createDate,
          'writeDate': odooOrder.writeDate,
          'orderType': odooOrder.orderType,
          'paymentMode': odooOrder.paymentMode,
          'amount': odooOrder.grandTotal,
          'currency': 'AED',
          'branch': {
            'id': odooOrder.branch.isNotEmpty ? (odooOrder.branch.first as int? ?? 0) : 0,
            'name': odooOrder.branch.isNotEmpty ? odooOrder.branch[1].toString() : '',
          },
          'customer': customer != null ? {
            'id': customer['id'],
            'name': customer['name'] ?? '',
            'email': customer['email'] ?? '',
            'phone': customer['phone'] ?? customer['mobile'] ?? '',
            'address': {
              'street': customer['street'] ?? '',
              'street2': customer['street2'] ?? '',
              'city': customer['city'] ?? '',
              'zip': customer['zip'] ?? '',
            },
            'location': {
              'latitude': customer['partner_latitude']?.toDouble() ?? 0.0,
              'longitude': customer['partner_longitude']?.toDouble() ?? 0.0,
            },
          } : {
            'id': customerId,
            'name': odooOrder.customerId.isNotEmpty ? odooOrder.customerId[1].toString() : '',
            'email': '',
            'phone': '',
            'address': {
              'street': '',
              'street2': '',
              'city': '',
              'zip': '',
            },
            'location': {
              'latitude': 0.0,
              'longitude': 0.0,
            },
          },
          'items': orderWithItems.lineItems?.map((li) => {
            'id': li.id,
            'name': li.itemName.isNotEmpty ? li.itemName[1].toString() : '',
            'brand': li.brand.isNotEmpty ? li.brand[1].toString() : '',
            'qty': li.qty,
            'price': li.price,
            'total': li.total,
          }).toList() ?? [],
          // State trail sub-jsons: draft/accepted/dispatched/delivered
          'stateTrail': {
            'draft': {
              'at': odooOrder.createDate,
              'by': null,
            },
            'accepted': null,
            'dispatched': null,
            'delivered': null,
          },
          'is_cancelled_or_refunded': false,
        };

        await FirebaseService.upsertOrder(orderJson);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing orders to Firestore: $e');
      }
    }
  }


  // Accept order
  Future<bool> acceptOrder(String orderId, String riderId) async {
    try {
      if (_currentUserId == null) {
        _error = 'User not authenticated';
          return false;
      }

      // Update state in Odoo backend first
      final apiSuccess = await ApiService.updateOrderState(int.parse(orderId), 'accepted');
      
      if (apiSuccess) {
        // Update state trail in Firestore
        await FirebaseService.updateOrderStateTrail(orderId, 'accepted', _currentUserId!);
        
        // The real-time listener will automatically update the UI
        return true;
      } else {
        _error = 'Failed to update order state in backend';
        return false;
      }
    } catch (e) {
      _error = 'Failed to accept order';
      return false;
    }
  }

  // Update delivery_kms in Odoo once (first time only), and mirror to Firestore
  Future<bool> updateDeliveryKmsOnce(String orderId, double kms, {double? estimatedSeconds}) async {
    try {
      // Guard: check if already updated in Firestore
      final existing = await FirebaseService.getOrderById(orderId);
      if (existing != null) {
        final already = existing['delivery_kms'];
        if (already != null) {
          return true; // already updated
        }
      }

      // Update in Odoo (kms only)
      final apiOk = await ApiService.updateOrderFields(int.parse(orderId), {
        'delivery_kms': kms,
      });
      if (!apiOk) return false;

      // Mirror to Firestore and set guard
      // If we have an estimate from the route, use it to set the deadline
      final Map<String, dynamic> fieldsToUpdate = {
        'delivery_kms': kms,
        'delivery_kms_updated_at': DateTime.now().toIso8601String(),
      };

      if (estimatedSeconds != null && estimatedSeconds > 0) {
        final estimate = DateTime.now().add(Duration(seconds: estimatedSeconds.round()));
        fieldsToUpdate['estimatedDeliveryTime'] = estimate.toIso8601String();
        fieldsToUpdate['route_duration_seconds'] = estimatedSeconds;
      }

      await FirebaseService.updateOrderFields(orderId, fieldsToUpdate);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Update order status
  Future<bool> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    try {
      if (_currentUserId == null) {
        _error = 'User not authenticated';
          return false;
      }

      // Map OrderStatus to state trail state and Odoo state
      String stateTrailState;
      String? odooState;
      
      switch (newStatus) {
        case OrderStatus.pickedUp:
          // Rider picks up order - this should only update Firestore, not Odoo
          // Manager handles accepted → dispatch in Odoo
          stateTrailState = 'dispatched';
          odooState = null; // No Odoo update for picked up
          break;
        case OrderStatus.delivered:
          // Rider delivers order - update Odoo from dispatch → delivered
          stateTrailState = 'delivered';
          odooState = 'delivered';
          break;
        case OrderStatus.cancelled:
          // Rider cancels order - update Odoo
          stateTrailState = 'cancelled';
          odooState = 'cancelled';
          break;
        default:
          _error = 'Invalid status for update';
          return false;
      }

      // Update state in Odoo backend first (if applicable)
      bool apiSuccess = true;
      if (odooState != null) {
        apiSuccess = await ApiService.updateOrderState(int.parse(orderId), odooState);
      }
      
      if (apiSuccess) {
        // Update state trail in Firestore
        await FirebaseService.updateOrderStateTrail(orderId, stateTrailState, _currentUserId!);

        // If cancelled, update the flag
        if (newStatus == OrderStatus.cancelled) {
          await FirebaseService.updateOrderFields(orderId, {
            'is_cancelled_or_refunded': true,
          });
        }

        // If order was delivered, update rider statistics
        if (newStatus == OrderStatus.delivered) {
          // Trigger statistics refresh in AuthProvider
          // This will be handled by the UI layer
        }

        // The real-time listener will automatically update the UI
        return true;
      } else {
        _error = 'Failed to update order state in backend';
        return false;
      }
    } catch (e) {
      _error = 'Failed to update order status';
      return false;
    }
  }



  // Returns true if the order's branch is in the rider's allowed list.
  // null  → field absent (no restriction)  → allow all orders.
  // []    → field present but empty        → block all orders.
  // [..] → filter to those IDs.
  bool _isBranchAllowed(Map<String, dynamic> json) {
    // null means field doesn't exist on rider doc – no restriction
    if (_allowedBranchIds == null) return true;
    // Empty list means the rider has no branch access – block everything
    if (_allowedBranchIds!.isEmpty) return false;
    final branchMap = json['branch'] as Map<String, dynamic>?;
    if (branchMap == null) return false; // order has no branch info → block
    final rawId = branchMap['id'];
    if (rawId == null) return false;
    final branchId =
        (rawId is int) ? rawId : int.tryParse(rawId.toString()) ?? -1;
    return _allowedBranchIds!.contains(branchId);
  }

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Get order by ID
  Order? getOrderById(String orderId) {
    final allOrders = [..._availableOrders, ..._acceptedOrders, ..._completedOrders];
    try {
      return allOrders.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  // Accept order (simplified version for compatibility)
  Future<bool> acceptOrderSimple(String orderId) async {
    return acceptOrder(orderId, 'current_rider_id');
  }
} 