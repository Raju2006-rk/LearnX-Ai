import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

/// Root widget of the LearnX application.
///
/// Wires the go_router configuration and the app theme into a
/// [MaterialApp.router]. State is provided by Riverpod via [ProviderScope]
/// (installed in `main.dart`). (Requirements 12.1)
class LearnXApp extends ConsumerWidget {
  const LearnXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'LearnX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
