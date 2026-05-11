# CLAUDE.md — Aetherfin Project Guide

This document is the **single source of truth** for AI coding agents working
on Aetherfin (Claude, Devin, Cursor, GPT, etc.). Read this end to end before
making changes. It captures the constraints, conventions, and gotchas
discovered while building the v1 client and is updated as we learn more.

## 1. What Aetherfin is

A native-feeling Android music player backed by a self-hosted **Jellyfin**
server. The only first-class platform is Android. iOS may follow but is not
considered when making trade-offs. The app is a single Flutter binary that
talks to Jellyfin over HTTP.

> **North star:** Spotify's polish, Apple Music's typography, Soulseek's
> respect for the listener. Aetherfin must read as a *premium music* app,
> not "a Jellyfin client."

### 1.1 Mental model — what runs where

The architectural split between server and app is non-negotiable. Treat
Jellyfin as a **file source + library state store**, nothing else.
**Aetherfin is the player.**

**Jellyfin (server) is responsible for:**
- Storing the audio files (mp3 / flac / m4a / opus / wav / ogg) and
  serving the original bytes byte-for-byte.
- Catalog metadata: titles, artists, albums, genres, durations, year,
  artwork.
- Search (`/Users/{id}/Items?searchTerm=…` — never `/Search/Hints`).
- Auth (user accounts + access tokens).
- Per-user state that must follow the user across devices: favorites,
  play counts, last-played-at, playlists.
- LRC lyric files. The server only *stores* them; the app parses them.
- "Now Playing" telemetry display — `POST /Sessions/Playing*` exists
  purely so the Jellyfin Dashboard widget shows who's listening to
  what. It does NOT drive playback.

**Aetherfin (app) is responsible for everything else, on-device:**
- All audio **decoding** (ExoPlayer via just_audio).
- Buffering, gapless transitions, output routing, position tracking.
- Queue management (order, shuffle, repeat, reorder).
- UI rendering for every screen.
- LRC parsing + synced line highlighting.
- Spectral color extraction from artwork (`palette_generator`).
- Lock-screen / notification media-session integration.
- Cover-art file cache (`cached_network_image`).
- Local settings: audio-quality preference, crossfade, sleep timer.

**Strict consequence:** stream URLs MUST use
`/Audio/{id}/stream?Static=true` — the direct-stream endpoint. The
universal endpoint (`/Audio/{id}/universal`) triggers server-side
transcoding to HLS, which (1) wastes the server's CPU, (2) gives a
codec ExoPlayer can't always decode, and (3) was the cause of the
"track plays but position never advances" bug fixed in PR #4. If you
ever feel the need to re-introduce transcoding, do it as a
*fallback only* and bring back the full Finamp param set
(`Container=…&TranscodingProtocol=hls&AudioCodec=aac&PlaySessionId=…`)
— never partial.

**Strict consequence #2:** favorites, play counts, and playlist contents
are server-owned even though the heart icon flips locally first. The
client does optimistic UI then `POST/DELETE /Users/{id}/FavoriteItems/
{itemId}` (see `JellyfinClient.setFavorite()`). On HTTP error, revert
the local state. Never store favorite state only on-device — a second
device must see the same state on next sign-in.

