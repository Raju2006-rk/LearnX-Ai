import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The learner's entitlement level. Premium is reserved for the billing phase;
/// the MVP defaults every account to [AccountTier.free].
enum AccountTier {
  free,
  premium;

  /// The Remote Config key segment used for this tier's limits.
  String get key => name;
}

/// A metered AI action subject to a per-tier daily [Usage_Limit].
///
/// The names mirror the server-side `kind` values used by the `AI_Proxy`
/// middleware so limits line up across client and functions.
enum MeteredAction {
  chat('chatMessages'),
  lessonPersonalization('lessonPersonalizations'),
  placementQuestion('placementGenerations');

  const MeteredAction(this.usageField);

  /// The counter field under `users/{uid}/usage/{yyyy-mm-dd}`.
  final String usageField;
}

/// A configured badge milestone: the [tier] awarded when a progress value
/// reaches [threshold] (for example, a current streak of [threshold] days).
///
/// Milestones come from config so the award thresholds are centralized and
/// can be retuned without shipping a build, matching the design's "badges are
/// client-evaluated against server-defined thresholds". (Requirement 7.3)
///
/// A milestone's [id] is the stable identifier recorded on an awarded
/// `progress/main.badges[]` entry (its `milestone` field) so awarding stays
/// idempotent — a milestone is awarded at most once.
@immutable
class BadgeMilestone {
  const BadgeMilestone({
    required this.id,
    required this.tier,
    required this.threshold,
  }) : assert(threshold >= 0, 'milestone threshold cannot be negative');

  /// Stable identifier recorded on the awarded badge (e.g. `"streak-7"`).
  final String id;

  /// The reward tier earned when [threshold] is reached.
  final BadgeTier tier;

  /// The progress value (inclusive) at which this milestone is crossed.
  final int threshold;

  @override
  bool operator ==(Object other) =>
      other is BadgeMilestone &&
      other.id == id &&
      other.tier == tier &&
      other.threshold == threshold;

  @override
  int get hashCode => Object.hash(id, tier, threshold);

  @override
  String toString() =>
      'BadgeMilestone(id: $id, tier: ${tier.name}, threshold: $threshold)';
}

/// The reward tiers a learner can earn as they cross configured progress
/// milestones. Mirrors the progress feature's `BadgeTier`; kept here so the
/// config layer can describe milestones without depending on a feature.
enum BadgeTier { bronze, silver, gold }

/// Client-side feature flags. Values are read from Remote Config so features
/// can be toggled without shipping a new build.
enum FeatureFlag {
  offlineContentCache('feature_offline_content_cache'),
  weeklySummary('feature_weekly_summary'),
  premiumPlaceholder('feature_premium_placeholder');

  const FeatureFlag(this.key);

  /// The Remote Config key backing this flag.
  final String key;
}

/// Reads tier usage limits and feature flags from Firebase Remote Config,
/// falling back to built-in defaults when a value is missing or a fetch has
/// not completed.
///
/// Limits are keyed `limit_{tier}_{action}` (for example
/// `limit_free_chatMessages`). The client uses these to show remaining quota;
/// the authoritative enforcement happens server-side in the `AI_Proxy`.
/// (Requirements 11.3)
class RemoteConfigService {
  RemoteConfigService(this._remoteConfig);

  final FirebaseRemoteConfig _remoteConfig;

  /// Built-in default daily limits by tier and action. Used as Remote Config
  /// defaults and as the fallback when no fetched value is available.
  static const Map<AccountTier, Map<MeteredAction, int>> _defaultLimits = {
    AccountTier.free: {
      MeteredAction.chat: 20,
      MeteredAction.lessonPersonalization: 10,
      MeteredAction.placementQuestion: 12,
    },
    AccountTier.premium: {
      MeteredAction.chat: 500,
      MeteredAction.lessonPersonalization: 200,
      MeteredAction.placementQuestion: 50,
    },
  };

  /// Built-in default feature-flag states.
  static const Map<FeatureFlag, bool> _defaultFlags = {
    FeatureFlag.offlineContentCache: true,
    FeatureFlag.weeklySummary: true,
    FeatureFlag.premiumPlaceholder: true,
  };

  /// The Remote Config key carrying the badge-milestone thresholds, encoded as
  /// a JSON array of `{ "id", "tier", "threshold" }` objects.
  static const String badgeMilestonesKey = 'badge_milestones';

  /// Built-in default badge milestones, keyed on the learner's current streak.
  /// Thresholds climb Bronze → Silver → Gold. Used as the Remote Config
  /// default and the fallback when no fetched value is available or a fetched
  /// value is malformed. (Requirement 7.3)
  static const List<BadgeMilestone> _defaultMilestones = [
    BadgeMilestone(id: 'streak-3', tier: BadgeTier.bronze, threshold: 3),
    BadgeMilestone(id: 'streak-7', tier: BadgeTier.silver, threshold: 7),
    BadgeMilestone(id: 'streak-15', tier: BadgeTier.gold, threshold: 15),
  ];

