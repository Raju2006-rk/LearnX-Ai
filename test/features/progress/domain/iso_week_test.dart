// Unit tests for the IsoWeek helper: it produces the same YYYY-Www key and the
// same Monday->Sunday dailyActivity date keys as the server's weekly-summary
// function, so a live client view and the persisted summary agree. (Req 7.4)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/iso_week.dart';

void main() {
  test('formats the ISO week id as YYYY-Www with a zero-padded week', () {
    // 2024-01-04 is in ISO week 1.
    expect(IsoWeek.of(DateTime.utc(2024, 1, 4)).id, '2024-W01');
    // 2024-03-13 (Wednesday) is in ISO week 11.
    expect(IsoWeek.of(DateTime.utc(2024, 3, 13)).id, '2024-W11');
  });

  test('assigns late-December days to the next ISO year when applicable', () {
    // 2024-12-30 (Monday) belongs to ISO week 1 of 2025.
    expect(IsoWeek.of(DateTime.utc(2024, 12, 30)).id, '2025-W01');
  });

  test('monday is the UTC Monday opening the week', () {
    final week = IsoWeek.of(DateTime.utc(2024, 3, 13)); // Wednesday
    expect(week.monday, DateTime.utc(2024, 3, 11)); // the Monday
  });

  test('dateKeys are the seven Monday->Sunday yyyy-mm-dd ids', () {
    final week = IsoWeek.of(DateTime.utc(2024, 3, 13));
    expect(week.dateKeys, [
      '2024-03-11',
      '2024-03-12',
      '2024-03-13',
      '2024-03-14',
      '2024-03-15',
      '2024-03-16',
      '2024-03-17',
    ]);
  });

  test('every day of a week maps to the same ISO week id', () {
    final ids = <String>{
      for (var d = 11; d <= 17; d++) IsoWeek.of(DateTime.utc(2024, 3, d)).id,
    };
    expect(ids, {'2024-W11'});
  });
}
