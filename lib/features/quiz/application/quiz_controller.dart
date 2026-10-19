import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/connectivity.dart';
import '../data/quiz_providers.dart';
import '../data/quiz_repository.dart';
import '../domain/quiz.dart';

/// The phase a quiz session is in, driving which view the quiz screen renders.
enum QuizPhase {
  /// Loading the authored quiz-item bank.
  loading,

  /// A question is being presented and answered.
  inProgress,

  /// Every loaded question has been answered; the results view is shown.
  results,

  /// The session could not be started (for example the bank failed to load).
  error,

  /// The bank loaded but held no questions, so there is nothing to quiz on.
  empty,

  /// The session could not start because the device is offline. Quizzes are
  /// network-required, so the learner is told to reconnect rather than left
  /// waiting on a request that cannot complete. (Requirements 6.6, 8.4)
  offline,
}

/// The live state of a quiz session the UI renders. (Requirements 6.1, 6.2)
///
/// A session walks the learner through [questions] one at a time. [index]
/// points at the current question while [phase] is [QuizPhase.inProgress];
/// each scored response is appended to [answers] in order. [correctCount] and
/// [wrongCount] are the running tallies the results view shows
/// (Requirement 6.2); they are always derivable from [answers] but are kept on
/// the state so the UI reads them directly without recomputing.
///
/// When [index] reaches the end of [questions] the session transitions to
/// [QuizPhase.results]. [errorMessage] carries a user-facing explanation when
/// [phase] is [QuizPhase.error].
@immutable
class QuizState {
  const QuizState({
    this.phase = QuizPhase.loading,
    this.questions = const [],
    this.answers = const [],
    this.index = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.errorMessage,
  });

  /// The phase driving which view is shown.
  final QuizPhase phase;

  /// The ordered questions for this session.
  final List<Question> questions;

  /// The scored answers recorded so far, in presentation order.
  final List<Answer> answers;

  /// The index of the current question in [questions].
  final int index;

  /// The number of questions answered correctly so far. (Requirement 6.2)
  final int correctCount;

  /// The number of questions answered incorrectly so far. (Requirement 6.2)
  final int wrongCount;

  /// A user-facing error shown when [phase] is [QuizPhase.error].
  final String? errorMessage;

  /// The question currently being presented, or `null` when the session is not
  /// [QuizPhase.inProgress] or the index is out of range.
  Question? get currentQuestion {
    if (phase != QuizPhase.inProgress) return null;
    if (index < 0 || index >= questions.length) return null;
    return questions[index];
  }

  /// The total number of questions answered so far.
  int get answeredCount => answers.length;

  /// The total number of questions in this session.
  int get totalCount => questions.length;

  QuizState copyWith({
    QuizPhase? phase,
    List<Question>? questions,
    List<Answer>? answers,
    int? index,
    int? correctCount,
    int? wrongCount,
    String? errorMessage,
  }) {
    return QuizState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      answers: answers ?? this.answers,
      index: index ?? this.index,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
      // errorMessage is cleared unless explicitly provided so a fresh session
      // or a successful load never carries a stale error.
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuizState &&
      other.phase == phase &&
      listEquals(other.questions, questions) &&
      listEquals(other.answers, answers) &&
      other.index == index &&
      other.correctCount == correctCount &&
      other.wrongCount == wrongCount &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
    phase,
    Object.hashAll(questions),
    Object.hashAll(answers),
    index,
    correctCount,
    wrongCount,
    errorMessage,
  );
}

/// Drives a daily quiz session: loads the authored question bank, presents
/// fill-in-the-blank and choose-the-right-word questions one at a time, scores
/// each response via [Answer.score], and tracks the running correct/wrong
/// counts the results view shows. (Requirements 6.1, 6.2)
///
/// The controller is the orchestration seam between the quiz screen and
/// [QuizRepository]. [build] loads the bank via
/// [QuizRepository.loadQuizItems] and resolves the opening phase:
/// [QuizPhase.inProgress] when there are questions, [QuizPhase.empty] when the
/// bank is empty, or [QuizPhase.error] on a load failure. [answer] scores the
/// current question, updates the tallies, and advances — transitioning to
/// [QuizPhase.results] after the final question.
///
/// Review-queue scheduling (surfacing due items at the start of a session and
/// enqueuing missed items on a wrong answer) is deliberately **not** wired here
/// — that is task 9.4. This controller is structured so that integration slots
/// in without reshaping the session: [_scoreAnswer] is the single place every
/// answer is recorded, so a future wrong-answer hook attaches there, and
/// [build] is the single place the question set is assembled, so due review
/// items can be merged in there.
class QuizController extends AsyncNotifier<QuizState> {
  /// Surfaced when a session is started while the device is offline. Quizzes
  /// are network-required, so the learner is told plainly to reconnect rather
  /// than left waiting on a load that cannot complete. (Requirements 6.6, 8.4)
  @visibleForTesting
  static const String offlineMessage =
      'Quizzes require a network connection. Reconnect and try again.';

