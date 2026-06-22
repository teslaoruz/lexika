import 'package:flutter/material.dart';

/// Palette from lexika-prototype.html `:root`, now mode-aware. Colors are
/// getters that resolve against [dark]; flip [dark] (via the theme provider in
/// main.dart) and rebuild to switch the whole app. ponytail: accents stay the
/// same in both modes — only the neutrals + pale tints flip, which is what a
/// dark theme actually needs. Shadows stay `const` (identical both modes) so
/// their existing const call-sites don't need touching.
class AppColors {
  AppColors._();

  /// Whether the app is currently in dark mode. Set once per build by the root
  /// before widgets read the getters below.
  static bool dark = false;

  static T _p<T>(T light, T darkV) => dark ? darkV : light;

  // Neutrals — these carry the light/dark difference.
  static Color get bg => _p(const Color(0xFFF7F6FB), const Color(0xFF14121E));
  static Color get bgSoft =>
      _p(const Color(0xFFEFEDFA), const Color(0xFF211E30));
  // "white" = card/surface colour. Dark mode → an elevated dark surface.
  static Color get white =>
      _p(const Color(0xFFFFFFFF), const Color(0xFF252233));
  static Color get ink => _p(const Color(0xFF2D2A3D), const Color(0xFFF0EEF8));
  static Color get inkSoft =>
      _p(const Color(0xFF6E6B85), const Color(0xFFB6B2CC));
  static Color get inkFaint =>
      _p(const Color(0xFFA6A3BC), const Color(0xFF807C98));

  // Accents — identical in both modes.
  static const coral = Color(0xFFFF6B5B);
  static Color get coralLight =>
      _p(const Color(0xFFFFE2DD), const Color(0xFF40221F));
  static const coralDark = Color(0xFFE8503F);

  static const violet = Color(0xFF6C5CE7);
  static Color get violetLight =>
      _p(const Color(0xFFE8E4FD), const Color(0xFF2C2747));
  static const violetDark = Color(0xFF5443D4);

  static const mint = Color(0xFF00D9A3);
  static Color get mintLight =>
      _p(const Color(0xFFD7FBEF), const Color(0xFF103A30));
  static const mintDark = Color(0xFF00AC81);

  static const amber = Color(0xFFFFC94D);
  static Color get amberLight =>
      _p(const Color(0xFFFFF3D6), const Color(0xFF3E3417));
  static const amberDark = Color(0xFFE8A800);

  static const sky = Color(0xFF4FC3F7);
  static Color get skyLight =>
      _p(const Color(0xFFDFF3FD), const Color(0xFF16313D));

  static const pink = Color(0xFFFF8FB1);
  static Color get pinkLight =>
      _p(const Color(0xFFFFE4ED), const Color(0xFF3E2230));

  // Antonym chip text + starred deck text from the prototype.
  static const antText = Color(0xFFC23E68);

  // Soft layered shadows (translated from CSS box-shadow vars). Kept const.
  static const shadowSm = [
    BoxShadow(color: Color(0x0F2D2A3D), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const shadowMd = [
    BoxShadow(color: Color(0x1A2D2A3D), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const shadowLg = [
    BoxShadow(color: Color(0x292D2A3D), blurRadius: 40, offset: Offset(0, 16)),
  ];
  static const shadowCoral = [
    BoxShadow(color: Color(0x59FF6B5B), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const shadowViolet = [
    BoxShadow(color: Color(0x596C5CE7), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const shadowMint = [
    BoxShadow(color: Color(0x5900D9A3), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const shadowPink = [
    BoxShadow(color: Color(0x66FF8FB1), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
