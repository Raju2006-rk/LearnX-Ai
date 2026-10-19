import 'package:flutter/foundation.dart';

/// Client-side ISO-8601 week identity, mirroring the server's weekly-summary
/// function so a `weeklySummaries/{isoWeek}` document and a live client-computed
/// current-week view agree on the same `YYYY-Www` key and the same set of
/// `dailyActivity/{yyyy-mm-dd}` days. (Requirement 7.4)
///
/// ISO weeks start on Monday and week 1 is the week containing the year's first
/// Thursday, so the ISO week-numbering [year] can differ from the calendar year
/// for dates in late December or early January. All arithmetic is done in UTC so
/// the result is independent of the device timezone, exactly matching the
/// scheduled Cloud Function (`functions/src/scheduled/weekly_summary.ts`).
@immutable
class IsoWeek {
  const IsoWeek({required this.year, required this.week})
    : assert(week >= 1 && week <= 53, 'ISO week number must be 1..53');

  /// The ISO week-numbering year (may differ from the calendar year near Jan 1).
  final int year;

  /// The ISO week number, 1–53.
  final int week;

  /// The ISO week that [date] falls in.
  factory IsoWeek.of(DateTime date) {
    // Work on a UTC-midnight copy so the day-of-week math ignores any time
    // component and the device timezone.
    final d = DateTime.utc(date.year, date.month, date.day);
    // Monday = 0 … Sunday = 6.
    final dayNum = (d.weekday + 6) % 7;
    // Shift to the Thursday of this week; that Thursday's year is the ISO year.
    final thursday = d.add(Duration(days: 3 - dayNum));
    final isoYear = thursday.year;
    // First Thursday of the ISO year.
    final jan4 = DateTime.utc(isoYear, 1, 4);
    final jan4DayNum = (jan4.weekday + 6) % 7;
    final firstThursday = jan4.add(Duration(days: 3 - jan4DayNum));
    final week =
        1 + (thursday.difference(firstThursday).inDays / 7).round();
    return IsoWeek(year: isoYear, week: week);
  }

  /// The `YYYY-Www` document id for this week, e.g. `2024-W03`. Matches the
  /// key the scheduled function writes under `weeklySummaries/{isoWeek}`.
  String get id {
    final w = week < 10 ? '0$week' : '$week';
    return '$year-W$w';
  }

  /// The Monday (UTC midnight) that opens this ISO week.
  DateTime get monday {
    // Jan 4 is always in ISO week 1; walk back to that week's Monday, then
    // forward whole weeks to reach this week's Monday.
    final jan4 = DateTime.utc(year, 1, 4);
    final jan4DayNum = (jan4.weekday + 6) % 7;
    final week1Monday = jan4.subtract(Duration(days: jan4DayNum));
    return week1Monday.add(Duration(days: (week - 1) * 7));
  }

  /// The seven `yyyy-mm-dd` daily-activity document ids (Monday → Sunday) that
  /// belong to this week, used to aggregate a live current-week view from
  /// `dailyActivity`.
  List<String> get dateKeys {
    final start = monday;
    return List<String>.generate(
      7,
      (i) => _dateKey(start.add(Duration(days: i))),
      growable: false,
    );
  }

  /// Formats a date as the `yyyy-mm-dd` daily-activity document id (UTC).
  static String _dateKey(DateTime date) {
    final mm = date.month < 10 ? '0${date.month}' : '${date.month}';
    final dd = date.day < 10 ? '0${date.day}' : '${date.day}';
    return '${date.year}-$mm-$dd';
  }

  @override
  bool operator ==(Object other) =>
      other is IsoWeek && other.year == year && other.week == week;

  @override
  int get hashCode => Object.hash(year, week);

  @override
  String toString() => 'IsoWeek($id)';
}
