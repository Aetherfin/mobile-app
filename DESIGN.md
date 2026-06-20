---
name: Aetherfin
description: Dark moody music player with album-art-driven spectral atmosphere
colors:
  surfaceCanvas: "#0A0B0E"
  surfaceLow: "#14161A"
  surfaceBase: "#1E2028"
  surfaceRaised: "#282A34"
  surfaceHigh: "#343640"
  surfaceMax: "#40424E"
  textPrimary: "#E8ECF2"
  textSecondary: "#9AA0AD"
  textTertiary: "#7C8290"
  textDisabled: "#4A4E58"
  textOnPrimary: "#F0F4F8"
  accentPrimary: "#2E6FA8"
  accentSecondary: "#3A7CA5"
  accentMuted: "#6B8FA3"
  semanticSuccess: "#7DB88F"
  semanticWarning: "#5B9BD5"
  semanticError: "#D4735A"
  semanticInfo: "#7BA3B8"
typography:
  display:
    fontFamily: "Outfit, sans-serif"
    fontSize: "36dp"
    fontWeight: 700
    lineHeight: "40/36"
    letterSpacing: -0.5
  titleExtraLarge:
    fontFamily: "Outfit, sans-serif"
    fontSize: "32dp"
    fontWeight: 700
    lineHeight: "38/32"
    letterSpacing: -0.4
  titleLarge:
    fontFamily: "Outfit, sans-serif"
    fontSize: "28dp"
    fontWeight: 700
    lineHeight: "34/28"
    letterSpacing: -0.3
  titleMedium:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "22dp"
    fontWeight: 600
    lineHeight: "28/22"
    letterSpacing: -0.2
  titleSmall:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "17dp"
    fontWeight: 600
    lineHeight: "22/17"
    letterSpacing: -0.1
  bodyLarge:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "16dp"
    fontWeight: 400
    lineHeight: "24/16"
    letterSpacing: 0
  bodyMedium:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "14dp"
    fontWeight: 400
    lineHeight: "20/14"
    letterSpacing: 0
  bodySmall:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "12dp"
    fontWeight: 400
    lineHeight: "16/12"
    letterSpacing: 0.1
  label:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "11dp"
    fontWeight: 600
    lineHeight: "14/11"
    letterSpacing: 0.6
  caption:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "10dp"
    fontWeight: 400
    lineHeight: "13/10"
    letterSpacing: 0.2
  overline:
    fontFamily: "DM Sans, sans-serif"
    fontSize: "9dp"
    fontWeight: 500
    lineHeight: "12/9"
    letterSpacing: 0.8
  mono:
    fontFamily: "JetBrains Mono, monospace"
    fontSize: "11dp"
    fontWeight: 500
    lineHeight: "14/11"
    letterSpacing: 0
rounded:
  xs: "4dp"
  sm: "8dp"
  md: "12dp"
  lg: "16dp"
  xl: "24dp"
  rounded: "20dp"
  pill: "999dp"
spacing:
  s4: "4dp"
  s8: "8dp"
  s12: "12dp"
  s16: "16dp"
  s24: "24dp"
  s32: "32dp"
  s48: "48dp"
  s64: "64dp"
  s96: "96dp"
components:
  button-primary:
    backgroundColor: "{colors.accentPrimary}"
    textColor: "{colors.textOnPrimary}"
    rounded: "{rounded.pill}"
    padding: "16dp 32dp"
  chip:
    backgroundColor: "{colors.surfaceRaised}"
    textColor: "{colors.textSecondary}"
    rounded: "{rounded.pill}"
    padding: "8dp 16dp"
  card:
    backgroundColor: "{colors.surfaceBase}"
    textColor: "{colors.textPrimary}"
    rounded: "{rounded.sm}"
    padding: "16dp"
---

# Design System: Aetherfin

## 1. Overview

**Creative North Star: "The Dark Listening Room"**

Aetherfin's visual system is built for one activity: listening to music in dim environments. The palette is dark by function, not by fashion — headphone sessions happen in bedrooms, cars, and late-night commutes. The UI recedes into near-black surfaces while album artwork takes over: runtime-extracted spectral colors shift the entire atmosphere to match the current track. The system rejects the bright Material You defaults of cloud-first streaming apps and the settings-overload density of power-user tools. Instead, it walks the line between calm surface and technical depth — 86 DSP effects exist, but the now-playing screen doesn't scream about them.

