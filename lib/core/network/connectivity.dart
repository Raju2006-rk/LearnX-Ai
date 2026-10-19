import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coarse online/offline connectivity status.
///
/// This is intentionally binary: network-required features (chat, quizzes)
/// only need to know whether a connection is plausibly available so they can
/// fail fast with a clear message instead of hanging. (Requirements 4.5, 6.6,
/// 8.4)
enum ConnectivityStatus {
  /// At least one network transport reports connectivity.
  online,

  /// No network transport is available.
  offline;

  /// Whether the device is currently online.
  bool get isOnline => this == ConnectivityStatus.online;

  /// Whether the device is currently offline.
  bool get isOffline => this == ConnectivityStatus.offline;
}

/// Maps a set of raw [ConnectivityResult]s to a coarse [ConnectivityStatus].
///
/// The list is considered [ConnectivityStatus.online] when it contains any
/// transport other than [ConnectivityResult.none]. An empty list is treated
/// as offline.
ConnectivityStatus statusFromResults(List<ConnectivityResult> results) {
  final hasConnection = results.any(
    (result) => result != ConnectivityResult.none,
  );
  return hasConnection ? ConnectivityStatus.online : ConnectivityStatus.offline;
}

/// Exposes the platform [Connectivity] plugin as a provider.
///
/// Overridable in tests with a fake that returns a scripted stream.
final connectivityProvider = Provider<Connectivity>(
  (ref) => Connectivity(),
  name: 'connectivityProvider',
);

/// A live stream of the device's [ConnectivityStatus].
///
/// Emits the current status immediately on subscription, then a new value
/// whenever connectivity changes. Controllers `ref.watch` this to branch on
/// online/offline state.
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>(
  (ref) {
    final connectivity = ref.watch(connectivityProvider);

    final controller = StreamController<ConnectivityStatus>();

    // Emit the current status right away so listeners don't wait for the
    // first change event.
    unawaited(
      connectivity.checkConnectivity().then(
        (results) {
          if (!controller.isClosed) {
            controller.add(statusFromResults(results));
          }
        },
        onError: (Object _) {
          if (!controller.isClosed) {
            controller.add(ConnectivityStatus.offline);
          }
        },
      ),
    );

    final subscription = connectivity.onConnectivityChanged.listen(
      (results) => controller.add(statusFromResults(results)),
      onError: (Object _) => controller.add(ConnectivityStatus.offline),
    );

    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(controller.close());
    });

    return controller.stream;
  },
  name: 'connectivityStatusProvider',
);
