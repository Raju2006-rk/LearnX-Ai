import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseInitializer.ensureInitialized();
  } catch (error, stackTrace) {
    // A failed Firebase bootstrap (e.g. invalid/placeholder config or no
    // network at launch) would otherwise throw before runApp and leave a blank
    // screen. Surface a readable error instead so the failure is diagnosable
    // rather than silent.
    debugPrint('Firebase initialization failed: $error\n$stackTrace');
    runApp(_StartupErrorApp(error: error));
    return;
  }

  runApp(
    const ProviderScope(
      child: LearnXApp(),
    ),
  );
}

/// A minimal fallback app shown when Firebase fails to initialize at startup,
/// so the learner sees a clear message instead of a blank screen.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  "LearnX couldn't start",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'We could not connect to the backend. Check your connection '
                  'and app configuration, then restart the app.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
