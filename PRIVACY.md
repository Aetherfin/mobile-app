# Privacy Policy

**Effective date:** May 11, 2026
**Author / maintainer:** Azrim &lt;mirzaspc@gmail.com&gt;
**Software:** Aetherfin — an open-source Android music player
**Repository:** <https://github.com/Aetherfin/mobile-app>

Short version: **Aetherfin does not collect, transmit, or sell any
personal data.** It is a client that talks only to the Jellyfin server
you configure. Everything else stays on your phone.

The rest of this document explains what data the App handles, where it
lives, and what we (the maintainer) do and do not see.

---

## 1. Who runs Aetherfin

Aetherfin is open-source software maintained by Azrim
(&lt;mirzaspc@gmail.com&gt;). **There is no Aetherfin-operated server, no
account system, and no telemetry pipeline.** The maintainer does not
host, receive, store, or analyze any of your activity.

If you obtain a build of Aetherfin from a source other than the
[official repository](https://github.com/Aetherfin/mobile-app), this
policy describes only the behavior of unmodified upstream builds. Forks
or third-party redistributions may add their own data collection and
are out of scope of this policy.

## 2. What data the App handles

| Data | Where it lives | Who sees it |
|---|---|---|
| Jellyfin **server URL** (e.g. `http://omahsangar.local:8097`) | `flutter_secure_storage` on your device | You + your Jellyfin server |
| Jellyfin **username** | `flutter_secure_storage` on your device | You + your Jellyfin server |
| Jellyfin **access token** (issued by your server on sign-in) | `flutter_secure_storage` on your device | You + your Jellyfin server |
| Jellyfin **user ID** | `flutter_secure_storage` on your device | You + your Jellyfin server |
| **Device ID** — random 16-byte value generated on first launch and used as Jellyfin's `DeviceId` for session bookkeeping | `flutter_secure_storage` on your device | Your Jellyfin server |
| **Settings** (audio-quality preference, crossfade, sleep-timer state, sort order, theme overrides) | `shared_preferences` on your device | Only you |
| **Cover-art image cache** | `cached_network_image` files in the App's private cache directory | Only you |
| **HTTP cache** of catalog requests | Dio cache files in the App's private cache directory | Only you |
| **Lyrics (LRC files)** fetched from your Jellyfin server | In-memory only — not persisted | Only you, while playing |
| **Playback state** (current track, position, queue) | In-memory + lock-screen `MediaSession` | Only you |
| **Diagnostic logs** (`aetherfin:boot`, `aetherfin:http`, `aetherfin:data`, `aetherfin:audio`, `aetherfin:error`) | Standard Android logcat buffer (volatile, capped by the OS) | Only you, when you run `adb logcat` |

**Aetherfin does not send any of the above to the maintainer or any
third party.** The only network destination Aetherfin contacts is the
Jellyfin server URL you provide.

## 3. What Aetherfin sends to your Jellyfin server

The App is a client for the Jellyfin HTTP API. When you sign in and use
the App it sends the same requests any Jellyfin client (Finamp, the
official web client, etc.) would send, including:

- **Authentication:** `POST /Users/AuthenticateByName` (your username
  and password) — sent only once per sign-in to obtain an access token.
- **Catalog reads:** `GET /Users/{id}/Items`, `/Users/{id}/Items/Latest`,
  `/Users/{id}/Items/Resume`, `/Items/{id}/Images/Primary`, etc. —
  necessary to render the library, album, artist, and queue screens.
- **Audio streaming:** `GET /Audio/{id}/stream?Static=true` — direct
  byte-for-byte download of the audio file you chose to play.
- **Library state writes:**
  - `POST` / `DELETE /Users/{id}/FavoriteItems/{id}` when you tap the
    heart icon (favorite / un-favorite).
  - `POST /Sessions/Playing`, `POST /Sessions/Playing/Progress`, and
    `POST /Sessions/Playing/Stopped` so your Jellyfin dashboard shows
    what you're currently playing, and so play counts and
    last-played-at timestamps are updated. These can be disabled by
    your Jellyfin server administrator if desired.

Your Jellyfin server logs and stores this data according to its own
configuration, which is **outside the control of the App and its
maintainer**. Refer to your Jellyfin server administrator for its
retention and access policy.

## 4. What Aetherfin does NOT do

- No analytics SDK is integrated (no Firebase Analytics, Mixpanel,
  Amplitude, Sentry, Crashlytics, etc.).
- No advertising SDK is integrated. No ads are served.
- No telemetry, "anonymous usage statistics", "diagnostic data", or
  "improvement program" payloads are sent to the maintainer or any
  third party.
- No background location, contacts, calendar, SMS, or call-log access
  is requested or used.
- The App does not phone home on launch. The only initial network call
  is to the Jellyfin server URL you typed during onboarding.

You can verify this by reading the source code at
<https://github.com/Aetherfin/mobile-app>. The full list of network
endpoints the App touches is enumerated in `lib/core/jellyfin/client.dart`.

## 5. Android permissions Aetherfin requests

| Permission | Why |
|---|---|
| `INTERNET` | To talk to your Jellyfin server. |
| `ACCESS_NETWORK_STATE` | So the App can react to your phone being offline. |
| `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (Android 14+) | So music keeps playing when the App is backgrounded, via Android's standard media session. |
| `WAKE_LOCK` | So the CPU stays awake long enough to decode the next chunk of audio when the screen is off. |

The App does **not** request location, microphone, camera, contacts, or
storage permissions.

## 6. Children's privacy

Aetherfin is not directed to children under 13. The App itself collects
no information from anyone — children or otherwise — and transmits none
to the maintainer. Whether the content on your Jellyfin server is
appropriate for children is a matter for the server's owner.

## 7. Security

Credentials and access tokens are stored using Android's
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage),
which on modern Android uses the Android Keystore. Encrypted-at-rest
where the OS provides it.

That said, **rooted devices, malware, and physical access by a third
party can defeat any on-device storage**. If you believe your device
has been compromised, sign out from Settings → Profile → Sign out
(which deletes the stored token from secure storage) and revoke the
token in your Jellyfin server's "Devices" dashboard.

## 8. Open-source verifiability

Aetherfin is **open-source under the MIT License**. The entire client
behavior — every HTTP call, every storage write — is visible at:

> <https://github.com/Aetherfin/mobile-app>

If you want to verify the claims in this policy, the relevant files are:

- `lib/core/jellyfin/client.dart` — the only file that issues HTTP
  requests.
- `lib/core/jellyfin/auth_storage.dart` — the secure-storage adapter.
- `lib/state/providers.dart` — every data fetch the UI watches.
- `lib/main.dart` — bootstrap and initialization.

## 9. Changes to this policy

The maintainer may update this policy from time to time. The current
version is always the file `PRIVACY.md` at the root of the
[Aetherfin repository](https://github.com/Aetherfin/mobile-app). Material
changes — for example, if the App ever started collecting data — will
be called out in the commit message and the release notes for the
build that introduces them.

## 10. Contact

Privacy questions or requests can be sent to **mirzaspc@gmail.com** or
filed as a GitHub Issue on the
[Aetherfin repository](https://github.com/Aetherfin/mobile-app/issues).
