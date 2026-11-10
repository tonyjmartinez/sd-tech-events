import 'dart:async';

import 'package:flutter/material.dart';

import 'event.dart';
import 'event_detail.dart';
import 'feed_repository.dart';
import 'filters.dart';
import 'format.dart';
import 'pacific.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository, this.clock});

  final FeedRepository repository;

  /// Overridable for tests.
  final DateTime Function()? clock;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  EventFeed? _feed;
  bool _refreshing = false;
  String? _error;
  EventFilter _filter = const EventFilter();
  final _search = TextEditingController();
  Timer? _debounce;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cached = await widget.repository.loadCached();
      if (mounted && _feed == null) setState(() => _feed = cached);
    } catch (_) {}
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final feed = await widget.repository.fetch();
      if (mounted) setState(() => (_feed = feed, _error = null));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Couldn’t refresh. Showing saved events.');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _setFilter(EventFilter f) => setState(() => _filter = f);

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final now = _now;
    final events = feed == null
        ? const <TechEvent>[]
        : _filter.apply(feed.events, now);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header(context, feed, now)),
                  SliverToBoxAdapter(child: _filters(context)),
                  if (feed == null)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (events.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _empty(context),
                    )
                  else
                    ..._groupedList(context, events, now),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, EventFeed? feed, DateTime now) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SD Tech Events',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_refreshing)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            feed == null
                ? 'Startup and tech events around San Diego'
                : '${feed.events.length} startup and tech events from Meetup, Eventbrite and Luma · '
                      'updated ${updatedAgo(feed.updated, now)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search AI, founders, Python, La Jolla…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _setFilter(_filter.copyWith(query: ''));
                      },
                    ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(28)),
              ),
              isDense: true,
            ),
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 200),
                () => _setFilter(_filter.copyWith(query: q)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final f = _filter;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          PopupMenuButton<When>(
            tooltip: 'When',
            initialValue: f.when,
            onSelected: (w) => _setFilter(f.copyWith(when: w)),
            itemBuilder: (_) => [
              for (final w in When.values)
                PopupMenuItem(value: w, child: Text(w.label)),
            ],
            child: Chip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(f.when.label),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('In person'),
            selected: f.inPersonOnly,
            onSelected: (v) => _setFilter(f.copyWith(inPersonOnly: v)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Free'),
            selected: f.freeOnly,
            onSelected: (v) => _setFilter(f.copyWith(freeOnly: v)),
          ),
          for (final s in EventSource.values) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(s.label),
              selected: f.sources.contains(s),
              onSelected: (v) => _setFilter(
                f.copyWith(
                  sources: v ? {...f.sources, s} : ({...f.sources}..remove(s)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.event_busy, size: 48),
        const SizedBox(height: 12),
        const Text('No events match.', textAlign: TextAlign.center),
        if (!_filter.isDefault)
          TextButton(
            onPressed: () {
              _search.clear();
              _setFilter(const EventFilter());
            },
            child: const Text('Clear filters'),
          ),
      ],
    ),
  );

  List<Widget> _groupedList(
    BuildContext context,
    List<TechEvent> events,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final slivers = <Widget>[];
    var i = 0;
    while (i < events.length) {
      final day = toPacific(events[i].start);
      final group = <TechEvent>[];
      while (i < events.length) {
        final d = toPacific(events[i].start);
        if (d.year != day.year || d.month != day.month || d.day != day.day) {
          break;
        }
        group.add(events[i++]);
      }
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Semantics(
              header: true,
              child: Text(
                dayHeading(day, toPacific(now)),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverList.builder(
          itemCount: group.length,
          itemBuilder: (context, j) => EventTile(event: group[j]),
        ),
      );
    }
    return slivers;
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event});

  final TechEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event;
    final where = e.online ? 'Online' : (e.city ?? e.venue ?? 'San Diego');
    return InkWell(
      onTap: () => showEventDetail(context, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timeRange(e),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              e.title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SourceBadge(source: e.source),
                Text(
                  [where, if (e.organizer != null) e.organizer!].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final String source;

  static const _colors = {
    'meetup': Color(0xFFE0393E),
    'eventbrite': Color(0xFFD1410C),
    'luma': Color(0xFF6E56CF),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[source] ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        EventSource.byName(source)?.label ?? source,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
