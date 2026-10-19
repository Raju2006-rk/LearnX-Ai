// Unit tests for StreakRepository.watchStreak: it maps the learner's
// progress/main document to a Streak, defaults to Streak.none when absent, and
// defensively clamps inconsistent stored values. (Requirement 3.7)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/data/streak_repository.dart';
import 'package:learnx/features/progress/domain/streak.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;
  late StreakRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = StreakRepository(firestore: firestore);
  });

  test('emits Streak.none when no progress document exists', () {
    expect(repository.watchStreak(uid), emits(Streak.none));
  });

  test('maps persisted current/longest streak', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 4,
      'longestStreak': 9,
    });

    expect(
      repository.watchStreak(uid),
      emits(const Streak(current: 4, longest: 9)),
    );
  });

  test('clamps a negative current streak to zero', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': -3,
      'longestStreak': 2,
    });

    expect(
      repository.watchStreak(uid),
      emits(const Streak(current: 0, longest: 2)),
    );
  });

  test(
    'lifts longest to at least current when stored inconsistently',
    () async {
      await firestore.doc(FirestorePaths.progressDoc(uid)).set(
        <String, dynamic>{'currentStreak': 6, 'longestStreak': 1},
      );

      expect(
        repository.watchStreak(uid),
        emits(const Streak(current: 6, longest: 6)),
      );
    },
  );

  // Offline progress writes and last-write-wins sync: streak and daily-goal /
  // daily-activity updates run as transactional read-modify-writes that carry
  // a server `updatedAt`, so they queue via Firestore offline persistence,
  // replay on reconnect, and reconcile against server state. (Requirement 8.2)
  group('recordQualifyingActivity transactional streak update (Req 8.2)', () {
    Future<Map<String, dynamic>?> readProgress() async {
      final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
      return snap.data();
    }

    test(
      'creates progress/main with a server updatedAt on first activity',
      () async {
        final streak = await repository.recordQualifyingActivity(
          uid,
          '2024-06-01',
        );

        expect(streak, const Streak(current: 1, longest: 1));
        final data = await readProgress();
        expect(data?['currentStreak'], 1);
        expect(data?['longestStreak'], 1);
        expect(data?['lastActivityDate'], '2024-06-01');
        // Carries a server timestamp for last-write-wins resolution.
        expect(data?['updatedAt'], isNotNull);
      },
    );

    test(
      'read-modify-write increments against stored state on a consecutive day',
      () async {
        // Simulate server state the replayed write must reconcile against.
        await firestore.doc(FirestorePaths.progressDoc(uid)).set(
          <String, dynamic>{
            'currentStreak': 3,
            'longestStreak': 5,
            'lastActivityDate': '2024-06-01',
          },
        );

        final streak = await repository.recordQualifyingActivity(
          uid,
          '2024-06-02',
        );

        // Incremented from the value read in the transaction (3 -> 4), not
        // blindly reset; longest is preserved as max(5, 4).
        expect(streak, const Streak(current: 4, longest: 5));
        final data = await readProgress();
        expect(data?['currentStreak'], 4);
        expect(data?['longestStreak'], 5);
        expect(data?['updatedAt'], isNotNull);
      },
    );

    test('a gap day resets the current run to one', () async {
      await firestore.doc(FirestorePaths.progressDoc(uid)).set(
        <String, dynamic>{
          'currentStreak': 4,
          'longestStreak': 4,
          'lastActivityDate': '2024-06-01',
        },
      );

      final streak = await repository.recordQualifyingActivity(
        uid,
        '2024-06-05',
      );

      expect(streak, const Streak(current: 1, longest: 4));
    });

    test(
      'a same-day repeat is a no-op and leaves the document untouched',
      () async {
        await firestore
            .doc(FirestorePaths.progressDoc(uid))
            .set(<String, dynamic>{
              'currentStreak': 2,
              'longestStreak': 7,
              'lastActivityDate': '2024-06-01',
              'note': 'kept',
            });

        final streak = await repository.recordQualifyingActivity(
          uid,
          '2024-06-01',
        );

        expect(streak, const Streak(current: 2, longest: 7));
        final data = await readProgress();
        expect(data?['currentStreak'], 2);
        expect(data?['note'], 'kept');
      },
    );

    test(
      'updates in place, preserving sibling fields on progress/main',
      () async {
        await firestore.doc(FirestorePaths.progressDoc(uid)).set(
          <String, dynamic>{
            'currentStreak': 1,
            'longestStreak': 1,
            'lastActivityDate': '2024-06-01',
            'badges': <dynamic>['bronze'],
          },
        );

        await repository.recordQualifyingActivity(uid, '2024-06-02');

        final data = await readProgress();
        expect(data?['currentStreak'], 2);
        // The sibling badges field survives the targeted update.
        expect(data?['badges'], <dynamic>['bronze']);
      },
    );
  });

  group('recordGoalAndActivity transactional increments (Req 8.2, 7.5)', () {
    Future<Map<String, dynamic>?> readActivity(String date) async {
      final snap = await firestore
          .doc(FirestorePaths.dailyActivityDoc(uid, date))
          .get();
      return snap.data();
    }

    test(
      'creates the daily-activity counters with a server updatedAt',
      () async {
        await repository.recordGoalAndActivity(
          uid,
          '2024-06-01',
          metrics: const ActivityMetrics(
            timeSpentSec: 30,
            wordsLearned: 2,
            mistakesFixed: 1,
          ),
        );

        final data = await readActivity('2024-06-01');
        expect(data?['activities'], 1);
        expect(data?['timeSpentSec'], 30);
        expect(data?['wordsLearned'], 2);
        expect(data?['mistakesFixed'], 1);
        expect(data?['updatedAt'], isNotNull);
      },
    );

    test(
      'read-modify-write accumulates counters against stored server state',
      () async {
        // Pre-existing server counters a replayed offline write accumulates on.
        await firestore
            .doc(FirestorePaths.dailyActivityDoc(uid, '2024-06-01'))
            .set(<String, dynamic>{
              'activities': 5,
              'timeSpentSec': 100,
              'wordsLearned': 4,
              'mistakesFixed': 2,
            });

        await repository.recordGoalAndActivity(
          uid,
          '2024-06-01',
          metrics: const ActivityMetrics(
            timeSpentSec: 10,
            wordsLearned: 1,
            mistakesFixed: 3,
          ),
        );

        final data = await readActivity('2024-06-01');
        // Each counter is the stored value plus this activity's contribution,
        // not an overwrite: activities 5->6, time 100->110, words 4->5,
        // mistakes 2->5.
        expect(data?['activities'], 6);
        expect(data?['timeSpentSec'], 110);
        expect(data?['wordsLearned'], 5);
        expect(data?['mistakesFixed'], 5);
      },
    );

    test('a same-day repeat still ticks the activity counters', () async {
      await repository.recordGoalAndActivity(uid, '2024-06-01');
      await repository.recordGoalAndActivity(uid, '2024-06-01');

      final data = await readActivity('2024-06-01');
      // Both activities count toward the day's totals even though the goal day
      // does not advance a second time.
      expect(data?['activities'], 2);
    });

    test(
      'advances the daily-goal day and carries a server updatedAt',
      () async {
        final goal = await repository.recordGoalAndActivity(uid, '2024-06-01');

        expect(goal.day, greaterThanOrEqualTo(1));
        final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
        expect(snap.data()?['dailyGoal'], isNotNull);
        expect(snap.data()?['updatedAt'], isNotNull);
      },
    );
  });
}
