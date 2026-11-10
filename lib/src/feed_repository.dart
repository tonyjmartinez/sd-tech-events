import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'event.dart';

/// Where the scheduled GitHub Action publishes the aggregated feed.
const feedUrl = String.fromEnvironment(
  'FEED_URL',
  defaultValue: 'https://raw.githubusercontent.com/tonyjmartinez/sd-tech-events/data/events.json',
);

const _cacheKey = 'feed_json';

/// Loads the feed: last cached copy (or the bundled snapshot) first, then the
/// network copy when it is reachable.
class FeedRepository {
  FeedRepository({http.Client? client, this.url = feedUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String url;

  Future<EventFeed> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        return _parse(cached);
      } catch (_) {
        await prefs.remove(_cacheKey);
      }
    }
    return _parse(await rootBundle.loadString('assets/events.json'));
  }

  /// Throws when offline or the feed is unavailable.
  Future<EventFeed> fetch() async {
    final res = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Feed returned HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final feed = _parse(body);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, body);
    return feed;
  }

  EventFeed _parse(String body) =>
      EventFeed.fromJson(jsonDecode(body) as Map<String, dynamic>);
}
