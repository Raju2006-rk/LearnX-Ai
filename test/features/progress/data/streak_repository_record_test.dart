// Unit tests for StreakRepository.recordQualifyingActivity: the transactional
// streak update persists same-day no-op, consecutive-day increment, and gap
// reset to progress/main, preserving sibling fields. (Requirements 3.7, 7.1,
// 7.5)

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

  Future<Map<String, dynamic>?> readDoc() async {
    final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
    return snap.data();
  }

  test('first activity creates the document with a streak of 1', () async {
    final result = await repository.recordQualifyingActivity(uid, '2024-03-10');

    expect(result, const Streak(current: 1, longest: 1));

    final data = await readDoc();
    expect(data?['currentStreak'], 1);
    expect(data?['longestStreak'], 1);
    expect(data?['lastActivityDate'], '2024-03-10');
  });

  test('consecutive-day activity increments the persisted streak', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 4,
      'longestStreak': 9,
      'lastActivityDate': '2024-03-10',
    });

    final result = await repository.recordQualifyingActivity(uid, '2024-03-11');

    expect(result, const Streak(current: 5, longest: 9));

    final data = await readDoc();
    expect(data?['currentStreak'], 5);
    expect(data?['longestStreak'], 9);
    expect(data?['lastActivityDate'], '2024-03-11');
  });

  test('new longest run is persisted when current exceeds longest', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 9,
      'longestStreak': 9,
      'lastActivityDate': '2024-03-10',
    });

    final result = await repository.recordQualifyingActivity(uid, '2024-03-11');

    expect(result, const Streak(current: 10, longest: 10));
    final data = await readDoc();
    expect(data?['longestStreak'], 10);
  });

  test('a gap resets current to 1 and preserves longest', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 7,
      'longestStreak': 12,
      'lastActivityDate': '2024-03-10',
    });

    final result = await repository.recordQualifyingActivity(uid, '2024-03-20');

    expect(result, const Streak(current: 1, longest: 12));
    final data = await readDoc();
    expect(data?['currentStreak'], 1);
    expect(data?['longestStreak'], 12);
    expect(data?['lastActivityDate'], '2024-03-20');
  });

  test(
    'same-day activity is a no-op and leaves the document unchanged',
    () async {
      await firestore.doc(FirestorePaths.progressDoc(uid)).set(
        <String, dynamic>{
          'currentStreak': 4,
          'longestStreak': 9,
          'lastActivityDate': '2024-03-10',
          'dailyGoal': <String, dynamic>{'day': 3, 'targetPerDay': 2},
        },
      );

      final result = await repository.recordQualifyingActivity(
        uid,
        '2024-03-10',
      );

      expect(result, const Streak(current: 4, longest: 9));
      final data = await readDoc();
      expect(data?['currentStreak'], 4);
      expect(data?['longestStreak'], 9);
      expect(data?['lastActivityDate'], '2024-03-10');
    },
  );

  test('update preserves sibling fields (dailyGoal, badges)', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 2,
      'longestStreak': 2,
      'lastActivityDate': '2024-03-10',
      'dailyGoal': <String, dynamic>{'day': 2, 'targetPerDay': 3},
      'badges': <Map<String, dynamic>>[
        <String, dynamic>{'tier': 'bronze', 'milestone': 'streak-3'},
      ],
    });

    await repository.recordQualifyingActivity(uid, '2024-03-11');

    final data = await readDoc();
    expect(data?['currentStreak'], 3);
    expect(data?['dailyGoal'], <String, dynamic>{'day': 2, 'targetPerDay': 3});
    expect(data?['badges'], <Map<String, dynamic>>[
      <String, dynamic>{'tier': 'bronze', 'milestone': 'streak-3'},
    ]);
  });

  test(
    'stamps updatedAt for last-write-wins sync on a streak advance',
    () async {
      // A write that participates in sync must carry updatedAt so a replayed
      // offline write resolves against server state. (Requirement 8.2)
      await repository.recordQualifyingActivity(uid, '2024-03-10');

      final data = await readDoc();
      expect(data?.containsKey('updatedAt'), isTrue);
      expect(data?['updatedAt'], isNotNull);
    },
  );

  test('clamps an inconsistent stored document before updating', () async {
    // longest < current is impossible but could be stored by a buggy write;
    // the read clamps longest up to current (6) before applying the rule.
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 6,
      'longestStreak': 1,
      'lastActivityDate': '2024-03-10',
    });

    final result = await repository.recordQualifyingActivity(uid, '2024-03-11');

    expect(result, const Streak(current: 7, longest: 7));
  });
}
