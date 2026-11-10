import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_tech_events/src/event.dart';

import 'package:sd_tech_events/src/pacific.dart';

import '../tool/sources.dart';

Map<String, dynamic> meetupNode({
  String id = '1',
  String title = 'San Diego JavaScript Monthly',
  String type = 'PHYSICAL',
  double? lat = 32.71,
  double? lon = -117.16,
  double groupLat = 32.72,
}) => {
  'node': {
    'id': id,
    'title': title,
    'dateTime': '2026-11-11T18:30:00-08:00',
    'endTime': '2026-11-11T20:30:00-08:00',
    'eventUrl': 'https://www.meetup.com/sdjs/events/$id/',
    'eventType': type,
    'description': '**Bring a laptop!** See [our site](https://x.y)',
    'featuredEventPhoto': null,
    'venue': {
      'name': 'Edge',
      'address': '1 Main St',
      'city': 'San Diego',
      'state': 'CA',
      'lat': lat,
      'lon': lon,
    },
    'group': {
      'name': 'SDJS',
      'urlname': 'sdjs',
      'city': 'San Diego',
      'lat': groupLat,
      'lon': -117.17,
    },
    'feeSettings': null,
  },
};

String meetupBody(List<Map<String, dynamic>> edges, {bool next = false}) =>
    jsonEncode({
      'data': {
        'recommendedEvents': {
          'pageInfo': {'hasNextPage': next, 'endCursor': 'abc'},
          'edges': edges,
        },
      },
    });

