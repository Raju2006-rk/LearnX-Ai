import '../../../core/result.dart';
import '../data/quiz_repository.dart';
import '../domain/quiz.dart';

/// Application-level seam that wires the pure [SpacedRepetition] scheduling
/// rules to the [QuizRepository] persistence so the quiz flow can enter,
/// surface, and advance Leitner review items without re-implementing any
/// scheduling math.
///
/// The `QuizController` (task 9.2) owns the quiz session and scoring; it
/// delegates review-queue side effects to this service:
///
///  * [recordWrongAnswer] — on *any* wrong quiz answer, (re)enters the item at
///    the shortest interval (`intervalIndex 0`). (Requirement 6.3)
///  * [loadDueItems] — at quiz start, surfaces only the items whose due date
///    has passed, ordered by due date. (Requirement 6.4)
///  * [recordReviewAnswer] — after a review-item attempt, advances a correct
///    item to a strictly longer interval (clamped at the final rung) or resets
///    a wrong one to the shortest. (Requirement 6.5)
///
/// Every method returns a typed [Result] so callers branch on success/failure
/// without try/catch, mirroring the repository's error contract. The service
/// holds no state; the clock is injectable via [now] on each call so tests
/// drive the schedule deterministically. Scheduling decisions stay in
/// [SpacedRepetition] and I/O stays in [QuizRepository]; this type only
/// composes the two.
class ReviewQueueService {
  ReviewQueueService({required QuizRepository repository})
    : _repository = repository;

  final QuizRepository _repository;

  /// Enters a freshly-missed [itemId] into the learner [uid]'s review queue at
  /// the shortest interval (`intervalIndex 0`), returning the persisted
  /// [ReviewItem] on success.
  ///
  /// Called for *any* wrong quiz answer — whether the question was new or
  /// already under review — because a wrong answer always resets an item to the
  /// shortest interval. Uses [SpacedRepetition.onWrongAnswer] to compute the
  /// entry, then persists it via [QuizRepository.upsertReviewItem]. [now]
  /// defaults to the current UTC instant so it matches the UTC instants DTOs
  /// carry. (Requirement 6.3)
  Future<Result<ReviewItem>> recordWrongAnswer({
    required String uid,
    required String itemId,
    DateTime? now,
  }) async {
    final item = SpacedRepetition.onWrongAnswer(
      itemId: itemId,
      now: now ?? DateTime.now().toUtc(),
    );
    final result = await _repository.upsertReviewItem(uid: uid, item: item);
    return result.map((_) => item);
  }

  /// Loads the learner [uid]'s review items that are due at [now], ordered by
  /// due date — exactly the items a new quiz session should reintroduce.
  ///
  /// Delegates to [QuizRepository.loadDueReviewItems], which filters and orders
  /// via [SpacedRepetition.dueItems]; items not yet due are withheld.
  /// (Requirement 6.4)
  Future<Result<List<ReviewItem>>> loadDueItems({
    required String uid,
    DateTime? now,
  }) {
    return _repository.loadDueReviewItems(uid: uid, now: now);
  }

  /// Applies a review outcome for an existing [item] in the learner [uid]'s
  /// queue, returning the updated [ReviewItem] on success.
  ///
  /// A [correct] answer advances the item to a strictly longer interval
  /// (clamped at the ladder's final rung); a wrong answer resets it to the
  /// shortest. Uses [SpacedRepetition.onReviewAnswer] to compute the next
  /// state, then persists it via [QuizRepository.upsertReviewItem]. [now]
  /// defaults to the current UTC instant. (Requirement 6.5)
  Future<Result<ReviewItem>> recordReviewAnswer({
    required String uid,
    required ReviewItem item,
    required bool correct,
    DateTime? now,
  }) async {
    final next = SpacedRepetition.onReviewAnswer(
      item: item,
      correct: correct,
      now: now ?? DateTime.now().toUtc(),
    );
    final result = await _repository.upsertReviewItem(uid: uid, item: next);
    return result.map((_) => next);
  }
}
