/// Barrel export for the Firestore DTO layer.
///
/// DTOs are pure serialization mappers between Firestore document maps and
/// typed Dart objects for every collection in the design's data model. They
/// carry enum-valued fields as raw strings; feature domain types (added by
/// later tasks) parse/validate them.
library;

export 'chat_dto.dart';
export 'content_dto.dart';
export 'firestore_converters.dart';
export 'path_progress_dto.dart';
export 'profile_dto.dart';
export 'progress_dto.dart';
export 'quiz_dto.dart';
export 'report_dto.dart';
export 'usage_dto.dart';
export 'user_dto.dart';