**Key Characteristics:**

- Artwork is the interface. Colors, gradients, atmosphere — all derived from the current track's album art at runtime.
- Dark by nature. Cool blue-grey surfaces at near-black tones, depth via tone not shadow decoration.
- Restrained accent. Ocean blue (`#2E6FA8`) used for primary actions only; spectral system provides dynamic accent replacement.
- iOS-like motion. Heavier, springier transitions than stock Material. Audio-coupled animations always linear.
- Technical depth, calm surface. EQ, DSP, visualizer — powerful but discoverable, never mandatory.

## 2. Colors

The palette is cool blue-grey at near-black tones, with ocean blue as the single accent. Spectral colors extracted from album artwork at runtime replace accent colors dynamically — the base palette stays calm and restrained.

### Primary

- **Ocean Blue** (`#2E6FA8`): Primary accent — buttons, switches, sliders, focus rings. WCAG AA 4.80:1 against `surfaceCanvas`. Used on ≤10% of any screen; its rarity is the point.
- **Deep Blue** (`#3A7CA5`): Secondary accent — badges, secondary actions, chips.
- **Muted Blue** (`#6B8FA3`): Subtle accents — icon tint, chip background, disabled accent states.

### Neutral

- **Void Black** (`#0A0B0E`): Page background (`surfaceCanvas`). The deepest surface; pure darkness for headphone listening.
- **Dark Slate** (`#14161A`): Sunken areas, input fields (`surfaceLow`).
- **Slate** (`#1E2028`): Cards, list items (`surfaceBase`). Default surface for interactive content.
- **Elevated Slate** (`#282A34`): Raised cards, floating elements (`surfaceRaised`).
- **Active Slate** (`#343640`): Hover states, active indicators (`surfaceHigh`).
- **Max Slate** (`#40424E`): Maximum elevation (`surfaceMax`).
- **Bright White** (`#E8ECF2`): Body text, headings (`textPrimary`). APCA Lc ≥ 60.
- **Cool Gray** (`#9AA0AD`): Captions, secondary info (`textSecondary`). APCA Lc ≥ 45.
- **Muted Gray** (`#7C8290`): Hints, disabled text (`textTertiary`). APCA Lc ≥ 30.
- **Disabled Gray** (`#4A4E58`): Disabled state (`textDisabled`).
- **On Accent** (`#F0F4F8`): Text on accent buttons (`textOnPrimary`).

### Semantic

- **Success Green** (`#7DB88F`): Success states.
- **Info Blue** (`#5B9BD5`): Warnings (blue, not red — matches ocean hue).
- **Error Coral** (`#D4735A`): Error states.
- **Info Slate** (`#7BA3B8`): Informational cues.

### Spectral System

Runtime-extracted from album artwork via `palette_generator_master`. The `Spectral` class provides `energy`, `shadow`, `glow` (now-playing specific) plus `primary`, `secondary`, `muted`, `link`, `warning` (app-wide accent replacements). Surface and text colors are also hue-shifted from artwork. Falls back to ocean-blue `Spectral.fallback` until artwork is parsed.

### Glass Morphism

Translucent white overlays for frosted surfaces (mini-player, now-playing top bar, cast button, track rows). Used sparingly — not decorative glassmorphism.

- **Subtle** (4% white): Faint overlays.
- **Standard** (6% white): Frosted glass surfaces.
- **Strong** (8% white): Emphasized frosted surfaces.
- **Heavy** (55% `#0A0A0A`): Queue overlay.

### Named Rules

**The Accent Ration Rule.** Ocean blue appears on ≤10% of any given screen. Its rarity is the point — buttons, switches, sliders, focus rings. Never used for decoration, background fills, or borders on static elements.

**The Spectral Override Rule.** When artwork is loaded, spectral colors replace ocean blue for primary, secondary, muted, link, and warning roles. The base palette is a fallback, not a default.

## 3. Typography

**Display Font:** Outfit (geometric, modern, premium)
**Body Font:** DM Sans (clean, characterful, excellent readability)
**Label/Mono Font:** JetBrains Mono (technical readouts only — bitrate, codec, EQ parameters)

**Character:** Outfit carries display/headline weight with geometric precision. DM Sans handles everything body/UI with friendly readability. JetBrains Mono is reserved for data readouts — never used for labels or UI text.

