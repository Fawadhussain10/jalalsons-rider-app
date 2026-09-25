// Renders the order cards to test/preview/cards.png for a visual check:
//   flutter test test/preview/cards_preview_test.dart --update-goldens
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/screens/orders_screen.dart';
import 'package:jsrider/utils/app_colors.dart';
import 'package:jsrider/utils/app_theme.dart';

Future<void> _font(String family, List<String> files) async {
  final dir = '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await loader.load();
}

Order _order(int id, String name, {required String status, bool dispatched = false, bool cod = true}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return Order.fromJson({
    'id': id, 'reference': '$id', 'status': status, 'live_on_app': true,
    'paymentMode': cod ? 'cod' : 'online', 'amount': cod ? 2448 : 4807, 'delivery_kms': 20.0,
    'createdAt': now, 'branch': {'id': 1, 'name': 'Jalal Sons - DHA Phase - 5'},
    'customer': {'name': name, 'phone': '+923001234567',
      'address': {'street': 'Branch: Jalal Sons - DHA Phase - 5', 'street2': '', 'city': ''},
      'location': {'latitude': 31.5, 'longitude': 74.3}},
    'stateTrail': {'draft': {'at': now, 'by': 2},
      'accepted': {'at': status == 'draft' ? null : now, 'by': status == 'draft' ? null : 7},
      'dispatched': {'at': dispatched ? now : null, 'by': null}, 'delivered': {'at': null, 'by': null}},
  });
}

void main() {
  setUpAll(() async {
    await _font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  testWidgets('preview', (tester) async {
    tester.view.physicalSize = const Size(351 * 2, 1180 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => OrderProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
          filledButtonTheme: FilledButtonThemeData(
            style: AppTheme.lightTheme.filledButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
        home: Scaffold(
          backgroundColor: AppColors.canvas,
          body: ListView(padding: const EdgeInsets.all(16), children: [
            OrderCard(order: _order(31824386, 'afaf Tayyab', status: 'dispatch', dispatched: true), mode: 'ongoing'),
            const SizedBox(height: 14),
            OrderCard(order: _order(31825532, 'Kanwal Khurram', status: 'accepted', cod: false), mode: 'ongoing'),
            const SizedBox(height: 14),
            OrderCard(order: _order(31826001, 'Ali Raza', status: 'draft'), mode: 'upcoming'),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('cards.png'));
  });
}
