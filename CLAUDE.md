# CLAUDE.md — Aetherfin Project Guide

This document is the **single source of truth** for AI coding agents working
on Aetherfin. Read this end to end before making changes. It captures the
constraints, conventions, and gotchas discovered while building the client
and is updated as we learn more.

## 1. What Aetherfin is

A native-feeling Android music player that operates in one of two modes:
- **Server mode** — streams from a self-hosted **Jellyfin** or **Navidrome** server.
- **Local mode** — plays audio files from device storage via SAF (Storage Access Framework).

The only first-class platform is Android. iOS may follow but is not
considered when making trade-offs.

> Aetherfin must read as a *premium music* app,
> not "a Jellyfin/Navidrome client."

### 1.1 App modes

The user picks a mode during onboarding. Only one mode is active at a time.
Mode is persisted in `shared_preferences` via `AppModeStore`. Switching
mode returns to onboarding.

```dart
enum AppMode { server, local }
```

### 1.2 Mental model — what runs where (Server mode)

Treat the server (Jellyfin or Navidrome) as a **file source + library state
store**, nothing else. **Aetherfin is the player.**

The app supports two server backends via the `MusicBackend` abstraction
(`lib/core/backend/music_backend.dart`). `ServerType` (jellyfin | subsonic)
is persisted in auth storage and determines which client is instantiated.

**Server (Jellyfin or Navidrome) is responsible for:**
- Storing audio files and serving the original bytes byte-for-byte.
- Catalog metadata: titles, artists, albums, genres, durations, year, artwork.
- Search (Jellyfin: `/Users/{id}/Items?searchTerm=…` — never `/Search/Hints`;
  Navidrome: `search3.view`).
- Auth (Jellyfin: user accounts + access tokens; Navidrome: Subsonic token
  auth — `md5(password + salt)`).
- Per-user state: favorites, play counts, last-played-at, playlists.
- LRC lyric files (stored only; the app parses them).
- "Now Playing" telemetry display — Jellyfin: `POST /Sessions/Playing*`;
  Navidrome: `scrobble.view`.

### 1.3 Mental model — Local mode

In local mode there is no server. The app scans device folders via SAF,
extracts metadata using Android's `MediaMetadataRetriever`, caches it in
a local SQLite database (`sqflite`), and plays files via `content://` URIs.

**Local mode provides:**
- Albums, Artists, Songs, Genres (parsed from file tags)
- Cover art (embedded in files, cached to disk)
- Full playback: queue, shuffle, loop, gapless, visualizer, EQ/DSP
- Favorites and playlists (stored in local SQLite via Drift)
- Smart playlists (resolved via SQL against the local tag cache)

**Aetherfin (app) is responsible for everything, on-device:**
- All audio **decoding** (libmpv via `mpv_audio_kit`).
- Buffering, gapless transitions, output routing, position tracking.
- Queue management (order, shuffle, repeat, reorder).
- UI rendering for every screen.
- LRC parsing + synced line highlighting.
- Real-time FFT spectrum + client-side DSP for the visualizer.
- FFT-driven artwork pulse (sub-bass transient detector).
- Spectral color extraction from artwork (`palette_generator_master`).
- Lock-screen / notification media-session integration (custom Kotlin `MediaSessionCompat` + MethodChannel).
- Cover-art file cache (`cached_network_image` for server, `Image.file` for local).
- Local settings: audio-quality preference, sleep timer, EQ/DSP, ReplayGain.
- **Local mode only:** metadata scanning, SQLite cache, SAF folder management.

**Strict consequence (Jellyfin):** stream URLs MUST use
`/Audio/{id}/stream?Static=true` — the direct-stream endpoint. The
universal endpoint (`/Audio/{id}/universal`) triggers server-side
transcoding to HLS, which (1) wastes the server's CPU, (2) gives a
codec that may not decode cleanly, and (3) was the cause of the
"track plays but position never advances" bug.

**Strict consequence (Navidrome):** stream URLs use
`/rest/stream.view?id={id}&u=…&t=…&s=…&v=1.16.1&c=Aetherfin&f=json`.
Auth is embedded as query parameters (username, token, salt) because
libmpv/FFmpeg cannot use Subsonic header auth.

**Strict consequence #2:** stream URLs embed auth as query parameters.
Jellyfin: `api_key=<token>`. Navidrome: `u`, `t` (md5 hash), `s` (salt).
FFmpeg/libmpv rejects the `Authorization: MediaBrowser …` header
(commas treated as header-list separators).

**Strict consequence #3:** favorites, play counts, and playlist contents
are server-owned even though the heart icon flips locally first.
Jellyfin: `POST/DELETE /Users/{id}/FavoriteItems/{itemId}`.
Navidrome: `star.view` / `unstar.view`.
On HTTP error, revert. Never store favorite state only on-device.

## 2. Tech stack (exact versions)

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter **3.44.0 stable**, Dart **3.11.5** | `flutter --version` must match. CI pins this. |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier` for Riverpod providers. |
| Routing | `go_router` ^14.7 | Shell route with bottom nav. See `lib/app/router.dart`. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per client, each with its own `IOHttpClientAdapter` (adapter isolation — `close(force:true)` on one client does not kill another). Jellyfin: auth header in `BaseOptions.headers`. Subsonic: auth as query params. |
| Crypto | `crypto` ^3.0.6 | Subsonic token auth: `md5(password + salt)`. |
| Audio | `mpv_audio_kit` 0.3.6 | libmpv-backed player. Replaces `just_audio` + `audio_session`. |
| Lock-screen | Native MediaSession | Custom Kotlin service (`AetherfinMediaSessionService`) with `MethodChannel` (`aetherfin.media_session`). |
| Storage | `flutter_secure_storage` ^9.2 (creds + deviceId), `shared_preferences` ^2.3 (settings), `drift` ^2.19 (local metadata cache) | Never store creds in shared_preferences. |
| Discovery | `multicast_dns` ^0.3.2 | mDNS scan for `_jellyfin._tcp`. Navidrome: probed via Subsonic `ping.view`. |
| Icons | `lucide_icons` ^0.257.0, `lucide_icons_flutter` ^3.1.14+1 | All UI icons use **Lucide** (replaced hugeicons). Import from `package:lucide_icons_flutter/lucide_icons.dart`. |
| Imagery | `cached_network_image` ^3.4, `flutter_svg` ^2.0, `palette_generator_master` ^1.1 | All cover art through `cached_network_image`. |
| Fonts | `google_fonts` ^6.2, `cupertino_icons` ^1.0.8 | Inter Variable + JetBrains Mono. cupertino_icons satisfies transitive font validator. |
| UUID | `uuid` ^4.5 | Fallback device ID generation (cryptographically random). |
| Skeleton | Custom skeleton widgets in `lib/widgets/skeletons/` | Shimmer skeleton loading on all screens. Each screen has a corresponding `*_skeleton.dart` file. |

The min Android SDK is **24** (Android 7.0). Built with **Java 17** + Gradle
in CI. Local Java 17 is required.

`mpv_audio_kit` downloads `libmpv.so` from GitHub Releases at build time
(~20 MB per ABI, arm64-v8a + x86_64). The first build requires internet
access. Subsequent builds reuse the cached `.so` files.

### 2.1 mpv_audio_kit API surface used

```dart
// Queue replacement
await player.openAll(medias, index: startIndex, play: true);

// Playback control
await player.play();
await player.pause();
await player.seek(position);
await player.next();
await player.previous();
await player.jump(index);
// Note: player.setShuffle(true/false) and player.setGapless(...) are not used.
// Aetherfin uses a single-track decoder model. Shuffle is managed in Dart inside AfQueueManager,
// and gapless transitions are supported via a custom Dart-side StreamPrefetcher.

// State streams (core)
player.stream.position    // Stream<Duration>
player.stream.playing     // Stream<bool>
player.stream.shuffle     // Stream<bool>
player.stream.loop        // Stream<Loop>  (Loop.off / Loop.file / Loop.playlist)
player.stream.rate        // Stream<double>
player.stream.spectrum    // Stream<FftFrame> — 64 bands, post-DSP, ~120 fps
player.stream.coverArt    // Stream<CoverArt?> — embedded art bytes
player.stream.playlist    // Stream<Playlist>
player.stream.completed   // Stream<bool>
player.stream.buffering   // Stream<bool>

// Playback state (extended)
player.mpvPlaybackStateStream  // Stream — raw mpv playback state
player.bufferingStream         // Stream<bool>
player.bufferingPercentageStream // Stream<double>

// Volume
player.volumeStream       // Stream<double>
player.setVolume(double)
player.muteStream         // Stream<bool>
player.setMute(bool)

// Quality info
player.audioBitrateStream   // Stream<int?>
player.audioParamsStream    // Stream<AudioParams?>

// Gapless
player.prefetchStateStream  // Stream
player.setGapless(Gapless)
player.setPrefetchPlaylist(bool)

// Errors
player.errorStream          // Stream<String?>

// A-B loop
player.setAbLoopA / setAbLoopB / setAbLoopCount
player.abLoopAStream        // Stream<Duration?>
player.abLoopBStream        // Stream<Duration?>
player.remainingAbLoopsStream // Stream<int?>

// DSP / Audio effects
player.setAudioEffects(AudioEffects)
player.updateAudioEffects(AudioEffects)
player.audioEffectsStream   // Stream<AudioEffects>

