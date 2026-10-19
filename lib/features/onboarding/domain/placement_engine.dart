import 'package:flutter/foundation.dart';

/// A CEFR-like difficulty band used by the adaptive placement ladder and
/// stored as the learner's `placementLevel`. (Requirements 2.4, 2.5)
///
/// The [wireValue] matches the strings the Firestore security rules validate
/// `placementLevel` against ("A1".."C1") and the `band` the server-side
/// `generatePlacementQuestion` callable expects, so the engine never
/// hand-writes these literals. The ordering of [values] (A1 → C1) is the band
/// ladder itself: [PlacementEngine] steps between adjacent bands by index.
enum CefrLevel {
  /// A1 — beginner (ladder index 0).
  a1('A1'),

  /// A2 — elementary (ladder index 1).
  a2('A2'),

  /// B1 — intermediate (ladder index 2).
  b1('B1'),

  /// B2 — upper intermediate (ladder index 3).
  b2('B2'),

  /// C1 — advanced (ladder index 4).
  c1('C1');

  const CefrLevel(this.wireValue);

  /// The Firestore/wire representation of this level ("A1".."C1"), shared with
  /// the server's placement `band`.
  ///
  /// This band's position on the ladder is its enum `index` (0 for [a1] .. 4
  /// for [c1]), used directly by [PlacementEngine].
  final String wireValue;

  /// Parses a stored/wire [value] back into a [CefrLevel], returning `null`
  /// when the value is unknown.
  static CefrLevel? fromWire(String? value) {
    if (value == null) return null;
    for (final level in CefrLevel.values) {
      if (level.wireValue == value) return level;
    }
    return null;
  }
}

/// The pure, deterministic state machine behind the adaptive placement test.
///
/// Models the design's difficulty-band ladder: questions target the band at
/// [bandIndex]; a correct answer steps the band up (clamped at C1) and a wrong
/// answer steps it down (clamped at A1), so the band never leaves A1–C1. After
/// [totalQuestions] answers the session [isComplete] and [settleLevel] maps the
/// per-band performance to a final CEFR level. (Requirements 2.4, 2.5)
///
/// This is intentionally free of IO and Flutter/Riverpod dependencies so it is
/// trivially unit- and property-testable. `PlacementController` owns an
/// instance and threads it through the server-driven question flow.
@immutable
class PlacementEngine {
  /// Creates an engine with explicit state. Prefer [PlacementEngine.initial]
  /// for a fresh session; this constructor backs [answer]'s copy-on-write.
  const PlacementEngine({
    required this.bandIndex,
    required this.asked,
    required this.correctByBand,
    this.totalQuestions = defaultTotalQuestions,
  });

  /// A fresh session starting at A2 (ladder index 1), as the design
  /// prescribes, so a mid-range learner needs the fewest steps to settle.
  factory PlacementEngine.initial({
    int totalQuestions = defaultTotalQuestions,
  }) {
    return PlacementEngine(
      bandIndex: _a2Index,
      asked: 0,
      correctByBand: const {},
      totalQuestions: totalQuestions,
    );
  }

  /// The fixed number of questions a placement session asks before settling.
  static const int defaultTotalQuestions = 8;

  static const int _minIndex = 0;
  static const int _maxIndex = 4; // C1
  static const int _a2Index = 1;

  /// The ladder index of the band the next question targets (0..4).
  final int bandIndex;

  /// How many questions have been answered so far.
  final int asked;

  /// Per-band tally of answers, keyed by ladder index, as
  /// `{ correct, total }`. Drives [settleLevel].
  final Map<int, BandTally> correctByBand;

  /// The number of questions this session asks in total.
  final int totalQuestions;

  /// The CEFR band the next question should target.
  CefrLevel get currentBand => CefrLevel.values[bandIndex];

  /// Whether every question has been answered and the session can settle.
  bool get isComplete => asked >= totalQuestions;

  /// Records an [correct]/incorrect answer for the current band and returns the
  /// next engine state.
  ///
  /// The current band's tally is updated, then the band steps up on a correct
  /// answer (clamped at C1) or down on a wrong one (clamped at A1), and [asked]
  /// is incremented. Answering a [isComplete] session is a no-op, so an extra
  /// grade from an in-flight request can never push past the bounds.
  PlacementEngine answer({required bool correct}) {
    if (isComplete) return this;

    final updated = Map<int, BandTally>.from(correctByBand);
    final existing = updated[bandIndex] ?? const BandTally();
    updated[bandIndex] = existing.record(correct: correct);

    final nextIndex = correct
        ? (bandIndex + 1).clamp(_minIndex, _maxIndex)
        : (bandIndex - 1).clamp(_minIndex, _maxIndex);

    return PlacementEngine(
      bandIndex: nextIndex,
      asked: asked + 1,
      correctByBand: Map.unmodifiable(updated),
      totalQuestions: totalQuestions,
    );
  }

  /// The assigned CEFR level for the completed session.
  ///
  /// Always one of the five bands (never leaves A1–C1). Delegates to
  /// [settleIndex] and maps the resulting ladder index to a [CefrLevel].
  CefrLevel get settleLevel => CefrLevel.values[settleIndex];

  /// The ladder index the session settles on.
  ///
  /// Biases toward the highest band the learner answered correctly a majority
  /// of the time, rather than the last swing, so a single lucky/unlucky answer
  /// at the end does not decide the level. When no band reached a correct
  /// majority, it falls back to where the ladder stabilized ([bandIndex]),
  /// clamped to valid bounds. The result is always in 0..4. (Requirement 2.5)
  int get settleIndex {
    int? bestMajorityBand;
    for (final entry in correctByBand.entries) {
      final tally = entry.value;
      if (tally.total == 0) continue;
      // A strict majority correct marks a band the learner can hold.
      if (tally.correct * 2 > tally.total) {
        if (bestMajorityBand == null || entry.key > bestMajorityBand) {
          bestMajorityBand = entry.key;
        }
      }
    }

    final settled = bestMajorityBand ?? bandIndex;
    return settled.clamp(_minIndex, _maxIndex);
  }

  @override
  bool operator ==(Object other) =>
      other is PlacementEngine &&
      other.bandIndex == bandIndex &&
      other.asked == asked &&
      other.totalQuestions == totalQuestions &&
      mapEquals(other.correctByBand, correctByBand);

  @override
  int get hashCode => Object.hash(
        bandIndex,
        asked,
        totalQuestions,
        Object.hashAll(
          correctByBand.entries
              .map((e) => Object.hash(e.key, e.value))
              .toList()
            ..sort(),
        ),
      );

  @override
  String toString() => 'PlacementEngine(bandIndex: $bandIndex, asked: $asked, '
      'correctByBand: $correctByBand)';
}

/// An immutable per-band answer tally: how many answers were [correct] out of
/// [total] served at that band.
@immutable
class BandTally {
  const BandTally({this.correct = 0, this.total = 0});

  /// Number of correct answers at this band.
  final int correct;

  /// Number of answers served at this band.
  final int total;

  /// Returns a copy with one more answer recorded, incrementing [correct] when
  /// [correct] is true.
  BandTally record({required bool correct}) => BandTally(
        correct: this.correct + (correct ? 1 : 0),
        total: total + 1,
      );

  @override
  bool operator ==(Object other) =>
      other is BandTally && other.correct == correct && other.total == total;

  @override
  int get hashCode => Object.hash(correct, total);

  @override
  String toString() => 'BandTally(correct: $correct, total: $total)';
}
