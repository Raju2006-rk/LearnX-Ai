import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for `users/{uid}/pathProgress/{stepId}`:
/// `state ("locked"|"available"|"completed"), completedAt, updatedAt`.
///
/// `state` is carried as a raw string; the learning-path domain validates it.
@immutable
class PathProgressDto {
  const PathProgressDto({
    required this.state,
    this.completedAt,
    this.updatedAt,
  });

  factory PathProgressDto.fromMap(Map<String, dynamic> map) {
    return PathProgressDto(
      state: stringOr(map['state']),
      completedAt: dateTimeFromFirestore(map['completedAt']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
    );
  }

  /// `"locked" | "available" | "completed"`.
  final String state;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'state': state,
      'completedAt': timestampFromDateTime(completedAt),
      'updatedAt': timestampFromDateTime(updatedAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PathProgressDto &&
      other.state == state &&
      other.completedAt == completedAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(state, completedAt, updatedAt);
}
