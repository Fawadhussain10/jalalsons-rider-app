import 'package:flutter_test/flutter_test.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/utils/time_utils.dart';

/// Firestore document in the shape Odoo writes (naive UTC timestamps).
Map<String, dynamic> doc({
  required int id,
  required DateTime placedLocal,
  String payment = 'cod',
  double amount = 1000,
  int branch = 1,
  int? acceptedBy,
  DateTime? acceptedLocal,
  DateTime? dispatchedLocal,
  int? deliveredBy,
  DateTime? deliveredLocal,
  bool live = true,
  String orderType = 'delivery',
  String status = 'draft',
}) {
  String utc(DateTime d) => TimeUtils.toServerQueryString(d);
  return {
    'id': id,
    'reference': 'JS-$id',
    'status': status,
    'live_on_app': live,
    'orderType': orderType,
    'paymentMode': payment,
    'amount': amount,
    'delivery_kms': 3.5,
    'createdAt': utc(placedLocal),
    'branch': {'id': branch, 'name': 'Model Town'},
    'customer': {
      'name': 'Ali Khan $id',
      'phone': '+923001234567',
      'address': {'street': 'House 1, Block C', 'street2': '', 'city': 'Lahore'},
      'location': {'latitude': 31.5, 'longitude': 74.3},
    },
    'items': [
      {'name': 'Barfi', 'qty': 2.0},
    ],
    'stateTrail': {
      'draft': {'at': utc(placedLocal), 'by': 2},
      'accepted': {'at': acceptedLocal == null ? null : utc(acceptedLocal), 'by': acceptedBy},
      'dispatched': {'at': dispatchedLocal == null ? null : utc(dispatchedLocal), 'by': null},
      'delivered': {'at': deliveredLocal == null ? null : utc(deliveredLocal), 'by': deliveredBy},
    },
  };
}