void main() {
  group('Meetup', () {
    test('parses events and cleans Markdown', () {
      final page = parseMeetup(meetupBody([meetupNode()], next: true));
      expect(page.nextCursor, 'abc');
      final e = page.events.single;
      expect(e.id, 'meetup:1');
      expect(e.start, DateTime.utc(2026, 11, 12, 2, 30));
      expect(e.venue, 'Edge, 1 Main St');
      expect(e.free, isTrue);
      expect(e.description, 'Bring a laptop! See our site');
    });

    test('drops in-person events outside the county and online events of non-local groups', () {
      final page = parseMeetup(
        meetupBody([
          meetupNode(id: '2', lat: 34.05, lon: -118.24),
          meetupNode(id: '3', type: 'ONLINE', groupLat: 34.05),
          meetupNode(id: '4', type: 'ONLINE'),
        ]),
      );
      expect(page.events.map((e) => e.id), ['meetup:4']);
      expect(page.events.single.online, isTrue);
      expect(page.events.single.venue, isNull);
    });

    test('keyword search hits must look like tech', () {
      final page = parseMeetup(
        meetupBody([meetupNode(id: '5', title: 'Sunday Softball')]),
        requireTechWords: true,
      );
      expect(page.events, isEmpty);
    });
  });

  group('Eventbrite', () {
    String html(List<Map<String, dynamic>> results) =>
        '<script>window.__SERVER_DATA__ = ${jsonEncode({
          'search_data': {
            'events': {'results': results},
          },
        })};\n</script>';
    Map<String, dynamic> result(
      String name, {
      List<Map<String, String>> tags = const [],
      String lat = '32.87',
    }) => {
      'id': '9',
      'eventbrite_event_id': '9',
      'name': name,
      'summary': 'A summary',
      'start_date': '2026-11-20',
      'start_time': '09:00',
      'end_date': '2026-11-20',
      'end_time': '18:00',
      'timezone': 'America/Los_Angeles',
      'url': 'https://www.eventbrite.com/e/x-tickets-9?aff=search',
      'is_online_event': false,
      'tags': tags,
      'primary_venue': {
        'name': 'Marriott',
        'address': {
          'address_1': '4240 La Jolla Village Dr',
          'city': 'San Diego',
          'latitude': lat,
          'longitude': '-117.21',
        },
      },
    };

    test('parses server data and converts Pacific time', () {
      final e = parseEventbrite(html([result('HAPPY STARTUP San Diego')]))
          .single;
      expect(e.start, DateTime.utc(2026, 11, 20, 17));
      expect(e.url, 'https://www.eventbrite.com/e/x-tickets-9');
      expect(e.venue, 'Marriott, 4240 La Jolla Village Dr');
    });

    test(
      'keeps Science & Tech category, filters other off-topic or remote events',
      () {
        final events = parseEventbrite(
          html([
            result(
              'Museum Night',
              tags: [
                {
                  'tag': 'EventbriteCategory/102',
                  'display_name': 'Science & Technology',
                },
              ],
            ),
            result('Wine Tasting'),
            result('AI Summit Irvine', lat: '33.68'),
          ]),
        );
        expect(events.map((e) => e.title), ['Museum Night']);
      },
    );
  });

  group('Luma', () {
    Map<String, dynamic> entry(
      String name, {
      String type = 'offline',
      double lat = 32.71,
      String cal = 'DEVx',
    }) => {
      'event': {
        'api_id': 'evt-$name',
        'name': name,
        'start_at': '2026-11-13T16:00:00.000Z',
        'end_at': '2026-11-14T02:00:00.000Z',
        'url': 'abc',
        'location_type': type,
        'visibility': 'public',
        'coordinate': {'latitude': lat, 'longitude': -117.16},
        'geo_address_info': {
          'city': 'San Diego',
          'full_address': '333 W Harbor Dr, San Diego',
        },
      },
      'calendar': {'name': cal},
      'hosts': [
        {'name': 'Host'},
      ],
      'ticket_info': {'is_free': true},
    };

    test('parses, filters by location and topic', () {
      final body = jsonEncode({
        'entries': [
          entry('Coffee Before Code'),
          entry('Yoga', cal: 'Personal'),
          entry('Remote AI talk', type: 'online'),
          entry('LA Hackathon', lat: 34.05),
        ],
        'has_more': true,
        'next_cursor': 'c1',
      });
      final page = parseLuma(body, requireTechWords: true);
      expect(page.nextCursor, 'c1');
      final e = page.events.single;
      expect(e.url, 'https://luma.com/abc');
      expect(e.organizer, 'DEVx');
      expect(e.free, isTrue);
    });
  });

  test('pacificToUtc handles DST boundaries', () {
    expect(pacificToUtc('2026-07-01', '12:00'), DateTime.utc(2026, 7, 1, 19));
    expect(pacificToUtc('2026-11-01', '01:00'), DateTime.utc(2026, 11, 1, 8));
    expect(pacificToUtc('2026-11-02', '12:00'), DateTime.utc(2026, 11, 2, 20));
    expect(pacificToUtc('2026-03-08', '03:00'), DateTime.utc(2026, 3, 8, 10));
  });

  test('toPacific shows San Diego wall-clock time', () {
    expect(
      toPacific(DateTime.utc(2026, 11, 10, 2)),
      DateTime.utc(2026, 11, 9, 18),
    );
    expect(
      toPacific(DateTime.utc(2026, 7, 1, 19)),
      DateTime.utc(2026, 7, 1, 12),
    );
  });

  test('mergeEvents drops off-topic titles', () {
    final merged = mergeEvents([
      TechEvent(
        id: 'eventbrite:9',
        source: 'eventbrite',
        title: 'PMP Certification Training | PMI Exam Prep',
        start: DateTime.utc(2026, 11, 12),
        url: 'u',
      ),
    ], now: DateTime.utc(2026, 11, 10));
    expect(merged, isEmpty);
  });

  test(
    'mergeEvents drops past events and cross-source duplicates, keeping Meetup',
    () {
      final now = DateTime.utc(2026, 11, 10);
      TechEvent ev(String id, String source, String title, DateTime start) =>
          TechEvent(
            id: id,
            source: source,
            title: title,
            start: start,
            url: 'u',
          );
      final merged = mergeEvents([
        ev(
          'eventbrite:1',
          'eventbrite',
          'Tech Startups Pitch Night!',
          DateTime.utc(2026, 11, 18, 3),
        ),
        ev(
          'meetup:1',
          'meetup',
          'Tech startups pitch night',
          DateTime.utc(2026, 11, 18, 3),
        ),
        ev('luma:old', 'luma', 'Old', DateTime.utc(2026, 11, 1)),
        ev('luma:2', 'luma', 'Coffee', DateTime.utc(2026, 11, 12)),
      ], now: now);
      expect(merged.map((e) => e.id), ['luma:2', 'meetup:1']);
    },
  );

  test('feed JSON round-trips', () {
    final feed = EventFeed(
      updated: DateTime.utc(2026, 11, 10),
      sources: {'meetup': 1},
      events: [
        TechEvent(
          id: 'meetup:1',
          source: 'meetup',
          title: 'T',
          start: DateTime.utc(2026, 11, 12),
          url: 'u',
          online: true,
        ),
      ],
    );
    final back = EventFeed.fromJson(
      jsonDecode(jsonEncode(feed.toJson())) as Map<String, dynamic>,
    );
    expect(back.events.single.online, isTrue);
    expect(back.sources, {'meetup': 1});
    expect(back.updated, feed.updated);
  });
}
