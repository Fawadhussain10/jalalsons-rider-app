import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class ErrorLogger {
  static const String _tag = 'JS_RIDER';
  
  // Log info messages
  static void info(String message, {String? tag}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag ?? _tag,
        level: 800, // INFO level
      );
    }
  }
  
  // Log warning messages
  static void warning(String message, {String? tag, Object? error}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag ?? _tag,
        level: 900, // WARNING level
        error: error,
      );
    }
  }
  
  // Log error messages
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag ?? _tag,
        level: 1000, // ERROR level
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  
  // Log authentication events
  static void auth(String message, {Object? error, StackTrace? stackTrace}) {
    info(message, tag: 'AUTH');
    if (error != null) {
      ErrorLogger.error('Auth error: $error', tag: 'AUTH', error: error, stackTrace: stackTrace);
    }
  }
  
  // Log API events
  static void api(String message, {Object? error, StackTrace? stackTrace}) {
    info(message, tag: 'API');
    if (error != null) {
      ErrorLogger.error('API error: $error', tag: 'API', error: error, stackTrace: stackTrace);
    }
  }
  
  // Log database events
  static void database(String message, {Object? error, StackTrace? stackTrace}) {
    info(message, tag: 'DATABASE');
    if (error != null) {
      ErrorLogger.error('Database error: $error', tag: 'DATABASE', error: error, stackTrace: stackTrace);
    }
  }
  
  // Log user actions
  static void userAction(String action, {Map<String, dynamic>? data}) {
    final message = data != null 
        ? '$action: ${data.toString()}'
        : action;
    info(message, tag: 'USER_ACTION');
  }
}
