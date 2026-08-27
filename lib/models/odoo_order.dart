
class OdooOrder {
  final int id;
  final String reference;
  final String tossdownSequence;
  final List<dynamic> customerId;
  final String orderType;
  final String orderPlacedAt;
  final List<dynamic> branch;
  final String paymentMode;
  final String state;
  final String tossdownStatus;
  final List<int> lineIds;
  final double totalQty;
  final double total;
  final double discount;
  final double deliveryCharges;
  final double taxAmount;
  final double serviceCharges;
  final double grandTotal;
  final String createDate;
  final String writeDate;
  final List<OdooOrderLine>? lineItems;

  OdooOrder({
    required this.id,
    required this.reference,
    required this.tossdownSequence,
    required this.customerId,
    required this.orderType,
    required this.orderPlacedAt,
    required this.branch,
    required this.paymentMode,
    required this.state,
    required this.tossdownStatus,
    required this.lineIds,
    required this.totalQty,
    required this.total,
    required this.discount,
    required this.deliveryCharges,
    required this.taxAmount,
    required this.serviceCharges,
    required this.grandTotal,
    required this.createDate,
    required this.writeDate,
    this.lineItems,
  });

  factory OdooOrder.fromJson(Map<String, dynamic> json) {
    return OdooOrder(
      id: json['id'] ?? 0,
      reference: json['reference'] ?? '',
      tossdownSequence: json['tossdown_sequence'] ?? '',
      customerId: json['customer_id'] ?? [],
      orderType: json['order_type'] ?? '',
      orderPlacedAt: json['order_placed_at'] ?? '',
      branch: json['branch'] ?? [],
      paymentMode: json['payment_mode'] ?? '',
      state: json['state'] ?? '',
      tossdownStatus: json['tossdown_status'] ?? '',
      lineIds: List<int>.from(json['line_ids'] ?? []),
      totalQty: json['total_qty'] ?? 0,
      total: (json['total'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      deliveryCharges: (json['delivery_charges'] ?? 0).toDouble(),
      taxAmount: (json['tax_amount'] ?? 0).toDouble(),
      serviceCharges: (json['service_charges'] ?? 0).toDouble(),
      grandTotal: (json['grand_total'] ?? 0).toDouble(),
      createDate: json['create_date'] ?? '',
      writeDate: json['write_date'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference': reference,
      'tossdown_sequence': tossdownSequence,
      'customer_id': customerId,
      'order_type': orderType,
      'order_placed_at': orderPlacedAt,
      'branch': branch,
      'payment_mode': paymentMode,
      'state': state,
      'tossdown_status': tossdownStatus,
      'line_ids': lineIds,
      'total_qty': totalQty,
      'total': total,
      'discount': discount,
      'delivery_charges': deliveryCharges,
      'tax_amount': taxAmount,
      'service_charges': serviceCharges,
      'grand_total': grandTotal,
      'create_date': createDate,
      'write_date': writeDate,
    };
  }

  OdooOrder copyWith({
    int? id,
    String? reference,
    String? tossdownSequence,
    List<dynamic>? customerId,
    String? orderType,
    String? orderPlacedAt,
    List<dynamic>? branch,
    String? paymentMode,
    String? state,
    String? tossdownStatus,
    List<int>? lineIds,
    double? totalQty,
    double? total,
    double? discount,
    double? deliveryCharges,
    double? taxAmount,
    double? serviceCharges,
    double? grandTotal,
    String? createDate,
    String? writeDate,
    List<OdooOrderLine>? lineItems,
  }) {
    return OdooOrder(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      tossdownSequence: tossdownSequence ?? this.tossdownSequence,
      customerId: customerId ?? this.customerId,
      orderType: orderType ?? this.orderType,
      orderPlacedAt: orderPlacedAt ?? this.orderPlacedAt,
      branch: branch ?? this.branch,
      paymentMode: paymentMode ?? this.paymentMode,
      state: state ?? this.state,
      tossdownStatus: tossdownStatus ?? this.tossdownStatus,
      lineIds: lineIds ?? this.lineIds,
      totalQty: totalQty ?? this.totalQty,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      deliveryCharges: deliveryCharges ?? this.deliveryCharges,
      taxAmount: taxAmount ?? this.taxAmount,
      serviceCharges: serviceCharges ?? this.serviceCharges,
      grandTotal: grandTotal ?? this.grandTotal,
      createDate: createDate ?? this.createDate,
      writeDate: writeDate ?? this.writeDate,
      lineItems: lineItems ?? this.lineItems,
    );
  }

  // Convert to local Order model
  Map<String, dynamic> toLocalOrder() {
    return {
      'id': id,
      'customerName': customerId.isNotEmpty ? customerId[1].toString() : 'Unknown Customer',
      'customerPhone': '', // Should be fetched from customer API
      'pickupAddress': branch.isNotEmpty ? branch[1].toString() : 'Unknown Address',
      'deliveryAddress': '', // Should be fetched from customer API
      'pickupLatitude': 0.0, // Should be fetched from branch API
      'pickupLongitude': 0.0,
      'deliveryLatitude': 0.0, // Should be fetched from customer API
      'deliveryLongitude': 0.0,
      'amount': grandTotal,
      'currency': 'AED',
      'status': _mapStatus(tossdownStatus),
      'priority': 'medium', // Default to medium is standard for priorities, but removed hardcoded time
      'createdAt': createDate,
      'estimatedDeliveryTime': null, // Don't guess the delivery time
      'notes': 'Order from Odoo: $reference',
      'riderId': null,
      'acceptedAt': null,
      'pickedUpAt': null,
      'deliveredAt': null,
      'items': lineItems
          ?.map((item) => item.itemName.isNotEmpty ? item.itemName[1].toString() : 'Unknown Item')
          .toList()
          ?? [],
    };
  }

  String _mapStatus(String odooStatus) {
    switch (odooStatus.toLowerCase()) {
      case 'confirm':
        return 'pending';
      case 'accepted':
        return 'accepted';
      case 'picked_up':
        return 'pickedUp';
      case 'delivered':
        return 'delivered';
      case 'cancelled':
        return 'cancelled';
      default:
        return 'pending';
    }
  }
}

class OdooOrderLine {
  final int id;
  final List<dynamic> orderId;
  final List<dynamic> itemName;
  final List<dynamic> brand;
  final double price;
  final double qty;
  final double weight;
  final double amount;
  final double total;
  final List<dynamic> createUid;
  final String createDate;
  final List<dynamic> writeUid;
  final String writeDate;

  OdooOrderLine({
    required this.id,
    required this.orderId,
    required this.itemName,
    required this.brand,
    required this.price,
    required this.qty,
    required this.weight,
    required this.amount,
    required this.total,
    required this.createUid,
    required this.createDate,
    required this.writeUid,
    required this.writeDate,
  });

  factory OdooOrderLine.fromJson(Map<String, dynamic> json) {
    return OdooOrderLine(
      id: json['id'] ?? 0,
      orderId: json['order_id'] ?? [],
      itemName: json['item_name'] ?? [],
      brand: json['brand'] ?? [],
      price: (json['price'] ?? 0).toDouble(),
      qty: (json['qty'] ?? 0).toDouble(),
      weight: (json['weight'] ?? 0).toDouble(),
      amount: (json['amount'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      createUid: json['create_uid'] ?? [],
      createDate: json['create_date'] ?? '',
      writeUid: json['write_uid'] ?? [],
      writeDate: json['write_date'] ?? '',
    );
  }
}
