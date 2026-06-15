# Aetherfin Architecture

## Overview

Aetherfin is a native Android music player (Flutter 3.44 / Dart 3.11) that streams
from self-hosted **Jellyfin** or **Navidrome** servers, or plays local files via
SAF. Audio decoding is handled entirely on-device by **libmpv** (`mpv_audio_kit`).
No cloud, no telemetry, no transcoding.

---

## Tech Stack

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter 3.44.0, Dart 3.11.5 | Android 7.0+ (min SDK 24) |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier` for Riverpod. |
| Routing | `go_router` ^14.7 | Shell route with 4-tab bottom nav + overlay routes |
| Audio engine | `mpv_audio_kit` 0.3.6 | libmpv wrapper. NOT `just_audio`. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per backend client, each with its own `IOHttpClientAdapter` (adapter isolation) |
| Persistence | `drift` ^2.19 (local DB), `flutter_secure_storage` ^9.2 (credentials), `shared_preferences` ^2.3 (settings) | |
| Discovery | `multicast_dns` ^0.3.2 | mDNS for Jellyfin; Subsonic ping for Navidrome |
| Fonts | `google_fonts` ^6.2 | Inter Variable + JetBrains Mono |
| Crypto | `crypto` ^3.0.6 | Subsonic MD5 token auth |
| Lock-screen | Native Kotlin `MediaSessionService` + MethodChannel | `AetherfinMediaSessionService` |

---

## Directory Structure

```
lib/
├─ main.dart                          # 4-phase boot sequence
├─ build_id.dart                      # Auto-generated (by tool/generate_build_id.dart)
├─ app/
│  ├─ app.dart                        # Root MaterialApp.router + theme
│  ├─ router.dart                     # GoRouter config (shell + 20+ routes)
│  └─ theme.dart                      # Nocturne dark theme from tokens
├─ design_tokens/                     # Single source of truth for visual spec
│  ├─ tokens.dart                     # Barrel export
│  ├─ colors.dart                     # AfColors (indigo scale + surface)
│  ├─ motion.dart                     # AfCurves + AfDurations + AfStagger
│  ├─ radii.dart                      # AfRadii
│  ├─ spacing.dart                    # AfSpacing
│  └─ typography.dart                 # AfTypography
├─ core/
│  ├─ backend/
│  │  └─ music_backend.dart           # Abstract MusicBackend interface
│  ├─ audio/                          # Playback engine
│  │  ├─ player_service.dart          # AfPlayerService — mpv + MediaSession bridge
│  │  ├─ position_tracker.dart        # AfPositionTracker — elapsed-time extrapolation
│  │  ├─ artwork_manager.dart         # AfArtworkManager — cover art cache
│  │  ├─ audio_device_manager.dart    # AfAudioDeviceManager — output routing
│  │  ├─ queue_manager.dart           # AfQueueManager — queue interface
│  │  ├─ queue_engine.dart            # AfQueueEngine — Fisher-Yates shuffle logic
│  │  ├─ play_actions.dart            # Cross-cutting play entry points
│  │  ├─ jellyfin_playback_reporter.dart # Playback reporting lifecycle
│  │  ├─ live_update_service.dart     # Android 16+ Live Update chip
│  │  ├─ offline_cache_service.dart   # Offline track caching
│  │  ├─ stream_prefetcher.dart       # StreamPrefetcher — gapless track downloader
│  │  ├─ media_session_bridge.dart    # NativeMediaSessionBridge — throttled platform pushes
│  │  ├─ af_loop_mode.dart            # Custom loop mode definition
│  │  ├─ shuffle_mode.dart           # Custom shuffle mode definition
│  │  ├─ track_id_extractor.dart      # Parses IDs from media files
│  │  ├─ spectral_extractor.dart      # palette_generator wrapper
│  │  ├─ spectrum_settings.dart       # FFT config constants
│  │  └─ player_settings_store.dart   # Persisted DSP/EQ settings
│  ├─ jellyfin/
│  │  ├─ client.dart                  # JellyfinClient (implements MusicBackend)
│  │  ├─ url_builder.dart             # Stream/image URL + auth header builder
│  │  ├─ response_parser.dart         # JSON→domain model parser
│  │  ├─ auth_storage.dart            # Encrypted auth storage
│  │  ├─ discovery.dart               # mDNS server discovery
│  │  └─ models/                      # Hand-written domain models (NO json_serializable)
│  │      ├─ items.dart               # AfAlbum, AfTrack, AfArtist, etc.
│  │      ├─ server.dart              # JellyfinAuth, JellyfinServer, ServerType
│  │      ├─ library.dart             # LibraryView
│  │      └─ quality.dart             # AfQuality, AudioParams
│  ├─ subsonic/
│  │  ├─ client.dart                  # SubsonicClient (implements MusicBackend)
│  │  └─ navidrome_client.dart        # NavidromeClient (JWT auth & queue sync)
│  ├─ lastfm/
│  │  └─ lastfm_client.dart           # LastFmClient — speaks to ws.audioscrobbler.com API
│  ├─ local/                          # Local mode backend
│  │  ├─ app_database.dart            # Drift DB definition
│  │  ├─ app_database.g.dart          # Drift codegen (DO NOT hand-edit)
│  │  ├─ local_db.dart                # High-level queries (6 repos)
│  │  ├─ local_db_tracks.dart         # TrackRepository
│  │  ├─ local_db_albums.dart         # AlbumRepository
│  │  ├─ local_db_playlists.dart      # PlaylistRepository
│  │  ├─ local_db_track_stats.dart    # TrackStatsRepository (playback stats)
│  │  ├─ local_db_co_occurrences.dart # TrackCoOccurrencesRepository (smart queue relevance)
│  │  ├─ local_db_lastfm.dart         # LocalLastFmRepository (fallback stats/offline cache)
│  │  ├─ local_library.dart           # Scan + query interface
│  │  ├─ local_backend.dart           # LocalBackend (implements MusicBackend)
│  │  ├─ metadata_scanner.dart        # SAF file scanner
│  │  ├─ saf_picker.dart              # SAF folder picker bridge
│  │  └─ app_mode_store.dart          # Persist AppMode (server|local)
│  ├─ smart_playlist/
│  │  ├─ smart_playlist_model.dart    # SmartPlaylist + SmartRule
│  │  ├─ smart_playlist_db.dart       # SQLite CRUD
│  │  └─ smart_playlist_engine.dart   # Rule→track resolution
│  ├─ lyrics/
│  │  ├─ lrc_parser.dart              # LRC sync/unsynced parser
│  │  └─ embedded_lyrics_parser.dart  # ID3/meta embedded lyrics parser
│  ├─ search/
│  │  └─ search_history_store.dart    # Recent searches
│  └─ battery_opt.dart                # Battery optimization bridge
├─ features/                          # One folder per screen
│  ├─ home/                           # HomeScreen (carousel + recent items)
│  ├─ search/                         # SearchScreen
│  ├─ library/                        # LibraryScreen (albums/artists/songs/etc)
│  ├─ album/                          # AlbumScreen
│  ├─ artist/                         # ArtistScreen
│  ├─ genre/                          # GenreScreen
│  ├─ playlist/                       # PlaylistScreen
│  ├─ profile/                        # ProfileScreen
│  ├─ queue/                          # QueueScreen
│  ├─ now_playing/                    # NowPlayingScreen + sub-widgets
│  │  ├─ eq_dsp_screen.dart           # EQ/DSP full-screen
│  │  ├─ eq_dsp_widgets.dart          # EQ sliders, cards
│  │  ├─ eq_preset.dart               # kEqBands, kBuiltInPresets
│  │  ├─ reactive_artwork.dart        # Album art with transient pulse
│  │  └─ top_bar.dart                 # Now playing custom top bar
│  ├─ lyrics/                         # LyricsScreen
│  ├─ onboarding/                     # Welcome → Discovery → Sign-in → Scope → Done
│  ├─ settings/                       # SettingsScreen (4 files)
│  ├─ sleep_timer/                    # SleepTimerScreen
│  ├─ smart_playlist/                 # List + Detail + Edit screens
│  └─ cast_picker/                    # CastPickerScreen
├─ state/                             # Riverpod providers (17 files)
│  ├─ providers.dart                  # Barrel re-export
│  ├─ auth_providers.dart
│  ├─ app_mode_providers.dart
│  ├─ player_providers.dart           # wirePlayerService, position polling
│  ├─ library_providers.dart
│  ├─ local_library_providers.dart
│  ├─ detail_providers.dart
│  ├─ favorite_providers.dart
│  ├─ playlist_providers.dart
│  ├─ search_providers.dart
│  ├─ search_history_providers.dart
│  ├─ music_backend_providers.dart
│  ├─ settings_providers.dart
│  ├─ spectral_providers.dart
│  ├─ lastfm_metadata_providers.dart  # Bios and album wiki metadata providers
│  ├─ lastfm_stats_providers.dart     # Personal stats charts providers
│  ├─ lastfm_sync_provider.dart      # Two-way favorite sync provider
│  └─ radio_providers.dart            # Similar track/artist radio provider
├─ widgets/                           # Shared reusable widgets (22 files)
│  ├─ app_shell.dart                  # 4-tab shell
│  ├─ bottom_nav.dart                 # Pill-sliding bottom nav
│  ├─ artwork.dart                    # Cached artwork widget
│  ├─ track_row.dart                  # Track list row (3 density modes)
│  ├─ audio_visual_scrubber.dart      # Combined FFT + scrubber
│  ├─ hero_album_card.dart            # Home carousel card
│  ├─ press_scale.dart                # Press-scale wrapper
│  ├─ stagger_reveal.dart             # Staggered fade+slide reveal for lists/grids
│  └─ ...                             # See full list below
└─ utils/
   ├─ log.dart                        # afLog() wrapper
   ├─ time_format.dart                # Duration formatting
   ├─ url.dart                        # URL redaction + cache key
   ├─ display_error.dart              # User-friendly error display
   ├─ sql.dart                        # SQL helpers
   └─ oklch.dart                      # OKLCH→sRGB conversion
