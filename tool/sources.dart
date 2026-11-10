// Parsers and filters for the upstream feeds. Pure Dart: no Flutter, no IO,
// so they can be unit-tested against saved responses.
import 'dart:convert';

import 'package:sd_tech_events/src/event.dart';
import 'package:sd_tech_events/src/pacific.dart';

/// Downtown San Diego, used as the search centre.
const sdLat = 32.7157;
const sdLon = -117.1611;

/// Rough bounding box for San Diego County.
bool inSanDiegoCounty(double? lat, double? lon) =>
    lat != null &&
    lon != null &&
    lat >= 32.53 &&
    lat <= 33.51 &&
    lon >= -117.62 &&
    lon <= -116.08;

final _techWords = RegExp(
  r'\b(tech|technology|technologists?|startups?|founders?|cofounders?|co-founders?|entrepreneurs?|entrepreneurship|'
  r'ai|a\.i\.|artificial intelligence|machine learning|ml|llms?|gen ?ai|agentic|ai agents?|chatgpt|claude|openai|'
  r'data science|software|developers?|devs|engineers?|engineering|code|coding|coders?|programming|programmers?|'
  r'hackathons?|cyber|cybersecurity|infosec|crypto|blockchain|web3|bitcoin|saas|cloud|'
  r'product managers?|product management|ux|ui/ux|venture|vc|angel investors?|pitch|accelerators?|incubators?|'
  r'biotech|medtech|healthtech|fintech|cleantech|bluetech|deeptech|robotics|drones?|iot|quantum|semiconductors?|'
  r'python|pydata|javascript|typescript|react|rust|golang|java|aws|azure|kubernetes|devops|linux|'
  r'ieee|1 million cups|demo day|open source|game dev|game design|web dev|it pros?)\b',
  caseSensitive: false,
);

final _offTopic = RegExp(
  r'\b(certification training|exam prep|pmp|real estate|realtors?|mortgage|airbnb|'
  r'softball|yoga|meditation|sound bath|singles|speed dating|wine tasting)\b',
  caseSensitive: false,
);

/// Titles that match tech words but aren't tech or startup events.
bool offTopic(String title) => _offTopic.hasMatch(title);

/// Whether a title/organizer looks like a tech or startup event. Match on
/// names only: descriptions mention "tech" or "AI" far too loosely.
bool looksTech(String text) => _techWords.hasMatch(text);

