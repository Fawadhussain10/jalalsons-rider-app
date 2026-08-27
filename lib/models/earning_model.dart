class Earning {
  final DateTime date;
  final double amount;
  final double bonuses;
  final int ordersCount;
  final String currency;

  Earning({
    required this.date,
    required this.amount,
    this.bonuses = 0.0,
    required this.ordersCount,
    this.currency = 'Rs',
  });

  factory Earning.fromJson(Map<String, dynamic> json) {
    return Earning(
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toDouble(),
      bonuses: (json['bonuses'] as num?)?.toDouble() ?? 0.0,
      ordersCount: json['orders_count'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'Rs',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'amount': amount,
      'bonuses': bonuses,
      'orders_count': ordersCount,
      'currency': currency,
    };
  }
}
