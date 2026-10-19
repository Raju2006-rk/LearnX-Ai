// Unit tests for the pure PlacementEngine band ladder and settle logic.
// (Requirements 2.4, 2.5)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/onboarding/domain/placement_engine.dart';

void main() {
  group('CefrLevel', () {
    test('ladder order maps indices 0..4 to A1..C1', () {
      expect(CefrLevel.values.map((l) => l.wireValue).toList(),
          ['A1', 'A2', 'B1', 'B2', 'C1']);
      expect(CefrLevel.a1.index, 0);
      expect(CefrLevel.c1.index, 4);
    });

    test('fromWire round-trips known values and drops unknown', () {
      expect(CefrLevel.fromWire('B1'), CefrLevel.b1);
      expect(CefrLevel.fromWire('Z9'), isNull);
      expect(CefrLevel.fromWire(null), isNull);
    });
  });

  group('PlacementEngine ladder', () {
    test('initial session starts at A2 with nothing asked', () {
      final engine = PlacementEngine.initial();
      expect(engine.currentBand, CefrLevel.a2);
      expect(engine.asked, 0);
      expect(engine.isComplete, isFalse);
    });

    test('a correct answer steps the band up, a wrong answer steps it down',
        () {
      final engine = PlacementEngine.initial();
      expect(engine.answer(correct: true).currentBand, CefrLevel.b1);
      expect(engine.answer(correct: false).currentBand, CefrLevel.a1);
    });

    test('band never rises above C1 on repeated correct answers', () {
      var engine = PlacementEngine.initial(totalQuestions: 100);
      for (var i = 0; i < 20; i++) {
        engine = engine.answer(correct: true);
        expect(engine.currentBand.index, lessThanOrEqualTo(CefrLevel.c1.index));
      }
      expect(engine.currentBand, CefrLevel.c1);
    });

    test('band never drops below A1 on repeated wrong answers', () {
      var engine = PlacementEngine.initial(totalQuestions: 100);
      for (var i = 0; i < 20; i++) {
        engine = engine.answer(correct: false);
        expect(
            engine.currentBand.index, greaterThanOrEqualTo(CefrLevel.a1.index));
      }
      expect(engine.currentBand, CefrLevel.a1);
    });

    test('asked increments and session completes after totalQuestions', () {
      var engine = PlacementEngine.initial(totalQuestions: 3);
      engine = engine.answer(correct: true);
      engine = engine.answer(correct: false);
      expect(engine.isComplete, isFalse);
      engine = engine.answer(correct: true);
      expect(engine.asked, 3);
      expect(engine.isComplete, isTrue);
    });

    test('answering a completed session is a no-op', () {
      var engine = PlacementEngine.initial(totalQuestions: 1);
      engine = engine.answer(correct: true);
      final completed = engine;
      expect(engine.answer(correct: true), completed);
    });
  });

  group('PlacementEngine settle', () {
    test('all-correct session settles at the highest reached band (C1)', () {
      var engine = PlacementEngine.initial(totalQuestions: 8);
      for (var i = 0; i < 8; i++) {
        engine = engine.answer(correct: true);
      }
      expect(engine.settleLevel, CefrLevel.c1);
    });

    test('all-wrong session settles at A1', () {
      var engine = PlacementEngine.initial(totalQuestions: 8);
      for (var i = 0; i < 8; i++) {
        engine = engine.answer(correct: false);
      }
      expect(engine.settleLevel, CefrLevel.a1);
    });

    test('settles at the highest band held by a strict majority, not the last '
        'swing', () {
      // Hold A2 correctly twice (majority), missing B1 each time so the ladder
      // ends at A2 but the settle favors the band actually held.
      var engine = PlacementEngine.initial(totalQuestions: 4);
      engine = engine.answer(correct: true); // A2 correct -> B1
      engine = engine.answer(correct: false); // B1 wrong -> A2
      engine = engine.answer(correct: true); // A2 correct -> B1
      engine = engine.answer(correct: false); // B1 wrong -> A2
      // A2: 2/2 correct (strict majority); B1: 0/2 (not held).
      expect(engine.settleLevel, CefrLevel.a2,
          reason: 'A2 is the highest band held by a strict majority');
    });

    test('settle index is always within 0..4', () {
      var engine = PlacementEngine.initial(totalQuestions: 6);
      engine = engine.answer(correct: false);
      engine = engine.answer(correct: false);
      engine = engine.answer(correct: true);
      engine = engine.answer(correct: false);
      engine = engine.answer(correct: true);
      engine = engine.answer(correct: false);
      expect(engine.settleIndex, inInclusiveRange(0, 4));
      expect(CefrLevel.values, contains(engine.settleLevel));
    });
  });
}
