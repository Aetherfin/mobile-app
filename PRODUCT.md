# Product

## Register

product

## Users

Self-hosters and audiophiles who run Jellyfin or Navidrome servers, care about lossless audio, DSP control, and data ownership. Casual music listeners who want a clean, subscription-free player. Power users are primary; the UI must be approachable for casual listeners without dumbing down the experience.

Context: headphones or car, offline or on-demand, library curation or quick shuffle. The app is opened to play music — every screen exists to get audio moving or let the listener stay in the moment.

## Product Purpose

Aetherfin is a native Android music player that streams from self-hosted Jellyfin/Navidrome servers or plays local files. It decodes on-device with libmpv, provides full DSP control (86 effects, 18-band EQ), and stays out of the way. No cloud, no telemetry, no transcoding. Success: the user forgets they're using an app and just hears their music.

## Brand Personality

Bold, immersive, intimate. Album-art-driven atmosphere — the music fills the screen. Technical confidence without flash. The UI recedes; the artwork and audio take over.

## Anti-references

- Generic AI dark UI: gradient text, glassmorphism everywhere, identical card grids, tiny uppercase eyebrows above every section. The saturated 2026 AI scaffold.
- YouTube Music / Spotify: bright Material You, subscription models, cloud-first. Not this.
- Poweramp settings overload: overwhelming EQ screens, tiny text, cluttered layouts. Aetherfin's DSP is powerful but the UI stays calm.

## Design Principles

1. **Artwork is the interface.** Colors, gradients, atmosphere — all extracted from the current track's album art. The UI adapts; the music leads.
2. **Technical depth, calm surface.** 86 DSP effects exist, but the now-playing screen doesn't scream about them. Depth is discoverable, not mandatory.
3. **Own your experience.** No cloud, no accounts beyond your server, no telemetry. The app talks only to the server you configure.
4. **Motion serves playback.** Visualizer bars, artwork pulse, gradient shifts — all driven by actual audio output, not decoration.
5. **Dark by nature, not by default.** The palette is dark because music listening happens in dim environments. The darkness is functional, not aesthetic posturing.

## Accessibility & Inclusion

WCAG AA contrast targets. Text scaling via system scaler. Reduced motion alternatives for all animations. Skeleton shimmer loading for async content. Semantic color usage (success/warning/error/info) with non-color cues.
