// Property-based test for offline progress writes surviving sync.
// (Requirements 8.2, 8.3)
//
// Property 20: Offline progress writes survive sync. For any set / interleaving
// of progress writes made while offline, after connectivity is restored the
// backend state reflects all of those writes under last-write-wins-by-timestamp
// resolution — and transactional increments (streak, daily-activity counters)
// reconcile against server state rather than blindly overwriting it.
// (Validates: Requirements 8.2, 8.3)
//
// The project has no dedicated property-testing package, so this test follows
// the convention of the other `*_property_test.dart` files: drive many (100+)
// randomly generated write sequences through the real repositories +
// `fake_cloud_firestore` and assert the invariant over each. A fixed seed keeps
// iterations reproducible; a failing case prints the generated scenario via
// `reason`.
//
// How last-write-wins is exercised here: every sync-participating write stamps
// `updatedAt` with `FieldValue.serverTimestamp()`, which the fake backend
// resolves to a monotonically increasing instant in the order the writes land.
// So "the write with the latest timestamp survives" is equivalent to "the last
// write applied survives" — the oracle folds the generated sequence the same
// way and the persisted document must match.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/learning_path/data/content_cache_data_source.dart';
import 'package:learnx/features/learning_path/data/path_repository.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';
import 'package:learnx/features/progress/data/streak_repository.dart';
import 'package:learnx/features/progress/domain/streak.dart';
import 'package:learnx/features/quiz/data/quiz_repository.dart';
import 'package:learnx/features/quiz/data/review_queue_data_source.dart';
import 'package:learnx/features/sync/data/restore_repository.dart';
import 'package:learnx/features/sync/domain/restored_state.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

import '../../learning_path/learning_path_test_support.dart';

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

const String _uid = 'learner-sync';

// A stable fixed seed keeps the 100+ iterations reproducible: a failing run
// always reproduces the same generated scenario.
const int _seed = 0x5110;
const int _iterations = 120;

/// A pool of `"YYYY-MM-DD"` dates spanning a few non-consecutive and
/// consecutive calendar days so generated activity sequences exercise same-day
/// no-ops, consecutive-day increments, and gap resets.
const List<String> _datePool = <String>[
  '2024-06-01',
  '2024-06-02',
  '2024-06-03',
  '2024-06-05',
  '2024-06-10',
];

// ---------------------------------------------------------------------------
// Property 1 — merge writes resolve last-write-wins (quiz session document).
//
// A quiz result earned offline is a merge write to
// `users/{uid}/quizSessions/{sessionId}` stamping a server `updatedAt`. Replay
// any sequence of results for the same session: the surviving document fields
// are those of the write with the latest timestamp (the last one applied),
// and the merge never drops fields it did not touch.
// ---------------------------------------------------------------------------

/// One generated quiz-result write in a replay sequence.
class _QuizWrite {
  const _QuizWrite({required this.correct, required this.wrong});

  final int correct;
  final int wrong;

  @override
  String toString() => '(c:$correct,w:$wrong)';
}

List<_QuizWrite> _quizSequence(Random random) {
  final count = 1 + random.nextInt(5); // 1..5 queued writes
  return List<_QuizWrite>.generate(
    count,
    (_) => _QuizWrite(correct: random.nextInt(20), wrong: random.nextInt(20)),
  );
}

// ---------------------------------------------------------------------------
// Property 2 — merge writes resolve last-write-wins (path-progress document).
//
// `completeStep` merge-writes `state: completed` to
// `users/{uid}/pathProgress/{stepId}` with a server `updatedAt`. The last
// write applied is the one whose timestamp survives; a sibling field seeded on
// the document (e.g. an authored note) must be preserved by the merge.
// ---------------------------------------------------------------------------

List<String> _stepSequence(Random random) {
  const stepPool = <String>['step-1', 'step-2', 'step-3', 'step-4'];
  final count = 1 + random.nextInt(6);
  return List<String>.generate(
    count,
    (_) => stepPool[random.nextInt(stepPool.length)],
  );
}

// ---------------------------------------------------------------------------
// Property 3 — transactional increments reconcile (streak + daily activity).
//
// Qualifying-activity writes are transactional read-modify-writes: a replayed
// offline write accumulates against the value it reads rather than overwriting
// it. For any sequence of qualifying-activity dates the final persisted streak
// and daily-activity counters equal an independent fold of the sequence.
// ---------------------------------------------------------------------------

/// One generated qualifying activity: the calendar day plus the metrics it
/// rolls into that day's activity counters.
class _Activity {
  const _Activity({
    required this.date,
    required this.timeSpentSec,
    required this.wordsLearned,
    required this.mistakesFixed,
  });

