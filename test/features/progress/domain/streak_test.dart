// Unit tests for the Streak read model used by the home streak flame
// indicator. (Requirement 3.7)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/streak.dart';

void main() {
  group('Streak', () {
    test('none is a zeroed, inactive streak', () {
      expect(Streak.none.current, 0);
      expect(Streak.none.longest, 0);
      expect(Streak.none.isActive, isFalse);
    });

    test('is active once the current run is at least one day', () {
      expect(const Streak(current: 1, longest: 1).isActive, isTrue);
      expect(const Streak(current: 7, longest: 9).isActive, isTrue);
      expect(const Streak(current: 0, longest: 5).isActive, isFalse);
    });

    test('values compare structurally', () {
      expect(
        const Streak(current: 3, longest: 5),
        equals(const Streak(current: 3, longest: 5)),
      );
      expect(
        const Streak(current: 3, longest: 5),
        isNot(equals(const Streak(current: 2, longest: 5))),
      );
    });
  });
}
