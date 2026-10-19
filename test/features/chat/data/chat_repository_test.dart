// Unit tests for ChatRepository: mapping the streaming chatWithTeacher payload
// into domain stream events, mapping each status (ok/limit_reached/refusal/
// error) to the matching terminal event, and filing wrong-correction reports.
// (Requirements 4.1, 4.6, 5.3, 5.4)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/chat/data/chat_repository.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';

/// A fake [AiFunctionClient] whose [stream] replays a canned list of events or
/// throws, recording the arguments of the last call so assertions can check
/// the wire shape.
class _FakeAiFunctionClient extends AiFunctionClient {
  _FakeAiFunctionClient({this.events = const [], this.error})
    : super(_UnusedFunctions());

  final List<AiStreamEvent> events;
  final Object? error;

  String? lastName;
  Map<String, dynamic>? lastData;

  @override
  Stream<AiStreamEvent> stream(String name, [Map<String, dynamic>? data]) {
    lastName = name;
    lastData = data;
    if (error != null) {
      return Stream<AiStreamEvent>.error(error!);
    }
    return Stream<AiStreamEvent>.fromIterable(events);
  }
}

/// Stand-in for the [FirebaseFunctions] the base client needs; never invoked
/// because [_FakeAiFunctionClient.stream] is overridden.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FirebaseFunctions is not used in this fake');
}

Map<String, dynamic> _feedbackMap({bool hasMistake = true}) {
  return <String, dynamic>{
    'hasMistake': hasMistake,
    if (hasMistake)
      'mistakeSpan': <String, dynamic>{'start': 0, 'end': 1, 'text': 'i'},
    'correctedSentence': 'I am happy.',
    'tip': 'Capitalize "I".',
    'translation': <String, dynamic>{'language': 'hi', 'text': 'संकेत'},
  };
}

