import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

/// Helper: emulate Firestore reading back a written map by turning the
/// `Timestamp` values `toMap()` produces into the shape `fromMap` accepts.
/// Since `fromMap` already accepts `Timestamp`, we can round-trip directly.
void main() {
  final t1 = DateTime.utc(2024, 1, 2, 3, 4, 5);
  final t2 = DateTime.utc(2024, 2, 3, 4, 5, 6);

  group('UserDto', () {
    test('round-trips through fromMap/toMap', () {
      final dto = UserDto(
        createdAt: t1,
        lastActiveAt: t2,
        accountTier: 'premium',
        consent: ConsentDto(
          dpdpAccepted: true,
          acceptedAt: t1,
          policyVersion: 'v3',
        ),
        authMethods: const ['phone', 'google'],
      );

      expect(UserDto.fromMap(dto.toMap()), dto);
    });

    test('defaults tier to free and authMethods to empty', () {
      final dto = UserDto.fromMap(const {});
      expect(dto.accountTier, 'free');
      expect(dto.authMethods, isEmpty);
      expect(dto.consent, isNull);
    });

    test('toMap nests consent as a sub-map', () {
      final dto = UserDto(
        consent: const ConsentDto(dpdpAccepted: true),
        authMethods: const ['email'],
      );
      expect(dto.toMap()['consent'], isA<Map<String, dynamic>>());
    });
  });

  group('ProfileDto', () {
    test('round-trips all enum-valued string fields', () {
      final dto = ProfileDto(
        englishLevel: 'B1',
        goal: 'both',
        nativeLanguage: 'ta',
        placementLevel: 'B2',
        onboarded: true,
        updatedAt: t1,
      );
      expect(ProfileDto.fromMap(dto.toMap()), dto);
    });

    test('defaults onboarded to false', () {
      expect(ProfileDto.fromMap(const {}).onboarded, isFalse);
    });
  });

  group('content DTOs', () {
    test('ContentPathDto / SectionDto / WeekDto round-trip', () {
      const p = ContentPathDto(title: 'Path', order: 0);
      const s = SectionDto(title: 'Sec', order: 1);
      const w = WeekDto(title: 'Wk', order: 2);
      expect(ContentPathDto.fromMap(p.toMap()), p);
      expect(SectionDto.fromMap(s.toMap()), s);
      expect(WeekDto.fromMap(w.toMap()), w);
    });

    test('StepDto round-trips including nested skeleton', () {
      const dto = StepDto(
        title: 'Greetings',
        order: 3,
        type: 'lesson',
        skeleton: StepSkeletonDto(
          objectives: ['say hello'],
          examples: ['Hello!', 'Hi there.'],
          practice: ['Greet a friend'],
        ),
        contentVersion: 7,
      );
      expect(StepDto.fromMap(dto.toMap()), dto);
    });

    test('StepDto defaults skeleton to empty when absent', () {
      final dto = StepDto.fromMap({'title': 't', 'order': 0, 'type': 'x'});
      expect(dto.skeleton, const StepSkeletonDto());
      expect(dto.contentVersion, 0);
    });
  });

  group('PathProgressDto', () {
    test('round-trips', () {
      final dto = PathProgressDto(
        state: 'completed',
        completedAt: t1,
        updatedAt: t2,
      );
      expect(PathProgressDto.fromMap(dto.toMap()), dto);
    });
  });

  group('chat DTOs', () {
    test('GrammarFeedbackDto with a mistake round-trips and keeps span', () {
      const dto = GrammarFeedbackDto(
        hasMistake: true,
        mistakeSpan: MistakeSpanDto(start: 0, end: 3, text: 'I is'),
        correctedSentence: 'I am',
        tip: 'Use "am" with "I".',
        translation: TranslationDto(language: 'hi', text: 'मैं हूँ'),
      );
      final map = dto.toMap();
      expect(map.containsKey('mistakeSpan'), isTrue);
      expect(GrammarFeedbackDto.fromMap(map), dto);
    });

    test('GrammarFeedbackDto omits mistakeSpan when hasMistake is false', () {
      const dto = GrammarFeedbackDto(
        hasMistake: false,
        correctedSentence: 'Looks good.',
        tip: 'No changes needed.',
        translation: TranslationDto(language: 'te', text: 'బాగుంది'),
      );
      final map = dto.toMap();
      expect(map.containsKey('mistakeSpan'), isFalse);
      expect(GrammarFeedbackDto.fromMap(map), dto);
    });

    test(
      'GrammarFeedbackDto drops span in toMap even if provided when no mistake',
      () {
        const dto = GrammarFeedbackDto(
          hasMistake: false,
          mistakeSpan: MistakeSpanDto(start: 0, end: 1, text: 'x'),
          correctedSentence: 'ok',
          tip: 'tip',
          translation: TranslationDto(language: 'bn', text: 'ঠিক আছে'),
        );
        expect(dto.toMap().containsKey('mistakeSpan'), isFalse);
      },
    );

    test('ChatMessageDto round-trips with and without feedback', () {
      final withFeedback = ChatMessageDto(
        role: 'assistant',
        text: 'Nice!',
        grammarFeedback: const GrammarFeedbackDto(
          hasMistake: false,
          correctedSentence: 'Nice!',
          tip: 'Great.',
          translation: TranslationDto(language: 'mr', text: 'छान'),
        ),
        createdAt: t1,
      );
      expect(ChatMessageDto.fromMap(withFeedback.toMap()), withFeedback);

      final plain = ChatMessageDto(role: 'user', text: 'hello', createdAt: t2);
      final decoded = ChatMessageDto.fromMap(plain.toMap());
      expect(decoded, plain);
      expect(decoded.grammarFeedback, isNull);
    });

    test('ChatSessionDto round-trips', () {
      final dto = ChatSessionDto(
        createdAt: t1,
        lastMessageAt: t2,
        title: 'Session 1',
      );
      expect(ChatSessionDto.fromMap(dto.toMap()), dto);
    });
  });

  group('ReportDto', () {
    test('preserves the full context snapshot on round-trip', () {
      const feedback = GrammarFeedbackDto(
        hasMistake: true,
        mistakeSpan: MistakeSpanDto(start: 2, end: 5, text: 'go'),
        correctedSentence: 'I went',
        tip: 'Past tense.',
        translation: TranslationDto(language: 'hi', text: 'मैं गया'),
      );
      final dto = ReportDto(
        sessionId: 'c1',
        messageId: 'm1',
        originalText: 'I go yesterday',
        grammarFeedback: feedback,
        reason: 'wrong tense correction',
        status: 'open',
        createdAt: t1,
      );
      expect(ReportDto.fromMap(dto.toMap()), dto);
    });

    test('defaults status to open', () {
      final dto = ReportDto.fromMap({
        'sessionId': 'c1',
        'messageId': 'm1',
        'originalText': 't',
      });
      expect(dto.status, 'open');
    });
  });

  group('quiz DTOs', () {
    test('QuizItemDto round-trips', () {
      const dto = QuizItemDto(
        type: 'choose_word',
        prompt: 'Pick the correct word',
        options: ['a', 'an', 'the'],
        answer: 'the',
        tags: ['articles'],
      );
      expect(QuizItemDto.fromMap(dto.toMap()), dto);
    });

    test('ReviewQueueItemDto round-trips', () {
      final dto = ReviewQueueItemDto(
        itemId: 'i1',
        intervalIndex: 2,
        dueDate: t1,
        lastResult: 'correct',
        updatedAt: t2,
      );
      expect(ReviewQueueItemDto.fromMap(dto.toMap()), dto);
    });

    test('QuizSessionDto round-trips including updatedAt', () {
      final dto = QuizSessionDto(
        startedAt: t1,
        completedAt: t2,
        correctCount: 8,
        wrongCount: 2,
        updatedAt: t2,
      );
      expect(QuizSessionDto.fromMap(dto.toMap()), dto);
    });
  });

  group('progress DTOs', () {
    test('ProgressDto round-trips including badges list', () {
      final dto = ProgressDto(
        currentStreak: 5,
        longestStreak: 9,
        lastActivityDate: '2024-01-02',
        dailyGoal: const DailyGoalDto(day: 3, targetPerDay: 20),
        badges: [
          BadgeDto(tier: 'bronze', awardedAt: t1, milestone: 'streak-3'),
          BadgeDto(tier: 'silver', awardedAt: t2, milestone: 'streak-7'),
        ],
      );
      expect(ProgressDto.fromMap(dto.toMap()), dto);
    });

    test('ProgressDto defaults are zero/empty', () {
      final dto = ProgressDto.fromMap(const {});
      expect(dto.currentStreak, 0);
      expect(dto.longestStreak, 0);
      expect(dto.badges, isEmpty);
      expect(dto.dailyGoal, const DailyGoalDto());
    });

    test('DailyActivityDto round-trips', () {
      const dto = DailyActivityDto(
        activities: 3,
        timeSpentSec: 600,
        wordsLearned: 12,
        mistakesFixed: 4,
      );
      expect(DailyActivityDto.fromMap(dto.toMap()), dto);
    });

    test('WeeklySummaryDto round-trips', () {
      final dto = WeeklySummaryDto(
        timeSpentSec: 3600,
        wordsLearned: 40,
        mistakesFixed: 15,
        generatedAt: t1,
      );
      expect(WeeklySummaryDto.fromMap(dto.toMap()), dto);
    });
  });

  group('UsageDto', () {
    test('round-trips', () {
      const dto = UsageDto(
        chatMessages: 5,
        lessonPersonalizations: 2,
        placementGenerations: 1,
      );
      expect(UsageDto.fromMap(dto.toMap()), dto);
    });

    test('defaults counters to zero', () {
      final dto = UsageDto.fromMap(const {});
      expect(dto.chatMessages, 0);
      expect(dto.lessonPersonalizations, 0);
      expect(dto.placementGenerations, 0);
    });
  });

  group('interoperates with real Firestore Timestamp values', () {
    test('ProfileDto reads a map containing a Timestamp', () {
      final map = {
        'englishLevel': 'A2',
        'goal': 'speaking',
        'nativeLanguage': 'hi',
        'placementLevel': 'A2',
        'onboarded': true,
        'updatedAt': Timestamp.fromDate(t1),
      };
      expect(ProfileDto.fromMap(map).updatedAt, t1);
    });
  });
}