// ReplayGain
player.setReplayGain(ReplayGainMode)
player.replayGainStream     // Stream<ReplayGainMode>

// Spectrum configuration — engine handles all bounce physics in C++
await player.setSpectrum(SpectrumSettings(
  fftSize: 2048,
  bandCount: 64,
  bandLowHz: 20.0,
  bandHighHz: 20000.0,
  attackSmoothing: 0.8,   // Fast attack for punch
  releaseSmoothing: 0.1,  // Slow release for bouncy decay
  minDb: -105.0,          // Very wide range for maximum dynamic headroom
  maxDb: 35.0,
  emitInterval: Duration(milliseconds: 8), // ~120 fps emission
));

// Loop enum values
Loop.off       // no looping
Loop.file      // repeat current track
Loop.playlist  // repeat entire queue
```

## 3. Source-tree map

```
lib/
├─ main.dart                ← runApp + boot trace + player service init
│                             Startup timeouts (5s storage).
│                             UUID v4 fallback device ID. Release error redaction.
├─ app/
│  ├─ app.dart              ← Root MaterialApp.router
│  ├─ router.dart           ← go_router config (shell + nested routes)
│  └─ theme.dart            ← ThemeData built from design tokens
├─ design_tokens/           ← Single source of truth for §4 visual spec
├─ core/
│  ├─ audio/
│  │  ├─ player_service.dart        ← AfPlayerService: mpv_audio_kit + NativeMediaSessionBridge
│  │  │                               bridge to Kotlin service. Composes position_tracker,
│  │  │                               artwork_manager, audio_device_manager, queue_manager,
│  │  │                               queue_engine, and stream_prefetcher.
│  │  │                               Throttled playbackState (~2 Hz), _pendingPlayNudgeIdx
│  │  │                               Shuffle: managed in Dart (Fisher-Yates) to support large queues.
│  │  │                               Single-track decoder model: rebuilding the player window with file://
│  │  │                               URI from custom StreamPrefetcher when ready, or remote URL fallback.
│  │  ├─ play_actions.dart          ← Cross-cutting play entry points (uses MusicBackend)
│  │  │                               PlayActions.playQueue shuffles before loading when shuffle is ON.
│  │  ├─ jellyfin_playback_reporter.dart ← Playback reporting lifecycle (uses MusicBackend)
│  │  │                               Jellyfin: POST /Sessions/Playing*
│  │  │                               Navidrome: scrobble.view
│  │  │                               Serialized progress loop (not Timer.periodic), 5s timeouts.
│  │  ├─ live_update_service.dart   ← Android 16+ Live Update chip (in-flight guard)
│  │  ├─ spectral_extractor.dart    ← palette_generator → Spectral triple (LRU cache)
│  │  ├─ position_tracker.dart      ← AfPositionTracker: elapsed-time position extrapolation
│  │  ├─ artwork_manager.dart       ← AfArtworkManager: cover art download + notification artwork
│  │  ├─ audio_device_manager.dart    ← AfAudioDeviceManager: audio device routing + nudge chains
│  │  ├─ queue_manager.dart         ← AfQueueManager: playlist queue interface
│  │  ├─ queue_engine.dart          ← AfQueueEngine: Fisher-Yates queue shuffle state machine
│  │  ├─ stream_prefetcher.dart     ← StreamPrefetcher: buffers upcoming tracks locally for gapless
│  │  ├─ media_session_bridge.dart  ← NativeMediaSessionBridge: throttled pushState (100ms),
│  │  │                               MediaSessionState snapshots, callback-based dispatch.
│  │  ├─ af_loop_mode.dart          ← Custom loop mode definition
│  │  ├─ shuffle_mode.dart           ← Custom shuffle mode definition
│  │  ├─ track_id_extractor.dart      ← Parses track IDs from paths
│  │  └─ spectrum_settings.dart     ← Default SpectrumSettings constants
│  ├─ backend/
│  │  └─ music_backend.dart ← Abstract MusicBackend interface. Both JellyfinClient and
│  │                          SubsonicClient implement this. Defines all server operations:
│  │                          library browsing, search, favorites, playlists, streaming,
│  │                          playback reporting, lyrics. ServerType enum exported here.
│  ├─ battery_opt.dart      ← Dart bridge to BatteryOptPlugin (aetherfin.battery_opt channel)
│  ├─ local/
│  │  ├─ app_mode_store.dart    ← Persist/restore AppMode (server|local) via SharedPreferences
│  │  ├─ app_database.dart      ← Drift database definition (tracks, folders, favorites, playlists)
│  │  ├─ app_database.g.dart    ← Drift-generated code (DO NOT hand-edit)
│  │  ├─ local_db.dart          ← High-level query methods composing 3 repositories:
│  │  │                           TrackRepository + AlbumRepository + PlaylistRepository
│  │  ├─ local_db_tracks.dart   ← TrackRepository: track CRUD + queries + rowToTrack + rawRowToTrack
│  │  ├─ local_db_albums.dart   ← AlbumRepository: all album aggregation queries
│  │  ├─ local_db_playlists.dart← PlaylistRepository: CRUD + transaction logic
│  │  ├─ local_library.dart     ← High-level interface: scan, query albums/artists/tracks/genres
│  │  ├─ local_backend.dart     ← LocalBackend: implements MusicBackend over LocalLibrary + LocalDb
│  │  ├─ metadata_scanner.dart  ← Orchestrates SAF scan: list files → read tags → insert DB
│  │  ├─ saf_picker.dart        ← Dart bridge to SafPlugin (aetherfin.saf MethodChannel)
│  │  └─ cover_cache_manager.dart ← CoverCacheManager: LRU-evicted cover art disk cache
│  │                               Cleans up orphan temp files on startup
│  ├─ smart_playlist/
│  │  ├─ smart_playlist_model.dart  ← SmartPlaylist + SmartRule data models
│  │  ├─ smart_playlist_db.dart     ← SQLite CRUD for smart playlists
│  │  └─ smart_playlist_engine.dart ← Resolves rules → tracks (SQL for local, filter for server)
│  ├─ jellyfin/
│  │  ├─ client.dart        ← HTTP to Jellyfin (implements MusicBackend). Composes
│  │  │                        JellyfinResponseParser + JellyfinUrlBuilder.
│  │  ├─ response_parser.dart ← JellyfinResponseParser: JSON→domain parsing + field constants
│  │  ├─ url_builder.dart    ← JellyfinUrlBuilder: auth headers, stream/image URLs
│  │  ├─ auth_storage.dart  ← secure_storage wrappers (token, userId, deviceId, serverType)
│  │  ├─ discovery.dart     ← mDNS scan + public-info probe
│  │  └─ models/            ← Plain Dart classes — NO json_serializable codegen
│  │                          server.dart includes ServerType enum + JellyfinAuth (used by both backends)
│  ├─ subsonic/
│  │  ├─ client.dart        ← Speaks HTTP to Navidrome (implements MusicBackend Subsonic API).
│  │  │                          Subsonic/OpenSubsonic REST API. Token auth: md5(password + salt).
│  │  │                          Random salt per request. All endpoints: albums, artists, tracks,
│  │  │                          playlists (CRUD), search, favorites, genres, lyrics, similar songs,
│  │  │                          scrobbling. Stream/cover art URLs embed auth as query params.
│  │  └─ navidrome_client.dart ← Speaks native Navidrome REST API for JWT auth and play queue sync.
│  ├─ lyrics/               ← LRC/embedded lyrics parser
│  │  ├─ lrc_parser.dart
│  │  └─ embedded_lyrics_parser.dart
├─ features/                ← One folder per top-level screen
│  ├─ home/        library/  album/      artist/     genre/
│  ├─ search/      queue/    now_playing/ lyrics/
│  ├─ onboarding/  profile/  settings/    cast_picker/  sleep_timer/  playlist/
│  │                            now_playing/ contains eq_dsp_screen.dart (EQ/DSP screen),
│  │                            eq_preset.dart (kEqBands, kBuiltInPresets),
│  │                            eq_dsp_widgets.dart (section labels, cards, sliders).
│  │                            now_playing_screen.dart composes reactive widgets:
│  │                            reactive_artwork, metadata_row, reactive_progress,
│  │                            reactive_transport, top_bar, transport_widgets,
│  │                            now_playing_chip, utility_row, sleep_timer_dialog.
│  │                            Gradient background via AnimatedContainer + spectral colors.
│  │                            smart_playlist/ — list, detail, edit screens (Samsung One UI style)
│  │                            settings_screen.dart — build() only; delegates to
│  │                            settings_widgets.dart (SettingsLabel, SettingsGroup, SettingsTile,
│  │                              SettingsSwitchTile, OptionTile),
│  │                            settings_dialogs.dart (6 dialogs + ReplayGainDialogContent),
│  │                            settings_sections.dart (MusicFoldersCard, PrefetchToggle, etc.).
│  │                            Samsung One UI grouped card layout. Sections:
│  │                            Server (info, switch, sign out), Appearance,
│  │                            Audio output (current output, sample rate, bit depth, exclusive),
│  │                            Network & cache (cache duration, audio buffer, keep audio active),
│  │                            Audio processing (ReplayGain, gapless, prefetch),
│  │                            About (dynamic version, source link, licenses).
│  │                            library/ sections: Albums, Artists, Songs, Playlists, Genres, Liked.
│  │                            Context menus use dialogs (not bottom sheets) for album 3-dot
│  │                            and track long-press. Bottom sheets use per-sheet manual drag
│  │                            handles (theme no longer provides showDragHandle).
├─ state/
│  ├─ providers.dart        ← Barrel re-export of 13 domain provider files
│  ├─ app_mode_providers.dart
│  ├─ auth_providers.dart
│  ├─ detail_providers.dart
│  ├─ favorite_providers.dart
│  ├─ library_providers.dart
│  ├─ local_library_providers.dart
│  ├─ music_backend_providers.dart
│  ├─ player_providers.dart
│  ├─ playlist_providers.dart
│  ├─ search_history_providers.dart
│  ├─ search_providers.dart
│  ├─ settings_providers.dart
│  └─ spectral_providers.dart
├─ widgets/                 ← Shared visual atoms
│  ├─ bottom_nav.dart       ← Google-style bottom nav with sliding pill background
│  │                          Animated sliding indigo900 pill behind active tab (240ms easeStandard).
│  │                          Inactive tabs show icon only; label appears when showNavLabelsProvider is true.
│  ├─ hero_album_card.dart  ← Hero album card (used in home screen carousel)
│  ├─ audio_visual_scrubber.dart ← Combined FFT visualizer + progress scrubber.
│  │                          _BlockNotifier: power-10 curve, vsync-aligned flush.
│  │                          Engine-driven rendering: ingest() updates data only (no
│  │                          notifyListeners). Ticker runs at vsync, calls flush() which
│  │                          fires notifyListeners when dirty.
│  │                          _ScrubNotifier: drag state.
│  │                          Two Stack layers: _CombinedBarPainter (path-batched, 4 draw calls) +
│  │                          _ScrubOverlayPainter.
│  │                          Lifecycle-aware (AppLifecycleListener + route obscure detection).
│  │                          Ticker drives repaints at vsync; 300ms silence timer for fade-out
│  │                          (0.85× decay). Scrubber drag race fix with _isDragging flag.
│  ├─ skeleton.dart         ← Reusable skeleton/shimmer base widget
│  ├─ skeletons/            ← Screen-specific skeleton loaders
│  │   ├─ home_skeleton.dart    album_card_skeleton.dart
│  │   ├─ library_skeleton.dart album_skeleton.dart
│  │   ├─ artist_skeleton.dart  genre_skeleton.dart
│  │   ├─ playlist_skeleton.dart track_row_skeleton.dart
│  │   ├─ search_skeleton.dart  lyrics_skeleton.dart
│  │   └─ sheet_skeleton.dart
│  ├─ af_dialog.dart        ← Unified dialog wrapper for context menus
│  ├─ album_more_sheet.dart ← Album 3-dot action sheet (dialog-based)
│  ├─ bottom_sheet.dart     ← Shared bottom sheet wrapper with frosted glass
│  ├─ press_scale.dart      ← Press-down scale animation wrapper
│  ├─ stagger_reveal.dart   ← Staggered fade+slide-up reveal for lists/grids
│  ├─ save_to_playlist_sheet.dart ← Save-track-to-playlist bottom sheet
│  ├─ track_details_sheet.dart  ← Track info bottom sheet
│  ├─ track_context_menu.dart   ← Long-press context menu builder
│  └─ …
└─ utils/
   ├─ log.dart              ← afLog() wrapper around dart:developer.log
   ├─ oklch.dart            ← OKLCH → sRGB conversion
   └─ time_format.dart      ← Duration formatting helpers
