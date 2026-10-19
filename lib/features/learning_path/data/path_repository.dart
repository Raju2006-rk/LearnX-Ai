import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/ai/ai_function_client.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/learning_path.dart';
import '../domain/step_content.dart';
import 'content_cache_data_source.dart';

/// Loads the authored learning path from the [Content_Store] and the
/// learner's per-user progress, then resolves each step's locked / available
/// / completed state. (Requirements 3.1, 3.2, 3.3, 3.4)
///
/// Reads are split across the read-only authored skeleton under `content/**`
/// (cacheable, shared by all learners) and the per-user progress collection
/// `users/{uid}/pathProgress`. The repository maps both to DTOs, then hands
/// the authored tree plus the set of completed step ids to
/// [StepProgress.resolve], which owns the unlock invariant. The stored
/// per-step `state` string is used only to decide which steps count as
/// *completed*; locked/available are always derived, so the path can never
/// surface a stale lock state.
///
/// Recording a step completion flips the learner's
/// `users/{uid}/pathProgress/{stepId}` document to `completed`; because the
/// path's locked/available state is always *derived* from the set of
/// completed steps (see [StepProgress.resolve]), a subsequent [loadPath]
/// re-resolves the path with the next step unlocked. The completion write is
/// a merge so it never clobbers other fields on the document.
class PathRepository {
  PathRepository({
    required FirebaseFirestore firestore,
    required AiFunctionClient aiClient,
    ContentCacheDataSource? contentCache,
  }) : _firestore = firestore,
       _aiClient = aiClient,
       _contentCache = contentCache ?? ContentCacheDataSource();

  final FirebaseFirestore _firestore;
  final AiFunctionClient _aiClient;

  /// The offline cache of authored step skeletons keyed by `contentVersion`.
  ///
  /// A step opened online is cached here so a later open can serve it for
  /// read/practice offline; a read that fails because the device is offline
  /// falls back to the cached skeleton rather than surfacing a network error.
  /// (Requirement 8.1)
  final ContentCacheDataSource _contentCache;

  /// The name of the lesson-personalization callable in the `AI_Proxy`.
  static const String personalizeLessonCallable = 'personalizeLesson';