  /// The Remote Config key for a tier/action daily limit.
  static String limitKey(AccountTier tier, MeteredAction action) =>
      'limit_${tier.key}_${action.usageField}';

  /// Configures fetch settings, seeds defaults, and activates any cached
  /// values. Safe to call once during startup.
  Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await _remoteConfig.setDefaults(_buildDefaults());
    try {
      await _remoteConfig.fetchAndActivate();
    } on Exception {
      // A failed fetch is non-fatal: defaults (and any previously activated
      // values) remain in effect.
    }
  }

  /// The daily [Usage_Limit] for [action] on [tier].
  int limitFor(AccountTier tier, MeteredAction action) {
    final key = limitKey(tier, action);
    final value = _remoteConfig.getInt(key);
    if (value > 0) return value;
    return _defaultLimits[tier]?[action] ?? 0;
  }

  /// Whether [flag] is enabled.
  bool isFeatureEnabled(FeatureFlag flag) {
    final value = _remoteConfig.getValue(flag.key);
    if (value.source == ValueSource.valueStatic) {
      return _defaultFlags[flag] ?? false;
    }
    return value.asBool();
  }

  /// The configured badge milestones, ordered by ascending [threshold] so the
  /// badge-awarding rule can walk them from lowest to highest.
  ///
  /// Reads the JSON array stored under [badgeMilestonesKey]; falls back to the
  /// built-in [_defaultMilestones] when the fetched value is absent (static
  /// source), empty, not valid JSON, or does not describe any usable
  /// milestone — so a misconfigured value can never leave the client with no
  /// milestones to award against. (Requirement 7.3)
  List<BadgeMilestone> badgeMilestones() {
    final value = _remoteConfig.getValue(badgeMilestonesKey);
    if (value.source == ValueSource.valueStatic) {
      return _sortedMilestones(_defaultMilestones);
    }
    final parsed = _parseMilestones(value.asString());
    if (parsed.isEmpty) return _sortedMilestones(_defaultMilestones);
    return _sortedMilestones(parsed);
  }

  /// Parses a Remote Config JSON string into milestones, silently dropping any
  /// malformed entry (missing id, unknown tier, missing/negative threshold)
  /// so one bad entry never discards the rest. Returns an empty list when the
  /// value cannot be parsed at all, signalling the caller to fall back.
  List<BadgeMilestone> _parseMilestones(String raw) {
    if (raw.trim().isEmpty) return const [];
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final milestones = <BadgeMilestone>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final tier = _tierFromName(entry['tier']);
      final threshold = entry['threshold'];
      if (id is! String || id.isEmpty) continue;
      if (tier == null) continue;
      if (threshold is! int || threshold < 0) continue;
      milestones.add(BadgeMilestone(id: id, tier: tier, threshold: threshold));
    }
    return milestones;
  }

  static BadgeTier? _tierFromName(Object? name) {
    if (name is! String) return null;
    for (final tier in BadgeTier.values) {
      if (tier.name == name) return tier;
    }
    return null;
  }

  static List<BadgeMilestone> _sortedMilestones(List<BadgeMilestone> source) {
    final sorted = [...source]
      ..sort((a, b) => a.threshold.compareTo(b.threshold));
    return List.unmodifiable(sorted);
  }

  Map<String, Object> _buildDefaults() {
    final defaults = <String, Object>{};
    _defaultLimits.forEach((tier, actions) {
      actions.forEach((action, limit) {
        defaults[limitKey(tier, action)] = limit;
      });
    });
    _defaultFlags.forEach((flag, enabled) {
      defaults[flag.key] = enabled;
    });
    defaults[badgeMilestonesKey] = jsonEncode(
      _defaultMilestones
          .map(
            (m) => <String, Object>{
              'id': m.id,
              'tier': m.tier.name,
              'threshold': m.threshold,
            },
          )
          .toList(growable: false),
    );
    return defaults;
  }
}

/// Exposes the platform [FirebaseRemoteConfig] as a provider.
final firebaseRemoteConfigProvider = Provider<FirebaseRemoteConfig>(
  (ref) => FirebaseRemoteConfig.instance,
  name: 'firebaseRemoteConfigProvider',
);

/// The app-facing [RemoteConfigService].
final remoteConfigServiceProvider = Provider<RemoteConfigService>(
  (ref) => RemoteConfigService(ref.watch(firebaseRemoteConfigProvider)),
  name: 'remoteConfigServiceProvider',
);
