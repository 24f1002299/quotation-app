import 'dart:math';

/// Day 20 — Support error-report IDs.
///
/// A short, human-readable reference the user can share with support over a
/// phone call: `ERR-20260928-A3F9K2`. Never shown as a technical error code
/// in the normal UI — it lives behind a `Get help` link (design.md).
/// Pure functions so they are unit-testable.
String newErrorReportId([DateTime? now]) {
  final d = now ?? DateTime.now();
  final date =
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I confusion
  final rnd = Random.secure();
  final suffix =
      List.generate(6, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  return 'ERR-$date-$suffix';
}

/// True when [value] looks like an ID produced by [newErrorReportId].
bool isValidErrorReportId(String value) {
  return RegExp(r'^ERR-\d{8}-[A-HJ-NP-Z2-9]{6}$').hasMatch(value.trim());
}

/// One-line support context: safe to copy into WhatsApp/email. Contains no
/// customer PII — only the report ID, failing area, and app timestamp.
String supportContextLine({
  required String errorReportId,
  required String area,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toIso8601String();
  return 'Report $errorReportId · $area · $at';
}
