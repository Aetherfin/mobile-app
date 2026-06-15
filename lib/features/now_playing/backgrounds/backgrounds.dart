/// Player background style variants for the Now Playing screen.
///
/// Each widget renders a distinct visual treatment using the artwork's
/// spectral energy color. The active style is controlled by
/// [playerBackgroundStyleProvider] and dispatched via [ReactiveBackground].
library;

export 'blur_background.dart';
export 'gradient_background.dart';
export 'glow_background.dart';
export 'solid_background.dart';