```

### 3.1 Android native plugins

```
android/app/src/main/kotlin/dev/aetherfin/aetherfin/
├─ MainActivity.kt            ← Registers LiveUpdatePlugin + BatteryOptPlugin + SafPlugin
├─ battery/
│  └─ BatteryOptPlugin.kt     ← MethodChannel: aetherfin.battery_opt
│                               ActivityAware. Methods:
│                               isIgnoringBatteryOptimizations() → bool
│                               requestIgnoreBatteryOptimizations() → bool
├─ live_update/
│  └─ LiveUpdatePlugin.kt     ← MethodChannel: aetherfin.live_update
│                               Android 16+ ProgressStyle Live Update chip
└─ saf/
   └─ SafPlugin.kt            ← MethodChannel: aetherfin.saf
                                ActivityAware. Methods:
                                pickFolder() → String? (tree URI)
                                listAudioFiles(uri) → List<Map> (recursive scan)
                                readMetadata(uri) → Map (MediaMetadataRetriever)
                                readCoverArt(uri) → ByteArray? (embedded art)
```

## 4. Design token usage rules

All visual values MUST come from `lib/design_tokens/`. Import via
`package:aetherfin/design_tokens/tokens.dart`.

**Spacing:** Use `AfSpacing.*` — `SizedBox(height: AfSpacing.s8)`,
`EdgeInsets.all(AfSpacing.s16)`. Never raw ints for layout spacing.

**Border radii:** Use `AfRadii.*` — `AfRadii.borderSm` (8dp),
`AfRadii.borderMd` (12dp), `AfRadii.borderPill` (999dp). Never
`BorderRadius.circular(N)`.

**Typography:** Use `AfTypography.*` text styles with `.copyWith()` for
color/weight overrides. Never raw `TextStyle(...)` or bare `fontSize:`.

**Colors:** Use `AfColors.*` — never `Colors.white`, `Colors.black`,
or raw `Color(0xFF...)` outside `design_tokens/colors.dart`.

**Lint enforcement:** `flutter analyze` must report 0 errors, 0 warnings.
`dart fix --apply` auto-fixes `prefer_const_constructors` info-level lints.

## 5. Jellyfin auth — battle-tested format

Every Jellyfin request carries:

```
Authorization: MediaBrowser UserId="…", Token="…", Client="Aetherfin", Device="Android", DeviceId="…", Version="<app-version>"
Content-Type: application/json
User-Agent: Aetherfin/<app-version> (Android)
Accept: application/json
```

`<app-version>` is loaded from `package_info_plus` in `main()` (Phase 1) and
injected into the HTTP clients through `aetherfinVersionProvider`. **Never
hardcode this value inside the clients** — a prior bug shipped `Aetherfin/0.1.0`
long after the app moved to `0.2.3` because two `_kAetherfinVersion` constants
drifted out of sync with pubspec.yaml.

Rules:
- **`UserId` and `Token` are OMITTED entirely before login.**
- **Send only `Authorization`** — not `X-Emby-Authorization`.
- **Field order matches Finamp**: `UserId, Token, Client, Device, DeviceId, Version`.
- **`DeviceId` is a per-install UUID v4** in `flutter_secure_storage`. Fallback uses `uuid` package (not timestamp).
- Non-ASCII bytes in the header are replaced with `_`.
- **Stream URLs use `api_key=<token>` query param** — NOT the Authorization header. FFmpeg rejects the MediaBrowser header format.

The canonical implementation lives in `_buildAuthHeader()` at
`lib/core/jellyfin/client.dart`. **Do not duplicate this logic.**

### 5.1 If `AuthenticateByName` returns 500
Almost always a server-side issue. Reproduce with `curl`:
```bash
curl -i -X POST 'http://SERVER/Users/AuthenticateByName' \
  -H 'Authorization: MediaBrowser Client="curl", Device="curl", DeviceId="curl-001", Version="1.0.0"' \
  -H 'Content-Type: application/json' \
  -d '{"Username":"u","Pw":"p"}'
