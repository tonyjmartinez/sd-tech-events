import 'event.dart';
import 'pacific.dart';

enum When {
  upcoming('Upcoming'),
  today('Today'),
  week('Next 7 days'),
  weekend('This weekend'),
  month('Next 30 days');

  const When(this.label);
  final String label;
}

class EventFilter {
  const EventFilter({
    this.query = '',
    this.when = When.upcoming,
    this.inPersonOnly = false,
    this.freeOnly = false,
    this.sources = const {},
  });

  final String query;
  final When when;
  final bool inPersonOnly;
  final bool freeOnly;

  /// Empty means all sources.
  final Set<EventSource> sources;

  EventFilter copyWith({
    String? query,
    When? when,
    bool? inPersonOnly,
    bool? freeOnly,
    Set<EventSource>? sources,
  }) => EventFilter(
    query: query ?? this.query,
    when: when ?? this.when,
    inPersonOnly: inPersonOnly ?? this.inPersonOnly,
    freeOnly: freeOnly ?? this.freeOnly,
    sources: sources ?? this.sources,
  );

  bool get isDefault =>
      query.isEmpty &&
      when == When.upcoming &&
      !inPersonOnly &&
      !freeOnly &&
      sources.isEmpty;

  /// Date windows are San Diego days, wherever the viewer is.
  List<TechEvent> apply(List<TechEvent> events, DateTime now) {
    final wall = toPacific(now);
    final today = DateTime.utc(wall.year, wall.month, wall.day);
    final (from, to) = switch (when) {
      When.upcoming => (null, null),
      When.today => (null, today.add(const Duration(days: 1))),
      When.week => (null, today.add(const Duration(days: 8))),
      When.month => (null, today.add(const Duration(days: 31))),
      When.weekend => _weekend(today),
    };
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return [
      for (final e in events)
        if ((e.end ?? e.start.add(const Duration(hours: 2))).isAfter(now) &&
            (from == null || !toPacific(e.start).isBefore(from)) &&
            (to == null || toPacific(e.start).isBefore(to)) &&
            (!inPersonOnly || !e.online) &&
            (!freeOnly || e.free == true) &&
            (sources.isEmpty ||
                sources.contains(EventSource.byName(e.source))) &&
            terms.every(e.searchText.contains))
          e,
    ];
  }

  /// Friday 5pm through Sunday night, in San Diego wall-clock time.
  static (DateTime?, DateTime) _weekend(DateTime today) {
    final back = today.weekday >= DateTime.friday
        ? today.weekday - DateTime.friday
        : -((DateTime.friday - today.weekday) % 7);
    final friday = today.subtract(Duration(days: back));
    return (
      friday.add(const Duration(hours: 17)),
      friday.add(const Duration(days: 3)),
    );
  }
}
