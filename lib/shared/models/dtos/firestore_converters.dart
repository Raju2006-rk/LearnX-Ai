import 'package:cloud_firestore/cloud_firestore.dart';

/// Conversion helpers shared by the DTO layer.
///
/// DTOs speak plain Dart types (`DateTime`, `String`, `int`, `List`) so they
/// stay pure and testable, while Firestore stores timestamps as [Timestamp].
/// These helpers normalize between the two and defensively read fields that
/// may arrive in more than one shape (for example a value written by the
/// client as a [Timestamp] vs. a cached value surfaced as a [DateTime]).
///
/// All functions are pure: no I/O, no Firestore instance required.

/// Reads a timestamp field that may be a Firestore [Timestamp], a
/// [DateTime], or an ISO-8601 [String], returning `null` when absent or
/// unrecognized.
///
/// The result is always normalized to UTC so instants compare and serialize
/// deterministically regardless of the device time zone. (Firestore's
/// [Timestamp.toDate] otherwise returns a local-time [DateTime].) DTOs are
/// therefore expected to carry timestamps as UTC instants.
DateTime? dateTimeFromFirestore(Object? value) {
  return switch (value) {
    null => null,
    final Timestamp t => t.toDate().toUtc(),
    final DateTime d => d.toUtc(),
    final String s => DateTime.tryParse(s)?.toUtc(),
    final int millis =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    _ => null,
  };
}

/// Converts a [DateTime] to a Firestore [Timestamp], preserving `null`.
///
/// Server-managed creation timestamps are written by repositories using
/// `FieldValue.serverTimestamp()`; this helper is for client-supplied or
/// already-known instants that participate in last-write-wins sync.
Timestamp? timestampFromDateTime(DateTime? value) {
  return value == null ? null : Timestamp.fromDate(value);
}

/// Reads a required string field, falling back to [fallback] (default empty)
/// when the value is missing or not a string.
String stringOr(Object? value, [String fallback = '']) {
  return value is String ? value : fallback;
}

/// Reads a nullable string field, returning `null` when absent or not a
/// string.
String? stringOrNull(Object? value) => value is String ? value : null;

/// Reads an integer field that may be stored as an `int`, a `num`, or a
/// numeric `String`, falling back to [fallback] (default `0`).
int intOr(Object? value, [int fallback = 0]) {
  return switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };
}

/// Reads a boolean field, falling back to [fallback] (default `false`).
bool boolOr(Object? value, [bool fallback = false]) {
  return value is bool ? value : fallback;
}

/// Reads a `List<String>` field, dropping non-string entries and returning
/// an empty list when absent.
List<String> stringListFrom(Object? value) {
  if (value is! Iterable) return const [];
  return value.whereType<String>().toList(growable: false);
}

/// Reads a `List<Map<String, dynamic>>` field (a list of nested documents),
/// returning an empty list when absent.
List<Map<String, dynamic>> mapListFrom(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
      .toList(growable: false);
}

/// Reads a nested map field, returning `null` when absent or not a map.
Map<String, dynamic>? mapOrNull(Object? value) {
  if (value is! Map) return null;
  return value.map((k, v) => MapEntry(k.toString(), v));
}
