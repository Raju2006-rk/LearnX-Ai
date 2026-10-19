// Shared test doubles for PlacementRepository-backed tests.
//
// PlacementRepository requires an AiFunctionClient, but the placement
// completion path (completePlacement) never calls the server. These fakes let
// a test construct a repository without a live Cloud Functions client: the
// client either returns a canned payload or throws, and the underlying
// FirebaseFunctions is never touched.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:learnx/core/ai/ai_function_client.dart';

/// A fake [AiFunctionClient] that returns a canned [response] or throws
/// [error], recording the last call's arguments for assertions.
class FakeAiFunctionClient extends AiFunctionClient {
  FakeAiFunctionClient({this.response, this.error})
      : super(_UnusedFunctions());

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
