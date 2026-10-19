import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/firestore_paths.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/iso_week.dart';
import '../domain/weekly_summary.dart';

/// Reads the learner's [WeeklySummary] for an ISO week.
///
/// The authoritative summary is the `users/{uid}/weeklySummaries/{isoWeek}`
/// document written by the scheduled Cloud Function (task 3.10). For the
/// *current* week that document usually does not exist yet — the function only
/// rolls up completed weeks — so this repository computes a **live fallback**
/// by aggregating the week's `users/{uid}/progress/main/dailyActivity/{yyyy-mm-dd}`
/// documents field-wise, mirroring the server's aggregation so the live view
/// and the eventual persisted summary agree. (Requirement 7.4)
///
/// Both the persisted read and the fallback go through the DTO layer and the
/// domain's flooring (`WeeklySummary.fromDto`), so a malformed stored negative
/// can never surface as an invalid summary.
class WeeklySummaryRepository {
  WeeklySummaryRepository({
    required FirebaseFirestore firestore,
    DateTime Function() clock = DateTime.now,
  }) : _firestore = firestore,
       _clock = clock;

  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  /// Watches the learner's current-week [WeeklySummary].
  ///
  /// Emits the persisted `weeklySummaries/{isoWeek}` document when it exists;
  /// otherwise falls back to a live aggregate of the current week's
  /// `dailyActivity`. The stream re-emits whenever the persisted summary
  /// changes (e.g. the scheduled function later writes it), swapping the live
  /// fallback out for the authoritative value.
  Stream<WeeklySummary> watchCurrentWeek(String uid) {
    final week = IsoWeek.of(_clock());
    return _firestore
        .doc(FirestorePaths.weeklySummaryDoc(uid, week.id))
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.exists && snapshot.data() != null) {
            return WeeklySummary.fromDto(
              WeeklySummaryDto.fromMap(snapshot.data()!),
            );
          }
          return _liveFallback(uid, week);
        });
  }

  /// Reads the learner's summary for [week] once.
  ///
  /// Returns the persisted summary when present, otherwise the live fallback
  /// aggregated from that week's `dailyActivity` documents.
  Future<WeeklySummary> readWeek(String uid, IsoWeek week) async {
    final snapshot = await _firestore
        .doc(FirestorePaths.weeklySummaryDoc(uid, week.id))
        .get();
    if (snapshot.exists && snapshot.data() != null) {
      return WeeklySummary.fromDto(WeeklySummaryDto.fromMap(snapshot.data()!));
    }
    return _liveFallback(uid, week);
  }

  /// Reads the learner's current-week summary once (persisted or live).
  Future<WeeklySummary> readCurrentWeek(String uid) =>
      readWeek(uid, IsoWeek.of(_clock()));

  /// Aggregates the seven `dailyActivity/{yyyy-mm-dd}` documents of [week] into
  /// a live [WeeklySummary], summing `timeSpentSec`, `wordsLearned`, and
  /// `mistakesFixed`. Missing days contribute nothing, so the live total always
  /// equals the field-wise sum of the days that exist — matching the server's
  /// aggregation (Property 18). The resulting summary has a `null` `generatedAt`
  /// to mark it as a live, not-yet-persisted view.
  Future<WeeklySummary> _liveFallback(String uid, IsoWeek week) async {
    final snapshots = await Future.wait(
      week.dateKeys.map(
        (key) =>
            _firestore.doc(FirestorePaths.dailyActivityDoc(uid, key)).get(),
      ),
    );

    var timeSpentSec = 0;
    var wordsLearned = 0;
    var mistakesFixed = 0;
    for (final snapshot in snapshots) {
      if (!snapshot.exists || snapshot.data() == null) continue;
      final day = DailyActivityDto.fromMap(snapshot.data()!);
      timeSpentSec += day.timeSpentSec < 0 ? 0 : day.timeSpentSec;
      wordsLearned += day.wordsLearned < 0 ? 0 : day.wordsLearned;
      mistakesFixed += day.mistakesFixed < 0 ? 0 : day.mistakesFixed;
    }

    // generatedAt left null: this is a live, client-computed view that the
    // scheduled function has not yet persisted.
    return WeeklySummary(
      timeSpentSec: timeSpentSec,
      wordsLearned: wordsLearned,
      mistakesFixed: mistakesFixed,
    );
  }
}