```

---

## App Bootstrap (4 phases)

```
main()
 ├─ runZonedGuarded
 │  ├─ WidgetsFlutterBinding.ensureInitialized()
 │  ├─ Install error handlers (FlutterError, PlatformDispatcher, ErrorWidget)
 │  ├─ Phase 1: Storage / auth hydration ────── Future.wait (5s timeout)
 │  │   ├─ AuthStorage.loadOrCreateDeviceId()
 │  │   ├─ AuthStorage.load()                    → JellyfinAuth?
 │  │   ├─ AppModeStore.load()                   → AppMode?
 │  │   ├─ SharedPreferences (artworkPulse, offlineCache*)
 │  │   └─ PackageInfo.fromPlatform()            → aetherfinVersion
 │  ├─ Phase 2: Native media engine
 │  │   └─ MpvAudioKit.ensureInitialized()
 │  ├─ Phase 3: OS audio service
 │  │   └─ AfPlayerService()
 │  │        ├─ AfPositionTracker
 │  │        ├─ AfArtworkManager
 │  │        ├─ AfAudioDeviceManager
 │  │        └─ AfQueueManager
 │  └─ Phase 4: Provider container + runApp
 │       ├─ ProviderContainer (9 overrides)
 │       ├─ wirePlayerService()           ← wires callbacks + polling + reporter
 │       ├─ OfflineCacheService.init()
 │       ├─ setRouterAuthState()          ← seed router with auth/mode
 │       ├─ authProvider listener         ← auth → router redirect
 │       ├─ appModeProvider listener      ← mode → router redirect
 │       └─ runApp(UncontrolledProviderScope → AetherfinApp())
