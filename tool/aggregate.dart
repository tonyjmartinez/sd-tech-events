// Fetches every source and writes the merged feed.
//
//   dart run tool/aggregate.dart [out.json]
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:sd_tech_events/src/event.dart';

import 'sources.dart';

const _ua =
    'Mozilla/5.0 (compatible; sd-tech-events/1.0; +https://github.com/tonyjmartinez/sd-tech-events)';
const _meetupKeywords = [
  'startup',
  'founders',
  'entrepreneur',
  'tech',
  'AI',
  'developer',
  'venture',
  'hackathon',
];

Future<void> main(List<String> args) async {
  final out = File(args.isEmpty ? 'events.json' : args.first);
  final client = http.Client();
  final now = DateTime.now().toUtc();
  final counts = <String, int>{};
  final all = <TechEvent>[];
  final failures = <String>[];

  Future<void> run(
    String name,
    Future<List<TechEvent>> Function() fetch,
  ) async {
    try {
      final events = await fetch();
      counts[name] = (counts[name] ?? 0) + events.length;
      all.addAll(events);
      stderr.writeln('$name: ${events.length}');
    } catch (e) {
      failures.add(name);
      stderr.writeln('$name FAILED: $e');
    }
  }

  // Eventbrite rate-limits bursts (HTTP 429), so back off and retry.
  Future<String> get(String url) async {
    for (var attempt = 0; ; attempt++) {
      final r = await client.get(
        Uri.parse(url),
        headers: {'User-Agent': _ua, 'Accept-Language': 'en-US'},
      );
      if (r.statusCode == 200) return r.body;
      if (r.statusCode != 429 || attempt == 2) {
        throw HttpException('HTTP ${r.statusCode} for $url');
      }
      await Future<void>.delayed(Duration(seconds: 20 * (attempt + 1)));
    }
  }

  Future<String> meetup(String body) async {
    final r = await client.post(
      Uri.parse(meetupEndpoint),
      headers: {'User-Agent': _ua, 'Content-Type': 'application/json'},
      body: body,
    );
    if (r.statusCode != 200) throw HttpException('Meetup HTTP ${r.statusCode}');
    return r.body;
  }

  // Meetup wants a zoned start like 2026-11-09T00:00:00-08:00[US/Pacific].
  final pacificNow = now.subtract(const Duration(hours: 8));
  final day =
      '${pacificNow.year}-${_pad(pacificNow.month)}-${_pad(pacificNow.day)}';
  await run('meetup', () async {
    final events = <TechEvent>[];
    String? cursor;
    for (var i = 0; i < 5; i++) {
      final page = parseMeetup(
        await meetup(
          meetupCategoryQuery(
            '${day}T00:00:00-08:00[US/Pacific]',
            after: cursor,
          ),
        ),
      );
      events.addAll(page.events);
      if ((cursor = page.nextCursor) == null) break;
    }
    for (final k in _meetupKeywords) {
      cursor = null;
      for (var i = 0; i < 3; i++) {
        final page = parseMeetup(
          await meetup(meetupSearchQuery(k, after: cursor)),
          requireTechWords: true,
        );
        events.addAll(page.events);
        if ((cursor = page.nextCursor) == null) break;
      }
    }
    return events;
  });

  await run('eventbrite', () async {
    final events = <TechEvent>[];
    Object? lastError;
    for (final slug in eventbriteSlugs) {
      for (var p = 1; p <= 3; p++) {
        try {
          events.addAll(parseEventbrite(await get(eventbriteUrl(slug, p))));
        } catch (e) {
          lastError = e;
          stderr.writeln('eventbrite $slug p$p: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (events.isEmpty && lastError != null) throw lastError;
    return events;
  });

  await run('luma', () async {
    final events = <TechEvent>[];
    for (final (feed, filter) in lumaFeeds) {
      String? cursor;
      for (var i = 0; i < 6; i++) {
        final page = parseLuma(
          await get(lumaUrl(feed, cursor: cursor)),
          requireTechWords: filter,
        );
        events.addAll(page.events);
        if ((cursor = page.nextCursor) == null) break;
      }
    }
    return events;
  });
  client.close();

  final merged = mergeEvents(all, now: now);
  final sources = {
    for (final s in EventSource.values)
      s.name: merged.where((e) => e.source == s.name).length,
  };
  stderr.writeln('raw: $counts, merged: ${merged.length} $sources');

  // Keep the previous feed's events for a source that failed this run, so a
  // single broken scraper doesn't empty the app.
  if (failures.isNotEmpty && out.existsSync()) {
    final previous = EventFeed.fromJson(
      jsonDecode(out.readAsStringSync()) as Map<String, dynamic>,
    );
    merged.addAll(previous.events.where((e) => failures.contains(e.source)));
  }
  if (failures.length == EventSource.values.length) {
    stderr.writeln('All sources failed; leaving ${out.path} untouched.');
    exitCode = 1;
    return;
  }

  final feed = EventFeed(
    updated: now,
    events: mergeEvents(merged, now: now),
    sources: sources,
  );
  out.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(feed.toJson()),
  );
  stderr.writeln('Wrote ${feed.events.length} events to ${out.path}');
}

String _pad(int n) => n.toString().padLeft(2, '0');
