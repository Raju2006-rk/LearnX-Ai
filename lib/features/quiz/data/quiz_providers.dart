import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../application/review_queue_service.dart';
import 'quiz_repository.dart';
import 'review_queue_data_source.dart';

/// Riverpod provider wiring the [ReviewQueueDataSource] to the shared
/// Firestore instance.
///
/// The data source is a thin Firestore mapper for the per-user review queue;
/// tests override [firebaseFirestoreProvider] (or this provider directly) with
/// a fake/emulator-backed instance.
final reviewQueueDataSourceProvider = Provider<ReviewQueueDataSource>(
  (ref) =>
      ReviewQueueDataSource(firestore: ref.watch(firebaseFirestoreProvider)),
  name: 'reviewQueueDataSourceProvider',
);

/// Riverpod provider wiring the [QuizRepository] to the shared Firestore
/// instance and the [ReviewQueueDataSource].
///
/// The application layer (`QuizController`, `ReviewQueueService`) depends on
/// this provider; tests override its dependencies (or this provider directly)
/// with fakes.
final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    reviewQueue: ref.watch(reviewQueueDataSourceProvider),
  ),
  name: 'quizRepositoryProvider',
);

/// Riverpod provider exposing the [ReviewQueueService] application seam.
///
/// This is the entry point the `QuizController` (task 9.2) calls to enter wrong
/// answers into the review queue, surface only due items at quiz start, and
/// advance/reset review items — without re-implementing any scheduling math.
/// It composes the pure `SpacedRepetition` rules with the [QuizRepository];
/// tests override [quizRepositoryProvider] (or this provider directly).
/// (Requirements 6.3, 6.4, 6.5)
final reviewQueueServiceProvider = Provider<ReviewQueueService>(
  (ref) => ReviewQueueService(repository: ref.watch(quizRepositoryProvider)),
  name: 'reviewQueueServiceProvider',
);
