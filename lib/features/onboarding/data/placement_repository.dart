import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../core/ai/ai_function_client.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../domain/placement_engine.dart';
import '../domain/placement_question.dart';

/// Drives the adaptive placement test against the server and persists its
/// result. (Requirements 2.4, 2.5, 2.6)
///
/// The difficulty ladder is driven by [PlacementEngine] on the client, but the
/// questions and answer keys live on the server: [nextQuestion] calls the
/// `generatePlacementQuestion` callable with the target band and any prior
/// answers, and the server returns the next question (no answer key) plus the
/// grading of those prior answers. [completePlacement] stores the assigned
/// `placementLevel` and marks the profile `onboarded` with a single merge write
/// so a returning learner's other profile fields are preserved.
class PlacementRepository {
  PlacementRepository({
    required AiFunctionClient aiClient,
    required FirebaseFirestore firestore,
  })  : _aiClient = aiClient,
        _firestore = firestore;

  /// The callable name of the server-side placement question generator.
  static const String callableName = 'generatePlacementQuestion';

  final AiFunctionClient _aiClient;
  final FirebaseFirestore _firestore;

  /// Requests the next placement [question] for [band], grading any
  /// [priorAnswers] server-side.
  ///
  /// The callable returns a discriminated payload (`status` of `ok`,
  /// `limit_reached`, or `refusal`); a non-`ok` status maps to the matching
  /// typed [AppException] so the controller can branch on the failure. A
  /// malformed question also fails rather than rendering a broken step.
  Future<Result<PlacementQuestionResult>> nextQuestion({
    required CefrLevel band,
    List<PlacementAnswer> priorAnswers = const [],
  }) async {
    try {
      final response = await _aiClient.call(callableName, <String, dynamic>{
        'sessionState': <String, dynamic>{
          'band': band.wireValue,
          if (priorAnswers.isNotEmpty)
            'priorAnswers': [
              for (final answer in priorAnswers) answer.toMap(),
            ],
        },
      });

      final status = response['status'];
      if (status == 'limit_reached') {
        return const Result.failure(UsageLimitException());
      }
      if (status == 'refusal') {
        final message = response['safeMessage'];
        return Result.failure(
          ModerationRefusalException(
            message is String && message.isNotEmpty
                ? message
                : 'This request was blocked by content moderation.',
          ),
        );
      }

      final result = response['result'];
      if (result is! Map) {
        return const Result.failure(
          NetworkException('Could not load a placement question.'),
        );
      }
      final resultMap = result.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      final question = PlacementQuestion.fromMap(
        _asStringMap(resultMap['question']),
      );
      if (question == null) {
        return const Result.failure(
          NetworkException('Could not load a placement question.'),
        );
      }

      final graded = <PlacementGrade>[
        for (final raw in (resultMap['gradedAnswers'] as List? ?? const []))
          if (_asStringMap(raw) case final map?)
            if (map['questionId'] is String)
              PlacementGrade(
                questionId: map['questionId'] as String,
                correct: map['correct'] == true,
              ),
      ];

      return Result.success(
        PlacementQuestionResult(question: question, gradedAnswers: graded),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Stores the placement result on the profile: writes the assigned
  /// [level] as `placementLevel`, refines `englishLevel` to match, and marks
  /// the profile `onboarded`. (Requirements 2.5, 2.6)
  ///
  /// A merge write preserves the previously-saved level/goal/native-language
  /// draft. On success the router's `onboardedProvider` seam (backed by the
  /// persisted `onboarded` flag) advances the learner to home.
  Future<Result<void>> completePlacement({
    required String uid,
    required CefrLevel level,
  }) async {
    try {
      await _firestore.doc(FirestorePaths.profileDoc(uid)).set(
        <String, dynamic>{
          'placementLevel': level.wireValue,
          'englishLevel': level.wireValue,
          'onboarded': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy, mirroring
  /// `OnboardingRepository`: connectivity failures map to [NetworkException],
  /// everything else to [AuthException] as a permission/auth failure.
  AppException _mapError(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'unauthenticated') {
        return AuthException(
          error.message ?? 'Please sign in and try again.',
          error,
        );
      }
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return NetworkException(
        error.message ?? 'Could not load a placement question.',
        error,
      );
    }
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Could not save your placement result.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return const NetworkException();
    }
    return AuthException('Could not complete placement.', error);
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
