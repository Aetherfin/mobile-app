# Design

## Theme

Dark moody palette. Deep blacks, cool blue-grey surfaces, ocean-blue accent. Album-art-driven atmosphere — runtime-extracted spectral colors shift the entire UI to match the current track. The darkness is functional (headphone listening in dim environments), not aesthetic posturing.

## Color Strategy

**Restrained** — tinted neutrals + one accent (ocean blue) ≤10%. The spectral system provides a second axis of color derived from artwork at runtime, but the base palette stays calm and restrained.

### Surface Scale

Cool blue-grey, no warm tint. Depth via tone, not blur or decorative shadow.

| Token | Hex | Usage |
|---|---|---|
| `surfaceCanvas` | `#0A0B0E` | Page background |
| `surfaceLow` | `#14161A` | Sunken areas, input fields |
| `surfaceBase` | `#1E2028` | Cards, list items |
| `surfaceRaised` | `#282A34` | Elevated cards, floating elements |
| `surfaceHigh` | `#343640` | Active states, hover |
| `surfaceMax` | `#40424E` | Maximum elevation |

### Foreground

APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30.

| Token | Hex | Usage |
|---|---|---|
| `textPrimary` | `#E8ECF2` | Body text, headings |
| `textSecondary` | `#9AA0AD` | Captions, secondary info |
| `textTertiary` | `#7C8290` | Hints, disabled text |
| `textDisabled` | `#4A4E58` | Disabled state |
| `textOnPrimary` | `#F0F4F8` | Text on accent buttons |

### Accent — Ocean Blue

| Token | Hex | Usage |
|---|---|---|
| `accentPrimary` | `#2E6FA8` | Buttons, switches, sliders, focus (WCAG AA 4.80:1) |
| `accentSecondary` | `#3A7CA5` | Secondary actions, badges |
| `accentMuted` | `#6B8FA3` | Subtle accents, chip bg, icon tint |

### Semantic

| Token | Hex | Usage |
|---|---|---|
| `semanticSuccess` | `#7DB88F` | Success states |
| `semanticWarning` | `#5B9BD5` | Warnings (blue, not red) |
| `semanticError` | `#D4735A` | Error states |
| `semanticInfo` | `#7BA3B8` | Informational |

### Spectral System

Runtime-extracted from album artwork via `palette_generator_master`. The `Spectral` class provides `energy`, `shadow`, `glow` (now-playing specific) plus `primary`, `secondary`, `muted`, `link`, `warning` (app-wide accent replacements). Surface and text colors are also hue-shifted from artwork. Falls back to ocean-blue `Spectral.fallback` until artwork is parsed.

### Glass Morphism

Translucent white overlays for frosted surfaces (mini-player, now-playing top bar, cast button, track rows). Used sparingly — not decorative glassmorphism.

| Token | Opacity | Usage |
|---|---|---|
| `glassFillSubtle` | 4% white | Subtle overlays |
| `glassFill` | 6% white | Standard frosted surfaces |
| `glassFillStrong` | 8% white | Emphasized frosted surfaces |
| `glassFillHeavy` | 55% `#0A0A0A` | Heavy overlays (queue) |

## Typography

Three-font system. **Outfit** for display/headlines (geometric, modern, premium). **DM Sans** for body/UI (clean, characterful, excellent readability). **JetBrains Mono** for technical readouts only (bitrate, codec, EQ parameters).

### Type Scale

| Style | Font | Size | Height | Weight | Letter Spacing |
|---|---|---|---|---|---|
| `display` | Outfit | 36dp | 40/36 | 700 | -0.5 |
| `titleExtraLarge` | Outfit | 32dp | 38/32 | 700 | -0.4 |
| `titleLarge` | Outfit | 28dp | 34/28 | 700 | -0.3 |
| `titleMedium` | DM Sans | 22dp | 28/22 | 600 | -0.2 |
| `titleSmall` | DM Sans | 17dp | 22/17 | 600 | -0.1 |
| `bodyLarge` | DM Sans | 16dp | 24/16 | 400 | 0 |
| `bodyMedium` | DM Sans | 14dp | 20/14 | 400 | 0 |
| `bodySmall` | DM Sans | 12dp | 16/12 | 400 | 0.1 |
| `label` | DM Sans | 11dp | 14/11 | 600 | 0.6 |
| `caption` | DM Sans | 10dp | 13/10 | 400 | 0.2 |
| `overline` | DM Sans | 9dp | 12/9 | 500 | 0.8 |
| `mono` | JetBrains Mono | 11dp | 14/11 | 500 | 0 |

