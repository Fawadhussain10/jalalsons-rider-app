import 'package:flutter_test/flutter_test.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/utils/time_utils.dart';
import 'package:jsrider/utils/delivery_rules.dart';

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
  int? attachedRider,
  int? acceptedByUser,
  int? deliveredByUser,
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
    if (attachedRider != null) 'rider': {'riderID': attachedRider, 'riderName': 'Rider $attachedRider'},
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
      'accepted': {'at': acceptedLocal == null ? null : utc(acceptedLocal), 'by': acceptedByUser ?? acceptedBy},
      'dispatched': {'at': dispatchedLocal == null ? null : utc(dispatchedLocal), 'by': null},
      'delivered': {'at': deliveredLocal == null ? null : utc(deliveredLocal), 'by': deliveredByUser ?? deliveredBy},
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

  group('Ongoing order limit (max 2)', () {
    Map<String, dynamic> ongoing(int id) => doc(
        id: id, placedLocal: today, acceptedBy: me, acceptedLocal: today, status: 'accepted');

    test('one ongoing order: can still accept', () {
      final p = OrderProvider()..debugLoadSnapshot([ongoing(40), doc(id: 41, placedLocal: today)], riderId: '$me', now: now);
      expect(p.atOrderLimit, isFalse);
    });

    test('two ongoing orders: third accept is refused without calling the server', () async {
      final p = OrderProvider()
        ..debugLoadSnapshot([ongoing(42), ongoing(43), doc(id: 44, placedLocal: today)], riderId: '$me', now: now);
      expect(p.atOrderLimit, isTrue);
      final ok = await p.acceptOrder('44');
      expect(ok, isFalse);
      expect(p.error, OrderProvider.orderLimitMessage);
    });

    test('delivering one of them frees a slot again', () {
      final p = OrderProvider()
        ..debugLoadSnapshot([
          ongoing(45),
          doc(id: 46, placedLocal: today, acceptedBy: me, deliveredBy: me, acceptedLocal: today,
              deliveredLocal: today.add(const Duration(minutes: 30)), status: 'delivered'),
        ], riderId: '$me', now: now);
      expect(p.atOrderLimit, isFalse);
    });

    test("other riders' orders don't count", () {
      final p = OrderProvider()
        ..debugLoadSnapshot([
          doc(id: 47, placedLocal: today, acceptedBy: 99, acceptedLocal: today, status: 'accepted'),
          doc(id: 48, placedLocal: today, acceptedBy: 99, acceptedLocal: today, status: 'accepted'),
          ongoing(49),
        ], riderId: '$me', now: now);
      expect(p.atOrderLimit, isFalse);
    });
  });

  group('Delivery point', () {
    test("uses the order's own location, not the customer's saved one", () {
      final j = doc(id: 60, placedLocal: today)
        ..['deliveryLocation'] = {'latitude': 31.4900, 'longitude': 74.4400};
      final o = Order.fromJson(j);
      expect(o.deliveryLatitude, 31.4900);
      expect(o.deliveryLongitude, 74.4400);
    });
    test('falls back to the customer location for older documents', () {
      final o = Order.fromJson(doc(id: 61, placedLocal: today));
      expect(o.deliveryLatitude, 31.5);
      expect(o.deliveryLongitude, 74.3);
    });
  });

  group('Steps done by the office in Odoo', () {
    const office = 2;
    final t = today.add(const Duration(minutes: 10));

    test('rider accepted, office marked delivered: stays in Completed and cash', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 70, placedLocal: today, attachedRider: me, acceptedBy: me, acceptedLocal: today,
            dispatchedLocal: t, deliveredByUser: office, deliveredLocal: t, status: 'delivered', amount: 800),
      ], riderId: me, now: now);
      expect(b.completed.map((o) => o.id), ['70']);
      expect(b.deliveredToday.map((o) => o.id), ['70']);
    });

    test('office accepted and delivered for the attached rider: still his', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 71, placedLocal: today, attachedRider: me, acceptedByUser: office, acceptedLocal: today,
            deliveredByUser: office, deliveredLocal: t, status: 'delivered'),
      ], riderId: me, now: now);
      expect(b.completed.map((o) => o.id), ['71']);
    });

    test('office dispatched to a rider without Accept: in his Ongoing, not Available to others', () {
      final docs = [doc(id: 72, placedLocal: today, attachedRider: me, dispatchedLocal: t, status: 'dispatch')];
      final mine = OrderProvider.bucketOrders(docs, riderId: me, now: now);
      expect(mine.accepted.map((o) => o.id), ['72']);
      expect(mine.available, isEmpty);
      final other = OrderProvider.bucketOrders(docs, riderId: 99, now: now);
      expect(other.available, isEmpty);
      expect(other.accepted, isEmpty);
    });

    test('order moved to another rider in Odoo leaves this rider', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 73, placedLocal: today, attachedRider: 99, acceptedBy: me, acceptedLocal: today, status: 'accepted'),
        doc(id: 74, placedLocal: today, attachedRider: 99, acceptedBy: me, acceptedLocal: today,
            deliveredByUser: office, deliveredLocal: t, status: 'delivered'),
      ], riderId: me, now: now);
      expect(b.accepted, isEmpty);
      expect(b.completed, isEmpty);
    });

    test('new order pre-assigned to a rider: only that rider can accept it', () {
      final docs = [doc(id: 75, placedLocal: today, attachedRider: me)];
      expect(OrderProvider.bucketOrders(docs, riderId: me, now: now).available.map((o) => o.id), ['75']);
      expect(OrderProvider.bucketOrders(docs, riderId: 99, now: now).available, isEmpty);
    });

    test('belongsTo: attached rider wins, old documents use who accepted', () {
      expect(Order.fromJson(doc(id: 76, placedLocal: today, attachedRider: me, acceptedByUser: office,
          acceptedLocal: today, status: 'accepted')).belongsTo(me), isTrue);
      expect(Order.fromJson(doc(id: 77, placedLocal: today, acceptedBy: me, acceptedLocal: today,
          status: 'accepted')).belongsTo(me), isTrue);
      expect(Order.fromJson(doc(id: 78, placedLocal: today)).belongsTo(me), isFalse);
    });

    test('office-dispatched order counts toward the 2-order limit', () {
      final p = OrderProvider()
        ..debugLoadSnapshot([
          doc(id: 79, placedLocal: today, attachedRider: me, dispatchedLocal: t, status: 'dispatch'),
          doc(id: 80, placedLocal: today, acceptedBy: me, acceptedLocal: today, status: 'accepted'),
        ], riderId: '$me', now: now);
      expect(p.atOrderLimit, isTrue);
    });
  });

  group('Delivered button (order location)', () {
    bool can(double? d, {double? acc, bool has = true}) =>
        DeliveryRules.canDeliver(orderHasLocation: has, distanceMeters: d, gpsAccuracyMeters: acc);

    test('unlocked within 400 m of the order location', () {
      expect(can(0), isTrue);
      expect(can(399), isTrue);
      expect(can(400), isTrue);
      expect(can(401), isFalse);
    });
    test('weak GPS fix gets up to 50 m benefit, no more', () {
      expect(can(430, acc: 35), isTrue);
      expect(can(449, acc: 300), isTrue);
      expect(can(451, acc: 300), isFalse);
    });
    test('no GPS fix yet: locked', () => expect(can(null), isFalse));
    test('order without a location is not locked', () => expect(can(null, has: false), isTrue));
    test("distance is measured to the order's own pin, not the customer's", () {
      final o = Order.fromJson(doc(id: 90, placedLocal: today)
        ..['deliveryLocation'] = {'latitude': 31.4900, 'longitude': 74.4400});
      expect([o.deliveryLatitude, o.deliveryLongitude], [31.49, 74.44]); // customer.location is 31.5/74.3
    });
  });

  group('Address / Notes from Odoo', () {
    test('shown separately; address uses the customer street, not the notes', () {
      final j = doc(id: 95, placedLocal: today);
      j['addressNotes'] = '  First floor of the building ';
      (j['customer']['address'] as Map)
        ..['street'] = 'First floor of the building\nBranch: Model Town'
        ..['line1'] = 'House 1, Block C';
      final o = Order.fromJson(j);
      expect(o.addressNotes, 'First floor of the building');
      expect(o.deliveryAddress, 'House 1, Block C, Lahore');
    });
    test('order without notes', () {
      final j = doc(id: 96, placedLocal: today)..['addressNotes'] = '';
      (j['customer']['address'] as Map)['line1'] = 'House 1, Block C';
      expect(Order.fromJson(j).addressNotes, isEmpty);
    });
    test('documents from older Odoo keep the old address text', () {
      final o = Order.fromJson(doc(id: 97, placedLocal: today));
      expect(o.addressNotes, isEmpty);
      expect(o.deliveryAddress, 'House 1, Block C, Lahore');
    });
  });

  group('2:00 AM cut-off for yesterday\'s orders nobody accepted', () {
    final at0159 = DateTime(2026, 9, 25, 1, 59);
    final at0200 = DateTime(2026, 9, 25, 2, 0);
    final at1800 = DateTime(2026, 9, 25, 18, 0);
    List<Map<String, dynamic>> docs() => [
          doc(id: 101, placedLocal: yesterday2350), // yesterday, nobody accepted
          doc(id: 102, placedLocal: DateTime(2026, 9, 24, 15)), // yesterday afternoon, nobody accepted
          doc(id: 103, placedLocal: today.add(const Duration(minutes: 30))), // today 12:30 AM
          doc(id: 104, placedLocal: yesterday2350, acceptedBy: me, acceptedLocal: yesterday2350,
              status: 'accepted'), // yesterday, mine, ongoing
          doc(id: 105, placedLocal: yesterday2350, attachedRider: me,
              dispatchedLocal: today.add(const Duration(minutes: 5)), status: 'dispatch'), // office gave it to me
        ];

    test('1:59 AM: yesterday\'s not-accepted orders still offered', () {
      final b = OrderProvider.bucketOrders(docs(), riderId: me, now: at0159);
      expect(b.available.map((o) => o.id).toSet(), {'101', '102', '103'});
    });

    test('2:00 AM: they hide, today\'s order stays', () {
      final b = OrderProvider.bucketOrders(docs(), riderId: me, now: at0200);
      expect(b.available.map((o) => o.id), ['103']);
    });

    test('yesterday\'s ongoing orders stay until delivered, all day', () {
      final b = OrderProvider.bucketOrders(docs(), riderId: me, now: at1800);
      expect(b.accepted.map((o) => o.id).toSet(), {'104', '105'});
      expect(b.available.map((o) => o.id), ['103']);
    });

    test('delivered today: leaves Ongoing, not in Completed, counted in today\'s cash', () {
      final b = OrderProvider.bucketOrders([
        doc(id: 106, placedLocal: yesterday2350, acceptedBy: me, acceptedLocal: yesterday2350,
            deliveredBy: me, deliveredLocal: DateTime(2026, 9, 25, 10), status: 'delivered', amount: 1200),
      ], riderId: me, now: at1800);
      expect(b.accepted, isEmpty);
      expect(b.completed, isEmpty);
      expect(b.deliveredToday.map((o) => o.id), ['106']);
    });

    test('timer: time left to the cut-off', () {
      expect(TimeUtils.untilAvailableCarryOverEnd(DateTime(2026, 9, 25, 1, 0)), const Duration(hours: 1));
      expect(TimeUtils.untilAvailableCarryOverEnd(at0200), isNull);
      expect(TimeUtils.untilAvailableCarryOverEnd(DateTime(2026, 9, 24, 23, 0)), isNull); // next one comes after midnight resubscribe
    });
  });
}
