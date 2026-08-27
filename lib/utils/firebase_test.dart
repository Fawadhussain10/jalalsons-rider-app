import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseTest {
  static Future<bool> testConnection() async {
    try {
      // Test Firestore connection
      final firestore = FirebaseFirestore.instance;
      
      // Try to read from a test collection
      await firestore.collection('test').limit(1).get();
      
      if (kDebugMode) {
        print('✅ Firebase connection successful!');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Firebase connection failed: $e');
      }
      return false;
    }
  }

  static Future<void> createTestDocument() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      await firestore.collection('test').add({
        'message': 'Hello from JS Rider!',
        'timestamp': FieldValue.serverTimestamp(),
        'app': 'js_rider',
      });
      
      if (kDebugMode) {
        print('✅ Test document created successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to create test document: $e');
      }
    }
  }
}