### Hierarchy

- **Display** (Outfit, 700, 36dp, line-height 40/36, letter-spacing -0.5): Hero headlines on Now Playing, large hero text.
- **Title Extra Large** (Outfit, 700, 32dp, line-height 38/32, letter-spacing -0.4): Album/artist screen titles.
- **Title Large** (Outfit, 700, 28dp, line-height 34/28, letter-spacing -0.3): Section headers, large titles.
- **Title Medium** (DM Sans, 600, 22dp, line-height 28/22, letter-spacing -0.2): Card titles, list headers.
- **Title Small** (DM Sans, 600, 17dp, line-height 22/17, letter-spacing -0.1): Subtitles, dialog titles.
- **Body Large** (DM Sans, 400, 16dp, line-height 24/16): Primary body text, descriptions.
- **Body Medium** (DM Sans, 400, 14dp, line-height 20/14): Secondary body text, list content.
- **Body Small** (DM Sans, 400, 12dp, line-height 16/12, letter-spacing 0.1): Captions, metadata.
- **Label** (DM Sans, 600, 11dp, line-height 14/11, letter-spacing 0.6): UPPERCASE in widget. Section headers, category labels. Never bold, never accent-colored.
- **Caption** (DM Sans, 400, 10dp, line-height 13/10, letter-spacing 0.2): Timestamps, secondary metadata.
- **Overline** (DM Sans, 500, 9dp, line-height 12/9, letter-spacing 0.8): Tiny labels, micro text.
- **Mono** (JetBrains Mono, 500, 11dp, line-height 14/11): Bitrate, codec, hash readouts only.

All text styles support `Scaled` variants via `MediaQuery.textScalerOf(context)` for accessibility.

### Named Rules

**The Mono Restriction Rule.** JetBrains Mono appears only for technical data readouts (bitrate, codec, EQ parameters). Never for UI labels, buttons, or body text.

**The Label Case Rule.** The `label` style is always rendered UPPERCASE in widgets. It is never bold and never accent-colored — use `textSecondary` or `labelContrast` color only.

## 4. Elevation

Shadow-based elevation system. No Material elevation — shadows are explicit `BoxShadow` lists. Depth is conveyed through progressive shadow blur and offset, not tonal layering or decorative blur.

- **Subtle** (`box-shadow: 0 1px 4px rgba(0,0,0,0.1)`): Cards at rest, list items.
- **Medium** (`box-shadow: 0 2px 8px rgba(0,0,0,0.14)`): Raised cards, floating elements.
- **Large** (`box-shadow: 0 4px 16px rgba(0,0,0,0.2)`): Dialogs, bottom sheets.
- **Extra-Large** (`box-shadow: 0 8px 24px rgba(0,0,0,0.25)`): Modals, overlays.

### Spectral Glow

Dynamic `BoxShadow` pair driven by artwork energy level. Applied to Now Playing artwork and play button. Two shadows with artwork-derived color, opacity scaled by energy (0.0–1.0).

### Named Rules

**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadows appear only as a response to state (hover, elevation, focus). The spectral glow is the sole exception — it's audio-coupled, not interaction-coupled.

## 5. Components

### Buttons

- **Shape:** Full pill (`999dp` radius). Tall hit target (48dp minimum).
- **Primary:** Ocean blue (`#2E6FA8`) background, white text (`#F0F4F8`). Padding: 16dp vertical, 32dp horizontal.
- **Hover / Focus:** Transition via `easeStandard` (350ms). Focus ring uses accent color.
- **Secondary / Outlined:** Transparent background, ocean blue border (1.5dp), ocean blue text.

### Chips

- **Style:** Raised surface (`#282A34`), secondary text (`#9AA0AD`), pill shape.
- **State:** Selected state uses accent background with accent text. Filter and action variants.

### Cards / Containers

- **Corner Style:** 8dp radius (`sm`). No cards exceed 12dp.
- **Background:** `surfaceBase` (`#1E2028`) at rest. `surfaceRaised` on hover/active.
- **Shadow Strategy:** Subtle shadow at rest (blur 4dp, offset 1). Medium shadow on elevation.
- **Border:** No default border. 1dp `glassBorder` (6% white) on select containers.
- **Internal Padding:** 16dp standard, 24dp generous (Now Playing, Lyrics).

### Inputs / Fields

