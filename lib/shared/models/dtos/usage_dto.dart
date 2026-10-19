import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for the server-written usage counters at
/// `users/{uid}/usage/{yyyy-mm-dd}`:
/// `chatMessages, lessonPersonalizations, placementGenerations`.
///
/// These documents are written only by Cloud Functions (Admin SDK). Clients
/// read them to show remaining quota; the DTO's [toMap] exists for
/// server-side/test use and completeness.
@immutable
class UsageDto {
  const UsageDto({
    this.chatMessages = 0,
    this.lessonPersonalizations = 0,
    this.placementGenerations = 0,
  });

  factory UsageDto.fromMap(Map<String, dynamic> map) {
    return UsageDto(
      chatMessages: intOr(map['chatMessages']),
      lessonPersonalizations: intOr(map['lessonPersonalizations']),
      placementGenerations: intOr(map['placementGenerations']),
    );
  }

  final int chatMessages;
  final int lessonPersonalizations;
  final int placementGenerations;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'chatMessages': chatMessages,
      'lessonPersonalizations': lessonPersonalizations,
      'placementGenerations': placementGenerations,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is UsageDto &&
      other.chatMessages == chatMessages &&
      other.lessonPersonalizations == lessonPersonalizations &&
      other.placementGenerations == placementGenerations;

  @override
  int get hashCode =>
      Object.hash(chatMessages, lessonPersonalizations, placementGenerations);
}