All text styles support `Scaled` variants via `MediaQuery.textScalerOf(context)` for accessibility.

## Spacing

4dp base unit. 8dp default sibling rhythm. 24dp section gap. 16dp gutters (24dp for "generous" surfaces like Now Playing and Lyrics). 48dp minimum hit target.

| Token | Value | Usage |
|---|---|---|
| `s4` | 4dp | Base unit, tight spacing |
| `s8` | 8dp | Default sibling rhythm |
| `s12` | 12dp | Compact gaps |
| `s16` | 16dp | Standard gutter, page horizontal |
| `s24` | 24dp | Section gap, generous gutter |
| `s32` | 32dp | Large gaps |
| `s48` | 48dp | Minimum hit target |
| `s64` | 64dp | Play button, mini-player height |
| `s96` | 96dp | Profile avatar |

## Radii

| Token | Value | Usage |
|---|---|---|
| `xs` | 4dp | Tight corners |
| `sm` | 8dp | Cards, list items |
| `md` | 12dp | Standard containers |
| `lg` | 16dp | Large containers |
| `xl` | 24dp | Featured elements |
| `rounded` | 20dp | Rounded cards |
| `pill` | 999dp | Buttons, chips, pills |

## Elevation

Shadow-based elevation system. No Material elevation — shadows are explicit `BoxShadow` lists.

| Token | Blur | Offset | Usage |
|---|---|---|---|
| `sm` | 4dp | (0, 1) | Cards at rest, list items |
| `md` | 8dp | (0, 2) | Raised cards, floating elements |
| `lg` | 16dp | (0, 4) | Dialogs, bottom sheets |
| `xl` | 24dp | (0, 8) | Modals, overlays |

Spectral glow: dynamic `BoxShadow` pair driven by artwork energy level.

## Motion

iOS-like feel: heavier, springier, more deliberate than stock Material. Audio-coupled animations (waveform, progress, lyric scroll) use `linear` — easing audio time lies about playback position.

### Curves

| Token | Bezier | Usage |
|---|---|---|
| `easeStandard` | (0.16, 1, 0.3, 1) | Page transitions, tab switches |
| `easeEmphasized` | (0.22, 1, 0.36, 1) | Mini-player → Now Playing expand |
| `springPresent` | (0.175, 0.885, 0.32, 1.045) | Bottom sheet open, dialog open |
| `springDismiss` | (0.55, 0.055, 0.675, 0.19) | Bottom sheet close, dialog close |

### Durations

| Token | Value | Usage |
|---|---|---|
| `instant` | 80ms | Color/opacity micro-feedback |
| `quick` | 180ms | Small element transitions, heart pop |
| `standard` | 350ms | Default page/sheet transitions |
| `expressive` | 500ms | Now Playing expand, hero handoff |
| `long` | 700ms | Onboarding intro only |
| `bounce` | 250ms | Play button bounce, icon morph |
| `ambient` | 1200ms | Pulse glow, breathing animations |
| `shimmer` | 1500ms | Skeleton shimmer sweep |
| `spectral` | 800ms | Spectral color crossfade |

### Stagger

40ms per item for grid/list reveals. Max 8 items staggered (items 9+ share the last slot). Per-item animation: fade + 12dp translate up.

## Layout

Android phones (360dp+), foldables, tablets. Three screen size tiers: compact (<600dp), medium (600–840dp), expanded (>840dp).

| Constraint | Value |
|---|---|
| Max content width | 600dp |
| Max dialog width | 560dp |
| Album grid max tile | 200dp |
| Artist grid max tile | 160dp |
| Genre grid max tile | 280dp |
| Page horizontal padding | 16dp (24dp generous) |

## Components

- **Bottom nav**: 4-tab with sliding pill background (indigo900). Inactive tabs show icon only; label appears when enabled.
- **Mini-player**: 64dp height, frosted glass, artwork + progress ring + transport controls.
- **Track row**: 3 density modes (compact, comfortable, generous). Dialog-based context menus.
- **Album card**: Hero animation capable. Grid layout with `SliverGridDelegateWithMaxCrossAxisExtent`.
- **Skeleton loaders**: Per-screen `*_skeleton.dart` files using `ShimmerLayout` base widget.
- **Bottom sheets**: Frosted glass container, per-sheet manual drag handle, `AfRadii.borderLg` corners.
- **Context menus**: Dialog-based (not bottom sheets) for album 3-dot and track long-press.
- **EQ/DSP**: Full-screen with 18-band graphic EQ, preset system, frequency response curve visualization.
- **Now Playing**: Gradient background from spectral colors, artwork pulse on kick drums, 64-band FFT visualizer, synced lyrics.
