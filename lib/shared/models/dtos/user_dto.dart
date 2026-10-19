import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for the DPDP consent block stored on the user root document.
///
/// Mirrors `users/{uid}.consent`:
/// `{ dpdpAccepted, acceptedAt, policyVersion }`.
@immutable
class ConsentDto {
  const ConsentDto({
    required this.dpdpAccepted,
    this.acceptedAt,
    this.policyVersion,
  });

  factory ConsentDto.fromMap(Map<String, dynamic> map) {
    return ConsentDto(
      dpdpAccepted: boolOr(map['dpdpAccepted']),
      acceptedAt: dateTimeFromFirestore(map['acceptedAt']),
      policyVersion: stringOrNull(map['policyVersion']),
    );
  }

  /// Whether the learner accepted DPDP personal-data processing.
  final bool dpdpAccepted;

  /// When consent was recorded.
  final DateTime? acceptedAt;

  /// The policy version the learner accepted (read-only to clients).
  final String? policyVersion;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'dpdpAccepted': dpdpAccepted,
      'acceptedAt': timestampFromDateTime(acceptedAt),
      'policyVersion': policyVersion,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ConsentDto &&
      other.dpdpAccepted == dpdpAccepted &&
      other.acceptedAt == acceptedAt &&
      other.policyVersion == policyVersion;

  @override
  int get hashCode => Object.hash(dpdpAccepted, acceptedAt, policyVersion);
}

/// DTO for the user root document `users/{uid}`.
///
/// Mirrors: `createdAt, lastActiveAt, accountTier ("free"|"premium"),
/// consent, authMethods (["phone"|"google"|"email"])`.
///
/// Enum-valued fields (`accountTier`, `authMethods`) are carried as raw
/// strings; feature domain types validate/parse them later.
@immutable
class UserDto {
  const UserDto({
    this.createdAt,
    this.lastActiveAt,
    this.accountTier = 'free',
    this.consent,
    this.authMethods = const [],
  });

  factory UserDto.fromMap(Map<String, dynamic> map) {
    final consentMap = mapOrNull(map['consent']);
    return UserDto(
      createdAt: dateTimeFromFirestore(map['createdAt']),
      lastActiveAt: dateTimeFromFirestore(map['lastActiveAt']),
      accountTier: stringOr(map['accountTier'], 'free'),
      consent: consentMap == null ? null : ConsentDto.fromMap(consentMap),
      authMethods: stringListFrom(map['authMethods']),
    );
  }

  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  /// `"free" | "premium"` — premium reserved; MVP defaults free.
  final String accountTier;

  final ConsentDto? consent;

  /// Any of `"phone" | "google" | "email"`.
  final List<String> authMethods;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'createdAt': timestampFromDateTime(createdAt),
      'lastActiveAt': timestampFromDateTime(lastActiveAt),
      'accountTier': accountTier,
      'consent': consent?.toMap(),
      'authMethods': authMethods,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is UserDto &&
      other.createdAt == createdAt &&
      other.lastActiveAt == lastActiveAt &&
      other.accountTier == accountTier &&
      other.consent == consent &&
      listEquals(other.authMethods, authMethods);

  @override
  int get hashCode => Object.hash(
        createdAt,
        lastActiveAt,
        accountTier,
        consent,
        Object.hashAll(authMethods),
      );
}
