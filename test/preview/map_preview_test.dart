// Renders the Start Ride screen (everything drawn over the map) to
// test/preview/map_*.png with a fake GPS fix 1.2 km from the customer:
//   flutter test test/preview/map_preview_test.dart --update-goldens
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:jsrider/providers/auth_provider.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/screens/map_screen.dart';
import 'package:jsrider/utils/app_theme.dart';

class _FakeGeo extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _FakeGeo(this.pos);
  final Position pos;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.always;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => pos;
  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => pos;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => Stream.value(pos);
}

Future<void> _font(String family, List<String> files) async {
  final dir = '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  for (final cod in [true, false]) {
    testWidgets('map screen preview cod=$cod', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia; // map view renders as a placeholder
      GeolocatorPlatform.instance = _FakeGeo(Position(
        latitude: 31.5100, longitude: 74.3587, timestamp: DateTime.now(), accuracy: 5, altitude: 0,
        altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0));
      tester.view.physicalSize = const Size(351 * 2, 760 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final now = DateTime.now().toUtc().toIso8601String();
      final order = Order.fromJson({
        'id': 31824386, 'reference': '31824386', 'status': 'dispatch', 'live_on_app': true,
        'paymentMode': cod ? 'cod' : 'online', 'amount': 2448, 'createdAt': now,
        'branch': {'id': 1, 'name': 'DHA Phase 5'},
        'customer': {'name': 'afaf Tayyab', 'phone': '+923001234567',
          'address': {'street': 'House 12, Street 4, DHA Phase 5', 'street2': '', 'city': 'Lahore'},
          'location': {'latitude': 31.5204, 'longitude': 74.3587}},
        'stateTrail': {'draft': {'at': now}, 'accepted': {'at': now, 'by': 7}, 'dispatched': {'at': now}},
      });

      final button = TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700, fontSize: 15);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => OrderProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
            filledButtonTheme: FilledButtonThemeData(
              style: AppTheme.lightTheme.filledButtonTheme.style!.copyWith(textStyle: WidgetStatePropertyAll(button)),
            ),
          ),
          home: DefaultTextStyle(style: const TextStyle(fontFamily: 'Roboto'), child: MapScreen(order: order)),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(find.byType(MapScreen), matchesGoldenFile('map_cod_$cod.png'));
      if (!cod) {
        // Start navigation: the dark turn banner replaces the destination chip.
        await tester.tap(find.text('Navigate'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await expectLater(find.byType(MapScreen), matchesGoldenFile('map_navigating.png'));
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
