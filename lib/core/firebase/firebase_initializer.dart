import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Handles one-time Firebase bootstrap for the app.
///
/// Responsibilities:
/// - Initialize the Firebase app with the platform-specific [FirebaseOptions].
/// - Enable Firestore offline persistence on Android so per-user progress
///   writes queue locally and replay on reconnect. (Requirements 10.1, 8.2)
///
/// LearnX targets Android, web, and Windows. Web and Windows are intentionally
/// excluded from the explicit persistence configuration: the offline content
/// cache is an Android guarantee, while web/Windows rely on whatever Firestore
/// persistence the platform supports by default and otherwise operate online.
class FirebaseInitializer {
  const FirebaseInitializer._();

  /// Initializes Firebase and configures Firestore persistence.
  ///
  /// Safe to call once during app startup (before `runApp`).
  static Future<void> ensureInitialized() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _configureFirestorePersistence();
  }

  /// Enables unlimited offline persistence on Android only.
  static void _configureFirestorePersistence() {
    if (_isMobile) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  }

  /// True on Android (and never on web). LearnX targets Android, web, and
  /// Windows; Android is the only target that needs the explicit offline
  /// persistence guarantee.
  static bool get _isMobile =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}


