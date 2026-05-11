# Aetherfin

A native-feeling Android music player backed by your self-hosted
[Jellyfin](https://jellyfin.org) server. Aetherfin is the player —
Jellyfin is the file source.

> Spotify's polish. Apple Music's typography. Soulseek's respect for the
> listener.

[![Flutter](https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11.5-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Android](https://img.shields.io/badge/Android-5.0%2B-3DDC84?logo=android)](https://developer.android.com)

---

## What it is

Aetherfin streams music from a Jellyfin server you own and decodes it
fully on-device. No Aetherfin-operated servers exist. No telemetry.
Jellyfin is treated as a passive file source plus per-user state store
(favorites, play counts, playlists). Everything else — buffering,
decoding, queue management, lyrics, lock-screen controls, sleep timer,
spectral color extraction — runs on your phone.

**Why this matters**

- The Jellyfin server's CPU stays cool. Tracks are served as raw bytes
  via `/Audio/{id}/stream?Static=true`. No HLS transcoding round-trip.
- You can play lossless FLAC / ALAC / OPUS files without quality loss.
- Aetherfin keeps working as long as your Jellyfin server is reachable
  on the network. There is no "Aetherfin cloud" to depend on.

## Features

- **Library, Albums, Artists, Genres, Playlists** browsing
- **Search** (`/Users/{id}/Items?searchTerm=…`)
- **Queue** with drag-to-reorder
- **Now Playing** with waveform scrubbing, shuffle, loop (off / all / one),
  playback speed (0.5×–2.0×), favorite toggle
- **Synced lyrics** (LRC parsed on-device)
- **Lock-screen / notification** media controls via
  [`audio_service`](https://pub.dev/packages/audio_service)
- **Sleep timer**, **cast picker** (output routing)
- **mDNS discovery** of Jellyfin servers on the local network
- **Spectral-derived UI accents** — palette is sampled from the current
  cover art
- **Offline-friendly metadata cache** (cover art via
  [`cached_network_image`](https://pub.dev/packages/cached_network_image),
  Dio HTTP cache for catalog requests)

## Screenshots

> Coming soon. In the meantime, see the
> [APK builds](https://github.com/Aetherfin/mobile-app/actions/workflows/build-apk.yml)
> — install the latest one and try it against your own server.

## Requirements

- **Android 5.0 (API 21)** or newer.
- A reachable [**Jellyfin 10.8+**](https://jellyfin.org/downloads/server)
  server with at least one music library.
- Network reachability between phone and server (LAN, VPN, or
  publicly-exposed HTTPS — all work).

## Quick start

### Install the APK

1. Download the most recent `app-release.apk` (or per-ABI variant) from
   [Releases](https://github.com/Aetherfin/mobile-app/releases) or the
   [latest CI build](https://github.com/Aetherfin/mobile-app/actions/workflows/build-apk.yml).
2. Enable "Install from unknown sources" for your file manager / browser.
3. Open the APK, install, launch.

### First-run onboarding

1. **Discover or enter your server URL** (e.g. `http://omahsangar.local:8097`
   or `https://music.example.com`). mDNS will list nearby Jellyfin
   instances; otherwise type the URL manually.
2. **Sign in** with your Jellyfin username and password. Aetherfin uses
   the standard Jellyfin auth flow (`POST /Users/AuthenticateByName`).
3. **You're in.** Pick a track. It plays.

## Building from source

```bash
# Prereqs: Flutter 3.41.9 stable, Dart 3.11.5, Java 17, Android SDK
flutter --version    # must say 3.41.9
flutter pub get

# Run on a connected device / emulator
flutter run --debug

# Release APK
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Per-ABI APKs (smaller download per device)
flutter build apk --release --split-per-abi
```

### Pre-push checklist

```bash
flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
flutter test                       # 6/6 pass
```

CI runs both on every PR. See
[`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml).

## Architecture (the 30-second version)

```
   ┌────────────────────────────┐         ┌──────────────────────────────┐
   │   Aetherfin (Android)      │         │   Your Jellyfin server       │
   │                            │         │                              │
   │  ExoPlayer (just_audio) ◄──┼─bytes───┤  /Audio/{id}/stream          │
   │  Queue / shuffle / loop    │         │   ?Static=true               │
   │  Lyrics parse + sync       │◄─meta───┤  /Users/{id}/Items …         │
   │  Lock-screen controls      │         │  /Users/{id}/FavoriteItems   │
   │  Cover-art file cache      │◄─image──┤  /Items/{id}/Images/Primary  │
   │                            │         │                              │
   │  Optimistic favorite UI ───┼─POST────┤  (server is source of truth) │
   │  Telemetry (display only) ─┼─POST────┤  /Sessions/Playing[/Progress]│
   └────────────────────────────┘         └──────────────────────────────┘
```

Full architectural rules live in [`CLAUDE.md`](./CLAUDE.md), the
guide for any agent or human contributor.

## Privacy

Aetherfin does not operate any servers. The app talks only to the
Jellyfin server you configure. Credentials live in Android's secure
storage on the device. No analytics, no crash-reporting SDK, no ads,
no third-party trackers. Full statement in [PRIVACY.md](./PRIVACY.md).

## License

Aetherfin is open-source under the **MIT License**. See
[LICENSE](./LICENSE) for the full text.

Copyright © 2025 Azrim &lt;mirzaspc@gmail.com&gt;.

Jellyfin is © its respective authors and is licensed separately. This
project is not affiliated with the Jellyfin project.

## Contributing

PRs welcome. Read [CLAUDE.md](./CLAUDE.md) first — it covers the auth
header format, the data-source split, the design tokens, and the
non-negotiable rules. Branches are named `devin/<timestamp>-<slug>` for
agent-authored work; humans can use any naming they like.

## Acknowledgements

- [Jellyfin](https://jellyfin.org) — the free software media system this
  app is built around.
- [Finamp](https://github.com/jmshrv/finamp) — the prior-art Jellyfin
  music client whose auth-header format we follow.
- [just_audio](https://pub.dev/packages/just_audio) and
  [audio_service](https://pub.dev/packages/audio_service) — the audio
  + lock-screen plumbing.
