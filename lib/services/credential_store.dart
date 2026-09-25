import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Login saved for silent re-login, encrypted by the OS keystore
/// (Android Keystore / iOS Keychain). Never leaves the phone.
class CredentialStore {
  CredentialStore._();

  static const _storage = FlutterSecureStorage();
  static const _loginKey = 'js_rider_login';
  static const _passwordKey = 'js_rider_password';

  static Future<void> save(String login, String password) async {
    try {
      await _storage.write(key: _loginKey, value: login);
      await _storage.write(key: _passwordKey, value: password);
    } catch (e) {
      if (kDebugMode) print('CredentialStore.save failed: $e');
    }
  }

  static Future<({String login, String password})?> read() async {
    try {
      final login = await _storage.read(key: _loginKey);
      final password = await _storage.read(key: _passwordKey);
      if (login == null || login.isEmpty || password == null || password.isEmpty) {
        return null;
      }
      return (login: login, password: password);
    } catch (e) {
      if (kDebugMode) print('CredentialStore.read failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _loginKey);
      await _storage.delete(key: _passwordKey);
    } catch (e) {
      if (kDebugMode) print('CredentialStore.clear failed: $e');
    }
  }
}
