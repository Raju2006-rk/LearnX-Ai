import 'package:flutter/foundation.dart';

import '../../../shared/models/dtos/dtos.dart';

/// A learner's aggregated activity for one ISO week, mirroring a
/// `users/{uid}/weeklySummaries/{isoWeek}` document. (Requirement 7.4)
///
/// The summary is produced by a scheduled Cloud Function that rolls up
/// `dailyActivity/*` (task 3.10); the client can also compute a live
/// current-week view from `dailyActivity`. This domain type is the shared
/// read model the weekly-summary view (task 10.4) renders: it carries the
/// three headline metrics — time spent, words learned, mistakes fixed —
/// alongside when the summary was generated.
@immutable
class WeeklySummary {
  const WeeklySummary({
    this.timeSpentSec = 0,
    this.wordsLearned = 0,
    this.mistakesFixed = 0,
    this.generatedAt,
  }) : assert(timeSpentSec >= 0, 'timeSpentSec cannot be negative'),
       assert(wordsLearned >= 0, 'wordsLearned cannot be negative'),
       assert(mistakesFixed >= 0, 'mistakesFixed cannot be negative');

  /// An empty summary: no activity recorded. Used as the safe default for a
  /// week with no stored aggregate yet.
  static const WeeklySummary empty = WeeklySummary();

  /// Builds a [WeeklySummary] from its DTO, flooring each metric at zero so a
  /// malformed stored negative can never surface as an invalid summary.
  factory WeeklySummary.fromDto(WeeklySummaryDto dto) => WeeklySummary(
    timeSpentSec: dto.timeSpentSec < 0 ? 0 : dto.timeSpentSec,
    wordsLearned: dto.wordsLearned < 0 ? 0 : dto.wordsLearned,
    mistakesFixed: dto.mistakesFixed < 0 ? 0 : dto.mistakesFixed,
    generatedAt: dto.generatedAt,
  );

  /// Total time spent learning during the week, in seconds.
  final int timeSpentSec;

  /// The number of new words learned during the week.
  final int wordsLearned;

  /// The number of grammar mistakes the learner corrected during the week.
  final int mistakesFixed;

  /// When the summary was generated, or `null` for a live client-computed
  /// current-week view that has not been persisted by the scheduled function.
  final DateTime? generatedAt;

  /// Serializes this summary back to its DTO for persistence.
  WeeklySummaryDto toDto() => WeeklySummaryDto(
    timeSpentSec: timeSpentSec,
    wordsLearned: wordsLearned,
    mistakesFixed: mistakesFixed,
    generatedAt: generatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is WeeklySummary &&
      other.timeSpentSec == timeSpentSec &&
      other.wordsLearned == wordsLearned &&
      other.mistakesFixed == mistakesFixed &&
      other.generatedAt == generatedAt;

  @override
  int get hashCode =>
      Object.hash(timeSpentSec, wordsLearned, mistakesFixed, generatedAt);

  @override
  String toString() =>
      'WeeklySummary(timeSpentSec: $timeSpentSec, '
      'wordsLearned: $wordsLearned, mistakesFixed: $mistakesFixed)';
}
