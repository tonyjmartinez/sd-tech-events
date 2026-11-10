import 'package:intl/intl.dart';

import 'event.dart';
import 'pacific.dart';

String dayHeading(DateTime day, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final diff = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return DateFormat(day.year == now.year ? 'EEEE, MMM d' : 'EEEE, MMM d, y')
      .format(day);
}

String timeRange(TechEvent e) {
  final start = toPacific(e.start);
  final t = DateFormat.jm();
  final end = e.end == null ? null : toPacific(e.end!);
  if (end == null) return t.format(start);
  final sameDay =
      end.year == start.year &&
      end.month == start.month &&
      end.day == start.day;
  return sameDay
      ? '${t.format(start)} – ${t.format(end)}'
      : '${t.format(start)} – ${DateFormat('MMM d').format(end)}';
}

String updatedAgo(DateTime updated, DateTime now) {
  final d = now.difference(updated);
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// Google Calendar "add event" link; works on web and mobile without plugins.
Uri googleCalendarUri(TechEvent e) {
  String fmt(DateTime d) =>
      '${DateFormat("yyyyMMdd'T'HHmmss").format(d.toUtc())}Z';
  final end = e.end ?? e.start.add(const Duration(hours: 2));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': e.title,
    'dates': '${fmt(e.start)}/${fmt(end)}',
    'details': '${e.url}\n\n${e.description ?? ''}'.trim(),
    if (e.venue != null) 'location': e.venue!,
  });
}
