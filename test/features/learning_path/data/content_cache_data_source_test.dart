// Unit tests for ContentCacheDataSource: caching authored step skeletons
// keyed by contentVersion and serving them for offline read. (Requirement 8.1)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/learning_path/data/content_cache_data_source.dart';
import 'package:learnx/features/learning_path/domain/step_content.dart';

void main() {
  late ContentCacheDataSource cache;

  setUp(() => cache = ContentCacheDataSource());

  const skeletonV1 = StepSkeleton(
    objectives: ['Understand greetings'],
    examples: ['Hello!'],
    practice: ['Greet a friend.'],
  );
  const skeletonV2 = StepSkeleton(
    objectives: ['Understand greetings', 'Introduce yourself'],
    examples: ['Hello!', 'My name is Sam.'],
    practice: ['Greet a friend.', 'Introduce yourself.'],
  );

  test('lookup returns null for a step that was never cached', () {
    expect(cache.lookup(stepId: 's1', contentVersion: 1), isNull);
    expect(cache.lookupAny('s1'), isNull);
    expect(cache.contains(stepId: 's1', contentVersion: 1), isFalse);
  });

  test('caches and serves a skeleton at its exact contentVersion', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 1,
      title: 'Greetings',
      skeleton: skeletonV1,
    );

    final entry = cache.lookup(stepId: 's1', contentVersion: 1);
    expect(entry, isNotNull);
    expect(entry!.title, 'Greetings');
    expect(entry.skeleton, skeletonV1);
    expect(cache.contains(stepId: 's1', contentVersion: 1), isTrue);
  });

  test('a mismatched contentVersion is a deliberate cache miss', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 1,
      title: 'Greetings',
      skeleton: skeletonV1,
    );

    // The authored content changed (version bumped): exact-version lookup
    // misses so the caller reads the live document instead of a stale entry.
    expect(cache.lookup(stepId: 's1', contentVersion: 2), isNull);
  });

  test('bumping contentVersion supersedes the prior entry for the step', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 1,
      title: 'Greetings',
      skeleton: skeletonV1,
    );
    cache.cache(
      stepId: 's1',
      contentVersion: 2,
      title: 'Greetings v2',
      skeleton: skeletonV2,
    );

    // The old version is gone; only the newest is retained per step.
    expect(cache.lookup(stepId: 's1', contentVersion: 1), isNull);
    final current = cache.lookup(stepId: 's1', contentVersion: 2);
    expect(current!.skeleton, skeletonV2);
    expect(current.title, 'Greetings v2');
  });

  test('lookupAny serves the last-cached entry regardless of version', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 7,
      title: 'Greetings',
      skeleton: skeletonV1,
    );

    // The offline fallback does not know the current version; it serves
    // whatever was last cached for the step.
    final entry = cache.lookupAny('s1');
    expect(entry, isNotNull);
    expect(entry!.skeleton, skeletonV1);
    expect(entry.title, 'Greetings');
  });

  test('entries are isolated per step id', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 1,
      title: 'Step 1',
      skeleton: skeletonV1,
    );
    cache.cache(
      stepId: 's2',
      contentVersion: 1,
      title: 'Step 2',
      skeleton: skeletonV2,
    );

    expect(cache.lookupAny('s1')!.title, 'Step 1');
    expect(cache.lookupAny('s2')!.title, 'Step 2');
  });

  test('clear empties the cache', () {
    cache.cache(
      stepId: 's1',
      contentVersion: 1,
      title: 'Step 1',
      skeleton: skeletonV1,
    );

    cache.clear();

    expect(cache.lookupAny('s1'), isNull);
    expect(cache.contains(stepId: 's1', contentVersion: 1), isFalse);
  });
}