void main() {
  const uid = 'user-123';
  const sessionId = 'session-1';

  group('sendMessage - status mapping', () {
    test(
      'forwards sessionId and text, streams tokens then an ok reply',
      () async {
        final client = _FakeAiFunctionClient(
          events: [
            const AiChunk('Hel'),
            const AiChunk('lo'),
            AiStreamResult(<String, dynamic>{
              'status': 'ok',
              'result': <String, dynamic>{
                'reply': 'Hello there!',
                'messageId': 'm1',
                'grammarFeedback': _feedbackMap(),
              },
            }),
          ],
        );
        final repo = ChatRepository(
          aiClient: client,
          firestore: FakeFirebaseFirestore(),
        );

        final events = await repo
            .sendMessage(sessionId: sessionId, text: 'helo')
            .toList();

        expect(client.lastName, ChatRepository.callableName);
        expect(client.lastData, {'sessionId': sessionId, 'text': 'helo'});

        expect(events[0], const ChatToken('Hel'));
        expect(events[1], const ChatToken('lo'));
        expect(events.last, isA<ChatReply>());
        final reply = (events.last as ChatReply).message;
        expect(reply.role, ChatRole.assistant);
        expect(reply.text, 'Hello there!');
        expect(reply.id, 'm1');
        expect(reply.grammarFeedback, isNotNull);
        expect(reply.grammarFeedback!.hasMistake, isTrue);
        expect(reply.grammarFeedback!.mistakeSpan!.text, 'i');
        expect(reply.grammarFeedback!.correctedSentence, 'I am happy.');
        expect(
          reply.grammarFeedback!.translation.language,
          NativeLanguage.hindi,
        );
      },
    );

    test(
      'an ok reply with no feedback yields a reply without feedback',
      () async {
        final client = _FakeAiFunctionClient(
          events: [
            AiStreamResult(<String, dynamic>{
              'status': 'ok',
              'result': <String, dynamic>{'reply': 'Nice!'},
            }),
          ],
        );
        final repo = ChatRepository(
          aiClient: client,
          firestore: FakeFirebaseFirestore(),
        );

        final events = await repo
            .sendMessage(sessionId: sessionId, text: 'hi')
            .toList();

        expect(events.single, isA<ChatReply>());
        final reply = (events.single as ChatReply).message;
        expect(reply.text, 'Nice!');
        expect(reply.grammarFeedback, isNull);
      },
    );

    test('limit_reached status maps to ChatLimitReached', () async {
      final client = _FakeAiFunctionClient(
        events: [
          AiStreamResult(<String, dynamic>{
            'status': 'limit_reached',
            'limit': 5,
          }),
        ],
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(events.single, isA<ChatLimitReached>());
      expect(
        (events.single as ChatLimitReached).exception,
        isA<UsageLimitException>(),
      );
    });

    test('refusal status maps to ChatRefused with the safe message', () async {
      final client = _FakeAiFunctionClient(
        events: [
          AiStreamResult(<String, dynamic>{
            'status': 'refusal',
            'safeMessage': 'Let us keep it friendly.',
          }),
        ],
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(events.single, isA<ChatRefused>());
      expect(
        (events.single as ChatRefused).exception.message,
        'Let us keep it friendly.',
      );
    });

    test('error status maps to ChatFailed with a NetworkException', () async {
      final client = _FakeAiFunctionClient(
        events: [
          AiStreamResult(<String, dynamic>{
            'status': 'error',
            'message': 'Upstream failed.',
          }),
        ],
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(events.single, isA<ChatFailed>());
      expect((events.single as ChatFailed).exception, isA<NetworkException>());
    });

    test('an unknown status maps to ChatFailed', () async {
      final client = _FakeAiFunctionClient(
        events: [
          AiStreamResult(<String, dynamic>{'status': 'something-new'}),
        ],
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(events.single, isA<ChatFailed>());
    });

    test('an ok reply missing reply text maps to ChatFailed', () async {
      final client = _FakeAiFunctionClient(
        events: [
          AiStreamResult(<String, dynamic>{
            'status': 'ok',
            'result': <String, dynamic>{'grammarFeedback': _feedbackMap()},
          }),
        ],
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(events.single, isA<ChatFailed>());
    });

    test(
      'a thrown FirebaseFunctionsException is surfaced as ChatFailed',
      () async {
        final client = _FakeAiFunctionClient(
          error: FirebaseFunctionsException(
            message: 'offline',
            code: 'unavailable',
          ),
        );
        final repo = ChatRepository(
          aiClient: client,
          firestore: FakeFirebaseFirestore(),
        );

        final events = await repo
            .sendMessage(sessionId: sessionId, text: 'hi')
            .toList();

        expect(events.single, isA<ChatFailed>());
        expect(
          (events.single as ChatFailed).exception,
          isA<NetworkException>(),
        );
      },
    );

    test('a resource-exhausted throw maps to a UsageLimitException', () async {
      final client = _FakeAiFunctionClient(
        error: FirebaseFunctionsException(
          message: 'quota',
          code: 'resource-exhausted',
        ),
      );
      final repo = ChatRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final events = await repo
          .sendMessage(sessionId: sessionId, text: 'hi')
          .toList();

      expect(
        (events.single as ChatFailed).exception,
        isA<UsageLimitException>(),
      );
    });
  });

  group('fileReport', () {
    test(
      'persists the report under the user and returns it with an id',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = ChatRepository(
          aiClient: _FakeAiFunctionClient(),
          firestore: firestore,
        );

        const feedback = GrammarFeedback(
          hasMistake: true,
          mistakeSpan: MistakeSpan(start: 0, end: 1, text: 'i'),
          correctedSentence: 'I am happy.',
          tip: 'Capitalize "I".',
          translation: FeedbackTranslation(
            language: NativeLanguage.hindi,
            text: 'संकेत',
          ),
        );
        const report = Report(
          sessionId: sessionId,
          messageId: 'm1',
          originalText: 'i am happy',
          grammarFeedback: feedback,
          reason: 'The correction is wrong.',
        );

        final result = await repo.fileReport(uid: uid, report: report);

        expect(result, isA<Success<Report>>());
        final stored = result.valueOrNull!;
        expect(stored.id, isNotNull);
        expect(stored.status, ReportStatus.open);

        final snap = await firestore
            .doc(FirestorePaths.reportDoc(uid, stored.id!))
            .get();
        final data = snap.data()!;
        expect(data['sessionId'], sessionId);
        expect(data['messageId'], 'm1');
        expect(data['originalText'], 'i am happy');
        expect(data['status'], 'open');
        expect(data['reason'], 'The correction is wrong.');
        // Full context snapshot preserved. (Requirement 5.4)
        final feedbackMap = data['grammarFeedback'] as Map<String, dynamic>;
        expect(feedbackMap['correctedSentence'], 'I am happy.');
        expect((feedbackMap['translation'] as Map)['language'], 'hi');
      },
    );
  });

  group('loadHistory - pagination (Req 9.3)', () {
    // Seeds [count] messages with ascending createdAt so newest-first ordering
    // is deterministic. Message i has id "m$i" and text "msg $i".
    Future<FakeFirebaseFirestore> seedMessages(int count) async {
      final firestore = FakeFirebaseFirestore();
      final base = DateTime.utc(2024, 1, 1);
      for (var i = 0; i < count; i++) {
        await firestore
            .doc(FirestorePaths.messageDoc(uid, sessionId, 'm$i'))
            .set(<String, dynamic>{
              'role': i.isEven ? 'user' : 'assistant',
              'text': 'msg $i',
              'grammarFeedback': null,
              'createdAt': Timestamp.fromDate(base.add(Duration(minutes: i))),
            });
      }
      return firestore;
    }

    test(
      'returns a bounded page oldest-first and flags more remaining',
      () async {
        final firestore = await seedMessages(5);
        final repo = ChatRepository(
          aiClient: _FakeAiFunctionClient(),
          firestore: firestore,
        );

        final result = await repo.loadHistory(
          uid: uid,
          sessionId: sessionId,
          pageSize: 2,
        );

        final page = result.valueOrNull!;
        // Newest two messages (m4, m3) returned oldest-first within the page.
        expect(page.messages.map((m) => m.text), ['msg 3', 'msg 4']);
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, isNotNull);
      },
    );

    test(
      'paging with the cursor walks older messages without overlap',
      () async {
        final firestore = await seedMessages(5);
        final repo = ChatRepository(
          aiClient: _FakeAiFunctionClient(),
          firestore: firestore,
        );

        final first = await repo.loadHistory(
          uid: uid,
          sessionId: sessionId,
          pageSize: 2,
        );
        final firstPage = first.valueOrNull!;
        // Newest two, oldest-first within the page.
        expect(firstPage.messages.map((m) => m.text), ['msg 3', 'msg 4']);
        expect(firstPage.hasMore, isTrue);

        final second = await repo.loadHistory(
          uid: uid,
          sessionId: sessionId,
          pageSize: 2,
          startAfter: firstPage.nextCursor,
        );
        final secondPage = second.valueOrNull!;

        // The second page is strictly older than the first with no overlap.
        final secondTexts = secondPage.messages.map((m) => m.text).toList();
        expect(secondTexts, isNotEmpty);
        expect(secondTexts, isNot(contains('msg 3')));
        expect(secondTexts, isNot(contains('msg 4')));
        // Prepending older pages ahead of newer ones yields ascending order.
        final combined = [
          ...secondTexts,
          ...firstPage.messages.map((m) => m.text),
        ];
        final sorted = [...combined]
          ..sort(
            (a, b) => int.parse(
              a.split(' ')[1],
            ).compareTo(int.parse(b.split(' ')[1])),
          );
        expect(combined, sorted);
      },
    );

    test('the last page has hasMore false', () async {
      final firestore = await seedMessages(3);
      final repo = ChatRepository(
        aiClient: _FakeAiFunctionClient(),
        firestore: firestore,
      );

      final result = await repo.loadHistory(
        uid: uid,
        sessionId: sessionId,
        pageSize: 5,
      );

      final page = result.valueOrNull!;
      expect(page.messages.map((m) => m.text), ['msg 0', 'msg 1', 'msg 2']);
      expect(page.hasMore, isFalse);
    });

    test('an empty session returns the empty page', () async {
      final repo = ChatRepository(
        aiClient: _FakeAiFunctionClient(),
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.loadHistory(uid: uid, sessionId: sessionId);

      final page = result.valueOrNull!;
      expect(page.messages, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });
}
