import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../data/onboarding_providers.dart';
import '../data/placement_repository.dart';
import '../domain/placement_engine.dart';
import '../domain/placement_question.dart';

/// The phase of the placement flow the UI renders.
enum PlacementPhase {
  /// The first question is being requested; nothing to show yet.
  loading,

  /// A question is ready to answer.
  question,

  /// The next question / grade is being fetched after an answer.
  submitting,

  /// All questions are answered; the assigned level is being persisted.
  finishing,

  /// Placement is done, the level is stored, and the profile is onboarded.
  /// The router advances to home off the persisted flag.
  complete,

  /// A recoverable error occurred; [PlacementViewState.errorMessage] explains
  /// it and the learner can retry.
  error,
}

/// The view state the placement screen renders, produced by
/// [PlacementController]. (Requirements 2.4, 2.5, 2.6)
@immutable
class PlacementViewState {
  const PlacementViewState({
    this.phase = PlacementPhase.loading,
    this.question,
    this.askedCount = 0,
    this.totalQuestions = PlacementEngine.defaultTotalQuestions,
    this.assignedLevel,
    this.errorMessage,
  });

  /// The current phase of the flow.
  final PlacementPhase phase;

  /// The question to present, when [phase] is [PlacementPhase.question] (or
  /// while [PlacementPhase.submitting] keeps the last question on screen).
  final PlacementQuestion? question;

  /// How many questions have been answered so far, for progress display.
  final int askedCount;

  /// Total questions in the session, for progress display.
  final int totalQuestions;

  /// The assigned CEFR level once placement is [PlacementPhase.complete].
  final CefrLevel? assignedLevel;

  /// A human-readable error shown when [phase] is [PlacementPhase.error].
  final String? errorMessage;

  /// Whether a request is in flight (first load, an answer submission, or the
  /// final save), so the UI can disable inputs.
  bool get isBusy =>
      phase == PlacementPhase.loading ||
      phase == PlacementPhase.submitting ||
      phase == PlacementPhase.finishing;

  PlacementViewState copyWith({
    PlacementPhase? phase,
    PlacementQuestion? question,
    int? askedCount,
    int? totalQuestions,
    CefrLevel? assignedLevel,
    String? errorMessage,
  }) {
    return PlacementViewState(
      phase: phase ?? this.phase,
      question: question ?? this.question,
      askedCount: askedCount ?? this.askedCount,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      assignedLevel: assignedLevel ?? this.assignedLevel,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlacementViewState &&
      other.phase == phase &&
      other.question == question &&
      other.askedCount == askedCount &&
      other.totalQuestions == totalQuestions &&
      other.assignedLevel == assignedLevel &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
        phase,
        question,
        askedCount,
        totalQuestions,
        assignedLevel,
        errorMessage,
      );
}

/// Drives the adaptive placement test: walks the [PlacementEngine] ladder,
/// fetches each question from the server via [PlacementRepository], records the
/// learner's answers, and on completion stores the assigned level and marks the
/// profile onboarded. (Requirements 2.4, 2.5, 2.6)
///
/// The engine is the pure source of truth for the band ladder and the final
/// level; this controller is the IO/orchestration seam around it. The server
/// grades answers, so the controller submits the learner's selected option with
/// the next request and feeds the returned grade back into the engine before
/// advancing. The last question's answer is graded on a final call whose
/// returned question is discarded, since the session is already complete.
class PlacementController extends Notifier<PlacementViewState> {
  PlacementEngine _engine = PlacementEngine.initial();
  String? _pendingQuestionId;

  @override
  PlacementViewState build() {
    // Kick off the first question request once, after construction.
    Future.microtask(start);
    return const PlacementViewState();
  }

  PlacementRepository get _repository => ref.read(placementRepositoryProvider);

  /// Begins (or restarts) the placement session, requesting the first question.
  Future<void> start() async {
    _engine = PlacementEngine.initial();
    _pendingQuestionId = null;
    state = PlacementViewState(
      phase: PlacementPhase.loading,
      totalQuestions: _engine.totalQuestions,
    );
    await _fetchQuestion();
  }

