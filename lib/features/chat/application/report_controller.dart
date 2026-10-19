import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/chat.dart';

/// The view state the report-a-wrong-correction control renders, produced by
/// [ReportController]. (Requirements 5.3, 5.4)
///
/// A small, closed set of states so the control branches exhaustively instead
/// of juggling loose booleans: the learner has not reported yet ([ReportIdle]),
/// a report is being filed ([ReportSubmitting]), a report was stored and a
/// receipt should be confirmed ([ReportFiled]) carrying the stored [Report], or
/// filing failed ([ReportFailure]) with a message to show while leaving the
/// control available to retry.
@immutable
sealed class ReportViewState {
  const ReportViewState();
}

/// No report filed yet; the control offers the report affordance.
@immutable
final class ReportIdle extends ReportViewState {
  const ReportIdle();
}

/// A report is being written; the control shows progress and disables itself.
@immutable
final class ReportSubmitting extends ReportViewState {
  const ReportSubmitting();
}

/// The report was stored under the learner's own `reports` collection and a
/// receipt should be confirmed to the learner. Carries the stored [report]
/// (with its generated id and `open` status). (Requirement 5.4)
@immutable
final class ReportFiled extends ReportViewState {
  const ReportFiled(this.report);

  /// The stored report, with the id Firestore assigned.
  final Report report;

  @override
  bool operator ==(Object other) =>
      other is ReportFiled && other.report == report;

  @override
  int get hashCode => report.hashCode;
}

/// Filing the report failed; [message] is a human-readable error to display
/// while leaving the control available so the learner can retry.
@immutable
final class ReportFailure extends ReportViewState {
  const ReportFailure(this.message);

  /// The error text to surface to the learner.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ReportFailure && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Drives filing a wrong-correction report for a single `Grammar_Feedback`
/// item by calling [ChatRepository.fileReport] and mapping its
/// `Result`/`AppException` outcome to a [ReportViewState] the control renders.
/// (Requirements 5.3, 5.4)
///
/// The controller is family-keyed by the reported message id so each feedback
/// item in the chat has its own independent report state — reporting one item
/// never flips another item's control. The learner's uid comes from the
/// [authStateProvider] seam (overridable in tests and the app's single source
/// of auth identity). The repository writes the full context snapshot and
/// returns the stored report, which the controller surfaces as [ReportFiled]
/// so the UI can confirm receipt.
class ReportController extends Notifier<ReportViewState> {
  @override
  ReportViewState build() => const ReportIdle();

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// The signed-in learner's uid, or `null` when signed out.
  String? get _uid => ref.read(authStateProvider).uid;

  /// Files a report capturing the full context of the flagged [feedback] for
  /// the reported message. [sessionId], [messageId], and [originalText] are the
  /// context snapshot the learner was shown; [reason] is an optional free-text
  /// note. On success transitions to [ReportFiled] so the control confirms
  /// receipt; on failure transitions to [ReportFailure] keeping the control
  /// available to retry. (Requirements 5.3, 5.4)
  Future<void> fileReport({
    required String sessionId,
    required String messageId,
    required String originalText,
    GrammarFeedback? feedback,
    String? reason,
  }) async {
    final uid = _uid;
    if (uid == null) {
      state = const ReportFailure('You need to be signed in to report.');
      return;
    }

    state = const ReportSubmitting();
    final report = Report(
      sessionId: sessionId,
      messageId: messageId,
      originalText: originalText,
      grammarFeedback: feedback,
      reason: (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : null,
    );
    final result = await _repository.fileReport(uid: uid, report: report);
    state = result.fold(
      ReportFiled.new,
      (exception) => ReportFailure(_messageFor(exception)),
    );
  }

  /// Clears a failure back to idle so the learner can retry.
  void reset() => state = const ReportIdle();

  String _messageFor(AppException exception) {
    if (exception.message.isNotEmpty) return exception.message;
    return 'Could not file your report. Please try again.';
  }
}

/// Exposes the per-message [ReportController] and its [ReportViewState] to the
/// report control on each `Grammar_Feedback` item. Keyed by the reported
/// message id so each feedback item tracks its own report state.
final reportControllerProvider =
    NotifierProvider.family<ReportController, ReportViewState, String>(
      (String messageId) => ReportController(),
      name: 'reportControllerProvider',
    );