  QuizRepository get _repository => ref.read(quizRepositoryProvider);

  /// Whether the device is currently known to be offline.
  ///
  /// Reads the connectivity status [build] established via `ref.watch`. The
  /// status stream emits the current connectivity immediately on subscription,
  /// so by the time a session resolves a value is normally present; while the
  /// first reading is still pending (or errored) the load is allowed to
  /// proceed so a transient unknown state never blocks a legitimate session —
  /// the repository still surfaces a failure if the call cannot reach the
  /// backend. (Requirements 6.6, 8.4)
  bool get _isOffline =>
      ref.read(connectivityStatusProvider).asData?.value.isOffline ?? false;

  @override
  Future<QuizState> build() {
    // Watch connectivity so the opening load branches on a resolved status:
    // the status stream's first value lands on a microtask after this
    // controller first builds, and watching re-runs build() when it arrives
    // (and again if connectivity later changes). (Requirements 6.6, 8.4)
    ref.watch(connectivityStatusProvider);
    return _loadSession();
  }

  /// Loads the question bank and resolves the opening [QuizState].
  ///
  /// Quizzes are network-required: when the device is offline the session
  /// resolves to [QuizPhase.offline] with a clear message rather than calling
  /// the repository, so the learner is told to reconnect instead of waiting on
  /// a load that cannot complete. (Requirements 6.6, 8.4)
  ///
  /// Otherwise a successful non-empty load starts the session at the first
  /// question; an empty bank resolves to [QuizPhase.empty]; a failure resolves
  /// to [QuizPhase.error] carrying the typed exception's message.
  Future<QuizState> _loadSession() async {
    // Quizzes are network-required. Fail fast when offline so the learner gets
    // a clear message instead of a hanging load. (Requirements 6.6, 8.4)
    if (_isOffline) {
      return const QuizState(
        phase: QuizPhase.offline,
        errorMessage: offlineMessage,
      );
    }

    final result = await _repository.loadQuizItems();
    return result.fold(
      (questions) {
        if (questions.isEmpty) {
          return const QuizState(phase: QuizPhase.empty);
        }
        return QuizState(
          phase: QuizPhase.inProgress,
          questions: questions,
          index: 0,
        );
      },
      (exception) => QuizState(
        phase: QuizPhase.error,
        errorMessage: _messageFor(exception),
      ),
    );
  }

  /// Scores [response] against the current question, records it, and advances
  /// to the next question (or the results view after the last one).
  ///
  /// Ignores the call when the session is not in progress, so a stray submit
  /// from the results or error view is a no-op. Scoring is delegated to
  /// [Answer.score] (case-insensitive, whitespace-trimmed) so fill-in-the-blank
  /// and choose-the-right-word answers are judged identically.
  void answer(String response) {
    final current = state.value;
    if (current == null || current.phase != QuizPhase.inProgress) return;

    final question = current.currentQuestion;
    if (question == null) return;

    state = AsyncValue.data(_scoreAnswer(current, question, response));
  }

  /// Records a scored [response] to [question] into [current], returning the
  /// next [QuizState].
  ///
  /// This is the single choke point every answer flows through: it scores the
  /// response, appends the [Answer], bumps the matching tally, and either
  /// advances the index or transitions to [QuizPhase.results] when the last
  /// question is answered. Task 9.4's wrong-answer review-queue enqueue hooks
  /// in here where [Answer.correct] is known.
  QuizState _scoreAnswer(
    QuizState current,
    Question question,
    String response,
  ) {
    final scored = Answer.score(question, response);
    final answers = [...current.answers, scored];
    final correct = current.correctCount + (scored.correct ? 1 : 0);
    final wrong = current.wrongCount + (scored.correct ? 0 : 1);

    final nextIndex = current.index + 1;
    final finished = nextIndex >= current.questions.length;

    return current.copyWith(
      phase: finished ? QuizPhase.results : QuizPhase.inProgress,
      answers: answers,
      index: nextIndex,
      correctCount: correct,
      wrongCount: wrong,
    );
  }

  /// Restarts the session from the beginning, reloading the question bank so a
  /// retry after an error or a replay after results starts from a clean slate.
  Future<void> restart() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadSession);
  }

  String _messageFor(AppException exception) => exception.message.isNotEmpty
      ? exception.message
      : 'Could not load your quiz.';
}

/// Exposes the [QuizController] and its asynchronous [QuizState] to the quiz
/// UI.
final quizControllerProvider = AsyncNotifierProvider<QuizController, QuizState>(
  QuizController.new,
  name: 'quizControllerProvider',
);