  /// Records the learner's [selectedIndex] for the current question and
  /// advances.
  ///
  /// The engine does not know correctness until the server grades it, so the
  /// answer is sent with the next request; the returned grade is applied to the
  /// engine. When the engine is complete after that grade, the assigned level
  /// is persisted instead of requesting another question. Ignores taps while a
  /// request is in flight or when there is no active question.
  Future<void> submitAnswer(int selectedIndex) async {
    final question = state.question;
    if (state.isBusy ||
        question == null ||
        state.phase != PlacementPhase.question) {
      return;
    }

    state = state.copyWith(phase: PlacementPhase.submitting);
    await _fetchQuestion(
      priorAnswer: PlacementAnswer(
        questionId: question.questionId,
        selectedIndex: selectedIndex,
      ),
    );
  }

  /// Retries the last failed step (the pending question request or the final
  /// save), reusing the current engine state so no progress is lost.
  Future<void> retry() async {
    if (_engine.isComplete) {
      await _finish();
    } else {
      state = state.copyWith(
        phase: state.question == null
            ? PlacementPhase.loading
            : PlacementPhase.submitting,
      );
      await _fetchQuestion();
    }
  }

  /// Requests a question for the engine's current band, optionally submitting a
  /// [priorAnswer] to be graded. Applies the returned grade to the engine; if
  /// the engine then completes, persists the result, otherwise shows the next
  /// question.
  Future<void> _fetchQuestion({PlacementAnswer? priorAnswer}) async {
    final result = await _repository.nextQuestion(
      band: _engine.currentBand,
      priorAnswers: priorAnswer == null ? const [] : [priorAnswer],
    );

    if (result.isFailure) {
      state = state.copyWith(
        phase: PlacementPhase.error,
        errorMessage: result.exceptionOrNull?.message ??
            'Something went wrong. Please try again.',
      );
      return;
    }

    final payload = result.valueOrNull!;

    // Apply the grade for the answer we just submitted, if any, stepping the
    // ladder and advancing the asked count.
    if (priorAnswer != null) {
      final grade = payload.gradedAnswers.firstWhere(
        (g) => g.questionId == priorAnswer.questionId,
        orElse: () => PlacementGrade(
          questionId: priorAnswer.questionId,
          correct: false,
        ),
      );
      _engine = _engine.answer(correct: grade.correct);
    }

    if (_engine.isComplete) {
      await _finish();
      return;
    }

    _pendingQuestionId = payload.question.questionId;
    state = state.copyWith(
      phase: PlacementPhase.question,
      question: payload.question,
      askedCount: _engine.asked,
      totalQuestions: _engine.totalQuestions,
    );
  }

  /// Stores the engine's settled level and marks the profile onboarded.
  Future<void> _finish() async {
    _pendingQuestionId = null;
    final level = _engine.settleLevel;
    state = state.copyWith(
      phase: PlacementPhase.finishing,
      askedCount: _engine.asked,
      assignedLevel: level,
    );

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      state = state.copyWith(
        phase: PlacementPhase.error,
        errorMessage: 'You need to be signed in to finish placement.',
      );
      return;
    }

    final result = await _repository.completePlacement(uid: uid, level: level);
    state = result.fold(
      (_) => state.copyWith(
        phase: PlacementPhase.complete,
        assignedLevel: level,
      ),
      (exception) => state.copyWith(
        phase: PlacementPhase.error,
        assignedLevel: level,
        errorMessage: exception.message,
      ),
    );
  }

  /// The id of the question currently awaiting an answer, exposed for tests.
  @visibleForTesting
  String? get pendingQuestionId => _pendingQuestionId;
}

/// Exposes the [PlacementController] and its [PlacementViewState] to the
/// placement UI.
final placementControllerProvider =
    NotifierProvider<PlacementController, PlacementViewState>(
  PlacementController.new,
  name: 'placementControllerProvider',
);
