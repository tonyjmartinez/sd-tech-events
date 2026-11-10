/// A single tech or startup event. Pure Dart so the aggregator in `tool/`
/// can share it with the app.
class TechEvent {
  const TechEvent({
    required this.id,
    required this.source,
    required this.title,
    required this.start,
    required this.url,
    this.end,
    this.organizer,
    this.venue,
    this.city,
    this.online = false,
    this.imageUrl,
    this.description,
    this.free,
  });

  /// Stable id, prefixed with the source (e.g. `meetup:317317398`).
  final String id;

  /// One of [EventSource.values] names.
  final String source;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String url;
  final String? organizer;
  final String? venue;
  final String? city;
  final bool online;
  final String? imageUrl;
  final String? description;

  /// `true` free, `false` paid, `null` unknown.
  final bool? free;

  factory TechEvent.fromJson(Map<String, dynamic> j) => TechEvent(
    id: j['id'] as String,
    source: j['source'] as String,
    title: j['title'] as String,
    start: DateTime.parse(j['start'] as String),
    end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
    url: j['url'] as String,
    organizer: j['organizer'] as String?,
    venue: j['venue'] as String?,
    city: j['city'] as String?,
    online: j['online'] as bool? ?? false,
    imageUrl: j['image'] as String?,
    description: j['description'] as String?,
    free: j['free'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'start': start.toUtc().toIso8601String(),
    if (end != null) 'end': end!.toUtc().toIso8601String(),
    'url': url,
    if (organizer != null) 'organizer': organizer,
    if (venue != null) 'venue': venue,
    if (city != null) 'city': city,
    'online': online,
    if (imageUrl != null) 'image': imageUrl,
    if (description != null) 'description': description,
    if (free != null) 'free': free,
  };

  /// Lower-cased text used for search.
  String get searchText => [
    title,
    organizer,
    venue,
    city,
    description,
  ].whereType<String>().join(' ').toLowerCase();
}

enum EventSource {
  meetup('Meetup'),
  eventbrite('Eventbrite'),
  luma('Luma');

  const EventSource(this.label);
  final String label;

  static EventSource? byName(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// The aggregated feed file (`events.json`).
class EventFeed {
  const EventFeed({
    required this.updated,
    required this.events,
    this.sources = const {},
  });

  final DateTime updated;
  final List<TechEvent> events;

  /// Per-source event counts from the last refresh, for transparency.
  final Map<String, int> sources;

  factory EventFeed.fromJson(Map<String, dynamic> j) => EventFeed(
    updated: DateTime.parse(j['updated'] as String),
    events: [
      for (final e in j['events'] as List)
        TechEvent.fromJson(e as Map<String, dynamic>),
    ],
    sources: {
      for (final MapEntry(:key, :value)
          in ((j['sources'] as Map?) ?? {}).entries)
        key as String: value as int,
    },
  );

  Map<String, dynamic> toJson() => {
    'updated': updated.toUtc().toIso8601String(),
    'sources': sources,
    'events': [for (final e in events) e.toJson()],
  };
}
