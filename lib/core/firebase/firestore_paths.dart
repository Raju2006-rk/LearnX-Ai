/// Centralized Firestore collection/document path helpers.
///
/// Every collection and document path in the app is derived from these
/// helpers so callers never hand-assemble path strings (which is
/// error-prone) and so the layout stays in one place, matching the
/// design's "Firestore Collections" data model.
///
/// The helpers are pure string builders: they take identifiers and return
/// the slash-delimited path Firestore expects. This keeps them trivially
/// unit-testable without a `FirebaseFirestore` instance. Repositories use
/// them via `db.doc(FirestorePaths.userDoc(uid))` /
/// `db.collection(FirestorePaths.chatSessions(uid))`.
///
/// Firestore requires document paths to have an even number of segments and
/// collection paths an odd number; the helper names make the intended kind
/// explicit (`*Doc` for documents, plural nouns for collections).
abstract final class FirestorePaths {
  const FirestorePaths._();

  // --- Top-level collection segment names ---
  static const String users = 'users';
  static const String content = 'content';
  static const String quizItems = 'quizItems';

  // --- Per-user sub-collection / fixed-document segment names ---
  static const String profile = 'profile';
  static const String pathProgress = 'pathProgress';
  static const String chatSessions = 'chatSessions';
  static const String messages = 'messages';
  static const String reports = 'reports';
  static const String reviewQueue = 'reviewQueue';
  static const String quizSessions = 'quizSessions';
  static const String progress = 'progress';
  static const String dailyActivity = 'dailyActivity';
  static const String weeklySummaries = 'weeklySummaries';
  static const String usage = 'usage';

  // --- Content sub-collection segment names ---
  static const String sections = 'sections';
  static const String weeks = 'weeks';
  static const String steps = 'steps';

  /// The fixed document id used for singleton per-user documents such as
  /// `profile/main` and `progress/main`.
  static const String mainDoc = 'main';

  // --- users/{uid} ---

  /// Collection of all user root documents: `users`.
  static String usersCollection() => users;

  /// A user's root document: `users/{uid}`.
  static String userDoc(String uid) => '$users/$uid';

  // --- users/{uid}/profile/main ---

  /// A user's profile collection: `users/{uid}/profile`.
  static String profileCollection(String uid) => '${userDoc(uid)}/$profile';

  /// A user's singleton profile document: `users/{uid}/profile/main`.
  static String profileDoc(String uid) => '${profileCollection(uid)}/$mainDoc';

  // --- content/{pathId}/sections/{sectionId}/weeks/{weekId}/steps/{stepId} ---

  /// Authored learning paths collection: `content`.
  ///
  /// Each authored path is a document directly under the top-level `content`
  /// collection (`content/{pathId}`). The design's data model writes this
  /// conceptually as `content/paths/{pathId}`; the concrete Firestore layout
  /// drops the intermediate `paths` segment so path/section/week/step
  /// references keep Firestore's required document/collection segment parity
  /// (documents have an even number of segments, collections an odd number).
  static String contentPathsCollection() => content;

  /// A single authored path: `content/{pathId}`.
  static String contentPathDoc(String pathId) =>
      '${contentPathsCollection()}/$pathId';

  /// Sections of a path: `content/{pathId}/sections`.
  static String sectionsCollection(String pathId) =>
      '${contentPathDoc(pathId)}/$sections';

  /// A single section: `content/{pathId}/sections/{sectionId}`.
  static String sectionDoc(String pathId, String sectionId) =>
      '${sectionsCollection(pathId)}/$sectionId';

  /// Weeks of a section:
  /// `content/{pathId}/sections/{sectionId}/weeks`.
  static String weeksCollection(String pathId, String sectionId) =>
      '${sectionDoc(pathId, sectionId)}/$weeks';

  /// A single week:
  /// `content/{pathId}/sections/{sectionId}/weeks/{weekId}`.
  static String weekDoc(String pathId, String sectionId, String weekId) =>
      '${weeksCollection(pathId, sectionId)}/$weekId';

  /// Steps of a week:
  /// `.../weeks/{weekId}/steps`.
  static String stepsCollection(
    String pathId,
    String sectionId,
    String weekId,
  ) =>
      '${weekDoc(pathId, sectionId, weekId)}/$steps';

  /// A single authored step:
  /// `.../weeks/{weekId}/steps/{stepId}`.
  static String stepDoc(
    String pathId,
    String sectionId,
    String weekId,
    String stepId,
  ) =>
      '${stepsCollection(pathId, sectionId, weekId)}/$stepId';

  // --- users/{uid}/pathProgress/{stepId} ---

  /// A user's path-progress collection: `users/{uid}/pathProgress`.
  static String pathProgressCollection(String uid) =>
      '${userDoc(uid)}/$pathProgress';

