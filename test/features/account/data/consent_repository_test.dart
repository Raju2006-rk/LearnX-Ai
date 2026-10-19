// Unit tests for ConsentRepository: the DPDP consent write records
// dpdpAccepted + acceptedAt without touching the server-owned policyVersion,
// merges without clobbering sibling user fields, and reads consent back.
// (Requirement 10.3)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/account/data/consent_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ConsentRepository repository;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ConsentRepository(firestore: firestore);
  });

  Future<Map<String, dynamic>?> readUser() async =>
      (await firestore.doc(FirestorePaths.userDoc(uid)).get()).data();

  test('acceptDpdp records dpdpAccepted and acceptedAt', () async {
    // The auth repository has already created the user root doc.
    await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
      'accountTier': 'free',
      'authMethods': ['email'],
    });

    final result = await repository.acceptDpdp(uid: uid);

    expect(result, isA<Success<void>>());
    final user = await readUser();
    final consent = user!['consent'] as Map<String, dynamic>;
    expect(consent['dpdpAccepted'], isTrue);
    expect(consent['acceptedAt'], isNotNull);
  });

  test('acceptDpdp does not write the server-owned policyVersion', () async {
    await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
      'accountTier': 'free',
    });

    await repository.acceptDpdp(uid: uid);

    final consent = (await readUser())!['consent'] as Map<String, dynamic>;
    // The client records acceptance only; policyVersion is stamped server-side
    // (read-only to clients), so it must be absent from the client write.
    expect(consent.containsKey('policyVersion'), isFalse);
  });

  test('acceptDpdp merges without clobbering sibling user fields', () async {
    await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
      'accountTier': 'free',
      'authMethods': ['phone', 'google'],
    });

    await repository.acceptDpdp(uid: uid);

    final user = await readUser();
    expect(user!['accountTier'], 'free');
    expect(user['authMethods'], ['phone', 'google']);
    expect((user['consent'] as Map)['dpdpAccepted'], isTrue);
  });

  test('acceptDpdp preserves an existing server-stamped policyVersion',
      () async {
    // Simulate a doc where the server already stamped the policy version.
    await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
      'accountTier': 'free',
      'consent': {'policyVersion': 'v1'},
    });

    await repository.acceptDpdp(uid: uid);

    final consent = (await readUser())!['consent'] as Map<String, dynamic>;
    // Merge preserves the sibling policyVersion within the consent map.
    expect(consent['policyVersion'], 'v1');
    expect(consent['dpdpAccepted'], isTrue);
    expect(consent['acceptedAt'], isNotNull);
  });

  group('loadConsent', () {
    test('returns null when the user document does not exist', () async {
      final result = await repository.loadConsent(uid);
      expect(result.valueOrNull, isNull);
    });

    test('returns null consent when no consent block is recorded', () async {
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
      });
      final result = await repository.loadConsent(uid);
      expect(result.valueOrNull, isNull);
    });

    test('reads a recorded consent block', () async {
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'consent': {
          'dpdpAccepted': true,
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
          'policyVersion': 'v1',
        },
      });

      final consent = (await repository.loadConsent(uid)).valueOrNull;
      expect(consent, isNotNull);
      expect(consent!.dpdpAccepted, isTrue);
      expect(consent.policyVersion, 'v1');
      expect(consent.acceptedAt, DateTime.utc(2024, 1, 2));
    });
  });
}
