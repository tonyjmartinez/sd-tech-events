import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'event.dart';
import 'format.dart';
import 'pacific.dart';
import 'home_page.dart' show SourceBadge;

Future<void> showEventDetail(BuildContext context, TechEvent event) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            EventDetail(event: event, controller: controller),
      ),
    );

class EventDetail extends StatelessWidget {
  const EventDetail({super.key, required this.event, this.controller});

  final TechEvent event;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event;
    final source = EventSource.byName(e.source)?.label ?? e.source;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        if (e.imageUrl != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2,
                child: Image.network(
                  e.imageUrl!,
                  fit: BoxFit.cover,
                  semanticLabel: '',
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Text(e.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        _row(
          context,
          Icons.schedule,
          '${DateFormat('EEEE, MMMM d').format(toPacific(e.start))}\n${timeRange(e)}',
        ),
        _row(
          context,
          e.online ? Icons.videocam_outlined : Icons.place_outlined,
          e.online
              ? 'Online'
              : [
                  e.venue,
                  if (e.venue == null) e.city,
                ].whereType<String>().join('\n'),
        ),
        if (e.organizer != null)
          _row(context, Icons.groups_outlined, e.organizer!),
        if (e.free != null)
          _row(
            context,
            Icons.confirmation_number_outlined,
            e.free! ? 'Free' : 'Paid',
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(e.url)),
              icon: const Icon(Icons.open_in_new),
              label: Text('Open on $source'),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(googleCalendarUri(e)),
              icon: const Icon(Icons.event_available),
              label: const Text('Add to Google Calendar'),
            ),
          ],
        ),
        if (e.description != null) ...[
          const SizedBox(height: 20),
          SelectableText(e.description!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Listed on '),
            SourceBadge(source: e.source),
          ],
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