## 2. Tech stack (exact versions)

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter **3.41.9 stable**, Dart **3.11.5** | `flutter --version` must match. The CI workflow pins this. |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier`. |
| Routing | `go_router` ^14.7 | See `lib/app/router.dart` — shell route with bottom nav. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per `JellyfinClient`. Auth header is baked into `BaseOptions.headers`. |
| Audio | `just_audio` ^0.10 + `audio_service` ^0.18 | Lock-screen controls; deferred init after first frame. |
| Storage | `flutter_secure_storage` ^9.2 (creds + deviceId), `shared_preferences` ^2.3 (settings) | Never store creds in shared_preferences. |
| Discovery | `multicast_dns` ^0.3.2 | mDNS scan for `_jellyfin._tcp` on the local network. |
| Imagery | `cached_network_image` ^3.4, `flutter_svg` ^2.0, `palette_generator` ^0.3 | All cover art renders through `cached_network_image`. |
| Fonts | `google_fonts` ^6.2 | Inter Variable + JetBrains Mono. Fetched at runtime, cached on disk. |

The min Android SDK is **21** (Android 5.0). Built with **Java 17** + Gradle
in CI. Local Java 17 is required.

## 3. Source-tree map

```
lib/
├─ main.dart                ← `runApp` + first-frame boot trace + AudioService kick
├─ app/
│  ├─ app.dart              ← Root MaterialApp.router
│  ├─ router.dart           ← go_router config (shell + nested routes)
│  └─ theme.dart            ← ThemeData built from design tokens
├─ design_tokens/           ← The single source of truth for §4 visual spec
│  ├─ colors.dart           ← OKLCH-derived sRGB hexes — DO NOT modify without spec change
│  ├─ motion.dart           ← Five duration tiers, five easing curves (§4.2)
│  ├─ spacing.dart          ← 4-pt grid, mini-player insets
│  ├─ radii.dart            ← Pill / md / lg corner rules
│  ├─ typography.dart       ← Inter Variable scale
│  └─ tokens.dart           ← Re-exports for `import '../../design_tokens/tokens.dart';`
├─ core/
│  ├─ audio/                ← PlayerService (just_audio + audio_service) + play actions
│  ├─ demo/                 ← `DemoLibrary` — bundled albums/artists for the onboarding preview
│  ├─ jellyfin/
│  │  ├─ client.dart        ← The only file that speaks HTTP to Jellyfin
│  │  ├─ auth_storage.dart  ← secure_storage wrappers (token, userId, deviceId)
│  │  ├─ discovery.dart     ← mDNS scan + public-info probe
│  │  └─ models/            ← Plain Dart classes — NO json_serializable codegen
│  └─ lyrics/               ← LRC parser (sync + unsynced)
├─ features/                ← One folder per top-level screen
│  ├─ home/        library/  album/      artist/
│  ├─ search/      queue/    now_playing/ lyrics/
│  ├─ onboarding/  profile/  settings/    cast_picker/  sleep_timer/
├─ state/
│  └─ providers.dart        ← All Riverpod providers in one file (intentional)
├─ widgets/                 ← Shared visual atoms (Tile, TrackRow, SectionHeader, GenreTile, MiniPlayer…)
└─ utils/                   ← oklch.dart, etc.
```

The deliberate "everything in `providers.dart`" decision: providers are
small, depend on each other heavily, and there are <30 of them. Splitting
across files made cross-references painful. Don't split it without a real
reason.

## 4. Design spec — non-negotiables

The design spec is a separate document (`docs/SPEC.md` in any future PR;
currently lives in the user's notes). What MUST hold true in code at all
times:

### 4.1 Colour
- Indigo scale (`AfColors.indigo50…900`) is derived from **OKLCH** with
  fixed lightness/chroma steps. Do not eyeball-adjust hexes. To add a new
  color, derive it in `lib/utils/oklch.dart` first.
- `AfColors.surfaceBase = #0B0B14`. `textPrimary` is white with 92% alpha.
- Quality-chip "lossless" = `AfColors.tealAccent`, "lossy" = `slate500`,
  "transcoded" adds 1dp `AfColors.warningAmber` border.

### 4.2 Motion (`lib/design_tokens/motion.dart`)
- **Exactly five** duration tiers: `instant 80ms`, `quick 160ms`,
  `standard 240ms`, `expressive 400ms`, `long 600ms`. The 200/300/500ms
  Material defaults are forbidden — `test/design_tokens_test.dart` enforces
  this.
- Exactly five easing curves: `easeStandard`, `easeEmphasized`, `easeOut`,
  `easeIn`, `linear`. Audio-coupled animations (waveform, progress ring,
  lyric scroll) MUST use `linear` — easing audio time lies about playback
  position. Any new animation must pick from these.

### 4.3 Mini-player rules
- **56 dp tall, 12 dp horizontal margin, 16 dp gap to bottom nav** —
  `AfSpacing.bottomInsetWithMiniAndNav` is the canonical bottom-inset for
  every scrollable so content never hides under it.
- Visible only when the queue is non-empty. Tapping it opens Now Playing
  with a shared-element hero on the artwork.
- Slides up with `AfCurves.easeOut` over `AfDurations.standard`.

### 4.4 Profile rules (Settings → Profile)
Phases 1–8 of the spec require:
1. Avatar = first letter of Jellyfin display name, indigo-tinted.
2. Server name + Jellyfin version chip under the display name.
3. "Listening on" device row.
4. Quality preference selector (Auto / Lossless / Lossy / Data-saver).
5. Crossfade slider (0–12 s).
6. Lock-screen art selector (Album / Artist / Off).
7. "Sign out" — destructive red, double-confirm.
8. App version + git short SHA at the bottom.

If you're changing the profile screen, walk through this list before
shipping.

## 5. Jellyfin auth — battle-tested format

Every Jellyfin request carries:

