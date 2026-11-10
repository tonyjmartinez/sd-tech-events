import 'package:flutter/material.dart';

import 'src/feed_repository.dart';
import 'src/home_page.dart';

void main() => runApp(SdTechEventsApp(repository: FeedRepository()));

class SdTechEventsApp extends StatelessWidget {
  const SdTechEventsApp({super.key, required this.repository});

  final FeedRepository repository;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0E7C86),
        brightness: b,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'SD Tech Events',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(repository: repository),
    );
  }
}
