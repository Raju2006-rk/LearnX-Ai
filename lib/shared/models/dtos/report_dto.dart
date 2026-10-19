import 'package:flutter/foundation.dart';

import 'chat_dto.dart';
import 'firestore_converters.dart';

/// DTO for `users/{uid}/reports/{reportId}`:
/// `sessionId, messageId, originalText, grammarFeedback, reason,
/// status ("open"|"reviewed"), createdAt`.
///
/// Captures a full context snapshot of a reported wrong correction so it can
/// be reviewed later. `status` is carried as a raw string.
@immutable
class ReportDto {
  const ReportDto({
    required this.sessionId,
    required this.messageId,
    required this.originalText,
    this.grammarFeedback,
    this.reason,
    this.status = 'open',
    this.createdAt,
  });

  factory ReportDto.fromMap(Map<String, dynamic> map) {
    final feedbackMap = mapOrNull(map['grammarFeedback']);
    return ReportDto(
      sessionId: stringOr(map['sessionId']),
      messageId: stringOr(map['messageId']),
      originalText: stringOr(map['originalText']),
      grammarFeedback:
          feedbackMap == null ? null : GrammarFeedbackDto.fromMap(feedbackMap),
      reason: stringOrNull(map['reason']),
      status: stringOr(map['status'], 'open'),
      createdAt: dateTimeFromFirestore(map['createdAt']),
    );
  }

  final String sessionId;
  final String messageId;
  final String originalText;
  final GrammarFeedbackDto? grammarFeedback;
  final String? reason;

  /// `"open" | "reviewed"`.
  final String status;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'messageId': messageId,
      'originalText': originalText,
      'grammarFeedback': grammarFeedback?.toMap(),
      'reason': reason,
      'status': status,
      'createdAt': timestampFromDateTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReportDto &&
      other.sessionId == sessionId &&
      other.messageId == messageId &&
      other.originalText == originalText &&
      other.grammarFeedback == grammarFeedback &&
      other.reason == reason &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        sessionId,
        messageId,
        originalText,
        grammarFeedback,
        reason,
        status,
        createdAt,
      );
}
