import 'package:flutter/widgets.dart';

/// Container shape radii — Dark Moody edition.
///
/// All radii are in dp (logical pixels in Flutter).
/// `pill` is 999dp — used for buttons, chips, pills.
abstract final class AfRadii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double rounded = 20;
  static const double pill = 999;

  static const Radius rXs = Radius.circular(xs);
  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
  static const Radius rXl = Radius.circular(xl);
  static const Radius rPill = Radius.circular(pill);
  static const Radius rRounded = Radius.circular(rounded);

  static const BorderRadius borderXs = BorderRadius.all(rXs);
  static const BorderRadius borderSm = BorderRadius.all(rSm);
  static const BorderRadius borderMd = BorderRadius.all(rMd);
  static const BorderRadius borderLg = BorderRadius.all(rLg);
  static const BorderRadius borderXl = BorderRadius.all(rXl);
  static const BorderRadius borderRounded = BorderRadius.all(rRounded);
  static const BorderRadius borderPill = BorderRadius.all(rPill);
  static const BorderRadius borderNone = BorderRadius.zero;
}