```
If `curl` also returns 500, restart the Jellyfin Docker container.

### 5.2 Race-free auth hydration

`main()` reads `AuthStorage().load()` before `runApp` and injects the
result via `ProviderScope` overrides. `AuthNotifier` takes the initial
value through its constructor — no async hydrate, no race window.
Storage IO has a 5s timeout.

### 5.3 Router-level auth redirects

`go_router` is wired with a `refreshListenable` that fires when
`authProvider` changes. The `redirect` callback sends signed-in users
to `/home` and anonymous users to `/`. Every onboarding route must
start with `/onboarding/`.

### 5.4 Subsonic (Navidrome) auth

Navidrome uses the Subsonic API authentication scheme. Every request
carries these query parameters (not headers):

| Param | Value |
|---|---|
| `u` | Username |
| `t` | `md5(password + salt)` — computed fresh per request |
| `s` | Random salt (unique per request to prevent replay) |
| `v` | `1.16.1` (Subsonic API version) |
| `c` | `Aetherfin` (client identifier) |
| `f` | `json` (response format) |

Rules:
- **Password is stored in `JellyfinAuth.accessToken`** (encrypted in
  `flutter_secure_storage`). Needed to compute the per-request token.
- **Salt is random per request** — never reuse salts.
- **No Authorization header** — Subsonic auth is purely query-param-based.
- **Stream and cover art URLs embed auth** — same params as above appended
  to `/rest/stream.view?id=…` and `/rest/getCoverArt.view?id=…`.
- The canonical implementation lives in `SubsonicClient._authParams()`
  at `lib/core/subsonic/client.dart`. **Do not duplicate this logic.**
- **Navidrome Native REST API Auth**: To support play queue synchronization, `NavidromeClient` (`lib/core/subsonic/navidrome_client.dart`) authenticates via `POST auth/login` using the username and raw password to obtain a temporary JWT token, which is stored in memory and sent via the `x-nd-authorization: Bearer <token>` header for native endpoints.

### 5.5 Server detection during onboarding

The server discovery screen (`server_discovery_screen.dart`) probes
servers in order:
1. Try Jellyfin `publicInfo()` — if it responds, server is Jellyfin.
2. If that fails, try Subsonic `ping.view` — Navidrome responds with a
   Subsonic API envelope even on bad credentials.
3. The detected `ServerType` is passed to the sign-in screen via the
   router's `extra` parameter.

## 6. Navigation rules

- **`context.push()`** for transient/detail screens: `/now-playing`, `/lyrics`, `/queue`, `/album/:id`, `/artist/:id`, `/playlist/:id`, `/settings`, `/sleep`, `/cast`. These sit on the navigation stack; back gesture pops them.
- **`context go()`** only for top-level shell navigation (tab switches, auth redirects). These replace the stack.
- Mixing `go()` and `push()` incorrectly destroys the back stack. `lyrics_screen.dart` and `queue_screen.dart` both use `push()` to navigate to each other — using `go()` would replace the stack and break the back gesture.
- `/lyrics` and `/queue` routes use `NoTransitionPage` (not default `MaterialPage`) to prevent out-of-frame rendering when pushed on `_rootKey` above the now-playing overlay.

## 7. Notification / lock-screen / app widget rules

- Implemented via a platform-native Kotlin foreground service `AetherfinMediaSessionService` and a `NativeMediaSessionBridge` (Dart bridge) over `MethodChannel` (`aetherfin.media_session`).
- Controls are dynamically updated on the native side based on the current queue bounds (Previous/Play-Pause/Next).
- **Never pass a network artwork URL** to the native player state — the native service reads artwork directly from local storage. Always resolve and download/save the artwork to a local `file://` URI first, and pass the path using `artPath` to the native service.
- When playback is paused, the foreground service status is dropped (`stopForeground(false)`) to let the user swipe the notification away, but the notification itself is kept visible.
- **App Widget & Palette extraction**: The app widget (`AetherfinAppWidgetProvider`) dynamically extracts dominant/muted background colors using Android's `Palette` API on the artwork, checks luminance for accessible white/black text contrast, and links a favorite heart `ImageButton` to broadcast `ACTION_TOGGLE_FAVORITE` back to the service.
- **Dynamic Launcher Icons**: Configured via four `<activity-alias>` elements (`DefaultIcon`, `MidnightIcon`, `NordicIcon`, `SunsetIcon`) in `AndroidManifest.xml` targetting `.MainActivity`. Switching icons calls `changeAppIcon` on the method channel. `tryFixLauncherIconIfNeeded` runs on boot to guarantee that if all aliases are somehow disabled, the `DefaultIcon` is automatically re-enabled to prevent the app from disappearing from the launcher.

## 8. Background playback (Samsung / Doze)

- Auto-advance uses stream callbacks (`_pendingPlayNudgeIdx` state machine), not `Future.delayed` or `.then()` chaining. Doze throttles both when the screen is off.
- `_jumpAndPlay(index)` uses `async/await` — not `.then()` — so `play()` is not deferred by the Dart scheduler under Doze.
- Race-condition guard: the `playlist` stream listener checks `_player.state.playing` synchronously. If already `false` when the index changes, nudge fires immediately without waiting for the next `playing` event.
- Nudge is bounded to `_maxNudgeRetries = 3` to prevent infinite play loops.
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission declared in manifest. Battery exemption dialog shown on first HomeScreen visit via `BatteryOpt.requestIgnore()` → `BatteryOptPlugin` (`aetherfin.battery_opt` MethodChannel).

## 9. Visualizer + scrubber architecture (engine-driven rendering)

The visualizer and progress scrubber are merged into a single widget
(`AudioVisualScrubber` at `lib/widgets/audio_visual_scrubber.dart`) with
two painter layers in a `Stack`. The architecture is engine-driven:
`ingest()` updates data only (no notifyListeners). A ticker runs at vsync
and calls `flush()` which fires notifyListeners when dirty. Power-8 curve.
300ms silence timer triggers fade-out (0.85× decay). Path-batched painter
(4 draw calls). Scrubber drag race fix with `_isDragging` flag.

### 9.1 Signal pipeline (`_BlockNotifier`)

The engine's native C++ EMA (attack 0.8, release 0.1) handles all bounce
physics. The client does NO smoothing — it renders bands directly with
only a power curve for visual compression.

```
Player.stream.spectrum (64 bands, ~120 fps, engine-smoothed)
    │
    ▼  ingest() — data update only, no notifyListeners
for each band i:
  raw = bands[i].clamp(0, 1)
  smoothed[i] = pow(raw, 10.0)    ← power-10 compression (precomputed LUT, 1024 entries)
totalEnergy = mean(smoothed)
_dirty = true
    │
    ▼  flush() — called by ticker on every vsync (60 fps)
if (_dirty):
  _dirty = false
  notifyListeners()              ← triggers repaint, frame-aligned
```

**Why vsync-aligned:** Stream events arrive from Dart's async zone, not
aligned to Flutter's vsync. If an event arrives right after a vsync, the
repaint waits until the next one — halving perceived frame rate. The ticker
guarantees frame-aligned repaints at a steady 60 fps.

**Fade-out:** When audio stops (300ms silence timer), `startFadeOut()` sets
a flag. The ticker's `flush()` detects it and runs `_tickFadeOut()` which
decays bars at 0.85× per frame until they reach zero. Ticker self-stops
when no energy remains.

**Lifecycle awareness:**
- `AppLifecycleListener` stops the ticker on `onPause`, resumes on `onResume`.
- `ModalRoute.secondaryAnimation` detects when another screen covers Now
  Playing; `_shouldRender` guards drop FFT frames entirely when obscured.

### 9.2 Rendering (two painter layers)

Layer 1 — `_CombinedBarPainter` (repaint: `Listenable.merge([fft, scrub])`):
- Path-batched: 4 `Path` objects (top/reflection × played/unplayed) drawn
  with 4 `drawPath` calls instead of ~128 individual `drawRRect` calls.
  Eliminates Skia pipeline thrashing from constant color switches.
- 64 solid rounded bars, bottom-anchored, growing upward (80% max of half-height)
- Reflection: 40% height, 35% opacity, grows downward
- Per-bar color: `playedColor` if bar center ≤ playhead, else `unplayedColor`

Layer 2 — `_ScrubOverlayPainter` (repaint: `_ScrubNotifier` only):
- 3dp rounded track (unplayed: textTertiary 20% opacity)
- Gradient tail: transparent → `playedColor` across the filled portion
- Playhead flare: ambient glow circle + horizontal "star" streak
- White-hot 4dp core during drag

### 9.3 Scrubber drag race fix

`_ReactiveProgressState` has an `_isDragging` flag that suppresses
`positionStreamProvider` rebuilds during the drag gesture. Without this,
the engine keeps emitting position ticks at 30-60 Hz while the user drags,
causing the playhead to stutter between the drag position and the engine's
real position. The lock holds until `seek()` resolves.

### 9.4 Key invariants

- The engine handles ALL smoothing/physics in C++. The client applies only
   a power-10 curve for visual compression — no lerp, no AGC, no treble boost.
- `bandCount: 64` in `SpectrumSettings` must match `_BlockNotifier.bins = 64`.
- `ingest()` never calls `notifyListeners()`. Only `flush()` does (on vsync).
- No shaders are allocated per bar. Path batching keeps GPU state changes to 4.
- Both `shouldRepaint` methods only check color props — the repaint flow is
  driven by the `Listenable` passed to `super(repaint:)`.

## 10. Artwork pulse architecture

The artwork bumps on kick drums via a transient detector on FFT bin 0.

```
_bassAverage += (rawBass - _bassAverage) × 0.05       ← running baseline
if (rawBass > _bassAverage × 1.5 && rawBass > 0.02 && _cooldown == 0):
  _scale.value = 1.06                                 ← +6% bump
  _cooldown    = 15                                   ← ~250ms lockout
  ticker.repeat()
    │
    ▼  spring decay each frame
_scale.value = 1.0 + (_scale.value - 1.0) × 0.85
ticker stops when scale < 1.001
    │
    ▼  ValueListenableBuilder → Transform.scale
```

Lives in `reactive_artwork.dart` (extracted from `now_playing_screen.dart`).
`ValueNotifier<double>` + `Transform.scale` — no `setState`, no parent rebuild.

## 11. Build, run, lint, test

```bash
flutter pub get
flutter run --debug
flutter analyze   # 0 errors, 0 warnings
flutter test
flutter build apk --release
flutter build apk --release --split-per-abi
adb logcat -c && adb logcat -s flutter
```

## 12. Debug trace conventions

Use `afLog('<category>', '<message>')` from `lib/utils/log.dart`.
PII (usernames, server URLs) must be redacted in release builds.

| Prefix | When |
|---|---|
| `aetherfin:boot` | Boot ordering, auth restoration |
| `aetherfin:http →/←/✕` | HTTP request / response / error |
| `aetherfin:error` | Caught exception + stacktrace |
| `aetherfin:data` | Provider data provenance (`source=live\|demo`) |
| `aetherfin:audio` | Player state transitions |

## 13. Data layer conventions

- Two HTTP clients, each the **only** file that speaks to its server:
  - `JellyfinClient` (`lib/core/jellyfin/client.dart`) — Jellyfin REST API.
    Composes `JellyfinResponseParser` for JSON→domain parsing and `JellyfinUrlBuilder`
    for auth headers and stream/image URL construction.
  - `SubsonicClient` (`lib/core/subsonic/client.dart`) — Subsonic/OpenSubsonic API (Navidrome).
