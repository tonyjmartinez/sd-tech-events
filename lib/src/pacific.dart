/// San Diego time without a timezone database: US Pacific with DST from the
/// second Sunday of March to the first Sunday of November, both at 2am local.
library;

DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final offset = (DateTime.sunday - first.weekday) % 7;
  return DateTime.utc(year, month, 1 + offset + 7 * (n - 1), 2);
}

bool _isDstWallClock(DateTime wall) =>
    !wall.isBefore(_nthSunday(wall.year, 3, 2)) &&
    wall.isBefore(_nthSunday(wall.year, 11, 1));

/// Converts a San Diego wall-clock time (fields read as-is) to UTC.
DateTime pacificWallToUtc(DateTime wall) {
  final w = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  return w.add(Duration(hours: _isDstWallClock(w) ? 7 : 8));
}

/// The San Diego wall-clock time of [instant], as a UTC-flagged DateTime
/// whose fields read as Pacific time. Use it for display and day grouping.
DateTime toPacific(DateTime instant) {
  final u = instant.toUtc();
  final pdt = u.subtract(const Duration(hours: 7));
  return _isDstWallClock(pdt) ? pdt : u.subtract(const Duration(hours: 8));
}