```

---

## Core Components

### Audio Service (`AfPlayerService`)
The central hub. Composes 4 managers and helpers:
- **AfPositionTracker** — Elapsed-time extrapolation (anchor on play/seek, poll time-pos, fallback to `anchor + elapsed × speed`)
- **AfArtworkManager** — Downloads cover art to local storage for notifications
- **AfAudioDeviceManager** — Output routing with nudge chains (generation-counter guarded)
- **AfQueueManager** and **AfQueueEngine** — Queue state + Fisher-Yates shuffle mapping
- **StreamPrefetcher** — Dart-level pre-download caching of upcoming tracks to local storage for gapless playback under the single-track decoder model.

Communicates with native `AetherfinMediaSessionService` via `NativeMediaSessionBridge` (wrapping `MethodChannel('aetherfin.media_session')`). Operations serialized via `AfAsyncLock` (`_queueLock`).

### Backend Abstraction (`MusicBackend`)
```dart
abstract class MusicBackend {
  ServerType get serverType;
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20});
  Future<List<AfTrack>> search(String query);
  Future<void> setFavorite(String itemId, bool isFavorite);
  String trackStreamUrl(String trackId, {int? maxBitrateKbps});
  // ... 20+ methods for library, playlists, reporting
}
```
Three implementations:
- **JellyfinClient** (`lib/core/jellyfin/client.dart`) — Jellyfin REST API
- **SubsonicClient** (`lib/core/subsonic/client.dart`) — Subsonic/OpenSubsonic (Navidrome)
- **LocalBackend** (`lib/core/local/local_backend.dart`) — Local files via SAF

### State Management (Riverpod)
13 provider files in `lib/state/`, barrel-exported by `providers.dart`. Providers use `musicBackendProvider` (not `jellyfinClientProvider`) for backend ops. Pattern: `FutureProvider.autoDispose` for async data, `StateNotifierProvider` for mutable state.

**Provider lifecycle:**
- Library providers (allAlbums, allArtists, etc.) use `ref.keepAlive()` inside the provider body to persist across navigation
- Search, detail, and transient providers remain `.autoDispose` — they teardown when no longer needed
- Manual invalidation via `ref.invalidate()` or `ref.refresh()` refreshes kept-alive providers

**Token usage rules:**
- Never hardcode colors — use `AfColors.*` tokens.
- Never hardcode spacing — use `AfSpacing.*` tokens (e.g. `SizedBox(height: AfSpacing.s8)`).
- Never hardcode border radii — use `AfRadii.*` tokens (e.g. `BorderRadius: AfRadii.borderSm`).
- Never hardcode font sizes — use `AfTypography.*` text styles, optionally with `.copyWith()`.
- Never use raw `TextStyle(...)` — use `AfTypography.*.copyWith(...)` instead.

---

## Data Flow

```
┌──────────┐    ┌──────────────────────┐    ┌─────────────────┐
│  Widget   │◄───│   Riverpod Provider   │───▶│  MusicBackend    │
│  (UI)     │    │   (lib/state/)       │    │  (JellyfinClient │
│           │    │                      │    │   SubsonicClient│
│           │    │                      │    │   LocalBackend)  │
└──────────┘    └──────────────────────┘    └────────┬────────┘
                                                     │
                     ┌───────────────────────────────┤
                     │                               │
                     ▼                               ▼
          ┌──────────────────┐             ┌──────────────────┐
          │  dio HTTP client │             │  Local DB (drift)│
          │  (Jellyfin/Sub)  │             │  + SAF Scanner   │
          └────────┬─────────┘             └──────────────────┘
                   │
                   ▼
          ┌──────────────────┐
          │  Your Server     │
          │  (Jellyfin/      │
          │   Navidrome)     │
          └──────────────────┘