  /// A user's progress for one step: `users/{uid}/pathProgress/{stepId}`.
  static String pathProgressDoc(String uid, String stepId) =>
      '${pathProgressCollection(uid)}/$stepId';

  // --- users/{uid}/chatSessions/{sessionId}/messages/{messageId} ---

  /// A user's chat-sessions collection: `users/{uid}/chatSessions`.
  static String chatSessionsCollection(String uid) =>
      '${userDoc(uid)}/$chatSessions';

  /// A single chat session: `users/{uid}/chatSessions/{sessionId}`.
  static String chatSessionDoc(String uid, String sessionId) =>
      '${chatSessionsCollection(uid)}/$sessionId';

  /// Messages of a chat session:
  /// `users/{uid}/chatSessions/{sessionId}/messages`.
  static String messagesCollection(String uid, String sessionId) =>
      '${chatSessionDoc(uid, sessionId)}/$messages';

  /// A single chat message:
  /// `users/{uid}/chatSessions/{sessionId}/messages/{messageId}`.
  static String messageDoc(String uid, String sessionId, String messageId) =>
      '${messagesCollection(uid, sessionId)}/$messageId';

  // --- users/{uid}/reports/{reportId} ---

  /// A user's reports collection: `users/{uid}/reports`.
  static String reportsCollection(String uid) => '${userDoc(uid)}/$reports';

  /// A single report: `users/{uid}/reports/{reportId}`.
  static String reportDoc(String uid, String reportId) =>
      '${reportsCollection(uid)}/$reportId';

  // --- quizItems/{itemId} ---

  /// The global quiz-item bank collection: `quizItems`.
  static String quizItemsCollection() => quizItems;

  /// A single authored quiz item: `quizItems/{itemId}`.
  static String quizItemDoc(String itemId) => '$quizItems/$itemId';

  // --- users/{uid}/reviewQueue/{itemId} ---

  /// A user's spaced-repetition review queue: `users/{uid}/reviewQueue`.
  static String reviewQueueCollection(String uid) =>
      '${userDoc(uid)}/$reviewQueue';

  /// A single review-queue entry: `users/{uid}/reviewQueue/{itemId}`.
  static String reviewQueueDoc(String uid, String itemId) =>
      '${reviewQueueCollection(uid)}/$itemId';

  // --- users/{uid}/quizSessions/{sessionId} ---

  /// A user's quiz-sessions collection: `users/{uid}/quizSessions`.
  static String quizSessionsCollection(String uid) =>
      '${userDoc(uid)}/$quizSessions';

  /// A single quiz session: `users/{uid}/quizSessions/{sessionId}`.
  static String quizSessionDoc(String uid, String sessionId) =>
      '${quizSessionsCollection(uid)}/$sessionId';

  // --- users/{uid}/progress/main (+ dailyActivity) ---

  /// A user's progress collection: `users/{uid}/progress`.
  static String progressCollection(String uid) => '${userDoc(uid)}/$progress';

  /// A user's singleton progress document: `users/{uid}/progress/main`.
  static String progressDoc(String uid) =>
      '${progressCollection(uid)}/$mainDoc';

  /// Daily-activity collection under progress:
  /// `users/{uid}/progress/main/dailyActivity`.
  static String dailyActivityCollection(String uid) =>
      '${progressDoc(uid)}/$dailyActivity';

  /// A single day's activity document keyed by `yyyy-MM-dd`:
  /// `users/{uid}/progress/main/dailyActivity/{yyyy-mm-dd}`.
  static String dailyActivityDoc(String uid, String yyyyMmDd) =>
      '${dailyActivityCollection(uid)}/$yyyyMmDd';

  // --- users/{uid}/weeklySummaries/{isoWeek} ---

  /// A user's weekly-summaries collection: `users/{uid}/weeklySummaries`.
  static String weeklySummariesCollection(String uid) =>
      '${userDoc(uid)}/$weeklySummaries';

  /// A single ISO-week summary: `users/{uid}/weeklySummaries/{isoWeek}`.
  static String weeklySummaryDoc(String uid, String isoWeek) =>
      '${weeklySummariesCollection(uid)}/$isoWeek';

  // --- users/{uid}/usage/{yyyy-mm-dd} ---

  /// A user's server-written usage collection: `users/{uid}/usage`.
  static String usageCollection(String uid) => '${userDoc(uid)}/$usage';

  /// A single day's usage counters keyed by `yyyy-MM-dd`:
  /// `users/{uid}/usage/{yyyy-mm-dd}`.
  static String usageDoc(String uid, String yyyyMmDd) =>
      '${usageCollection(uid)}/$yyyyMmDd';
}
