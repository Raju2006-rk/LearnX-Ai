import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/remote_config.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/badge.dart';
import '../domain/badge_awarder.dart';

/// Supplies the currently-configured badge milestones. Backed in production by
/// [RemoteConfigService.badgeMilestones]; tests inject a fixed list directly
/// so the awarding logic can be exercised without a Remote Config fake.
typedef BadgeMilestoneSource = List<BadgeMilestone> Function();

/// Awards Bronze/Silver/Gold badges against the configured milestone
/// thresholds and records them on `users/{uid}/progress/main`. (Requirement
/// 7.3)
///
/// The threshold arithmetic lives in the pure [BadgeAwarder]; this repository
/// is the persistence seam around it. [evaluateAndAward] runs inside a
/// Firestore **transaction** (read-modify-write) so a replayed offline write
/// or a concurrent device reconciles against server state: it reads the stored
/// `badges[]`, evaluates which configured milestones the learner's progress
/// value has newly crossed, and appends only those — leaving sibling fields
/// (`currentStreak`, `longestStreak`, `dailyGoal`) untouched.
///
/// Awarding is **idempotent per milestone**: a milestone already present in
/// `badges[]` (matched by its `milestone` id) is never re-awarded, so running
/// the evaluation again on an unchanged progress value writes nothing.
class BadgeRepository {
  BadgeRepository({
    required FirebaseFirestore firestore,
    required BadgeMilestoneSource milestones,
  }) : _firestore = firestore,
       _milestones = milestones;

  /// Builds a repository that reads its milestones from [remoteConfig].
  BadgeRepository.fromRemoteConfig({
    required FirebaseFirestore firestore,
    required RemoteConfigService remoteConfig,
  }) : this(firestore: firestore, milestones: remoteConfig.badgeMilestones);

  final FirebaseFirestore _firestore;
  final BadgeMilestoneSource _milestones;

  /// Evaluates the configured badge milestones for learner [uid] against
  /// [progressValue] (for the MVP, the learner's current streak length) and
  /// records any newly-earned badges on `progress/main.badges[]`.
  ///
  /// Returns the [BadgeEvaluation] describing the existing and newly-awarded
  /// badges. When nothing new is earned the transaction performs no write and
  /// the document is left untouched. [awardedAt] stamps the new badges; it
  /// defaults to [DateTime.now] in UTC so an award always carries a time.
  Future<BadgeEvaluation> evaluateAndAward(
    String uid,
    int progressValue, {
    DateTime? awardedAt,
  }) {
    final milestones = _milestones();
    final stamp = awardedAt ?? DateTime.now().toUtc();
    final ref = _firestore.doc(FirestorePaths.progressDoc(uid));

    return _firestore.runTransaction<BadgeEvaluation>((transaction) async {
      final snapshot = await transaction.get(ref);
      final existing = _badgesFromSnapshot(snapshot);
      final awardedIds = existing
          .map((b) => b.milestone)
          .whereType<String>()
          .toSet();

      final newlyAwarded = BadgeAwarder.badgesToAward(
        progressValue: progressValue,
        milestones: milestones,
        awardedMilestoneIds: awardedIds,
        awardedAt: stamp,
      );

      final evaluation = BadgeEvaluation(
        existing: existing,
        newlyAwarded: newlyAwarded,
      );

      // Nothing new crossed: leave the document untouched (idempotent no-op).
      if (newlyAwarded.isEmpty) return evaluation;

      final mergedDtos = evaluation.merged
          .map((b) => b.toDto().toMap())
          .toList(growable: false);
      final fields = <String, dynamic>{'badges': mergedDtos};
      if (snapshot.exists) {
        // Write only the badges field so sibling streak/goal fields survive.
        transaction.update(ref, fields);
      } else {
        transaction.set(ref, fields);
      }
      return evaluation;
    });
  }

  /// Reads the stored `badges[]` into domain [Badge]s, dropping any entry with
  /// a missing/unrecognized tier (an invalid tier is not a valid badge) so a
  /// corrupt stored entry cannot crash the award pass.
  List<Badge> _badgesFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return const [];
    final dto = ProgressDto.fromMap(
      snapshot.data() ?? const <String, dynamic>{},
    );
    return dto.badges
        .map(Badge.fromDto)
        .whereType<Badge>()
        .toList(growable: false);
  }
}
