// Unit tests for StreakRepository.recordGoalAndActivity and watchDailyGoal:
// the goal tracker advances once per new calendar day (same-day no-op) while
// every qualifying activity ticks today's dailyActivity metrics, preserving
// sibling fields on progress/main. (Requirements 7.2, 7.5)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/data/streak_repository.dart';
import 'package:learnx/features/progress/domain/daily_goal.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;
  late StreakRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = StreakRepository(firestore: firestore);
  });

  Future<Map<String, dynamic>?> readProgress() async {
    final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
    return snap.data();
  }

  Future<Map<String, dynamic>?> readActivity(String date) async {
    final snap = await firestore
        .doc(FirestorePaths.dailyActivityDoc(uid, date))
        .get();
    return snap.data();
  }

  group('recordGoalAndActivity', () {
    test('first activity starts the tracker at Day 1', () async {
      final goal = await repository.recordGoalAndActivity(uid, '2024-03-10');

      expect(goal, const DailyGoal(day: 1));
      final data = await readProgress();
      expect(data?['dailyGoal'], <String, dynamic>{
        'day': 1,
        'targetPerDay': DailyGoal.defaultTargetPerDay,
      });
    });

    test('ticks today\'s activity metrics', () async {
      await repository.recordGoalAndActivity(
        uid,
        '2024-03-10',
        metrics: const ActivityMetrics(
          timeSpentSec: 120,
          wordsLearned: 4,
          mistakesFixed: 2,
        ),
      );

      final activity = await readActivity('2024-03-10');
      expect(activity?['activities'], 1);
      expect(activity?['timeSpentSec'], 120);
      expect(activity?['wordsLearned'], 4);
      expect(activity?['mistakesFixed'], 2);
    });

    test('carries updatedAt on both progress and activity writes', () async {
      // Both the goal advance on progress/main and the dailyActivity roll-up
      // participate in sync, so each must carry updatedAt. (Requirement 8.2)
      await repository.recordGoalAndActivity(uid, '2024-03-10');

      final progress = await readProgress();
      expect(progress?['updatedAt'], isNotNull);

      final activity = await readActivity('2024-03-10');
      expect(activity?['updatedAt'], isNotNull);
    });

    test('a new calendar day advances the tracker', () async {
      await firestore.doc(FirestorePaths.progressDoc(uid)).set(
        <String, dynamic>{
          'lastActivityDate': '2024-03-10',
          'dailyGoal': <String, dynamic>{'day': 4, 'targetPerDay': 2},
        },
      );

      final goal = await repository.recordGoalAndActivity(uid, '2024-03-11');

      expect(goal, const DailyGoal(day: 5, targetPerDay: 2));
    });

    test(
      'same-day repeat does not advance the day but still ticks metrics',
      () async {
        await firestore.doc(FirestorePaths.progressDoc(uid)).set(
          <String, dynamic>{
            'lastActivityDate': '2024-03-10',
            'dailyGoal': <String, dynamic>{'day': 3, 'targetPerDay': 1},
          },
        );

        // Two activities on the same day.
        await repository.recordGoalAndActivity(
          uid,
          '2024-03-10',
          metrics: const ActivityMetrics(wordsLearned: 1),
        );
        final goal = await repository.recordGoalAndActivity(
          uid,
          '2024-03-10',
          metrics: const ActivityMetrics(wordsLearned: 1),
        );

        // Day did not advance (same day).
        expect(goal, const DailyGoal(day: 3));
        final progress = await readProgress();
        expect((progress?['dailyGoal'] as Map)['day'], 3);

        // But both activities counted toward the day's metrics.
        final activity = await readActivity('2024-03-10');
        expect(activity?['activities'], 2);
        expect(activity?['wordsLearned'], 2);
      },
    );

    test(
      'preserves streak/badges sibling fields when advancing the goal',
      () async {
        await firestore.doc(FirestorePaths.progressDoc(uid)).set(
          <String, dynamic>{
            'currentStreak': 5,
            'longestStreak': 9,
            'lastActivityDate': '2024-03-10',
            'dailyGoal': <String, dynamic>{'day': 5, 'targetPerDay': 1},
            'badges': <Map<String, dynamic>>[
              <String, dynamic>{'tier': 'bronze', 'milestone': 'streak-3'},
            ],
          },
        );

        await repository.recordGoalAndActivity(uid, '2024-03-11');

        final data = await readProgress();
        expect(data?['currentStreak'], 5);
        expect(data?['longestStreak'], 9);
        expect((data?['dailyGoal'] as Map)['day'], 6);
        expect(data?['badges'], <Map<String, dynamic>>[
          <String, dynamic>{'tier': 'bronze', 'milestone': 'streak-3'},
        ]);
      },
    );
  });

  group('watchDailyGoal', () {
    test('emits DailyGoal.initial for a learner with no document', () {
      expect(repository.watchDailyGoal(uid), emits(DailyGoal.initial));
    });

    test('emits the stored, clamped goal', () async {
      await firestore.doc(FirestorePaths.progressDoc(uid)).set(
        <String, dynamic>{
          'dailyGoal': <String, dynamic>{'day': 12, 'targetPerDay': 2},
        },
      );

      expect(
        repository.watchDailyGoal(uid),
        emits(const DailyGoal(day: 12, targetPerDay: 2)),
      );
    });
  });
}
