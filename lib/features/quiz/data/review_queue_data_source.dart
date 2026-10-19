import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/firestore_paths.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/quiz.dart';

/// Reads and upserts a learner's spaced-repetition review queue under
/// `users/{uid}/reviewQueue/{itemId}`.
///
/// This is a thin data source: it maps between Firestore document maps and
/// the [ReviewItem] domain type via [ReviewQueueItemDto] and performs no
/// error normalization or scheduling. The [QuizRepository] owns error
/// mapping to the typed exception hierarchy, and [SpacedRepetition] owns the
/// interval transitions; this type only moves documents in and out of
/// Firestore. (Requirements 6.3, 6.4)
class ReviewQueueDataSource {
  ReviewQueueDataSource({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Reads every review-queue entry for the learner [uid].
  ///
  /// Returns the entries as [ReviewItem]s; the repository filters them to the
  /// due subset. May throw a raw Firestore error, which the caller maps.
  Future<List<ReviewItem>> readAll(String uid) async {
    final snap = await _firestore
        .collection(FirestorePaths.reviewQueueCollection(uid))
        .get();
    return <ReviewItem>[
      for (final doc in snap.docs)
        ReviewItem.fromDto(ReviewQueueItemDto.fromMap(doc.data())),
    ];
  }

  /// Reads a single review-queue entry [itemId] for the learner [uid], or
  /// `null` when the learner has no entry for that item.
  Future<ReviewItem?> read(String uid, String itemId) async {
    final doc = await _firestore
        .doc(FirestorePaths.reviewQueueDoc(uid, itemId))
        .get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return ReviewItem.fromDto(ReviewQueueItemDto.fromMap(data));
  }

  /// Upserts [item] into the learner [uid]'s review queue.
  ///
  /// Writes with a **merge** so the document is created when absent and
  /// updated in place otherwise, never clobbering unknown fields. The
  /// `updatedAt` field is written with [FieldValue.serverTimestamp] so
  /// last-write-wins sync uses the server clock rather than a client one.
  Future<void> upsert(String uid, ReviewItem item) async {
    final data = item.toDto().toMap()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .doc(FirestorePaths.reviewQueueDoc(uid, item.itemId))
        .set(data, SetOptions(merge: true));
  }
}
