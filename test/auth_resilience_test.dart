import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jsrider/providers/auth_provider.dart';
import 'package:jsrider/providers/order_provider.dart';
import 'package:jsrider/services/api_service.dart';

http.Response _ok(int uid) => http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': null, 'result': {'uid': uid, 'name': 'Rider $uid'}}),
      200,
      headers: {'set-cookie': 'session_id=abc$uid; Path=/; HttpOnly'},
    );

http.Response _odooError(String name, String message) => http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': 200, 'message': 'Odoo Server Error', 'data': {'name': name, 'message': message}},
      }),
      200,
    );

final _wrongPassword = _odooError('odoo.exceptions.AccessDenied', 'Access Denied');
final _tooMany = _odooError(
    'odoo.exceptions.AccessDenied', 'Too many login failures, please wait a bit before trying again.');
final _expired = _odooError('odoo.http.SessionExpiredException', 'Session expired');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.resetSession();
    ApiService.onSessionExpired = null;
  });

  group('ApiService.login tells failures apart', () {
    Future<AuthOutcome> loginWith(FutureOr<http.Response> Function() respond) {
      ApiService.httpClient = MockClient((_) async => respond());
      return ApiService.login('rider@js.com', 'pw');
    }

    test('success stores the session', () async {
      expect(await loginWith(() => _ok(24)), AuthOutcome.success);
      expect(ApiService.sessionId, 'abc24');
      expect(ApiService.userId, '24');
    });
    test('wrong password', () async => expect(await loginWith(() => _wrongPassword), AuthOutcome.wrongCredentials));
    test('Odoo login lock (too many failures)', () async => expect(await loginWith(() => _tooMany), AuthOutcome.tooManyAttempts));
    test('nginx 502 is not a wrong password', () async => expect(await loginWith(() => http.Response('Bad gateway', 502)), AuthOutcome.offline));
    test('no signal is not a wrong password', () async {
      expect(await loginWith(() => throw const SocketException('Network is unreachable')), AuthOutcome.offline);
    });
  });

  group('Expired session is renewed transparently', () {
    test('an action retries once after a silent re-login', () async {
      var calls = 0;
      ApiService.httpClient = MockClient((req) async {
        if (req.url.path == '/web/session/authenticate') return _ok(24);
        calls++;
        return calls == 1
            ? _expired
            : http.Response(jsonEncode({'jsonrpc': '2.0', 'id': null, 'result': true}), 200);
      });
      await ApiService.login('rider@js.com', 'pw');
      var renewals = 0;
      ApiService.onSessionExpired = () async {
        renewals++;
        return await ApiService.login('rider@js.com', 'pw') == AuthOutcome.success;
      };
      expect(await ApiService.updateOrderState(1, 'accepted'), isTrue);
      expect(renewals, 1);
      expect(calls, 2);
    });

    test('no session yet: logs in first, then does the action', () async {
      final paths = <String>[];
      ApiService.httpClient = MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path == '/web/session/authenticate') return _ok(24);
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': null, 'result': true}), 200);
      });
      ApiService.onSessionExpired = () async => await ApiService.login('rider@js.com', 'pw') == AuthOutcome.success;
      expect(await ApiService.updateOrderState(1, 'accepted'), isTrue);
      expect(paths, ['/web/session/authenticate', '/web/dataset/call_kw']);
    });
  });

  group('App start with a saved login', () {
    Future<AuthProvider> start({required FutureOr<http.Response> Function() authResponse, bool cachedProfile = true}) async {
      FlutterSecureStorage.setMockInitialValues({'js_rider_login': 'rider@js.com', 'js_rider_password': 'pw'});
      SharedPreferences.setMockInitialValues({
        if (cachedProfile)
          'cached_rider_v1': jsonEncode({'id': '24', 'name': 'Ikhlaq Ahmad', 'email': 'rider@js.com'}),
      });
      ApiService.httpClient = MockClient((_) async => authResponse());
      final orders = OrderProvider();
      final auth = AuthProvider()..setOrderProvider(orders);
      await auth.initializeAuth();
      return auth;
    }

    test('weak signal on the road: rider stays signed in, app opens instantly', () async {
      final auth = await start(authResponse: () => throw const SocketException('no signal'));
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentRider?.name, 'Ikhlaq Ahmad');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.isAuthenticated, isTrue, reason: 'a network error must not log the rider out');
      expect(auth.isReconnecting, isTrue);
      expect(await FlutterSecureStorage().read(key: 'js_rider_password'), 'pw',
          reason: 'saved login is kept');
    });

    test('server login lock: rider stays signed in', () async {
      final auth = await start(authResponse: () => _tooMany);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isReconnecting, isTrue);
    });

    test('password changed by the office: signed out with a clear message', () async {
      final auth = await start(authResponse: () => _wrongPassword);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.isAuthenticated, isFalse);
      expect(auth.error, contains('Wrong login or password'));
      expect(await FlutterSecureStorage().read(key: 'js_rider_password'), isNull);
    });

    test('no saved profile + no signal: login screen keeps the saved login', () async {
      final auth = await start(authResponse: () => throw const SocketException('no signal'), cachedProfile: false);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.error, contains('internet'));
      expect(await FlutterSecureStorage().read(key: 'js_rider_password'), 'pw');
    });
  });
}