- Both implement `MusicBackend` (`lib/core/backend/music_backend.dart`).
  All providers and UI code use `musicBackendProvider` which returns the
  correct client based on `auth.serverType`.
- `JellyfinClient` endpoints assert `userId` via `_assertUser()`.
  `SubsonicClient` endpoints embed auth via `_authParams()`.
- `LocalDb` composes three repositories at `lib/core/local/`: `TrackRepository`
  (`local_db_tracks.dart`, track CRUD), `AlbumRepository` (`local_db_albums.dart`,
  album aggregation), and `PlaylistRepository` (`local_db_playlists.dart`, playlist CRUD).
- No `json_serializable`. Models are hand-written in `lib/core/jellyfin/models/`.
  Both clients parse responses into the same `AfTrack`, `AfAlbum`, `AfArtist`,
  `AfPlaylist` types.
- Image URLs: Jellyfin embeds the `tag` query param for HTTP cacheability.
  Navidrome uses `/rest/getCoverArt.view?id=…` with auth params.
- Search queries are normalized (trim + lowercase) before hitting the provider. Minimum 2 characters.
- **Subsonic API gaps:** `resumeItems()` returns empty list (no Subsonic
  equivalent). `movePlaylistItem()` is a no-op (logs warning).

## 14. Workflow pipeline and conventions

The execution plan (design → plan → implement → verify → commit) follows a
strict pipeline with automated gates at the verify stage.

### 14.1 Verify gate

After all implementation batches complete and BEFORE committing, run:

```bash
# 1. Format check
dart format --output=none --set-exit-if-changed .
# If exitCode != 0, auto-fix with:
dart format .

# 2. Analyze
flutter analyze
# If issues found: REPORT the violations (file:line), STOP. Do NOT commit.
# Let the user decide whether to fix or override.

# 3. Test
flutter test
# If any failure: REPORT the failing test name and assertion. STOP. Do NOT commit.

# 4. Commit (only if all gates pass)
git add -A
git commit -m "type(scope): description"
git push

# 5. Post-commit housekeeping (see §14.6)
#   - Archive completed plan to thoughts/.legacy/
#   - Prune duplicate session ledgers from thoughts/ledgers/
#   - Update thoughts/workflow/BOOTSTRAP.md
```

Rules:
- **Format drift:** Auto-fix with `dart format .`, then re-run the check. Only fail if formatting can't be resolved.
- **Analyze fails:** Report violations with exact file:line. Do not commit broken code.
- **Test fails:** Report the failing test name and assertion line. Do not commit.
- **Ledger update:** After the final commit, append a dated entry to `thoughts/workflow/CONTINUITY.md` and prune to the 5 most recent entries (see §14.3).

### 14.2 Relative-position anchors in plans

Plan tasks describe insertion/reference points by **method or member adjacency**, not by line numbers. Line numbers become stale the moment any prior code moves.

**Bad (line numbers):**
```
Insert `stopAndClear()` after `stop()` at line 532.
```

**Good (relative anchors):**
```
Insert `stopAndClear()` immediately after the `stop()` method in `AfPlayerService`.
```

**Disambiguation rules:**
- **Method adjacency:** "Insert `stopAndClear()` after the `stop()` method"
- **Member adjacency:** "Add the `_buildProgressCard()` method after `_buildBody()` in `MusicFoldersCardState`"
- **Class context:** If two methods share a name, include the class: "In `MusicFoldersCardState`, add `_startScan()` before `_addFolder()`"
- **Getters/setters:** "Add the `replayGainMode` getter after the `audioEffects` getter in `PlayerSettingsStore`"

Plan documents MUST use relative-position anchors. The
plans folder (`thoughts/shared/plans/`) follows this convention.

### 14.2a Lean plans — no inline code

Plans **describe** what to build — they do **not** contain inline code. Full code blocks (complete test files, old/new diff blocks) bloat plans to 2,000+ lines and are redundant: the implementer reads actual source files to write code.

**Bad (inline code — bloats plan, redundant):**
```
**Test:**
```dart
test('parses simple #EXTM3U', () {
  const content = '#EXTM3U\n#EXTINF:123,Test - Song\n/path.mp3\n';
  final entries = M3uParser.parse(content);
  expect(entries.length, 2);
  ...
});
```
```

**Good (describe intent — implementer writes the code):**
```
**Test:** `test/m3u_parser_test.dart`
Cover: simple #EXTM3U, entries without #EXTINF, metadata parsing,
edge cases (empty file, malformed headers, unicode paths)
```

**Plan structure:**
- **Dependency graph** — batch/parallel structure (unchanged)
- **Per-task:** file path, test path, method/anchor, approach description, key edge cases — **no code**

Implementer agents write the actual code and tests. The plan gives them the shape, location, and edge cases to cover, not the byte-level implementation.

### 14.3 Rolling ledger consolidation

Session continuity is tracked in a single rolling ledger instead of scattered
files. This replaces the old per-session `thoughts/ledgers/CONTINUITY_ses_*.md`
pattern.

**Ledger location:** `thoughts/workflow/CONTINUITY.md`

**Format:**
```markdown
# Continuity Ledger

## 2026-05-25 — Workflow optimization + lint fixes
*Goal:* Add verify gate, consolidate ledgers, fix lucide_icons info-level lints
*Commits:* fb177c7
*Key decisions:* Use ast_grep_replace for pattern edits, relative anchors in plans
```

**Rules:**
- Append a new entry after every session that produces commits.
- Keep only the **5 most recent entries**. Prune older entries when adding a new one.
- Archived entries go to `thoughts/.legacy/`.
- If `thoughts/workflow/CONTINUITY.md` is missing (fresh clone), create it on first append.
- The `ledger-creator` agent may still create per-session files; the rolling ledger PRUNES on each append.

### 14.4 Format gate

The format check runs BEFORE analysis in the verify gate pipeline:

1. `dart format --output=none --set-exit-if-changed .` — dry-run check
2. If exit code != 0: `dart format .` — auto-fix formatting
3. Re-run `dart format --output=none --set-exit-if-changed .` — verify fix
4. Only then proceed to `flutter analyze`

This prevents formatting drift from accumulating across sessions.

### 14.5 Session bootstrap checkpoint

After every session that produces commits, update `thoughts/workflow/BOOTSTRAP.md` with a **concise status snapshot** so the next session can recover context in seconds.

**Format (max 30 lines, strictly summary):**
```markdown
# Workflow Bootstrap — 2026-05-29

## Last session
- **HEAD:** 84f3424 — fix: resolve 7 flutter analyze issues
- **Branch:** main
- **State:** All 383 tests pass, analyze: 0 errors

## In progress
- (nothing — all tasks committed)

## Pending plans
- `thoughts/shared/plans/2026-05-29-streaming-architecture-fixes.md`

## Known issues
- None
```

**Rules:**
- Always include HEAD hash + test/analyze state from the **last verify gate run**.
- List in-progress items or "(nothing)" if clean.
- List pending plans that haven't been fully committed yet.
- Keep it under 30 lines — no narrative, no rationale (that goes in CONTINUITY.md).
- If `BOOTSTRAP.md` is missing (fresh clone), the agent creates it by running `git log -1`, `flutter analyze`, and `flutter test`.

### 14.6 Archive and prune policy

Old artifacts accumulate fast. The active `thoughts/` directories should contain only **currently relevant** files.