```
Authorization: MediaBrowser UserId="…", Token="…", Client="Aetherfin", Device="Android", DeviceId="…", Version="0.1.0"
Content-Type: application/json
User-Agent: Aetherfin/0.1.0 (Android)
Accept: application/json
```

Rules learned the hard way:
- **`UserId` and `Token` are OMITTED entirely before login.** Sending
  `Token=""` triggers HTTP 500 in some plugin-heavy installs.
- **Send only `Authorization`** — not `X-Emby-Authorization`. Sending both
  confuses certain plugins' middleware.
- **Field order matches Finamp**: `UserId, Token, Client, Device, DeviceId,
  Version`.
- **`DeviceId` is a per-install random 16-byte value** persisted in
  `flutter_secure_storage`. Never reuse `"aetherfin-android"` or any other
  static value — Jellyfin keys session/device records on this, and a stale
  record from a previous install will crash session creation.
- Non-ASCII bytes in the header are replaced with `_` (defensive).

The canonical implementation lives in `_buildAuthHeader()` at
`lib/core/jellyfin/client.dart:120`. **Do not duplicate this logic.** Build
a fresh `JellyfinClient` instead if you need to override headers.

### 5.1 If `AuthenticateByName` returns 500
Almost always a server-side issue — confirmed by reproducing with `curl`:
```bash
curl -i -X POST 'http://SERVER/Users/AuthenticateByName' \
  -H 'Authorization: MediaBrowser Client="curl", Device="curl", DeviceId="curl-001", Version="1.0.0"' \
  -H 'Content-Type: application/json' \
  -d '{"Username":"u","Pw":"p"}'
```
If `curl` also returns 500, the server has stale `UserManager`/
`SessionManager` state. **Restart the Jellyfin Docker container.** This is
the known fix and it has solved every instance we've seen.

**Do not** disable plugins, downgrade Jellyfin, or modify our header to
work around it — those are all dead-ends.

### 5.2 Race-free auth hydration (post-mortem from PR #2)

**Symptom we burned a day on:** sign-in returned `200 OK` with a valid
`AccessToken`, but the very next request — `GET /Users/{id}/Views` —
returned `401`. Every subsequent library / home / artist / genre request
also 401’d. The token *was* being persisted to secure storage; the user
was just being kicked back to onboarding on every app launch.

**Root cause:** `AuthNotifier` was hydrated lazily with the cascade
`AuthNotifier(...)..hydrate()`. `hydrate()` is an async call into
`flutter_secure_storage`. On Android, **flutter_secure_storage serializes
all calls on a single MethodChannel** — reads and writes interleave on
one queue. At sign-in time the queue looked like:

```
load()    ← hydrate, started when authProvider was first read
write()   ← save, called by sign-in screen with the new auth
```

`load()` returned `null` (storage was empty pre-sign-in) and set
`state = null` — **after** the sign-in screen had synchronously set
`state = auth` but **before** the write finished. The token landed in
secure storage; the in-memory state did not. `jellyfinClientProvider`
rebuilt with `auth == null`, so every follow-up request flew without a
`Token=` in the header.

**The pattern we use now (`lib/state/providers.dart`, `lib/main.dart`):**

1. `main()` reads `AuthStorage().load()` **synchronously** (in parallel
   with `loadOrCreateDeviceId()`) before `runApp`.
2. The result is injected into the provider tree via an override:
   ```dart
   ProviderScope(overrides: [
     deviceIdProvider.overrideWithValue(deviceId),
     initialAuthProvider.overrideWithValue(initialAuth),
     …
   ])
   ```
3. `AuthNotifier` takes the initial value through its constructor:
   ```dart
   AuthNotifier(this._storage, {JellyfinAuth? initial}) : super(initial);
   ```
   No async hydrate. No race window.
4. `save(auth)` does `state = auth; await _storage.save(auth);` — nothing
   is competing to overwrite `state` because the load already happened
   before the widget tree was even built.

**Rules to keep this race dead:**
- **Never** add a second async hydrator that runs after construction.
- **Never** read `authProvider` lazily for the first time *during*
  sign-in. If you need a new provider that depends on auth, watch
  `authProvider` from the start — don't `ref.read(authProvider.notifier)`
  for the side-effect of building it.
- The boot trace logs `aetherfin:boot device id loaded (len=22); auth
  restored for <userName>` (or `auth absent`). If you don't see this line
  before `runApp returned`, the override is missing.

### 5.3 Router-level auth redirects

`go_router` has no built-in awareness of Riverpod state, so we wire it up
explicitly in `lib/app/router.dart`:

```dart
final refresh = _AuthRefreshListenable();
ref.listen<JellyfinAuth?>(authProvider, (_, __) => refresh._notify());

return GoRouter(
  refreshListenable: refresh,
  redirect: (context, state) {
    final auth = ref.read(authProvider);
    final inOnboarding =
        state.matchedLocation == '/' ||
        state.matchedLocation.startsWith('/onboarding');
    if (auth != null && inOnboarding) return '/home';   // signed in → skip onboarding
    if (auth == null && !inOnboarding) return '/';      // anonymous → back to welcome
    return null;
  },
  …
);
```

Rules:
- **Every new onboarding route must start with `/onboarding/`** so the
  redirect's prefix check catches it. The bare `/` is also treated as
  onboarding.
- **Every post-auth route must NOT start with `/onboarding/`**. Putting a
  signed-in screen under `/onboarding/*` would make the redirect bounce
  the user to `/home` forever.
- After `await authProvider.notifier.save(auth)` you can still call
  `context.go('/home')` manually. The refreshListenable will also fire,
  but the explicit `go()` covers the rare frame where the listener
  hasn't propagated yet.
- Don't call `context.pop()` on a screen that was reached via
  `context.go()` — the stack is empty and you'll hit
  `GoError("There is nothing to pop")`. Guard with `context.canPop()`
  or fall back to an explicit `context.go('/')`.

## 6. Build, run, lint, test

```bash
# One-time
flutter pub get
flutter pub run flutter_launcher_icons     # regenerates Android adaptive icon

# Dev loop
flutter run --debug                        # connects to running emulator/device
flutter analyze --no-fatal-infos           # lint — must report 0 errors, 0 warnings
flutter test                               # all 6 tests must pass
flutter build apk --release                # produces build/app/outputs/flutter-apk/app-release.apk

# Connected device
adb logcat -c && adb logcat -s flutter     # boot + HTTP trace (see §7)
```

CI is `.github/workflows/build-apk.yml`. It runs on every PR + on `main`,
produces a debug APK, and uploads it as a workflow artifact. To download an
APK from a PR: open the PR's "Checks" → "build" → "Artifacts" →
`app-debug-apk.zip`.

## 7. Debug trace conventions

The app emits structured log lines so that an `adb logcat -s flutter`
output is enough to diagnose most issues without attaching a debugger.

| Prefix | When | Example |
|---|---|---|
| `aetherfin:boot` | Boot ordering, persisted auth restoration, AudioService init | `aetherfin:boot device id loaded (len=22); auth restored for azrim` |
| `aetherfin:http →` | Outgoing request (method, URL, headers redacted, body redacted if auth-sensitive) | `aetherfin:http → POST http://srv/Users/AuthenticateByName` |
| `aetherfin:http ←` | Successful response (status, method, URL) | `aetherfin:http ← 200 GET http://srv/System/Info/Public` |
| `aetherfin:http ✕` | Failed response (status, method, URL) | `aetherfin:http ✕ 500 POST http://srv/Users/AuthenticateByName` |
| `aetherfin:error` | Caught exception with full Dio error + stacktrace | (multi-line block) |
| `aetherfin:data` | Data-source provenance — fires every time a Riverpod provider serves data, marking whether the bytes came from live Jellyfin (`source=live`), the bundled signed-out preview (`source=demo`), or a still-mocked code path (`source=mock`). Also covers player-state changes (`shuffleMode`, `loopMode`, `playbackSpeed`, `currentTrack`, `playbackProgress`, `favoriteToggle`). | `aetherfin:data recentlyAddedAlbums source=live count=20` / `aetherfin:data shuffleMode source=live enabled=true` |
| `aetherfin:audio` | Audio decoder / ExoPlayer state — every `processingState` transition (idle / loading / buffering / ready / completed), setAudioSource and play() exceptions, and `playbackEventStream` errors. The only place that exposes the actual reason a track silently failed to start. | `aetherfin:audio processingState=ready position=00:00 duration=03:42` |

`aetherfin:data` lines are emitted by `_logData()` in `lib/state/providers.dart`
and by `AfPlayerService` / `JellyfinPlaybackReporter` for queue + playback
events. Use `adb logcat -s flutter | grep aetherfin:data` to spot any screen
that has regressed onto `DemoLibrary` after sign-in — every signed-in
session should show `source=live` exclusively (with `source=demo` only on
the signed-out onboarding preview).

When adding new diagnostics:
- Always go through `print('aetherfin:<category> …')`. No `debugPrint`,
  no `log()`, no `developer.log`.
