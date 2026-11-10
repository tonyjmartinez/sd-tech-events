# SD Tech Events

Every startup and tech event in San Diego in one list. A Flutter app for web, Android and iOS.

## How it works

```
Meetup (GraphQL)  ─┐
Eventbrite (search)├─ tool/aggregate.dart ─ events.json on the `data` branch ─ Flutter app
Luma (discover)   ─┘    every 6 h (GitHub Action)       (raw.githubusercontent.com)
```

- **Meetup:** the Technology category within 40 mi of downtown, plus keyword searches (startup, founders, AI, …). Online events are kept only when the hosting group is in San Diego County.
- **Eventbrite:** the San Diego search pages for science & tech, startup, tech and AI. In-person events in the county only.
- **Luma:** the Tech, AI and Crypto discovery feeds near San Diego, plus the general San Diego feed filtered by topic.
- Events are filtered to San Diego County, deduplicated across sources (same title, same day) and limited to the next 120 days.

The app shows the last downloaded feed straight away, then refreshes it. If it can't reach the feed it falls back to the snapshot bundled in `assets/events.json`. You can search the list, filter by date, in person, free or source, open an event on its source site, or add it to Google Calendar.

No API keys or servers are needed. If one source breaks, the aggregator keeps that source's previous events.

## Develop

```sh
flutter pub get
flutter run -d chrome           # or an Android/iOS device
flutter test
dart run tool/aggregate.dart assets/events.json   # refresh the bundled snapshot
```

Use `--dart-define=FEED_URL=...` to point the app at a different feed.

## Ship

- **Feed:** `.github/workflows/refresh-feed.yml` runs every 6 hours, or run it by hand from the Actions tab.
- **Web:** each push to `main` builds the app and pushes it to the `gh-pages` branch. It's served by GitHub Pages (Settings → Pages → Deploy from a branch → `gh-pages`).
- **Android:** push a `v*` tag. CI attaches a debug-signed APK to a GitHub Release.
- **iOS:** `flutter build ios` on a Mac.
