import 'package:intl/intl.dart';

/// Formats a last-seen timestamp the way messaging apps do:
///
/// * today      → "last seen today at 2:05 PM"
/// * yesterday  → "last seen yesterday at 2:05 PM"
/// * this week  → "last seen Mon at 2:05 PM"
/// * this year  → "last seen 12 Mar"
/// * older      → "last seen 12 Mar 2025"
///
/// Absolute rather than "5 min ago" so the label never needs a ticking timer.
String formatLastSeen(DateTime lastSeen, {DateTime? now, String? locale}) {
  final seen = lastSeen.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final time = DateFormat.jm(locale).format(seen);

  final today = DateTime(current.year, current.month, current.day);
  final seenDay = DateTime(seen.year, seen.month, seen.day);
  final daysAgo = today.difference(seenDay).inDays;

  if (daysAgo <= 0) return 'last seen today at $time';
  if (daysAgo == 1) return 'last seen yesterday at $time';
  if (daysAgo < 7) {
    return 'last seen ${DateFormat.E(locale).format(seen)} at $time';
  }
  if (seen.year == current.year) {
    return 'last seen ${DateFormat('d MMM', locale).format(seen)}';
  }
  return 'last seen ${DateFormat('d MMM y', locale).format(seen)}';
}