- **Style:** Filled background (`surfaceLow`), no visible border. 8dp radius.
- **Focus:** Accent color border or glow. Background shifts to `surfaceBase`.
- **Error:** Error coral (`#D4735A`) border. Error text below field.
- **Disabled:** `textDisabled` text, `surfaceLow` background at reduced opacity.

### Navigation

- **Bottom Nav:** 4-tab with sliding pill background (`indigo900`). Inactive tabs show icon only; label appears when enabled. 64dp height.
- **Top App Bar:** Transparent over content, collapses on scroll. Title uses `titleMedium` style.

### Track Row

Three density modes: compact (48dp), comfortable (56dp), generous (64dp). Dialog-based context menus (not bottom sheets). Leading artwork thumbnail, title + subtitle, trailing actions.

### Mini-Player

64dp height, frosted glass container (`glassFill`), artwork thumbnail + progress ring + transport controls. Sits above bottom nav.

### Now Playing

Full-screen overlay. Gradient background from spectral colors. Artwork pulse on kick drums (transient detector + spring decay). 64-band FFT visualizer. Synced lyrics. Interactive drag-down sheet.

### Skeleton Loaders

Per-screen `*_skeleton.dart` files using `ShimmerLayout` base widget. Shimmer sweep at 1500ms. Used for all async content loading.

### Context Menus

Dialog-based (not bottom sheets) for album 3-dot and track long-press. Frosted glass container with manual drag handle.

## 6. Do's and Don'ts

### Do:

- **Do** use `AfColors.*` tokens for all colors. Never `Colors.white`, `Colors.black`, or raw `Color(0xFF...)`.
- **Do** use `AfSpacing.*` for all spacing. `SizedBox(height: AfSpacing.s8)`, `EdgeInsets.all(AfSpacing.s16)`.
- **Do** use `AfRadii.*` for all border radii. `AfRadii.borderSm` (8dp), `AfRadii.borderMd` (12dp), `AfRadii.borderPill` (999dp).
- **Do** use `AfTypography.*` text styles with `.copyWith()` for color/weight overrides. Never raw `TextStyle(...)`.
- **Do** use `AfDurations.*` and `AfCurves.*` for all animation timings. Never literal ms values.
- **Do** use `StaggerReveal` for list/grid entrance animations. 40ms per item, max 8 staggered.
- **Do** use dialog-based context menus for album 3-dot and track long-press.
- **Do** use skeleton shimmer loading for all async content.
- **Do** use `context.push()` for overlay/detail routes (Now Playing, Lyrics, Queue).
- **Do** use `context.go()` only for tab switches and auth redirects.

### Don't:

- **Don't** use `just_audio` or `audio_session` — use `mpv_audio_kit`.
- **Don't** use `json_serializable` — hand-write models.
- **Don't** use `ChangeNotifier` for Riverpod providers.
- **Don't** use `Timer.periodic` for progress reporting — use serialized `while` loop.
- **Don't** use `Future.delayed` for auto-advance — use stream callbacks.
- **Don't** use `.then()` for jump+play — use `async/await`.
- **Don't** use `NoTransitionPage` for tab switches — use `FadeInUp` from `animate_do` with `AfDurations.quick`.
- **Don't** hardcode animation durations (e.g. `Duration(milliseconds: 300)`) — use `AfDurations.standard` etc.
- **Don't** hardcode colors, spacing, border radii, or font sizes — use the design tokens.
- **Don't** use `jellyfinClientProvider` for backend ops in UI — use `musicBackendProvider`.
- **Don't** create a separate HTTP client — add to `JellyfinClient` or `SubsonicClient`.
- **Don't** store Subsonic auth token — store password, generate `md5(password + salt)` per request.
- **Don't** pass network artwork URLs to native MediaSession — download to local file first.
- **Don't** use `context.go()` for overlay screens (lyrics, queue, settings) — breaks back stack.
- **Don't** rebuild GoRouter — it's a module-level singleton.
- **Don't** use generic AI dark UI patterns: gradient text, glassmorphism everywhere, identical card grids, tiny uppercase eyebrows above every section.
- **Don't** use side-stripe borders (`border-left` > 1px as colored accent). Never intentional.
- **Don't** use `border-radius: 24dp+` on cards. Cards top out at 12dp.
- **Don't** use display fonts in UI labels, buttons, or data readouts.
- **Don't** use decorative motion that doesn't convey state.