void main() {
  const me = 7;
  final now = DateTime(2026, 9, 25, 1, 30); // 1:30 AM, just after midnight
  final today = DateTime(2026, 9, 25);
  final yesterday2350 = DateTime(2026, 9, 24, 23, 50);

  group('TimeUtils', () {
    test('naive server time is read as UTC, not local', () {
      final t = TimeUtils.parseServerTime('2026-09-25T06:50:00')!;
      expect(t.isUtc, isFalse);
      expect(t.toUtc(), DateTime.utc(2026, 9, 25, 6, 50));
    });

    test('explicit offsets are respected', () {
      expect(TimeUtils.parseServerTime('2026-09-25T06:50:00Z')!.toUtc(), DateTime.utc(2026, 9, 25, 6, 50));
      expect(TimeUtils.parseServerTime('2026-09-25T11:50:00+05:00')!.toUtc(), DateTime.utc(2026, 9, 25, 6, 50));
    });

    test('carry-over window starts at yesterday midnight', () {
      expect(TimeUtils.carryOverStart(now), DateTime(2026, 9, 24));
      expect(TimeUtils.untilNextMidnight(DateTime(2026, 9, 25, 23, 0)), const Duration(hours: 1));
    });

    test('query string round-trips through the parser', () {
      final local = DateTime(2026, 9, 24, 0, 0);
      expect(TimeUtils.parseServerTime(TimeUtils.toServerQueryString(local)), local);
    });
  });

  group('bucketOrders — midnight rule', () {
    test('yesterday 11:50 PM order still undelivered stays visible after midnight', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 1, placedLocal: yesterday2350),
        doc(id: 2, placedLocal: yesterday2350, acceptedBy: me, acceptedLocal: yesterday2350, status: 'accepted'),
      ], riderId: me, now: now);
      expect(b.available.map((o) => o.id), ['1']);
      expect(b.accepted.map((o) => o.id), ['2']);
    });

    test('yesterday order disappears once delivered, today order stays in Completed', () {
      final deliveredAt = today.add(const Duration(minutes: 20));
      final b = OrderProvider.bucketOrders([
        doc(id: 3, placedLocal: yesterday2350, acceptedBy: me, deliveredBy: me,
            acceptedLocal: yesterday2350, deliveredLocal: deliveredAt, status: 'delivered'),
        doc(id: 4, placedLocal: today.add(const Duration(minutes: 5)), acceptedBy: me, deliveredBy: me,
            acceptedLocal: today, deliveredLocal: deliveredAt, status: 'delivered'),
      ], riderId: me, now: now);
      expect(b.completed.map((o) => o.id), ['4']);
      // Both were delivered after midnight, so both count toward today's cash.
      expect(b.deliveredToday.map((o) => o.id).toSet(), {'3', '4'});
    });

    test('orders delivered yesterday are gone today', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 5, placedLocal: DateTime(2026, 9, 24, 18), acceptedBy: me, deliveredBy: me,
            acceptedLocal: DateTime(2026, 9, 24, 18, 5), deliveredLocal: DateTime(2026, 9, 24, 18, 40),
            status: 'delivered'),
      ], riderId: me, now: now);
      expect(b.completed, isEmpty);
      expect(b.deliveredToday, isEmpty);
    });

    test('orders older than yesterday are never shown', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 6, placedLocal: DateTime(2026, 9, 23, 22)),
      ], riderId: me, now: now);
      expect(b.available, isEmpty);
    });
  });

  group('bucketOrders — ownership, branch and type filters', () {
    test('other riders\' accepted/delivered orders are hidden', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 7, placedLocal: today, acceptedBy: 99, acceptedLocal: today, status: 'accepted'),
        doc(id: 8, placedLocal: today, acceptedBy: 99, deliveredBy: 99, acceptedLocal: today,
            deliveredLocal: now, status: 'delivered'),
      ], riderId: me, now: now);
      expect(b.accepted, isEmpty);
      expect(b.completed, isEmpty);
    });

    test('branch restriction, pickup, not-live and cancelled orders are filtered', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 9, placedLocal: today, branch: 2),
        doc(id: 10, placedLocal: today, orderType: 'pick'),
        doc(id: 11, placedLocal: today, live: false),
        doc(id: 12, placedLocal: today, status: 'cancelled'),
        doc(id: 13, placedLocal: today),
      ], riderId: me, allowedBranchIds: [1], now: now);
      expect(b.available.map((o) => o.id), ['13']);
    });

    test('empty allowed-branch list blocks everything', () {
      final b = OrderProvider.bucketOrders([doc(id: 14, placedLocal: today)],
          riderId: me, allowedBranchIds: const [], now: now);
      expect(b.available, isEmpty);
    });
  });

  group('Order model', () {
    test('payment mode, cash flag, times and search text', () {
      final o = Order.fromJson(doc(id: 20, placedLocal: today, payment: 'online'));
      expect(o.isCashOnDelivery, isFalse);
      expect(o.paymentLabel, 'Paid Online');
      expect(o.createdAt, today);
      expect(o.items, ['Barfi (2 x)']);
      expect(o.searchText, contains('js-20'));
      expect(o.searchText, contains('ali khan 20'));
      expect(o.searchText, contains('923001234567'));
      expect(o.deliveryAddress, 'House 1, Block C, Lahore');
    });

    test('only COD orders delivered today count as cash', () {
      final t = today.add(const Duration(minutes: 30));
      final b = OrderProvider.bucketOrders([
        doc(id: 21, placedLocal: today, payment: 'cod', amount: 1500, acceptedBy: me, deliveredBy: me,
            acceptedLocal: today, deliveredLocal: t, status: 'delivered'),
        doc(id: 22, placedLocal: today, payment: 'online', amount: 9000, acceptedBy: me, deliveredBy: me,
            acceptedLocal: today, deliveredLocal: t, status: 'delivered'),
      ], riderId: me, now: now);
      final cash = b.deliveredToday.where((o) => o.isCashOnDelivery).fold(0.0, (s, o) => s + o.amount);
      expect(cash, 1500);
    });
  });

  group('Search', () {
    test('matches order no., name and phone digits in any format', () {
      final p = OrderProvider();
      final orders = [
        Order.fromJson(doc(id: 30, placedLocal: today)),
      ];
      bool matches(String q) {
        p.setSearchQuery(q);
        final query = p.query;
        final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
        return orders.any((o) =>
            o.searchText.contains(query) || (digits.length >= 4 && o.searchText.contains(digits)));
      }

      expect(matches('JS-30'), isTrue);
      expect(matches('ali khan'), isTrue);
      expect(matches('0300 1234567'.substring(1)), isTrue);
      expect(matches('nobody'), isFalse);
    });
  });
}
