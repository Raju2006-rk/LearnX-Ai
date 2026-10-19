// Unit tests for BadgeRepository.evaluateAndAward: it appends newly-earned
// badges to progress/main.badges[] transactionally, is idempotent per
// milestone (never re-awards a recorded milestone), and preserves sibling
// streak/goal fields. (Requirement 7.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/config/remote_config.dart' as config;
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/data/badge_repository.dart';
import 'package:learnx/features/progress/domain/badge.dart';

void main() {
  const uid = 'learner-1';

  const milestones = <config.BadgeMilestone>[
    config.BadgeMilestone(
      id: 'streak-3',
      tier: config.BadgeTier.bronze,
      threshold: 3,
    ),
    config.BadgeMilestone(
      id: 'streak-7',
      tier: config.BadgeTier.silver,
      threshold: 7,
    ),
    config.BadgeMilestone(
      id: 'streak-15',
      tier: config.BadgeTier.gold,
      threshold: 15,
    ),
  ];

  late FakeFirebaseFirestore firestore;
  late BadgeRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = BadgeRepository(
      firestore: firestore,
      milestones: () => milestones,
    );
  });

  Future<Map<String, dynamic>?> readDoc() async {
    final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
    return snap.data();
  }

  List<Map<String, dynamic>> badgesOf(Map<String, dynamic>? data) {
    return (data?['badges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  test('awards Bronze when the streak first reaches 3, creating the doc', () async {
    final at = DateTime.utc(2024, 3, 11, 8);
    final result = await repository.evaluateAndAward(uid, 3, awardedAt: at);

    expect(result.hasNewAwards, isTrue);
    expect(result.newlyAwarded.single.tier, BadgeTier.bronze);

    final badges = badgesOf(await readDoc());
    expect(badges.length, 1);
    expect(badges.single['tier'], 'bronze');
    expect(badges.single['milestone'], 'streak-3');
  });

  test('awards all crossed milestones at once', () async {
    final result = await repository.evaluateAndAward(uid, 15);

    expect(
      result.newlyAwarded.map((b) => b.tier),
      [BadgeTier.bronze, BadgeTier.silver, BadgeTier.gold],
    );
    final badges = badgesOf(await readDoc());
    expect(badges.map((b) => b['milestone']), [
      'streak-3',
      'streak-7',
      'streak-15',
    ]);
  });

  test('does not re-award a milestone already recorded (idempotent)', () async {
    // Bronze already recorded from a prior pass.
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 7,
      'longestStreak': 7,
      'badges': <Map<String, dynamic>>[
        <String, dynamic>{'tier': 'bronze', 'milestone': 'streak-3'},
      ],
    });

    final result = await repository.evaluateAndAward(uid, 7);

    // Only Silver is newly awarded; Bronze is left as-is.
    expect(result.newlyAwarded.map((b) => b.milestone), ['streak-7']);
    final badges = badgesOf(await readDoc());
    expect(badges.map((b) => b['milestone']), ['streak-3', 'streak-7']);
  });

  test('a repeated evaluation on an unchanged value writes nothing', () async {
    await repository.evaluateAndAward(uid, 7);
    final afterFirst = badgesOf(await readDoc());

    final result = await repository.evaluateAndAward(uid, 7);

    expect(result.hasNewAwards, isFalse);
    final afterSecond = badgesOf(await readDoc());
    // Exactly the same badges — no duplicates appended.
    expect(afterSecond.map((b) => b['milestone']),
        afterFirst.map((b) => b['milestone']));
    expect(afterSecond.length, 2);
  });

  test('awards nothing below the lowest threshold', () async {
    final result = await repository.evaluateAndAward(uid, 2);

    expect(result.hasNewAwards, isFalse);
    // No document is created when there is nothing to award.
    expect(await readDoc(), isNull);
  });

  test('preserves sibling streak and dailyGoal fields when awarding', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 3,
      'longestStreak': 5,
      'lastActivityDate': '2024-03-11',
      'dailyGoal': <String, dynamic>{'day': 3, 'targetPerDay': 2},
    });

    await repository.evaluateAndAward(uid, 3);

    final data = await readDoc();
    expect(data?['currentStreak'], 3);
    expect(data?['longestStreak'], 5);
    expect(data?['lastActivityDate'], '2024-03-11');
    expect(data?['dailyGoal'], <String, dynamic>{'day': 3, 'targetPerDay': 2});
    expect(badgesOf(data).single['milestone'], 'streak-3');
  });

  test('ignores a corrupt stored badge entry without crashing', () async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'badges': <Map<String, dynamic>>[
        <String, dynamic>{'tier': 'platinum', 'milestone': 'bogus'},
      ],
    });

    // Streak of 3 should still award Bronze; the corrupt entry is dropped from
    // the read model, so Bronze is treated as not-yet-awarded.
    final result = await repository.evaluateAndAward(uid, 3);
    expect(result.newlyAwarded.single.milestone, 'streak-3');
  });
}