- Redact tokens and any header containing `auth`.
- Redact bodies for endpoints whose path contains `authenticate`.

## 8. Data layer conventions

- `JellyfinClient` is the **only** file that speaks HTTP. Anything that
  needs Jellyfin data goes through a method here.
- All endpoints assert `userId` is set via `_assertUser()`. They throw
  `StateError` if called pre-auth. Providers always check
  `jellyfinClientProvider != null` before calling.
- Pagination is not implemented yet. Lists default to `limit: 20` (home /
  recent rails) or `limit: 200` (library tabs). Add pagination only when
  a user-visible "load more" is added to the UI.
- Image URLs are built via `_buildImageUrl()` which embeds the `tag` query
  param. This makes URLs cacheable and lets `cached_network_image` reuse
  decoded images across screens.
- **No `json_serializable`**. Models are hand-written. The surface is small
  and codegen makes the build slower without meaningful benefit.

When the user is signed out (no `JellyfinClient`), providers fall back to
`DemoLibrary` so the onboarding preview screens have something to render.
Live screens should never hit `DemoLibrary` — they should be empty/loading
states until auth lands.

## 9. PR & CI rules

- Branch name: `devin/<timestamp>-<short-slug>` (see Devin git guidelines).
  Other agents may use their own prefix; just keep timestamps for sort
  order.
- Always run `flutter analyze --no-fatal-infos` and `flutter test` before
  pushing. CI runs the same.
- The PR body must follow `.github/PULL_REQUEST_TEMPLATE.md` if present.
- Do **not** force-push to `main`. `--force-with-lease` is okay on your
  own feature branches.
- Do **not** disable plugins, downgrade Jellyfin, or change the auth header
  shape to "fix" a 500. Reproduce with `curl` first — see §5.1.

## 10. Things AI agents have gotten wrong before

A non-exhaustive list of footguns. Read this before you do something that
seems obvious.

1. **"Just send Token="" — it's cleaner."** No. Omit the field entirely.
   (§5.)
2. **"Static DeviceId is fine for an Android app."** No. Per-install
   random value, persisted in secure_storage. (§5.)
3. **"`/Users/{id}/Items?searchTerm=…` doesn't work, use `/Search/Hints`."**
   No. `/Search/Hints` returns half-typed BaseItemDto shapes and is harder
   to parse. Stick with the standard items endpoint.
4. **"Material defaults are fine for animation curves."** No. There are
   exactly five durations and five curves and `test/design_tokens_test.dart`
   asserts it. (§4.2.)
5. **"The launcher icon doesn't matter."** It does — `pubspec.yaml`
   contains a `flutter_launcher_icons` config and the brand assets live in
   `assets/brand/`. Run `flutter pub run flutter_launcher_icons` after any
   icon change.
6. **"Use `Provider` for genres; they're static."** They're not — once
   signed in we hit `/MusicGenres`. Use `FutureProvider.autoDispose`.
7. **"Build a parallel HTTP client for endpoint X."** Don't. Add a method
   to `JellyfinClient`.
8. **"Just hydrate `AuthNotifier` asynchronously — it’s a tiny read."**
   No. flutter_secure_storage serializes on a single MethodChannel; an
   async hydrate races sign-in `save()` and clobbers the token in memory.
   Load auth in `main()` and inject via `initialAuthProvider`. (§5.2.)
9. **"go_router will figure out where to send a signed-in user on cold
   start."** No. Without `redirect:` + `refreshListenable`, you land on
   WelcomeScreen even with valid persisted auth. (§5.3.)
10. **"`context.pop()` is safe on any screen with a back button."** No.
    Screens reached via `context.go()` have an empty navigator stack and
    `pop()` raises `GoError("There is nothing to pop")`. Guard with
    `canPop()` or fall back to `context.go('/')`.

## 11. Glossary

- **Jellyfin item type**: `Audio`, `MusicAlbum`, `MusicArtist`, `Playlist`,
  `MusicGenre`. These are the only types Aetherfin renders.
- **`RunTimeTicks`**: Jellyfin's duration unit. 1 tick = 100 ns. Divide
  by 10 to get microseconds and then build a `Duration`.
- **`PrimaryImageTag`**: A short hash Jellyfin returns alongside an item.
  Including it in the image URL makes the URL change when the image
  changes — perfect for HTTP caching.
- **`Latest` endpoint** (`/Users/{id}/Items/Latest`): paged-list of items
  recently added to a user's library. Different from a normal item query
  with `SortBy=DateCreated` — `Latest` already returns deduped, grouped
  results that match what the Jellyfin web "Latest Music" row shows.

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
