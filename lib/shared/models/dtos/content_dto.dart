import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for `content/{pathId}`: `title, order`.
@immutable
class ContentPathDto {
  const ContentPathDto({required this.title, required this.order});

  factory ContentPathDto.fromMap(Map<String, dynamic> map) {
    return ContentPathDto(
      title: stringOr(map['title']),
      order: intOr(map['order']),
    );
  }

  final String title;
  final int order;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'title': title, 'order': order};

  @override
  bool operator ==(Object other) =>
      other is ContentPathDto && other.title == title && other.order == order;

  @override
  int get hashCode => Object.hash(title, order);
}

/// DTO for `content/{pathId}/sections/{sectionId}`: `title, order`.
@immutable
class SectionDto {
  const SectionDto({required this.title, required this.order});

  factory SectionDto.fromMap(Map<String, dynamic> map) {
    return SectionDto(
      title: stringOr(map['title']),
      order: intOr(map['order']),
    );
  }

  final String title;
  final int order;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'title': title, 'order': order};

  @override
  bool operator ==(Object other) =>
      other is SectionDto && other.title == title && other.order == order;

  @override
  int get hashCode => Object.hash(title, order);
}

/// DTO for `.../sections/{sectionId}/weeks/{weekId}`: `title, order`.
@immutable
class WeekDto {
  const WeekDto({required this.title, required this.order});

  factory WeekDto.fromMap(Map<String, dynamic> map) {
    return WeekDto(
      title: stringOr(map['title']),
      order: intOr(map['order']),
    );
  }

  final String title;
  final int order;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'title': title, 'order': order};

  @override
  bool operator ==(Object other) =>
      other is WeekDto && other.title == title && other.order == order;

  @override
  int get hashCode => Object.hash(title, order);
}

/// DTO for a step's authored `skeleton` block:
/// `{ objectives, examples[], practice[] }`.
///
/// `objectives`, `examples`, and `practice` are carried as string lists —
/// the authored fallback content rendered when AI personalization is absent.
@immutable
class StepSkeletonDto {
  const StepSkeletonDto({
    this.objectives = const [],
    this.examples = const [],
    this.practice = const [],
  });

  factory StepSkeletonDto.fromMap(Map<String, dynamic> map) {
    return StepSkeletonDto(
      objectives: stringListFrom(map['objectives']),
      examples: stringListFrom(map['examples']),
      practice: stringListFrom(map['practice']),
    );
  }

  final List<String> objectives;
  final List<String> examples;
  final List<String> practice;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'objectives': objectives,
      'examples': examples,
      'practice': practice,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is StepSkeletonDto &&
      listEquals(other.objectives, objectives) &&
      listEquals(other.examples, examples) &&
      listEquals(other.practice, practice);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(objectives),
        Object.hashAll(examples),
        Object.hashAll(practice),
      );
}

/// DTO for `.../weeks/{weekId}/steps/{stepId}`:
/// `title, order, type, skeleton, contentVersion`.
@immutable
class StepDto {
  const StepDto({
    required this.title,
    required this.order,
    required this.type,
    this.skeleton = const StepSkeletonDto(),
    this.contentVersion = 0,
  });

  factory StepDto.fromMap(Map<String, dynamic> map) {
    final skeletonMap = mapOrNull(map['skeleton']);
    return StepDto(
      title: stringOr(map['title']),
      order: intOr(map['order']),
      type: stringOr(map['type']),
      skeleton: skeletonMap == null
          ? const StepSkeletonDto()
          : StepSkeletonDto.fromMap(skeletonMap),
      contentVersion: intOr(map['contentVersion']),
    );
  }

  final String title;
  final int order;

  /// Authored step type (rendering hint), carried as a raw string.
  final String type;

  final StepSkeletonDto skeleton;

  /// Monotonic version used for cache invalidation of authored content.
  final int contentVersion;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'order': order,
      'type': type,
      'skeleton': skeleton.toMap(),
      'contentVersion': contentVersion,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is StepDto &&
      other.title == title &&
      other.order == order &&
      other.type == type &&
      other.skeleton == skeleton &&
      other.contentVersion == contentVersion;

  @override
  int get hashCode =>
      Object.hash(title, order, type, skeleton, contentVersion);
}
