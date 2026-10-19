// Unit tests for WeeklySummaryRepository.watchCurrentWeek: it serves the
// persisted weeklySummaries/{isoWeek} document when present, and otherwise
// computes a live current-week fallback by aggregating the week's dailyActivity
// documents field-wise. (Requirement 7.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/data/weekly_summary_repository.dart';
import 'package:learnx/features/progress/domain/iso_week.dart';

void main() {
  const uid = 'learner-1';
  // A fixed Wednesday so the current ISO week is deterministic across runs.
  final now = DateTime.utc(2024, 3, 13, 10);
  final week = IsoWeek.of(now);

  late FakeFirebaseFirestore firestore;
  late WeeklySummaryRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = WeeklySummaryRepository(
      firestore: firestore,
      clock: () => now,
    );
  });

  test('serves the persisted weekly summary when it exists', () async {
    await firestore
        .doc(FirestorePaths.weeklySummaryDoc(uid, week.id))
        .set(<String, dynamic>{
          'timeSpentSec': 7200,
          'wordsLearned': 40,
          'mistakesFixed': 12,
        });

    final summary = await repository.readCurrentWeek(uid);

    expect(summary.timeSpentSec, 7200);
    expect(summary.wordsLearned, 40);
    expect(summary.mistakesFixed, 12);
  });

  test('falls back to zero when no summary and no activity exist', () async {
    final summary = await repository.readCurrentWeek(uid);

    expect(summary.timeSpentSec, 0);
    expect(summary.wordsLearned, 0);
    expect(summary.mistakesFixed, 0);
    expect(summary.generatedAt, isNull);
  });

  test('aggregates dailyActivity across the week as a live fallback', () async {
    // Seed two days within the current ISO week.
    final keys = week.dateKeys;
    await firestore
        .doc(FirestorePaths.dailyActivityDoc(uid, keys[0]))
        .set(<String, dynamic>{
          'activities': 2,
          'timeSpentSec': 600,
          'wordsLearned': 5,
          'mistakesFixed': 1,
        });
    await firestore
        .doc(FirestorePaths.dailyActivityDoc(uid, keys[2]))
        .set(<String, dynamic>{
          'activities': 3,
          'timeSpentSec': 900,
          'wordsLearned': 8,
          'mistakesFixed': 4,
        });

    final summary = await repository.readCurrentWeek(uid);

    // Field-wise sum of the two seeded days (Property 18 analogue).
    expect(summary.timeSpentSec, 1500);
    expect(summary.wordsLearned, 13);
    expect(summary.mistakesFixed, 5);
    // A live view carries no generatedAt until the scheduled function persists.
    expect(summary.generatedAt, isNull);
  });

  test('persisted summary takes precedence over dailyActivity', () async {
    await firestore
        .doc(FirestorePaths.dailyActivityDoc(uid, week.dateKeys[0]))
        .set(<String, dynamic>{'timeSpentSec': 999, 'wordsLearned': 99});
    await firestore
        .doc(FirestorePaths.weeklySummaryDoc(uid, week.id))
        .set(<String, dynamic>{
          'timeSpentSec': 10,
          'wordsLearned': 1,
          'mistakesFixed': 0,
        });

    final summary = await repository.readCurrentWeek(uid);

    expect(summary.timeSpentSec, 10);
    expect(summary.wordsLearned, 1);
  });

  test('watchCurrentWeek emits the live fallback first', () {
    expect(
      repository.watchCurrentWeek(uid).map((s) => s.timeSpentSec),
      emits(0),
    );
  });
}
