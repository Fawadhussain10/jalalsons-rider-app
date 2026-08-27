class Shift {
  final String id;
  final DateTime scheduledStartTime;
  final DateTime scheduledEndTime;
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;
  final String status;
  final int totalOrders;
  final double totalEarnings;

  Shift({
    required this.id,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    this.actualStartTime,
    this.actualEndTime,
    required this.status,
    this.totalOrders = 0,
    this.totalEarnings = 0.0,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'] as String,
      scheduledStartTime: DateTime.parse(json['scheduled_start'] ?? json['start_time']),
      scheduledEndTime: DateTime.parse(json['scheduled_end'] ?? json['end_time']),
      actualStartTime: json['actual_start'] != null ? DateTime.parse(json['actual_start']) : (json['start_time'] != null ? DateTime.parse(json['start_time']) : null),
      actualEndTime: json['actual_end'] != null ? DateTime.parse(json['actual_end']) : (json['end_time'] != null ? DateTime.parse(json['end_time']) : null),
      status: json['status'] as String,
      totalOrders: json['total_orders'] as int? ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0.0,
    );
  }
  
  // Compatibility getters
  DateTime get startTime => actualStartTime ?? scheduledStartTime;
  DateTime? get endTime => actualEndTime;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scheduled_start': scheduledStartTime.toIso8601String(),
      'scheduled_end': scheduledEndTime.toIso8601String(),
      'actual_start': actualStartTime?.toIso8601String(),
      'actual_end': actualEndTime?.toIso8601String(),
      'status': status,
      'total_orders': totalOrders,
      'total_earnings': totalEarnings,
    };
  }

  bool get isActive => status == 'active' || (actualStartTime != null && actualEndTime == null);

  Duration get duration {
    final start = actualStartTime ?? scheduledStartTime;
    final end = actualEndTime ?? DateTime.now();
    return end.difference(start);
  }
}
