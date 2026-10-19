import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';

/// An event emitted while streaming a callable AI function.
///
/// A stream yields zero or more [AiChunk]s (incremental reply tokens) followed
/// by exactly one [AiStreamResult] carrying the final structured payload.
sealed class AiStreamEvent {
  const AiStreamEvent();
}

/// An incremental chunk of streamed text (e.g. reply tokens as the provider
/// streams them, backing the time-to-first-token target).
final class AiChunk extends AiStreamEvent {
  const AiChunk(this.text);

  /// The partial text received in this chunk.
  final String text;

  @override
  bool operator ==(Object other) => other is AiChunk && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'AiChunk($text)';
}

/// The final result of a streamed call, marking the end of the stream.
final class AiStreamResult extends AiStreamEvent {
  const AiStreamResult(this.data);

  /// The final structured payload returned by the function (e.g. the reply
  /// plus a `Grammar_Feedback` object and a `status`).
  final Map<String, dynamic> data;

  @override
  String toString() => 'AiStreamResult($data)';
}

/// A uniform wrapper over Cloud Functions callables used by every AI feature.
///
/// No client talks to an AI provider directly; all generation is routed
/// through the `AI_Proxy` callables. This client centralizes the
/// `httpsCallable` and streaming plumbing so repositories depend on a single,
/// testable surface. (Requirements 11.1)
class AiFunctionClient {
  const AiFunctionClient(this._functions);

  final FirebaseFunctions _functions;

  /// Invokes the callable named [name] with [data] and returns the structured
  /// response as a map.
  ///
  /// Used by non-streaming functions such as `personalizeLesson` and
  /// `generatePlacementQuestion`.
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call<dynamic>(data);
    return _asMap(result.data);
  }

  /// Streams the callable named [name] with [data].
  ///
  /// Emits an [AiChunk] for each partial message the function streams, then a
  /// terminal [AiStreamResult] with the final payload. Used by
  /// `chatWithTeacher` so reply tokens render as they arrive.
  Stream<AiStreamEvent> stream(
    String name, [
    Map<String, dynamic>? data,
  ]) async* {
    final callable = _functions.httpsCallable(name);
    await for (final response in callable.stream<dynamic, dynamic>(data)) {
      switch (response) {
        case Chunk<dynamic, dynamic>(:final partialData):
          yield AiChunk(_asText(partialData));
        case Result<dynamic, dynamic>(:final result):
          yield AiStreamResult(_asMap(result.data));
      }
    }
  }

  /// Normalizes a callable payload into a `Map<String, dynamic>`.
  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  /// Extracts streamed text from a chunk payload, tolerating either a raw
  /// string or a `{ text: ... }` shaped map.
  static String _asText(dynamic partialData) {
    if (partialData is String) return partialData;
    if (partialData is Map && partialData['text'] is String) {
      return partialData['text'] as String;
    }
    return partialData?.toString() ?? '';
  }
}

/// The app-facing [AiFunctionClient], wired to the shared [FirebaseFunctions]
/// instance.
final aiFunctionClientProvider = Provider<AiFunctionClient>(
  (ref) => AiFunctionClient(ref.watch(firebaseFunctionsProvider)),
  name: 'aiFunctionClientProvider',
);
