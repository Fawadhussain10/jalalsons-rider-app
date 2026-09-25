import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/screens/orders_screen.dart';
import 'package:jsrider/utils/app_theme.dart';

Order _order({required bool dispatched, bool cod = true, double kms = 20.0}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return Order.fromJson({
    'id': 31824386,
    'reference': '31824386',
    'status': dispatched ? 'dispatch' : 'accepted',
    'live_on_app': true,
    'paymentMode': cod ? 'cod' : 'online',
    'amount': 124448,
    'delivery_kms': kms,
    'createdAt': now,
    'branch': {'id': 1, 'name': 'Jalal Sons - DHA Phase - 5'},
    'customer': {
      'name': 'afaf Tayyab with a rather long customer name',
      'phone': '+923001234567',
      'address': {'street': 'Branch: Jalal Sons - DHA Phase - 5', 'street2': '', 'city': ''},
      'location': {'latitude': 31.5, 'longitude': 74.3},
    },
    'stateTrail': {
      'draft': {'at': now, 'by': 2},
      'accepted': {'at': now, 'by': 7},
      'dispatched': {'at': dispatched ? now : null, 'by': null},
      'delivered': {'at': null, 'by': null},
    },
  });
}

Future<void> _loadRoboto() async {
  // Measure with the real Android font, not the square test font.
  final dir = '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    final f = File('$dir/Roboto-$w.ttf');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);
  // Your phone: ~351 logical px wide. Also try a small 320 px phone and large text.
  for (final width in [320.0, 351.0, 412.0]) {
    for (final textScale in [1.0, 1.3]) {
      for (final mode in ['upcoming', 'ongoing', 'completed']) {
        for (final dispatched in [true, false]) {
          testWidgets('card fits: ${width}px, text x$textScale, $mode, dispatched=$dispatched',
              (tester) async {
            tester.view.physicalSize = Size(width * 3, 2400);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(ChangeNotifierProvider(
              create: (_) => OrderProvider(),
              child: MaterialApp(
                theme: AppTheme.lightTheme.copyWith(
                  textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
                ),
                home: DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'Roboto'),
                  child: MediaQuery(
                  data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [OrderCard(order: _order(dispatched: dispatched), mode: mode)],
                    ),
                  ),
                ),
                ),
              ),
            ));
            await tester.pump();
            // A RenderFlex overflow is reported as an exception and fails the test.
            expect(tester.takeException(), isNull);
            if (mode == 'ongoing' && dispatched) {
              final button = tester.getRect(find.text('Start Ride'));
              expect(button.right, lessThanOrEqualTo(width - 16));
            }
          });
        }
      }
    }
  }
}
