// Unit tests for the WeeklySummary domain type: DTO mapping, flooring
// negative metrics, and the empty default. (Requirement 7.4)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/weekly_summary.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

void main() {
  test('empty is a zeroed summary', () {
    expect(WeeklySummary.empty.timeSpentSec, 0);
    expect(WeeklySummary.empty.wordsLearned, 0);
    expect(WeeklySummary.empty.mistakesFixed, 0);
    expect(WeeklySummary.empty.generatedAt, isNull);
  });

  test('maps metrics and generatedAt from its DTO', () {
    final generatedAt = DateTime.utc(2024, 3, 11);
    final summary = WeeklySummary.fromDto(
      WeeklySummaryDto(
        timeSpentSec: 3600,
        wordsLearned: 25,
        mistakesFixed: 7,
        generatedAt: generatedAt,
      ),
    );

    expect(summary.timeSpentSec, 3600);
    expect(summary.wordsLearned, 25);
    expect(summary.mistakesFixed, 7);
    expect(summary.generatedAt, generatedAt);
  });

  test('floors negative stored metrics at zero', () {
    final summary = WeeklySummary.fromDto(
      const WeeklySummaryDto(
        timeSpentSec: -10,
        wordsLearned: -1,
        mistakesFixed: -5,
      ),
    );

    expect(summary.timeSpentSec, 0);
    expect(summary.wordsLearned, 0);
    expect(summary.mistakesFixed, 0);
  });

  test('round-trips through its DTO', () {
    const summary = WeeklySummary(
      timeSpentSec: 1200,
      wordsLearned: 12,
      mistakesFixed: 3,
    );

    expect(WeeklySummary.fromDto(summary.toDto()), summary);
  });
}
