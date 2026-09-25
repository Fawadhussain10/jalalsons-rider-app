/// Date/time helpers shared by the order list, cash screen and detail sheets.
///
/// Odoo stores every datetime in UTC and sends it without a zone suffix
/// (e.g. `2026-09-25T06:50:00`). Dart would read that as *local* time, which
/// shifted every order by the device's UTC offset (5 h in Pakistan). Anything
/// coming from the server therefore goes through [parseServerTime].
class TimeUtils {
  TimeUtils._();

  static final RegExp _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Parses a server timestamp to local time. Strings without a zone are UTC.
  static DateTime? parseServerTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is! String || value.isEmpty) return null;
    final text = value.trim().replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(_hasZone.hasMatch(text) ? text : '${text}Z');
    return parsed?.toLocal();
  }

  /// Timestamp to write into Firestore: UTC, so every writer agrees.
  static String nowForServer() => DateTime.now().toUtc().toIso8601String();

  /// Local midnight that starts "today".
  static DateTime startOfToday([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Oldest order the app still needs: previous-day orders are kept only while
  /// undelivered, so nothing older than yesterday's midnight is fetched.
  static DateTime carryOverStart([DateTime? now]) =>
      startOfToday(now).subtract(const Duration(days: 1));

  /// Server-format (naive UTC, second precision) string for Firestore range
  /// queries on `createdAt`, which Odoo writes as `YYYY-MM-DDTHH:MM:SS`.
  static String toServerQueryString(DateTime local) {
    final u = local.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  static Duration untilNextMidnight([DateTime? now]) {
    final n = now ?? DateTime.now();
    return startOfToday(n).add(const Duration(days: 1)).difference(n);
  }

  static String timeOfDay(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Just now", "12 min ago", "3:40 PM", "Yesterday 11:50 PM".
  static String relative(DateTime t, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final diff = n.difference(t);
    if (diff.inMinutes < 1 && !diff.isNegative) return 'Just now';
    if (diff.inMinutes < 60 && !diff.isNegative) return '${diff.inMinutes} min ago';
    final today = startOfToday(n);
    if (!t.isBefore(today)) return timeOfDay(t);
    if (!t.isBefore(today.subtract(const Duration(days: 1)))) return 'Yesterday ${timeOfDay(t)}';
    return '${t.day}/${t.month} ${timeOfDay(t)}';
  }

  static String duration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}