  final String date;
  final int timeSpentSec;
  final int wordsLearned;
  final int mistakesFixed;

  ActivityMetrics get metrics => ActivityMetrics(
    timeSpentSec: timeSpentSec,
    wordsLearned: wordsLearned,
    mistakesFixed: mistakesFixed,
  );

  @override
  String toString() =>
      '($date t:$timeSpentSec w:$wordsLearned m:$mistakesFixed)';
}

List<_Activity> _activitySequence(Random random) {
  final count = 1 + random.nextInt(6); // 1..6 replayed activities
  return List<_Activity>.generate(count, (_) {
    return _Activity(
      date: _datePool[random.nextInt(_datePool.length)],
      timeSpentSec: random.nextInt(600),
      wordsLearned: random.nextInt(10),
      mistakesFixed: random.nextInt(5),
    );
  });
}

/// Independent oracle for the streak after folding [activities] in order with
/// the pure rule — the same reconciliation the transactional write performs.
Streak _expectedStreak(List<_Activity> activities) {
  var state = StreakState.initial;
  for (final activity in activities) {
    state = StreakComputation.onQualifyingActivity(state, activity.date);
  }
  return state.streak;
}

/// Independent oracle for the per-day activity counters after folding
/// [activities]: every qualifying activity (including same-day repeats) ticks
/// its day's counters, so counts accumulate per date.
Map<String, DailyActivityDto> _expectedActivity(List<_Activity> activities) {
  final byDate = <String, DailyActivityDto>{};
  for (final activity in activities) {
    final prior = byDate[activity.date] ?? const DailyActivityDto();
    byDate[activity.date] = DailyActivityDto(
      activities: prior.activities + 1,
      timeSpentSec: prior.timeSpentSec + activity.timeSpentSec,
      wordsLearned: prior.wordsLearned + activity.wordsLearned,
      mistakesFixed: prior.mistakesFixed + activity.mistakesFixed,
    );
  }
  return byDate;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 20: offline progress writes survive sync (Req 8.2, 8.3)', () {
    test(
      'merge writes resolve last-write-wins — surviving quiz session is the '
      'latest-timestamp write and the merge preserves untouched fields',
      () async {
        final random = Random(_seed);

        for (var i = 0; i < _iterations; i++) {
          final firestore = FakeFirebaseFirestore();
          final repository = QuizRepository(
            firestore: firestore,
            reviewQueue: ReviewQueueDataSource(firestore: firestore),
          );

          const sessionId = 'session-1';
          final writes = _quizSequence(random);
          final reason = 'iteration $i, writes=$writes';

          // Seed a sibling field a replayed merge write must not clobber.
          await firestore
              .doc(FirestorePaths.quizSessionDoc(_uid, sessionId))
              .set(<String, dynamic>{'startedBy': 'device-A'});

          // Replay the queued offline writes in order. Each stamps a server
          // updatedAt, so the last one applied carries the latest timestamp.
          for (final write in writes) {
            final result = await repository.saveQuizSession(
              uid: _uid,
              sessionId: sessionId,
              session: QuizSessionDto(
                correctCount: write.correct,
                wrongCount: write.wrong,
              ),
            );
            expect(result, isA<Success<void>>(), reason: reason);
          }

          final snap = await firestore
              .doc(FirestorePaths.quizSessionDoc(_uid, sessionId))
              .get();
          final data = snap.data()!;

          // Last-write-wins: the surviving counts are the last write's.
          final winner = writes.last;
          expect(data['correctCount'], winner.correct, reason: reason);
          expect(data['wrongCount'], winner.wrong, reason: reason);

          // The merge preserved the untouched sibling field.
          expect(data['startedBy'], 'device-A', reason: reason);

          // A sync-participating write always carries a resolved updatedAt.
          expect(data['updatedAt'], isA<Timestamp>(), reason: reason);
        }
      },
    );

    test(
      'merge writes resolve last-write-wins — completed step survives with its '
      'seeded sibling field intact across a replayed sequence',
      () async {
        final random = Random(_seed ^ 0x1);

        for (var i = 0; i < _iterations; i++) {
          final firestore = FakeFirebaseFirestore();
          final repository = PathRepository(
            firestore: firestore,
            aiClient: FakeAiFunctionClient(),
            contentCache: ContentCacheDataSource(),
          );

          final steps = _stepSequence(random);
          final reason = 'iteration $i, steps=$steps';

          // Seed each step with a sibling field a merge write must preserve.
          for (final stepId in steps.toSet()) {
            await firestore
                .doc(FirestorePaths.pathProgressDoc(_uid, stepId))
                .set(<String, dynamic>{'authoredNote': 'keep-$stepId'});
          }

          // Replay the queued completion writes in order.
          for (final stepId in steps) {
            final result = await repository.completeStep(
              uid: _uid,
              stepId: stepId,
            );
            expect(result, isA<Success<void>>(), reason: reason);
          }

          // Every step written is persisted as completed (completion is
          // idempotent, so re-writes of the same step still win as completed),
          // carrying a resolved updatedAt, with its sibling field intact.
          for (final stepId in steps.toSet()) {
            final snap = await firestore
                .doc(FirestorePaths.pathProgressDoc(_uid, stepId))
                .get();
            final data = snap.data()!;
            expect(
              StepState.fromWire(data['state'] as String?),
              StepState.completed,
              reason: '$reason, stepId=$stepId',
            );
            expect(
              data['authoredNote'],
              'keep-$stepId',
              reason: '$reason, stepId=$stepId',
            );
            expect(
              data['updatedAt'],
              isA<Timestamp>(),
              reason: '$reason, stepId=$stepId',
            );
          }
        }
      },
    );

    test(
      'transactional increments reconcile — replayed qualifying activities '
      'accumulate to the folded streak and daily-activity counters',
      () async {
        final random = Random(_seed ^ 0x2);

        for (var i = 0; i < _iterations; i++) {
          final firestore = FakeFirebaseFirestore();
          final repository = StreakRepository(firestore: firestore);

          final activities = _activitySequence(random);
          final reason = 'iteration $i, activities=$activities';

          // Replay each offline qualifying-activity write. recordGoalAnd
          // Activity + recordQualifyingActivity are transactional read-modify-
          // writes, so a replayed write reconciles against server state.
          for (final activity in activities) {
            await repository.recordQualifyingActivity(_uid, activity.date);
            await repository.recordGoalAndActivity(
              _uid,
              activity.date,
              metrics: activity.metrics,
            );
          }

          // The persisted streak equals an independent fold of the sequence —
          // increments reconciled rather than overwrote.
          final progressSnap = await firestore
              .doc(FirestorePaths.progressDoc(_uid))
              .get();
          final progress = ProgressDto.fromMap(
            progressSnap.data() ?? const <String, dynamic>{},
          );
          final expectedStreak = _expectedStreak(activities);
          expect(
            progress.currentStreak,
            expectedStreak.current,
            reason: reason,
          );
          expect(
            progress.longestStreak,
            expectedStreak.longest,
            reason: reason,
          );

          // Every day's activity counters equal the accumulated per-day fold.
          final expectedByDate = _expectedActivity(activities);
          for (final entry in expectedByDate.entries) {
            final daySnap = await firestore
                .doc(FirestorePaths.dailyActivityDoc(_uid, entry.key))
                .get();
            final actual = DailyActivityDto.fromMap(
              daySnap.data() ?? const <String, dynamic>{},
            );
            expect(actual, entry.value, reason: '$reason, date=${entry.key}');
          }
        }
      },
    );

    test('cross-device restore reflects the synced last-write-wins state '
        '(Req 8.3)', () async {
      final random = Random(_seed ^ 0x3);

      for (var i = 0; i < _iterations; i++) {
        final firestore = FakeFirebaseFirestore();
        final streakRepo = StreakRepository(firestore: firestore);
        final pathRepo = PathRepository(
          firestore: firestore,
          aiClient: FakeAiFunctionClient(),
          contentCache: ContentCacheDataSource(),
        );
        final restoreRepo = RestoreRepository(firestore: firestore);

        // An account must exist for restore to report accountExists.
        await firestore.doc(FirestorePaths.userDoc(_uid)).set(<String, dynamic>{
          'accountTier': 'free',
        });

        final activities = _activitySequence(random);
        final steps = _stepSequence(random);
        final reason = 'iteration $i, activities=$activities, steps=$steps';

        for (final activity in activities) {
          await streakRepo.recordQualifyingActivity(_uid, activity.date);
          await streakRepo.recordGoalAndActivity(
            _uid,
            activity.date,
            metrics: activity.metrics,
          );
        }
        for (final stepId in steps) {
          await pathRepo.completeStep(uid: _uid, stepId: stepId);
        }

        // A new device reads users/{uid}/** and rehydrates the synced state.
        final result = await restoreRepo.restore(_uid);
        expect(result, isA<Success<RestoredState>>(), reason: reason);
        final state = result.valueOrNull!;

        // Restored streak matches the synced last-write-wins streak.
        expect(state.streak, _expectedStreak(activities), reason: reason);

        // Restored completed steps match exactly the set that was synced.
        expect(state.completedStepIds, steps.toSet(), reason: reason);
        expect(state.accountExists, isTrue, reason: reason);
      }
    });
  });
}