Audio playback flow:
  MusicBackend.trackStreamUrl() → URL → StreamPrefetcher (downloads & caches)
    → file:// URI (or URL fallback) → AfPlayerService → mpv_audio_kit (libmpv)
    → DSP effects → audio output
    → FFT stream → AudioVisualScrubber (64-band, vsync-aligned)
    → position stream → AfPositionTracker → TimeDisplay
```

---

## External Integrations

| Integration | Protocol | Details |
|---|---|---|
| **Jellyfin** | REST API | Auth: `Authorization: MediaBrowser ...` header. Stream: `/Audio/{id}/stream?Static=true` |
| **Navidrome** | Subsonic & Native REST | Auth: MD5 token in query params (Subsonic) or JWT via `POST /api/auth/login` (Native REST). Stream: `/rest/stream.view?id=...`. Queue Sync: `/api/queue` |
| **Android MediaSession** | MethodChannel | `aetherfin.media_session` — lock-screen controls (via `NativeMediaSessionBridge`) |
| **Battery Opt** | MethodChannel | `aetherfin.battery_opt` — request battery exemption |
| **SAF** | MethodChannel | `aetherfin.saf` — Storage Access Framework for local mode |
| **Live Update** | MethodChannel | `aetherfin.live_update` — Android 16+ progress chip |
| **mDNS** | `multicast_dns` | Jellyfin server discovery via `_jellyfin._tcp` |

---

## Configuration

| Config File | Purpose |
|---|---|
| `pubspec.yaml` | Dependencies, version (0.2.4+5), assets |
| `analysis_options.yaml` | Linter: strict-casts, strict-raw-types, trailing commas, prefer_final_locals |
| `android/app/build.gradle.kts` | NDK 28.2, Java 17, namespace `dev.aetherfin.aetherfin` |
| `android/settings.gradle.kts` | AGP 8.11.1, Kotlin 2.2.20 |
| `android/gradle.properties` | 8G JVM, parallel builds, no config cache |
| `.github/workflows/pr-checks.yml` | CI: analyze + test on PR/push |
| `.github/workflows/build-apk.yml` | Manual APK build + Telegram delivery |
| `.github/workflows/release.yml` | Full release with signing + GitHub Release |

Environment variables (secrets in CI): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

---

## Build & Deploy

```bash
# Development
flutter pub get
dart run build_runner build  # codegen (drift)
flutter analyze --no-fatal-infos
flutter test
flutter run --debug

# Release
tool/generate_build_id.dart          # writes lib/build_id.dart
flutter build apk --release
flutter build apk --release --split-per-abi

# CI order: pub get → build_runner → analyze → test → build
```

---

## Key Architecture Rules

1. **Audio engine is `mpv_audio_kit`** — never `just_audio` or any other player.
2. **No `json_serializable`** — all models are hand-written Dart classes.
3. **Stream URLs embed auth as query params** — libmpv/FFmpeg rejects header auth.
4. **Favorites are server-owned** — flip locally first, revert on HTTP error.
5. **Queue operations serialized via `AfAsyncLock`** — prevents interleaved mutations.
6. **Visualizer is engine-driven** — C++ EMA handles bounce physics; client applies only power-10 curve.
7. **Auth loaded before `runApp`** — injected via ProviderScope overrides, no async hydrate.
8. **GoRouter is a module-level singleton** — never recreated (causes Duplicate GlobalKey).
9. **`context.push()` for overlays, `context.go()` for tab switches** — mixing breaks back stack.
10. **Design token tests enforce exact values** — 80/160/240/400/600ms, specific hex colors.
