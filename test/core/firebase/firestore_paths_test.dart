import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';

void main() {
  group('user + profile paths', () {
    test('userDoc and usersCollection', () {
      expect(FirestorePaths.usersCollection(), 'users');
      expect(FirestorePaths.userDoc('u1'), 'users/u1');
    });

    test('profile collection and singleton doc', () {
      expect(FirestorePaths.profileCollection('u1'), 'users/u1/profile');
      expect(FirestorePaths.profileDoc('u1'), 'users/u1/profile/main');
    });
  });

  group('authored content paths', () {
    test('paths, sections, weeks, steps nest correctly', () {
      expect(FirestorePaths.contentPathsCollection(), 'content');
      expect(FirestorePaths.contentPathDoc('p1'), 'content/p1');
      expect(
        FirestorePaths.sectionsCollection('p1'),
        'content/p1/sections',
      );
      expect(
        FirestorePaths.sectionDoc('p1', 's1'),
        'content/p1/sections/s1',
      );
      expect(
        FirestorePaths.weeksCollection('p1', 's1'),
        'content/p1/sections/s1/weeks',
      );
      expect(
        FirestorePaths.weekDoc('p1', 's1', 'w1'),
        'content/p1/sections/s1/weeks/w1',
      );
      expect(
        FirestorePaths.stepsCollection('p1', 's1', 'w1'),
        'content/p1/sections/s1/weeks/w1/steps',
      );
      expect(
        FirestorePaths.stepDoc('p1', 's1', 'w1', 'st1'),
        'content/p1/sections/s1/weeks/w1/steps/st1',
      );
    });
  });

  group('per-user feature paths', () {
    test('path progress', () {
      expect(
        FirestorePaths.pathProgressCollection('u1'),
        'users/u1/pathProgress',
      );
      expect(
        FirestorePaths.pathProgressDoc('u1', 'st1'),
        'users/u1/pathProgress/st1',
      );
    });

    test('chat sessions and messages', () {
      expect(
        FirestorePaths.chatSessionsCollection('u1'),
        'users/u1/chatSessions',
      );
      expect(
        FirestorePaths.chatSessionDoc('u1', 'c1'),
        'users/u1/chatSessions/c1',
      );
      expect(
        FirestorePaths.messagesCollection('u1', 'c1'),
        'users/u1/chatSessions/c1/messages',
      );
      expect(
        FirestorePaths.messageDoc('u1', 'c1', 'm1'),
        'users/u1/chatSessions/c1/messages/m1',
      );
    });

    test('reports', () {
      expect(FirestorePaths.reportsCollection('u1'), 'users/u1/reports');
      expect(FirestorePaths.reportDoc('u1', 'r1'), 'users/u1/reports/r1');
    });

    test('review queue', () {
      expect(
        FirestorePaths.reviewQueueCollection('u1'),
        'users/u1/reviewQueue',
      );
      expect(
        FirestorePaths.reviewQueueDoc('u1', 'i1'),
        'users/u1/reviewQueue/i1',
      );
    });

    test('quiz sessions', () {
      expect(
        FirestorePaths.quizSessionsCollection('u1'),
        'users/u1/quizSessions',
      );
      expect(
        FirestorePaths.quizSessionDoc('u1', 'q1'),
        'users/u1/quizSessions/q1',
      );
    });

    test('progress and daily activity', () {
      expect(FirestorePaths.progressCollection('u1'), 'users/u1/progress');
      expect(FirestorePaths.progressDoc('u1'), 'users/u1/progress/main');
      expect(
        FirestorePaths.dailyActivityCollection('u1'),
        'users/u1/progress/main/dailyActivity',
      );
      expect(
        FirestorePaths.dailyActivityDoc('u1', '2024-01-02'),
        'users/u1/progress/main/dailyActivity/2024-01-02',
      );
    });

    test('weekly summaries', () {
      expect(
        FirestorePaths.weeklySummariesCollection('u1'),
        'users/u1/weeklySummaries',
      );
      expect(
        FirestorePaths.weeklySummaryDoc('u1', '2024-W01'),
        'users/u1/weeklySummaries/2024-W01',
      );
    });

    test('usage', () {
      expect(FirestorePaths.usageCollection('u1'), 'users/u1/usage');
      expect(
        FirestorePaths.usageDoc('u1', '2024-01-02'),
        'users/u1/usage/2024-01-02',
      );
    });
  });

  group('global quiz items', () {
    test('collection and doc', () {
      expect(FirestorePaths.quizItemsCollection(), 'quizItems');
      expect(FirestorePaths.quizItemDoc('i1'), 'quizItems/i1');
    });
  });

  group('path segment parity (user tree + global quiz items)', () {
    // Firestore requires document references to have an even number of
    // segments and collection references an odd number. The per-user tree, the
    // global quizItems collection, and the authored `content/**` tree all
    // follow this alternation, so every `*Doc` helper is a valid document
    // reference and every collection helper a valid collection reference.
    int segments(String p) => p.split('/').length;

    test('document helpers yield even segment counts', () {
      expect(segments(FirestorePaths.userDoc('u1')).isEven, isTrue);
      expect(segments(FirestorePaths.profileDoc('u1')).isEven, isTrue);
      expect(segments(FirestorePaths.pathProgressDoc('u1', 's')).isEven, isTrue);
      expect(
        segments(FirestorePaths.messageDoc('u1', 'c1', 'm1')).isEven,
        isTrue,
      );
      expect(segments(FirestorePaths.reportDoc('u1', 'r')).isEven, isTrue);
      expect(segments(FirestorePaths.reviewQueueDoc('u1', 'i')).isEven, isTrue);
      expect(segments(FirestorePaths.quizSessionDoc('u1', 'q')).isEven, isTrue);
      expect(segments(FirestorePaths.progressDoc('u1')).isEven, isTrue);
      expect(
        segments(FirestorePaths.dailyActivityDoc('u1', 'd')).isEven,
        isTrue,
      );
      expect(
        segments(FirestorePaths.weeklySummaryDoc('u1', 'w')).isEven,
        isTrue,
      );
      expect(segments(FirestorePaths.usageDoc('u1', 'd')).isEven, isTrue);
      expect(segments(FirestorePaths.quizItemDoc('i')).isEven, isTrue);
      // Authored content tree.
      expect(segments(FirestorePaths.contentPathDoc('p')).isEven, isTrue);
      expect(segments(FirestorePaths.sectionDoc('p', 's')).isEven, isTrue);
      expect(segments(FirestorePaths.weekDoc('p', 's', 'w')).isEven, isTrue);
      expect(
        segments(FirestorePaths.stepDoc('p', 's', 'w', 'st')).isEven,
        isTrue,
      );
    });

    test('collection helpers yield odd segment counts', () {
      expect(segments(FirestorePaths.usersCollection()).isOdd, isTrue);
      expect(segments(FirestorePaths.profileCollection('u1')).isOdd, isTrue);
      expect(
        segments(FirestorePaths.pathProgressCollection('u1')).isOdd,
        isTrue,
      );
      expect(
        segments(FirestorePaths.chatSessionsCollection('u1')).isOdd,
        isTrue,
      );
      expect(
        segments(FirestorePaths.dailyActivityCollection('u1')).isOdd,
        isTrue,
      );
      expect(segments(FirestorePaths.quizItemsCollection()).isOdd, isTrue);
      // Authored content tree.
      expect(segments(FirestorePaths.contentPathsCollection()).isOdd, isTrue);
      expect(segments(FirestorePaths.sectionsCollection('p')).isOdd, isTrue);
      expect(segments(FirestorePaths.weeksCollection('p', 's')).isOdd, isTrue);
      expect(
        segments(FirestorePaths.stepsCollection('p', 's', 'w')).isOdd,
        isTrue,
      );
    });
  });
}
