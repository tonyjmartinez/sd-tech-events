import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_tech_events/src/event.dart';
import 'package:sd_tech_events/src/feed_repository.dart';
import 'package:sd_tech_events/src/filters.dart';
import 'package:sd_tech_events/src/home_page.dart';

// 9am in San Diego on Tuesday, Nov 10 2026 (PST, UTC-8).
final now = DateTime.utc(2026, 11, 10, 17);
DateTime sd(int m, int d, int h) => DateTime.utc(2026, m, d, h + 8);

TechEvent ev(
  String id,
  String title,
  DateTime start, {
  String source = 'meetup',
  bool online = false,
  bool? free,
}) => TechEvent(
  id: id,
  source: source,
  title: title,
  start: start,
  url: 'https://example.com/$id',
  online: online,
  free: free,
  city: 'San Diego',
);

final events = [
  ev('a', 'San Diego JavaScript Monthly', sd(11, 10, 18), free: true),
  ev('b', 'Founder Coffee', sd(11, 14, 9), source: 'luma'),
  ev(
    'c',
    'Online Python Study Group',
    sd(11, 11, 10),
    online: true,
    free: true,
  ),
  ev('d', 'AI Summit', sd(12, 20, 9), source: 'eventbrite', free: false),
];

class FakeRepository extends FeedRepository {
  FakeRepository() : super(url: 'unused');
  @override
  Future<EventFeed> loadCached() async => EventFeed(
    updated: now.subtract(const Duration(hours: 3)),
    events: events,
  );
  @override
  Future<EventFeed> fetch() async => throw Exception('offline');
}

void main() {
  group('EventFilter', () {
    List<String> ids(EventFilter f) =>
        f.apply(events, now).map((e) => e.id).toList();

    test(
      'defaults to everything upcoming',
      () => expect(ids(const EventFilter()), ['a', 'b', 'c', 'd']),
    );
    test(
      'search matches all terms',
      () => expect(ids(const EventFilter(query: 'python group')), ['c']),
    );
    test('in person and free', () {
      expect(ids(const EventFilter(inPersonOnly: true, freeOnly: true)), ['a']);
    });
    test(
      'sources',
      () => expect(
        ids(
          const EventFilter(
            sources: {EventSource.luma, EventSource.eventbrite},
          ),
        ),
        ['b', 'd'],
      ),
    );
    test('date windows', () {
      expect(ids(const EventFilter(when: When.today)), ['a']);
      expect(ids(const EventFilter(when: When.week)), ['a', 'b', 'c']);
      expect(ids(const EventFilter(when: When.weekend)), ['b']);
    });
  });

  testWidgets(
    'lists events by day, filters by search, and falls back offline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(repository: FakeRepository(), clock: () => now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('San Diego JavaScript Monthly'), findsOneWidget);
      expect(find.textContaining('updated 3 h ago'), findsOneWidget);
      expect(find.textContaining('Couldn’t refresh'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'founder');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Founder Coffee'), findsOneWidget);
      expect(find.text('San Diego JavaScript Monthly'), findsNothing);

      await tester.tap(find.text('Founder Coffee'));
      await tester.pumpAndSettle();
      expect(find.text('Open on Luma'), findsOneWidget);
    },
  );
}
