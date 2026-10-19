import 'package:flutter/foundation.dart';

import '../domain/step_content.dart';

/// An authored step's cacheable content: its [title] and [skeleton].
///
/// Personalization is never cached — it is AI-generated per request and
/// requires a network round-trip, so only the authored, offline-serviceable
/// parts of a step are stored here. (Requirement 8.1)
@immutable
class CachedStepContent {
  const CachedStepContent({required this.title, required this.skeleton});

  /// The authored step title.
  final String title;

  /// The authored skeleton (objectives/examples/practice).
  final StepSkeleton skeleton;

  @override
  bool operator ==(Object other) =>
      other is CachedStepContent &&
      other.title == title &&
      other.skeleton == skeleton;

  @override
  int get hashCode => Object.hash(title, skeleton);
}

/// Caches authored step skeletons for offline read and practice on mobile,
/// keyed by the step's `contentVersion`. (Requirement 8.1)
///
/// The design's Offline Caching strategy pairs Firestore offline persistence
/// (which carries the raw documents across brief reconnects) with a
/// "lightweight local content cache keyed by `contentVersion`" so that a
/// previously opened step stays fully readable and practiceable without a
/// network connection. This data source is that lightweight cache: when a
/// step's authored skeleton is read online it is stored here, and when a
/// later read fails because the device is offline the repository serves the
/// cached skeleton instead of surfacing a network error.
///
/// ### Keying and invalidation
/// Entries are keyed by `(stepId, contentVersion)`. The authored `content/**`
/// documents carry a monotonic `contentVersion` that authors bump whenever a
/// step's skeleton changes, so a cached entry is only served when its version
/// matches the version last seen for that step. Caching a step at a newer
/// version supersedes the older entry, so stale authored content is never
/// served after an author updates it. Because the key encodes the version,
/// [lookup] with a mismatched version is a miss, which lets the repository
/// fall through to the live (or Firestore-persisted) document.
///
/// ### Storage mechanism
/// This MVP cache is **in-memory**, scoped to the app's lifetime. No
/// persistent key-value store is available in the project's dependencies
/// (`pubspec.yaml` ships `flutter_secure_storage`, which is reserved for auth
/// tokens, and no `shared_preferences` / `hive` / `sqflite`), so a persistent
/// on-disk cache is intentionally out of scope here. Firestore offline
/// persistence (enabled on mobile in task 1.2) already provides durable
/// across-launch caching of the underlying documents; this in-memory layer
/// complements it by guaranteeing an already-opened step renders from a
/// typed, version-checked skeleton even when the SDK read throws offline.
/// Swapping in a persistent store later is a drop-in change behind this same
/// interface with no repository or UI impact.
class ContentCacheDataSource {
  ContentCacheDataSource();

  /// The cached entries keyed by `(stepId, contentVersion)`.
  final Map<_CacheKey, CachedStepContent> _entries =
      <_CacheKey, CachedStepContent>{};

  /// Stores the authored [title] and [skeleton] for [stepId] at
  /// [contentVersion], superseding any older entry for the same step.
  ///
  /// Older-version entries for the same [stepId] are dropped so the cache
  /// holds at most one entry per step (the most recently seen version),
  /// keeping memory bounded and preventing a stale version from lingering
  /// after an author bumps [contentVersion].
  void cache({
    required String stepId,
    required int contentVersion,
    required String title,
    required StepSkeleton skeleton,
  }) {
    _entries.removeWhere((key, _) => key.stepId == stepId);
    _entries[_CacheKey(stepId, contentVersion)] = CachedStepContent(
      title: title,
      skeleton: skeleton,
    );
  }

  /// Returns the cached entry for [stepId] at [contentVersion], or `null`
  /// when nothing is cached for that step at that exact version.
  ///
  /// A version mismatch is a deliberate miss: it signals the authored content
  /// changed, so the caller should read the live document rather than serve a
  /// stale entry.
  CachedStepContent? lookup({
    required String stepId,
    required int contentVersion,
  }) {
    return _entries[_CacheKey(stepId, contentVersion)];
  }

  /// Returns the cached entry for [stepId] regardless of version, or `null`
  /// when the step has never been cached.
  ///
  /// This is the offline fallback: when a read fails because the device is
  /// offline the repository cannot know the current `contentVersion`, so it
  /// serves whatever version was last cached for the step. Online reads always
  /// go through [lookup]/[cache] with an exact version, so the cached entry is
  /// as fresh as the last successful online open.
  CachedStepContent? lookupAny(String stepId) {
    for (final entry in _entries.entries) {
      if (entry.key.stepId == stepId) return entry.value;
    }
    return null;
  }

  /// Whether an entry is cached for [stepId] at [contentVersion].
  bool contains({required String stepId, required int contentVersion}) =>
      _entries.containsKey(_CacheKey(stepId, contentVersion));

  /// Removes every cached entry. Primarily for tests and sign-out teardown.
  void clear() => _entries.clear();
}

/// A composite cache key: a step id paired with its authored `contentVersion`,
/// so bumping the version invalidates the prior entry for the same step.
class _CacheKey {
  const _CacheKey(this.stepId, this.contentVersion);

  final String stepId;
  final int contentVersion;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.stepId == stepId &&
      other.contentVersion == contentVersion;

  @override
  int get hashCode => Object.hash(stepId, contentVersion);
}