**Archive rules:**
- **Plans:** Move from `thoughts/shared/plans/` to `thoughts/.legacy/` once all implementation batches for that plan are committed.
- **Session ledgers:** Prune per-session ledger files from `thoughts/ledgers/` after their entry is reflected in the rolling `CONTINUITY.md`. Keep them accessible in `.legacy/` for 30 days.
- **Bootstrap:** Keep `BOOTSTRAP.md` at `thoughts/workflow/` (not archived — it's the entry point for next session).

**The verify gate's final step** (after commit) includes:
```
1. If this session completed a plan: mv that plan → thoughts/.legacy/
2. Prune redundant session ledgers from thoughts/ledgers/
3. Update BOOTSTRAP.md with new HEAD and state
```

This keeps the active directory focused on current work. Historical artifacts remain one directory away for reference.

**Git tracking:**
- `thoughts/` is in `.gitignore` — designs, plans, ledgers, and `.legacy/` stay local by default.
- **Exception:** `thoughts/workflow/CONTINUITY.md` and `thoughts/workflow/BOOTSTRAP.md` are un-ignored (`!thoughts/workflow/CONTINUITY.md`) so session continuity survives across clones. Agents never force-add other `thoughts/` files.

## 15. Things AI agents have gotten wrong before

> **Prefix legend:** ✅ ENFORCED = covered by a CI-enforced test. 📝 GUIDANCE = architectural rule, human judgment required.

1. ✅ ENFORCED **"Just send Token="" — it's cleaner."** No. Omit the field entirely.
2. 📝 GUIDANCE **"Static DeviceId is fine."** No. Per-install UUID v4 in secure_storage.
3. 📝 GUIDANCE **"Use `/Search/Hints`."** No. Use `/Users/{id}/Items?searchTerm=…`.
4. ✅ ENFORCED **"Material animation defaults are fine."** No. Five durations, five curves, tests enforce it.
5. 📝 GUIDANCE **"Use `just_audio` for playback."** No. The audio engine is `mpv_audio_kit`. `AfPlayerService` wraps it.
6. 📝 GUIDANCE **"Loop modes are `LoopMode.off/all/one`."** No. mpv_audio_kit uses `Loop.off / Loop.playlist / Loop.file`. Aetherfin extends this in Dart with `AfLoopMode` (`off`, `playlist`, `file`, `forNtimes`), using an intercept in the completed handler to repeat N times.
7. 📝 GUIDANCE **"Build a parallel HTTP client."** Don't. Add a method to `JellyfinClient`.
8. 📝 GUIDANCE **"Hydrate `AuthNotifier` asynchronously."** No. Load auth in `main()` and inject via `initialAuthProvider`.
9. 📝 GUIDANCE **"go_router will figure out where to send a signed-in user."** No. Without `redirect:` + `refreshListenable`, you land on WelcomeScreen.
10. 📝 GUIDANCE **"`context.pop()` is safe on any screen."** No. Guard with `canPop()` on screens reached via `context.go()`.
11. 📝 GUIDANCE **"Use `context.go()` to navigate from lyrics to queue."** No. `go()` replaces the stack. Use `push()` for all detail/overlay screens.
12. 📝 GUIDANCE **"Add stop action in compact controls."** No. Compact actions are handled dynamically on the native side (Previous/Play-Pause/Next) based on queue bounds.
13. 📝 GUIDANCE **"Pass the artwork network URL directly to the native media session."** No. The native service cannot fetch network URLs with auth headers. Always resolve and download/save artwork to a local `file://` URI first, passing the local file path as `artPath` to the native service.
14. 📝 GUIDANCE **"Use `Timer.periodic` for progress reporting."** No. It doesn't await the callback — requests pile up. Use a serialized `while (_running)` loop.
15. 📝 GUIDANCE **"Use `Future.delayed` for auto-advance."** No. Doze throttles it when the screen is off. Use stream callbacks.
16. 📝 GUIDANCE **"Use `.then()` chaining for jump+play."** No. Doze can defer `.then()` callbacks. Use `async/await` in a named method (`_jumpAndPlay`).
17. 📝 GUIDANCE **"Forget to call `notify()` after `stopForeground(false)` on pause."** If you stop the foreground service on pause without calling `notify()` again, the notification might be dismissed or hidden on some devices (like Samsung One UI).
18. 📝 GUIDANCE **"Use `AudioMotionVisualizer` or `Waveform` widgets."** These were deleted. The combined widget is `AudioVisualScrubber`.
19. 📝 GUIDANCE **"The visualizer should apply its own client-side DSP (log, treble boost, AGC, lerp)."** No. The engine's native C++ EMA handles all bounce physics. The client applies only a power-10 curve for visual compression and renders via vsync-aligned ticker. Adding client-side smoothing fights the engine and causes lag.
20. 📝 GUIDANCE **"Create a shader per bar inside `paint()`."** No. That's 64 allocations/frame at 60fps — causes raster-thread GC lag. Pre-compute shaders once per `paint()` call.
21. 📝 GUIDANCE **"Subscribe to `spectrumStream` in `didChangeDependencies`."** No. It fires on every ancestor dependency change and causes stream churn. Subscribe once in `initState` via `addPostFrameCallback`.
22. 📝 GUIDANCE **"The battery channel is `dev.aetherfin.aetherfin/battery`."** No. It's `aetherfin.battery_opt` (matches `BatteryOptPlugin.CHANNEL_NAME`).
23. 📝 GUIDANCE **"Drive the artwork pulse by continuously scaling with bin 0 amplitude."** No. That flickers on every frame. Use a transient detector with running baseline + cooldown + spring decay.
24. ✅ ENFORCED **"Use mpv's native setShuffle(true/false) or native gapless preloading."** No. Aetherfin manages shuffle (via Fisher-Yates mapping in `AfQueueEngine` / `AfQueueManager`) and prefetching (via Dart-side `StreamPrefetcher`) entirely in Dart. This resolves metadata sync issues on the lock screen and in notification controls.
25. 📝 GUIDANCE **"The utility row has 6 icons."** No. It's 4: Lyrics, Save, Queue, More. Sleep timer, playback speed, audio output, and EQ are behind the More popup.
26. 📝 GUIDANCE **"Apply EQ/DSP via a separate audio pipeline."** No. Use `player.updateAudioEffects(AudioEffects(...))`. The engine handles DSP natively.
27. 📝 GUIDANCE **"Build a parallel HTTP client for Navidrome."** Don't build from scratch. Implement the `MusicBackend` interface in `SubsonicClient`. All providers already use `musicBackendProvider`.
28. 📝 GUIDANCE **"Use `jellyfinClientProvider` for backend operations."** No. Use `musicBackendProvider` — it returns the correct client (Jellyfin or Subsonic) based on `auth.serverType`. `jellyfinClientProvider` is only for Jellyfin-specific operations like `publicInfo()` and `authenticate()`.
29. 📝 GUIDANCE **"Store the Subsonic auth token."** No. Store the **password** in `accessToken` (encrypted in secure storage). The token is `md5(password + salt)` and must be recomputed per request with a fresh random salt.
30. 📝 GUIDANCE **"Reuse a Subsonic salt across requests."** No. Each request generates a fresh random salt to prevent replay attacks.
31. 📝 GUIDANCE **"Navidrome supports all Jellyfin endpoints."** No. Subsonic API has gaps: no `resumeItems` equivalent (returns empty), no `movePlaylistItem` (no-op), no API key auth (always username + password).
32. 📝 GUIDANCE **"Read position from `_player.state.position` or `stream.position`."** No. On some devices, mpv's `observe_property` for `time-pos` never fires. Use elapsed-time extrapolation: anchor position on play/seek, then `pos = anchor + (now - anchorTime) × speed`. Poll `getRawProperty('time-pos')` as primary source; fall back to extrapolation if it returns 0.
33. ✅ ENFORCED **"Open all queue tracks in mpv."** No. Aetherfin uses a single-track player model where only the currently playing track is loaded into mpv. The queue state is managed entirely in Dart. `openAll` is only called with a single `Media` object for the active track.
34. 📝 GUIDANCE **"Read A-B loop state from `svc.abLoopA`."** No. `_player.state.abLoopA` doesn't update on affected devices. Track loop state in Dart providers (`abLoopAProvider`/`abLoopBProvider`). Use `getRawPosition()` for the actual position when setting markers.
35. 📝 GUIDANCE **"Use `Timer.periodic` for the progress reporting loop."** No. `Timer.periodic` doesn't await the callback — requests pile up. Use a serialized `while (_running)` loop with `Future.delayed`.
36. 📝 GUIDANCE **"Keep a manual drag handle on bottom sheets."** Now handled per-sheet. The theme sets `showDragHandle: false` with `Colors.transparent` background. Each sheet (`album_more_sheet.dart`, `track_details_sheet.dart`, `save_to_playlist_sheet.dart`) adds its own manual drag handle inside the frosted-glass container. This avoids the floating transparent handle on dark backgrounds.
37. 📝 GUIDANCE **"Use `builder` for overlay routes like `/lyrics` and `/queue`."** No. Use `pageBuilder` with `NoTransitionPage` — the default `MaterialPage` slide transition renders content out of frame when pushed on `_rootKey`.
38. 📝 GUIDANCE **"Load all tracks to prune deleted files."** No. `allTracks()` has a 500 limit. Use a SQL prefix query (`trackIdsByPrefix`) to get only the tracks matching the folder, with no limit.
39. 📝 GUIDANCE **"Call `_nudgeAudioDevice()` without a generation counter."** No. Rapid seeks/play/pause stack multiple nudge chains (3 delayed `setAudioDevice` calls each). Use `_nudgeGen` to cancel stale chains.
40. 📝 GUIDANCE **"Call `setAudioDriver()`/`setAudioBuffer()` in the constructor without error handling."** No. Both return `Future<void>` from a sync constructor — if the native plugin throws, the error becomes an unhandled future rejection. Wrap each with `.catchError((Object e, StackTrace? stack) { ... })` and explicitly type the parameters to satisfy `argument_type_not_assignable`.
41. 📝 GUIDANCE **"Let `playQueue` fail without cleaning up mpv's playlist."** No. When `Future.wait(addFutures...)` throws, some tracks may have already been added to mpv's internal playlist via `_player.add()`. Clear Dart-side state AND call `await _player.stop()` to reset mpv's playlist.
42. 📝 GUIDANCE **"Leave `pause()`/`_jumpAndPlay()` unawaited in stream listeners."** No. `Stream.listen()` callbacks that touch `Future<void>` methods must be `async` with `await` on each call. Un-awaited futures in listeners are unhandled rejection sources.
43. 📝 GUIDANCE **"Parse tint hex strings without validation."** No. `_hex()` in `home_screen.dart` called `int.parse(hex.replaceFirst('#', ''), radix: 16)` with no try-catch or length check — a malformed string (DB corruption, future provider change) crashes the entire HomeScreen build. Match `search_screen.dart`'s `_parseTint` pattern: try-catch, validate length (6 or 8), fallback to `AfColors.indigo600`.
44. ✅ ENFORCED **"Avoid serializing queue operations."** No. Multiple sequential queue mutations (reorders, additions, removals) can interleave while awaiting mpv responses, corrupting state. Use `_queueLock` (`AfAsyncLock`) to serialize all mutating operations.
45. 📝 GUIDANCE **"Allow playback controls during queue loading."** No. Issuing seeks, skips, or jumps while a new queue is loading (`_isLoadingQueue` is true) leads to state corruption or out-of-bounds errors. Guard playback controls to return early when loading.
46. ✅ ENFORCED **"Manage mpv's playlist queue dynamically via add/remove."** No. Aetherfin manages the playlist queue entirely in Dart (via `AfQueueManager` / `AfQueueEngine`), loading only the currently active track into mpv. Native mpv playlist addition is no longer used.
47. 📝 GUIDANCE **"Let the `completed` handler run outside `_queueLock`."** No. The handler reads `currentTrack`, `currentIndex`, `currentQueue.length` while a concurrent `removeFromQueue`/`reorderQueue` could be mutating those fields. Wrap the critical section — reading queue state + acting on it — in `_queueLock.run()` so mpv's track-advance command fires against a consistent view.
48. 📝 GUIDANCE **"`setAfLoopMode` can call `_jumpAndPlay` directly."** No. `_jumpAndPlay(0)` sends a `playlist-play-index` command that triggers a playlist event. If a queue mutation holds `_queueLock`, the event fires against stale state. Wrap the jump in `_queueLock.run()`.
49. 📝 GUIDANCE **"`skipToNext`/`skipToPrevious`/`skipToQueueItem` are lightweight, no lock needed."** No. Rapid skips interleave with queue mutations — the playlist listener fires mid-`removeFromQueue`, reading an inconsistent index. Wrap each in `_queueLock.run()`.
50. 📝 GUIDANCE **"Call `_jumpAndPlay(currentIndex)` when `Loop.file` completes."** No. When `loop-file=inf` is set, mpv restarts the file internally and fires `completed` after restart. `_jumpAndPlay(currentIndex)` issues a redundant `playlist-play-index` that reloads the same file, causing the first ~1s of audio to play twice. Only call `_player.play()` if mpv stopped.
51. 📝 GUIDANCE **"Use hugeicons or cupertino_icons for UI icons."** No. All UI icons use **Lucide** (`lucide_icons_flutter`). Import from `package:lucide_icons_flutter/lucide_icons.dart`. The old hugeicons dependency was removed entirely.
52. ✅ ENFORCED **"Use bottom sheets for context menus and album actions."** No. Album 3-dot menus and track long-press menus are now **dialogs** (`af_dialog.dart`), not bottom sheets. Bottom sheets are reserved for save-to-playlist and track details only. This avoids the floating transparent drag handle issue on dark backgrounds and provides a more native feel.
53. 📝 GUIDANCE **"`shouldAdvancePosition` returns true at the end of queue."** No. `shouldAdvancePosition` returns `false` when `isAtQueueEnd && !playing`. This prevents the QS media session from getting stuck at `playing=true` after the last track finishes — without this guard, a transient `playing=true` event interacts with the extrapolated position at speed=1.0, making the QS progress bar run forever.
54. 📝 GUIDANCE **"`ScrollEndNotification` always fires when finger lifts."** No. On Android (especially with Android 16 slow animations), `ScrollEndNotification` is NOT always fired when finger lifts at a scroll boundary. The EQ screen uses a `_scrollSafetyTimer` (300ms fallback) + `UserScrollNotification idle` listener + `ScrollUpdateNotification` keepalive to detect scroll end reliably.
55. 📝 GUIDANCE **"Seek at end-of-queue doesn't need a play() call."** No. When the queue ends, `_userPaused=true` and the player stops. Seeking via the progress bar positions the tracker but doesn't resume playback. The `seek()` handler detects `wasCompletedAtEnd` and calls `play()` after a successful seek to restart playback.
56. 📝 GUIDANCE **"`openAll()` with the entire queue works fine."** No. Aetherfin manages the playlist queue state entirely in Dart (in `AfQueueManager` / `AfQueueEngine`), loading only the currently active track into mpv. Passing the entire queue of tracks to mpv is obsolete and causes loading delays.
57. 📝 GUIDANCE **"Skeleton screens need complex widget trees."** No. Each screen has a dedicated `*_skeleton.dart` widget in `lib/widgets/skeletons/`. They use the shared `ShimmerLayout` base widget from `skeleton.dart` with `LinearGradient` shimmer animation. Skeleton widgets sit in the `widgets/skeletons/` directory and are loaded during data fetch.
58. 📝 GUIDANCE **"Cover art caching needs no eviction policy."** No. `CoverCacheManager` (`lib/core/local/cover_cache_manager.dart`) manages an LRU-evicted disk cache for cover art. Temp files are cleaned up on startup. The eviction test must be robust against filesystem-dependent directory order.
59. 📝 GUIDANCE **"Hand-write save/load triples for each setting."** No. Use the `SettingsKey<T>` descriptor pattern (`player_settings_store.dart`). Each setting is a typed key with `keyName`, `defaultValue`, `encoder`, and `decoder`. This eliminates the error-prone hand-rolled save/load triples.
60. ✅ ENFORCED **"info-level lints can be ignored."** No. All 363 info-level lints were fixed in a single pass (`9621d50`). `flutter analyze` reports **0 issues** across the entire codebase. New code must maintain this.
61. 📝 GUIDANCE **"QS media session progress bar after queue end is correct."** No. After the queue ends, the QS media session can keep running because `playing=false` events are throttled (arriving <100ms apart) while a transient `playing=true` event at ~54ms pushes `playing=true` to native. Android QS then extrapolates position from the last known speed=1.0 forever. Fix: `trackEnded` fallback in `_updateMediaSession` overrides transient `playing=true` when position >= duration at queue end.
62. 📝 GUIDANCE **"Forgetting to pass `isFavorite` in MethodChannel `updateState` args."** This causes the home screen widget's favorite/heart star to fail to update when favorited inside the app's Flutter UI.
63. 📝 GUIDANCE **"Declaring LAUNCHER intent filter on MainActivity while aliases are active."** If you declare category LAUNCHER in both `MainActivity` and `<activity-alias>` elements, Android lists both icons in the app drawer. Remove the launcher filter from `MainActivity` and declare it only inside `<activity-alias>` configurations.
64. 📝 GUIDANCE **"Use hardcoded durations (200ms, 300ms, 500ms) for animations."** No. Use `AfDurations` tokens (80/160/240/400/600ms) and `AfCurves` tokens. All animation durations in widgets must reference the design tokens, not literal values.
65. 📝 GUIDANCE **"Use `ListView.separated` for staggered list animations."** No. Use `StaggerReveal` widget (`lib/widgets/stagger_reveal.dart`) which wraps children with staggered fade+slide-up reveal using `Interval` timing per `AfStagger` tokens. `ListView.separated` doesn't support staggered entrance animations.
66. 📝 GUIDANCE **"Use `NoTransitionPage` for all shell tab switches."** No. Shell tabs use `AnimatedSwitcher` cross-fade with `AfDurations.quick`. `NoTransitionPage` is only for overlay routes like `/lyrics` and `/queue` that sit above the now-playing overlay.

## 16. Glossary

- **`RunTimeTicks`**: Jellyfin duration unit. 1 tick = 100 ns. Divide by 10 for microseconds.
- **`PrimaryImageTag`**: Short hash for HTTP cache-busting on image URLs.
- **`Loop.off / Loop.file / Loop.playlist`**: mpv_audio_kit loop enum.
- **`FftFrame`**: mpv_audio_kit spectrum frame — `bands: Float32List` (64 values in [0,1], post-DSP).
- **`AfPlayerService`**: Bridges the app's player with the platform-native Android `MediaSession` service. Wraps `Player` (mpv_audio_kit) and communicates with `AetherfinMediaSessionService` over the `aetherfin.media_session` MethodChannel via `NativeMediaSessionBridge`.
- **`_pendingPlayNudgeIdx`**: State machine field in `AfPlayerService`. Set when playlist index changes; cleared when `playing=true` fires. Prevents `Future.delayed` for auto-advance.
- **`AudioVisualScrubber`**: Combined FFT visualizer + progress scrubber widget. Owns `_BlockNotifier` (signal DSP) and `_ScrubNotifier` (drag state). Two `RepaintBoundary` layers.
- **`_BlockNotifier`**: `ChangeNotifier` inside `AudioVisualScrubber`. Applies power-10 curve to engine bands via precomputed LUT (1024 entries). `ingest()` updates data only; `flush()` fires `notifyListeners()` on vsync via ticker. 300ms silence timer triggers fade-out (0.85× decay per frame).
- **`_ScrubNotifier`**: `ChangeNotifier` inside `AudioVisualScrubber`. Owns drag state and display progress.
- **`Spectral`**: Runtime color triple (`energy`, `shadow`, `glow`) extracted from current artwork. Lives in `currentSpectralProvider`. Never hardcode these values.
- **`BatteryOptPlugin`**: Kotlin `ActivityAware` plugin on channel `aetherfin.battery_opt`. Fires `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` on first HomeScreen visit.
- **Reactive islands**: Architecture pattern in `NowPlayingScreen` where high-frequency streams (position, FFT) are isolated to leaf `ConsumerWidget`s so the top-level scaffold doesn't rebuild on every tick.
- **`AudioEffects`**: mpv_audio_kit model for DSP state — bass shelf, treble shelf, loudness normalization, dynamic compressor. Streamed via `audioEffectsStream`, mutated via `updateAudioEffects`.
- **`ReplayGainMode`**: mpv_audio_kit enum for ReplayGain behavior (off, track, album). Set via `setReplayGain`, observed via `replayGainStream`.
- **`_originalQueue`**: Field in `AfPlayerService` storing the unshuffled track order. Restored when shuffle is toggled off via mpv's `playlist-unshuffle`.
- **`playNext()` / `addToQueue()`**: `AfPlayerService` methods for inserting tracks relative to the current position. Used by long-press context menus on track rows and album tiles.
- **`MusicBackend`**: Abstract interface (`lib/core/backend/music_backend.dart`) defining all server operations. `JellyfinClient` and `SubsonicClient` both implement it. Providers use `musicBackendProvider` to get the active backend.
- **`musicBackendProvider`**: Riverpod provider that creates the correct `MusicBackend` implementation based on `auth.serverType`. Replaced `jellyfinClientProvider` as the primary backend accessor.
- **`SubsonicClient`**: HTTP client for Navidrome/Subsonic servers (`lib/core/subsonic/client.dart`). Uses token auth (`md5(password + salt)`) with random salt per request. Implements `MusicBackend`.
- **`ServerType`**: Enum (`jellyfin` | `subsonic`) persisted in auth storage. Determines which client `musicBackendProvider` instantiates. Defined in `lib/core/jellyfin/models/server.dart`, re-exported from `music_backend.dart`.
- **`SubsonicApiError`**: Exception thrown by `SubsonicClient` when the Subsonic API returns a non-OK status in its response envelope.
- **Subsonic token auth**: Authentication scheme used by Navidrome. Token = `md5(password + salt)`. Sent as query params `u`, `t`, `s` on every request. Password stored in `JellyfinAuth.accessToken`.
- **`SmartPlaylist`**: Rule-based playlist that resolves dynamically. Stored in SQLite via `SmartPlaylistDb`. Rules define field/operator/value conditions. Resolved via SQL (local mode) or client-side filter (server mode). UI at `/smart-playlists`.
- **`_PositionAnchor`**: Mutable state holder for elapsed-time extrapolation. Tracks `lastKnownPos`, `lastUpdateTime`, and `wasPlaying`. Used when mpv's property observation doesn't fire.
- **`getRawPosition()` / `getRawDuration()`**: Direct mpv property queries via `getRawProperty('time-pos')`/`getRawProperty('duration')`. Bypasses the broken `observe_property` reactive system. Returns `Duration.zero` on failure.
- **`abLoopAProvider` / `abLoopBProvider`**: Dart-side StateProviders tracking A-B loop markers. Necessary because `_player.state.abLoopA` doesn't update on devices with broken property observation.
- **`LocalBackend`**: Implements `MusicBackend` over `LocalLibrary` + `LocalDb`. Enables favorites, playlists, and smart playlists in local mode — same provider interface as server backends.
- **`_nudgeGen`**: Generation counter in `AfPlayerService` that cancels stale nudge chains. Each call to `_nudgeAudioDevice()` increments it; delayed retries bail out if the generation changed.
- **`_HeroAlbumCarousel`**: Swipeable PageView on the home screen showing up to 5 recent albums with `viewportFraction: 0.92` and a dot indicator.
- **`AfPositionTracker`**: Manager class in `AfPlayerService` (`lib/core/audio/af_position_tracker.dart`). Handles elapsed-time position extrapolation with `_PositionAnchor`, `getRawPosition()` fallback.
- **`AfArtworkManager`**: Manager class in `AfPlayerService` (`lib/core/audio/af_artwork_manager.dart`). Downloads cover art bytes and provides file:// URIs for notification artwork.
- **`AfAudioDeviceManager`**: Manager class in `AfPlayerService` (`lib/core/audio/af_audio_device_manager.dart`). Manages audio device routing and nudge chains with `_nudgeGen`.
- **`AfQueueManager`**: Manager class in `AfPlayerService` (`lib/core/audio/af_queue_manager.dart`). Manages playlist queue, shuffle state, and `_originalQueue` order tracking. Sync lock (`_activePlaylistSyncs`) blocks the playlist listener during batch operations.
- **`NativeMediaSessionBridge`**: Dart bridge (`lib/core/audio/media_session_bridge.dart`) wrapping the `aetherfin.media_session` MethodChannel. Provides 100ms throttle, `MediaSessionState` snapshots, and callback-based dispatch (`onPlay`, `onPause`, `onSeek`, etc.). Replaces raw `_channel.invokeMethod` calls in `AfPlayerService`.
- **`_queueLock`**: `AfAsyncLock` instance in `AfPlayerService` that serializes all queue-mutating operations (`playQueue`, `setAfShuffleMode`, `setAfLoopMode` jump, `skipToNext/Previous/QueueItem`, `reorderQueue`, `removeFromQueue`, `insertIntoQueue`, `playNext`, `addToQueue`, and the `completed` handler's critical section). Prevents interleaved state reads/writes across async boundaries.
- **`_isLoadingQueue`**: Guard flag in `AfPlayerService` that prevents playback controls (`play`, `pause`, `seek`, skip, queue mutations) and the `completed` handler from running while `playQueue` is actively loading tracks into mpv.
- **`JellyfinResponseParser`**: Extracted from `JellyfinClient` (`lib/core/jellyfin/response_parser.dart`). All JSON→domain parsing logic + field string constants.
- **`JellyfinUrlBuilder`**: Extracted from `JellyfinClient` (`lib/core/jellyfin/url_builder.dart`). Auth header construction, stream URL building, and image URL generation.
- **`TrackRepository`**: CRUD for tracks at `lib/core/local/local_db_tracks.dart`. Row-to-track mapping (`rowToTrack` for Drift entities, `rawRowToTrack` for raw SQL column projection), query helpers, 500-row limit on `allTracks()`.
- **`AlbumRepository`**: Aggregation queries for albums at `lib/core/local/local_db_albums.dart`. Album artist, year, track-count queries.
- **`PlaylistRepository`**: CRUD for playlists at `lib/core/local/local_db_playlists.dart`. Transaction-based insert/delete/reorder.
- **`AfAsyncLock`**: Utility class in `player_service.dart` used to serialize asynchronous queue mutations and loads sequentially using a single future chain.
- **`_queueLoadGen`**: Generation counter in `AfPlayerService` used to abort obsolete queue load operations. Incremented synchronously at the start of `playQueue`.
- **`_queueLoadLimit`**: Max tracks loaded into mpv on initial `playQueue` call (30 forward tracks). Remaining tracks are stored in `_cachedOverflow` and used by the shuffle engine for pool selection.
- **`_playbackEnded`**: Flag in `AfQueueManager` set on `endPlayback()`. Guards the playlist listener (`processPlaylistEvent`) to prevent reinstating tracks after a completed queue ends.
- **`CoverCacheManager`**: LRU-evicted disk cache for cover art (`lib/core/local/cover_cache_manager.dart`). Cleans up orphan temp files on startup. Eviction test must handle filesystem-dependent directory order.
- **`SettingsKey<T>`**: Typed descriptor pattern in `player_settings_store.dart` for persisted settings. Each setting has `keyName`, `defaultValue`, `encoder`, `decoder`. Eliminates hand-rolled save/load triples.
- **`ShimmerLayout`**: Base skeleton widget in `lib/widgets/skeleton.dart`. Applies `LinearGradient` shimmer animation over a gray placeholder. Each screen has a dedicated `*_skeleton.dart` in `widgets/skeletons/`.
- **`_scrollSafetyTimer`**: Fallback timer in `eq_dsp_screen.dart` that resets `_isScrollActive` after 300ms of no scroll activity. Compensates for `ScrollEndNotification` not always firing on Android at scroll boundaries.
- **`StaggerReveal`**: Reusable widget (`lib/widgets/stagger_reveal.dart`) that wraps children in a staggered fade+slide-up reveal animation. Uses `Interval` timing per `AfStagger` tokens. Items beyond `AfStagger.maxStaggered` (8) share the last stagger slot. Used on Home, Album, and Artist screens for entrance animations.
- **`AfLoopMode`**: Custom loop mode enum (`off`, `playlist`, `file`, `forNtimes`) extending beyond mpv's native Loop modes.
- **`ShuffleMode`**: Custom shuffle mode enum (`off`, `all`, `tail`) supporting Shuffle Next.
- **`PlaylistUndoBuffer`**: Ephemeral playlist operation undo buffer class that tracks the last add/remove action per playlist for 8 seconds.
- **`QueueHistory`**: SQLite database table and repository for saving lightweight played queue snapshots.
- **`LastFmClient`**: Service class (`lib/core/lastfm/lastfm_client.dart`) that connects to Last.fm API. Uses signed MD5 parameters for love/unlove and scrobble endpoints.
- **`RadioGenerator`**: Utility class (`lib/state/radio_providers.dart`) that generates continuous recommended queues (similar artist/track queues) concurrently.
- **`smartQueueProvider`**: Smart Queue Autoplay provider that tracks play history metrics (skips, plays, completion rates) and computes recommendation lists using Drift SQLite.
- **`lastFmSyncProvider`**: Reconciliation service provider (`lib/state/lastfm_sync_provider.dart`) that performs two-way loved track synchronization between local/server libraries and Last.fm.

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
