// Shared test doubles for PathRepository-backed tests.
//
// PathRepository requires an AiFunctionClient so it can request lesson
// personalization (the `personalizeLesson` callable). The path-loading and
// step-completion paths exercised by these tests never need a live Cloud
// Functions client, so this fake lets a test construct the repository (or
// override `aiFunctionClientProvider`) without touching FirebaseFunctions: the
// client returns a canned personalization payload (empty by default, which the
// repository maps to the skeleton-only fallback) or throws.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:learnx/core/ai/ai_function_client.dart';

/// A fake [AiFunctionClient] that returns a canned [response] or throws
/// [error], recording the last call's arguments for assertions.
///
/// The default empty response models the common case for path tests: no AI
/// personalization, so the step detail falls back to the authored skeleton.
class FakeAiFunctionClient extends AiFunctionClient {
  FakeAiFunctionClient({this.response, this.error}) : super(_UnusedFunctions());

  /// The payload returned from [call] when no [error] is set.
  final Map<String, dynamic>? response;

  /// When set, [call] throws this instead of returning [response].
  final Object? error;

  /// The callable name of the last [call].
  String? lastName;

  /// The data argument of the last [call].
  Map<String, dynamic>? lastData;

  @override
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    lastName = name;
    lastData = data;
    if (error != null) throw error!;
    return response ?? <String, dynamic>{};
  }
}

/// Stand-in for the [FirebaseFunctions] the base client needs; never invoked
/// because [FakeAiFunctionClient.call] is overridden.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FirebaseFunctions is not used in this fake');
}
