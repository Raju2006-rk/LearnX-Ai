import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/quiz.dart';
import 'review_queue_data_source.dart';

/// Loads quiz content and the learner's due spaced-repetition items.
///
/// Reads the authored, read-only question bank from the global
/// `quizItems/{itemId}` collection and the learner's per-user review queue
/// via [ReviewQueueDataSource] (`users/{uid}/reviewQueue`). The repository
/// returns typed [Result]s so callers branch on success/failure without
/// try/catch, mirroring the learning-path repository's error contract:
/// connectivity failures map to [NetworkException]; other read/write failures
/// (including a rules rejection) map to [AuthException].
///
/// Scheduling transitions live in [SpacedRepetition] (a pure domain helper);
/// this repository only moves data and decides which review items are *due*.
/// (Requirements 6.1, 6.3, 6.4)
class QuizRepository {
  QuizRepository({
    required FirebaseFirestore firestore,
    required ReviewQueueDataSource reviewQueue,
  }) : _firestore = firestore,
       _reviewQueue = reviewQueue;

  final FirebaseFirestore _firestore;
  final ReviewQueueDataSource _reviewQueue;

  /// Loads the authored quiz-item bank, returning a typed [Result].
  ///
  /// Reads every document from the global `quizItems` collection and maps it
  /// to a [Question]. The bank is read-only to clients and shared by all
  /// learners. An empty bank is a *success* carrying an empty list (not a
  /// [NotFoundException]) so the quiz UI can show an "all caught up" state
  /// rather than an error. (Requirement 6.1)
  Future<Result<List<Question>>> loadQuizItems() async {
    try {
      final snap = await _firestore
          .collection(FirestorePaths.quizItemsCollection())
          .get();
      final questions = <Question>[
        for (final doc in snap.docs)
          Question.fromDto(doc.id, QuizItemDto.fromMap(doc.data())),
      ];
      return Result.success(questions);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Loads the learner [uid]'s review-queue items that are due at [now],
  /// returning a typed [Result].
  ///
  /// Reads every `reviewQueue` entry and surfaces only those whose
  /// [ReviewItem.dueDate] has passed, ordered by due date via
  /// [SpacedRepetition.dueItems] — so a later quiz session reintroduces
  /// exactly the items the spaced-repetition schedule has made due, and no
  /// others. [now] is injectable so callers (and tests) control the clock;
  /// it defaults to [DateTime.now] in UTC to match the UTC instants DTOs
  /// carry. (Requirement 6.4)
  Future<Result<List<ReviewItem>>> loadDueReviewItems({
    required String uid,
    DateTime? now,
  }) async {
    try {
      final all = await _reviewQueue.readAll(uid);
      final due = SpacedRepetition.dueItems(all, now ?? DateTime.now().toUtc());
      return Result.success(due);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Upserts [item] into the learner [uid]'s review queue, returning a typed
  /// [Result].
  ///
  /// Delegates the write to [ReviewQueueDataSource.upsert]; callers compute
  /// the next [ReviewItem] via [SpacedRepetition] before persisting it (for
  /// example after a wrong answer or a review attempt). (Requirements 6.3,
  /// 6.5)
  Future<Result<void>> upsertReviewItem({
    required String uid,
    required ReviewItem item,
  }) async {
    try {
      await _reviewQueue.upsert(uid, item);
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Persists the earned result of a completed quiz [session] for the learner
  /// [uid] under `users/{uid}/quizSessions/{sessionId}`, returning a typed
  /// [Result].
  ///
  /// The write is a **merge** stamping `updatedAt` with
  /// [FieldValue.serverTimestamp] (the other fields come from [session]) so,
  /// when the device is offline, Firestore offline persistence queues the
  /// result locally and replays it on reconnect. Because the document carries
  /// a server-clock `updatedAt`, a replayed offline write resolves against
  /// server state last-write-wins rather than blindly overwriting it, and the
  /// merge never clobbers unknown fields. (Requirement 8.2)
  Future<Result<void>> saveQuizSession({
    required String uid,
    required String sessionId,
    required QuizSessionDto session,
  }) async {
    try {
      final data = session.toMap()
        ..['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore
          .doc(FirestorePaths.quizSessionDoc(uid, sessionId))
          .set(data, SetOptions(merge: true));
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; every other failure
  /// (including a rules rejection) maps to [AuthException] as a permission
  /// failure, matching the learning-path repository's contract.
  AppException _mapError(Object error) {
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Could not load your quizzes.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(
        'A network error occurred. Check your connection and try again.',
        error,
      );
    }
    return AuthException('Could not load your quizzes.', error);
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