/// Strips Markdown/HTML noise and trims to a readable blurb.
String? cleanDescription(String? raw, {int max = 600}) {
  if (raw == null) return null;
  var s = raw
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\\([#*_\[\]()|,.!-])'), r'$1')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*_#`>]+'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
  if (s.isEmpty) return null;
  if (s.length > max) {
    final cut = s.lastIndexOf(' ', max);
    s = '${s.substring(0, cut > max ~/ 2 ? cut : max)}…';
  }
  return s;
}

// ---------------------------------------------------------------- Meetup

const meetupEndpoint = 'https://www.meetup.com/gql2';

const _meetupFields = '''
pageInfo { hasNextPage endCursor }
edges { node {
  id title dateTime endTime eventUrl eventType description
  featuredEventPhoto { highResUrl }
  venue { name address city state lat lon }
  group { name urlname city lat lon }
  feeSettings { amount currency }
} }''';

/// Meetup's "Technology" topic category near San Diego.
String meetupCategoryQuery(
  String startDateRange, {
  String? after,
}) => jsonEncode({
  'query':
      'query(\$after: String) { recommendedEvents(filter: {lat: $sdLat, lon: $sdLon, '
      'radius: 40, topicCategoryId: "546", startDateRange: "$startDateRange"}, '
      'first: 100, after: \$after) { $_meetupFields } }',
  'variables': {'after': after},
});

/// Keyword search near San Diego, to catch startup groups filed under other
/// categories (e.g. "Career & Business").
String meetupSearchQuery(String keyword, {String? after}) => jsonEncode({
  'query':
      'query(\$q: String!, \$after: String) { eventSearch(filter: {query: \$q, '
      'lat: $sdLat, lon: $sdLon, radius: 40}, first: 50, after: \$after) { $_meetupFields } }',
  'variables': {'q': keyword, 'after': after},
});

class MeetupPage {
  MeetupPage(this.events, this.nextCursor);
  final List<TechEvent> events;
  final String? nextCursor;
}

/// Parses one gql2 response. [requireTechWords] filters keyword-search hits,
/// which can be off-topic; the Technology category needs no filter.
MeetupPage parseMeetup(String body, {bool requireTechWords = false}) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) throw FormatException('Meetup error: ${json['errors']}');
  final conn =
      (data['recommendedEvents'] ?? data['eventSearch'])
          as Map<String, dynamic>;
  final events = <TechEvent>[];
  for (final edge in conn['edges'] as List) {
    final n = edge['node'] as Map<String, dynamic>;
    final venue = n['venue'] as Map<String, dynamic>?;
    final group = n['group'] as Map<String, dynamic>?;
    final online = n['eventType'] == 'ONLINE';
    final lat = (venue?['lat'] as num?)?.toDouble();
    final lon = (venue?['lon'] as num?)?.toDouble();
    // Meetup puts placeholder coordinates on some venues; only reject
    // in-person events whose real coordinates are outside the county.
    if (!online && lat != null && lat != 0 && !inSanDiegoCounty(lat, lon)) {
      continue;
    }
    // Online events are only local if the hosting group is.
    if (online &&
        !inSanDiegoCounty(
          (group?['lat'] as num?)?.toDouble(),
          (group?['lon'] as num?)?.toDouble(),
        )) {
      continue;
    }
    final title = (n['title'] as String).trim();
    final desc = n['description'] as String?;
    if (requireTechWords && !looksTech('$title ${group?['name'] ?? ''}')) {
      continue;
    }
    final fee = n['feeSettings'] as Map<String, dynamic>?;
    final venueName = venue?['name'] as String?;
    events.add(
      TechEvent(
        id: 'meetup:${n['id']}',
        source: EventSource.meetup.name,
        title: title,
        start: DateTime.parse(n['dateTime'] as String),
        end: n['endTime'] == null
            ? null
            : DateTime.parse(n['endTime'] as String),
        url: n['eventUrl'] as String,
        organizer: group?['name'] as String?,
        venue:
            online ||
                venueName == null ||
                venueName.toLowerCase() == 'online event'
            ? null
            : [
                venueName,
                venue?['address'],
              ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
        city: online ? null : venue?['city'] as String?,
        online: online,
        imageUrl: (n['featuredEventPhoto'] as Map?)?['highResUrl'] as String?,
        description: cleanDescription(desc),
        free: fee == null ? true : ((fee['amount'] as num?) ?? 0) == 0,
      ),
    );
  }
  final info = conn['pageInfo'] as Map<String, dynamic>?;
  return MeetupPage(
    events,
    info?['hasNextPage'] == true ? info!['endCursor'] as String? : null,
  );
}

// ------------------------------------------------------------ Eventbrite

/// Eventbrite search pages for San Diego. Results outside Eventbrite's
/// Science & Technology category still have to pass [looksTech].
const eventbriteSlugs = [
  'science-and-tech--events',
  'startup',
  'tech',
  'artificial-intelligence',
];

String eventbriteUrl(String slug, int page) =>
    'https://www.eventbrite.com/d/ca--san-diego/$slug/?page=$page';

/// Parses the `window.__SERVER_DATA__` blob of an Eventbrite search page.
List<TechEvent> parseEventbrite(String html) {
  final m = RegExp(
    r'window\.__SERVER_DATA__\s*=\s*(\{.*?\});\s*\n',
    dotAll: true,
  ).firstMatch(html);
  if (m == null) throw const FormatException('Eventbrite: no __SERVER_DATA__');
  final data = jsonDecode(m[1]!) as Map<String, dynamic>;
  final results =
      (((data['search_data'] as Map?)?['events'] as Map?)?['results']
          as List?) ??
      [];
  final events = <TechEvent>[];
  for (final r in results.cast<Map<String, dynamic>>()) {
    if (r['is_cancelled'] == true || r['is_online_event'] == true) continue;
    final venue = r['primary_venue'] as Map<String, dynamic>?;
    final addr = venue?['address'] as Map<String, dynamic>?;
    final lat = double.tryParse('${addr?['latitude']}');
    final lon = double.tryParse('${addr?['longitude']}');
    if (!inSanDiegoCounty(lat, lon)) continue;
    final title = (r['name'] as String).trim();
    final summary = r['summary'] as String?;
    final scienceAndTech = (r['tags'] as List? ?? []).any(
      (t) => (t as Map)['tag'] == 'EventbriteCategory/102',
    );
    if (!scienceAndTech && !looksTech(title)) continue;
    final tz = r['timezone'] as String?;
    if (tz != null && tz != 'America/Los_Angeles') continue;
    final start = pacificToUtc(
      r['start_date'] as String,
      r['start_time'] as String?,
    );
    final end = r['end_date'] == null
        ? null
        : pacificToUtc(r['end_date'] as String, r['end_time'] as String?);
    final image =
        ((r['image'] as Map?)?['original'] as Map?)?['url'] as String? ??
        (r['image'] as Map?)?['url'] as String?;
    events.add(
      TechEvent(
        id: 'eventbrite:${r['eventbrite_event_id'] ?? r['id']}',
        source: EventSource.eventbrite.name,
        title: title,
        start: start,
        end: end,
        url: (r['url'] as String).split('?').first,
        venue: [
          venue?['name'],
          addr?['address_1'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
        city: addr?['city'] as String?,
        imageUrl: image,
        description: cleanDescription(summary),
      ),
    );
  }
  return events;
}

/// Converts an Eventbrite San Diego date and time to UTC.
DateTime pacificToUtc(String date, String? time) {
  final d = DateTime.parse(date);
  final parts = (time ?? '00:00').split(':').map(int.parse).toList();
  return pacificWallToUtc(
    DateTime.utc(
      d.year,
      d.month,
      d.day,
      parts[0],
      parts.length > 1 ? parts[1] : 0,
    ),
  );
}

// ------------------------------------------------------------------ Luma

/// Luma discovery feeds near San Diego. Category feeds are already on-topic;
/// the general city feed is filtered with [looksTech].
const lumaFeeds = <(String, bool)>[
  ('discover_category_api_id=cat-tech', false),
  ('discover_category_api_id=cat-ai', false),
  ('discover_category_api_id=cat-crypto', false),
  ('', true),
];

String lumaUrl(String feed, {String? cursor}) =>
    'https://api.lu.ma/discover/get-paginated-events?${feed.isEmpty ? '' : '$feed&'}'
    'latitude=$sdLat&longitude=$sdLon&pagination_limit=50'
    '${cursor == null ? '' : '&pagination_cursor=$cursor'}';

class LumaPage {
  LumaPage(this.events, this.nextCursor);
  final List<TechEvent> events;
  final String? nextCursor;
}

LumaPage parseLuma(String body, {bool requireTechWords = false}) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final events = <TechEvent>[];
  for (final entry in (json['entries'] as List).cast<Map<String, dynamic>>()) {
    final e = entry['event'] as Map<String, dynamic>;
    if (e['visibility'] != null && e['visibility'] != 'public') continue;
    final coord = e['coordinate'] as Map<String, dynamic>?;
    if (e['location_type'] != 'offline' ||
        !inSanDiegoCounty(
          (coord?['latitude'] as num?)?.toDouble(),
          (coord?['longitude'] as num?)?.toDouble(),
        )) {
      continue;
    }
    final cal = entry['calendar'] as Map<String, dynamic>?;
    final hosts = [
      for (final h in (entry['hosts'] as List? ?? [])) (h as Map)['name'],
    ].whereType<String>();
    final calName = cal?['name'] as String?;
    final organizer = calName != null && calName != 'Personal'
        ? calName
        : hosts.firstOrNull;
    final title = (e['name'] as String).trim();
    if (requireTechWords && !looksTech('$title ${organizer ?? ''}')) continue;
    final geo = e['geo_address_info'] as Map<String, dynamic>?;
    final ticket = entry['ticket_info'] as Map<String, dynamic>?;
    events.add(
      TechEvent(
        id: 'luma:${e['api_id']}',
        source: EventSource.luma.name,
        title: title,
        start: DateTime.parse(e['start_at'] as String),
        end: e['end_at'] == null ? null : DateTime.parse(e['end_at'] as String),
        url: 'https://luma.com/${e['url']}',
        organizer: organizer,
        venue: geo?['full_address'] as String? ?? geo?['address'] as String?,
        city: geo?['city'] as String?,
        imageUrl: e['cover_url'] as String?,
        description: cleanDescription(cal?['description_short'] as String?),
        free: ticket?['is_free'] as bool?,
      ),
    );
  }
  return LumaPage(
    events,
    json['has_more'] == true ? json['next_cursor'] as String? : null,
  );
}

// ------------------------------------------------------------- Merging

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Drops past, off-topic and duplicate events (same title and day across sources,
/// e.g. a Meetup that links to its Eventbrite tickets) and sorts by start.
List<TechEvent> mergeEvents(
  Iterable<TechEvent> all, {
  required DateTime now,
  Duration horizon = const Duration(days: 120),
}) {
  final byId = <String, TechEvent>{};
  final seen = <String>{};
  final sorted = all.toList()..sort((a, b) => _rank(a).compareTo(_rank(b)));
  for (final e in sorted) {
    final ends = e.end ?? e.start.add(const Duration(hours: 2));
    if (ends.isBefore(now) || e.start.isAfter(now.add(horizon))) continue;
    if (byId.containsKey(e.id)) continue;
    if (offTopic(e.title)) continue;
    final local = toPacific(e.start);
    final key = '${_norm(e.title)}|${local.year}-${local.month}-${local.day}';
    if (!seen.add(key)) continue;
    byId[e.id] = e;
  }
  return byId.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

/// Prefer richer sources when the same event appears twice.
int _rank(TechEvent e) => switch (EventSource.byName(e.source)) {
  EventSource.meetup => 0,
  EventSource.luma => 1,
  _ => 2,
};