  /// Loads the authored path [pathId] and resolves every step's state for the
  /// learner [uid], returning a typed [Result].
  ///
  /// Fetches the authored section/week/step skeleton and the learner's
  /// `pathProgress` documents, then derives locked/available/completed via
  /// [StepProgress.resolve]. A missing authored path resolves to a
  /// [NotFoundException]; connectivity failures map to [NetworkException];
  /// other read failures map to [AuthException] (a permission failure).
  Future<Result<StepProgress>> loadPath({
    required String uid,
    required String pathId,
  }) async {
    try {
      final sections = await _loadAuthoredSections(pathId);
      if (sections.isEmpty) {
        return const Result.failure(
          NotFoundException('This learning path is not available yet.'),
        );
      }

      final completedStepIds = await _loadCompletedStepIds(uid);

      return Result.success(
        StepProgress.resolve(
          pathId: pathId,
          sections: sections,
          completedStepIds: completedStepIds,
        ),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Marks the step [stepId] completed for the learner [uid], returning a
  /// typed [Result].
  ///
  /// Writes `state: "completed"` to `users/{uid}/pathProgress/{stepId}` with a
  /// **merge** so any other fields on the document are preserved, stamping
  /// `completedAt` and `updatedAt` with the server timestamp (the latter for
  /// last-write-wins sync). Because locked/available are derived from the set
  /// of completed steps, re-loading the path after this write surfaces the
  /// next step as available (Requirement 3.4). Connectivity failures map to
  /// [NetworkException]; other write failures (including a rules rejection)
  /// map to [AuthException].
  Future<Result<void>> completeStep({
    required String uid,
    required String stepId,
  }) async {
    try {
      final data = <String, dynamic>{
        'state': StepState.completed.wireValue,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _firestore
          .doc(FirestorePaths.pathProgressDoc(uid, stepId))
          .set(data, SetOptions(merge: true));
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Loads the authored skeleton for a single step [stepId] of [pathId],
  /// returning a typed [Result].
  ///
  /// Walks the authored `content/**` tree to find the step document with the
  /// matching id and maps its `skeleton` block (objectives/examples/practice)
  /// plus title into a [StepContent] whose personalization is empty. The
  /// skeleton is read-only to clients and cacheable (keyed by
  /// `contentVersion`). A missing step resolves to a [NotFoundException];
  /// other read failures map to [AuthException]. The returned content always
  /// carries the authored skeleton so the step detail can render it before (or
  /// instead of) any AI personalization. (Requirement 3.6)
  ///
  /// **Offline read.** On a successful read the authored skeleton is cached by
  /// `contentVersion` so a later open can serve it without a network
  /// connection. When the live read fails with a connectivity error, the
  /// repository serves the step's last-cached skeleton if one exists, so a
  /// previously opened step stays fully readable and practiceable offline; it
  /// only surfaces a [NetworkException] when nothing is cached for the step.
  /// (Requirement 8.1)
  Future<Result<StepContent>> loadStepContent({
    required String pathId,
    required String stepId,
  }) async {
    try {
      final located = await _findStepDoc(pathId, stepId);
      if (located == null) {
        return const Result.failure(
          NotFoundException('This step is not available yet.'),
        );
      }
      final dto = located;
      final skeleton = StepSkeleton(
        objectives: dto.skeleton.objectives,
        examples: dto.skeleton.examples,
        practice: dto.skeleton.practice,
      );
      // Cache the freshly read skeleton keyed by its authored contentVersion
      // so a later open can serve it offline; a bumped version supersedes the
      // prior entry for this step.
      _contentCache.cache(
        stepId: stepId,
        contentVersion: dto.contentVersion,
        title: dto.title,
        skeleton: skeleton,
      );
      return Result.success(
        StepContent(stepId: stepId, title: dto.title, skeleton: skeleton),
      );
    } catch (error) {
      final mapped = _mapError(error);
      // Offline fallback: if this step was opened before, serve the cached
      // content so it stays readable/practiceable without a connection.
      if (mapped is NetworkException) {
        final cached = _contentCache.lookupAny(stepId);
        if (cached != null) {
          return Result.success(
            StepContent(
              stepId: stepId,
              title: cached.title,
              skeleton: cached.skeleton,
            ),
          );
        }
      }
      return Result.failure(mapped);
    }
  }

  /// Requests AI personalization for the step [stepId] from the
  /// `personalizeLesson` callable, returning a typed [Result].
  ///
  /// The callable returns CEFR/goal-tagged examples and practice. On any
  /// failure or moderation refusal it returns an empty/`null` personalization;
  /// this method maps that (and a thrown error) to
  /// [StepPersonalization.empty], so the caller falls back to the authored
  /// skeleton rather than surfacing an error. The result is therefore a
  /// *success* carrying an empty personalization in the no-content case — the
  /// client never fails a step open just because personalization was
  /// unavailable. (Requirements 3.5, 3.6)
  Future<Result<StepPersonalization>> personalizeStep({
    required String stepId,
  }) async {
    try {
      final data = await _aiClient.call(personalizeLessonCallable, {
        'stepId': stepId,
      });
      return Result.success(_personalizationFrom(data));
    } catch (_) {
      // A failed personalization call is non-fatal: fall back to skeleton.
      return const Result.success(StepPersonalization.empty);
    }
  }

  /// Maps a `personalizeLesson` response map into a [StepPersonalization],
  /// tolerating the empty/`null` shape the callable returns on failure or
  /// moderation refusal.
  ///
  /// The callable may return `{ personalization: null }`, `{ personalization:
  /// { examples, practice } }`, or the `examples`/`practice` lists at the top
  /// level. Any missing or non-list field becomes an empty list, so an absent
  /// personalization maps to [StepPersonalization.empty].
  StepPersonalization _personalizationFrom(Map<String, dynamic> data) {
    final nested = mapOrNull(data['personalization']);
    final source = nested ?? data;
    final examples = stringListFrom(source['examples']);
    final practice = stringListFrom(source['practice']);
    if (examples.isEmpty && practice.isEmpty) {
      return StepPersonalization.empty;
    }
    return StepPersonalization(examples: examples, practice: practice);
  }

  /// Finds the authored [StepDto] for [stepId] anywhere in the [pathId] tree,
  /// or `null` when no step with that id exists.
  Future<StepDto?> _findStepDoc(String pathId, String stepId) async {
    final sectionsSnap = await _firestore
        .collection(FirestorePaths.sectionsCollection(pathId))
        .get();
    for (final sectionDoc in sectionsSnap.docs) {
      final weeksSnap = await _firestore
          .collection(FirestorePaths.weeksCollection(pathId, sectionDoc.id))
          .get();
      for (final weekDoc in weeksSnap.docs) {
        final stepSnap = await _firestore
            .doc(
              FirestorePaths.stepDoc(pathId, sectionDoc.id, weekDoc.id, stepId),
            )
            .get();
        final data = stepSnap.data();
        if (stepSnap.exists && data != null) {
          return StepDto.fromMap(data);
        }
      }
    }
    return null;
  }

  /// Reads the authored section → week → step skeleton for [pathId] from
  /// `content/**`, mapping each document via the content DTOs.
  ///
  /// Ordering is left to [StepProgress.resolve], which sorts defensively by
  /// the authored `order` fields; this method only maps documents.
  Future<List<Section>> _loadAuthoredSections(String pathId) async {
    final sectionsSnap = await _firestore
        .collection(FirestorePaths.sectionsCollection(pathId))
        .get();

    final sections = <Section>[];
    for (final sectionDoc in sectionsSnap.docs) {
      final sectionDto = SectionDto.fromMap(sectionDoc.data());

      final weeksSnap = await _firestore
          .collection(FirestorePaths.weeksCollection(pathId, sectionDoc.id))
          .get();

      final weeks = <Week>[];
      for (final weekDoc in weeksSnap.docs) {
        final weekDto = WeekDto.fromMap(weekDoc.data());

        final stepsSnap = await _firestore
            .collection(
              FirestorePaths.stepsCollection(pathId, sectionDoc.id, weekDoc.id),
            )
            .get();

        final steps = <Step>[
          for (final stepDoc in stepsSnap.docs)
            _toStep(stepDoc.id, StepDto.fromMap(stepDoc.data())),
        ];

        weeks.add(
          Week(
            id: weekDoc.id,
            title: weekDto.title,
            order: weekDto.order,
            steps: steps,
          ),
        );
      }

      sections.add(
        Section(
          id: sectionDoc.id,
          title: sectionDto.title,
          order: sectionDto.order,
          weeks: weeks,
        ),
      );
    }

    return sections;
  }

  /// Reads the learner's `pathProgress` documents and returns the set of step
  /// ids whose stored `state` is `completed`.
  Future<Set<String>> _loadCompletedStepIds(String uid) async {
    final snap = await _firestore
        .collection(FirestorePaths.pathProgressCollection(uid))
        .get();

    final completed = <String>{};
    for (final doc in snap.docs) {
      final dto = PathProgressDto.fromMap(doc.data());
      if (StepState.fromWire(dto.state) == StepState.completed) {
        completed.add(doc.id);
      }
    }
    return completed;
  }

  /// Builds an authored [Step] with a placeholder [StepState.locked]; the real
  /// state is assigned during resolution.
  Step _toStep(String id, StepDto dto) => Step(
    id: id,
    title: dto.title,
    order: dto.order,
    type: dto.type,
    state: StepState.locked,
  );

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; every other read
  /// failure (including a rules rejection) maps to [AuthException] as a
  /// permission failure.
  AppException _mapError(Object error) {
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Could not load your learning path.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(
        'A network error occurred. Check your connection and try again.',
        error,
      );
    }
    return AuthException('Could not load your learning path.', error);
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
