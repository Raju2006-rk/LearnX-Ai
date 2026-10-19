import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/shared/models/dtos/firestore_converters.dart';

void main() {
  group('dateTimeFromFirestore', () {
    test('reads a Firestore Timestamp', () {
      final dt = DateTime.utc(2024, 1, 2, 3, 4, 5);
      expect(dateTimeFromFirestore(Timestamp.fromDate(dt)), dt);
    });

    test('passes through a DateTime', () {
      final dt = DateTime.utc(2024, 5, 6);
      expect(dateTimeFromFirestore(dt), dt);
    });

    test('parses an ISO-8601 string', () {
      expect(
        dateTimeFromFirestore('2024-01-02T03:04:05.000Z'),
        DateTime.utc(2024, 1, 2, 3, 4, 5),
      );
    });

    test('reads epoch millis as UTC', () {
      expect(
        dateTimeFromFirestore(0),
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('returns null for absent or unrecognized values', () {
      expect(dateTimeFromFirestore(null), isNull);
      expect(dateTimeFromFirestore(const Object()), isNull);
      expect(dateTimeFromFirestore('not-a-date'), isNull);
    });
  });

  group('timestampFromDateTime', () {
    test('round-trips a DateTime through Timestamp', () {
      final dt = DateTime.utc(2024, 7, 8, 9, 10, 11);
      final ts = timestampFromDateTime(dt);
      expect(ts, isA<Timestamp>());
      // Timestamp.toDate() yields local time; compare the same instant in UTC.
      expect(ts!.toDate().toUtc(), dt);
    });

    test('preserves null', () {
      expect(timestampFromDateTime(null), isNull);
    });
  });

  group('primitive readers', () {
    test('stringOr and stringOrNull', () {
      expect(stringOr('x'), 'x');
      expect(stringOr(null), '');
      expect(stringOr(42, 'fallback'), 'fallback');
      expect(stringOrNull('y'), 'y');
      expect(stringOrNull(7), isNull);
    });

    test('intOr handles int, num, numeric string, and fallback', () {
      expect(intOr(5), 5);
      expect(intOr(5.9), 5);
      expect(intOr('12'), 12);
      expect(intOr('nope', -1), -1);
      expect(intOr(null), 0);
    });

    test('boolOr', () {
      expect(boolOr(true), isTrue);
      expect(boolOr(null), isFalse);
      expect(boolOr('true', true), isTrue);
    });

    test('stringListFrom drops non-strings', () {
      expect(stringListFrom(['a', 1, 'b', null]), ['a', 'b']);
      expect(stringListFrom(null), isEmpty);
    });

    test('mapListFrom coerces nested maps', () {
      final result = mapListFrom([
        {'k': 1},
        'skip',
        {'j': 2},
      ]);
      expect(result, [
        {'k': 1},
        {'j': 2},
      ]);
    });

    test('mapOrNull', () {
      expect(mapOrNull({'a': 1}), {'a': 1});
      expect(mapOrNull(null), isNull);
      expect(mapOrNull('x'), isNull);
    });
  });
}
