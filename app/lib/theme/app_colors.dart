import 'package:flutter/material.dart';

/// Exact palette from lexika-prototype.html `:root`.
class AppColors {
  AppColors._();

  static const bg = Color(0xFFF7F6FB);
  static const bgSoft = Color(0xFFEFEDFA);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2D2A3D);
  static const inkSoft = Color(0xFF6E6B85);
  static const inkFaint = Color(0xFFA6A3BC);

  static const coral = Color(0xFFFF6B5B);
  static const coralLight = Color(0xFFFFE2DD);
  static const coralDark = Color(0xFFE8503F);

  static const violet = Color(0xFF6C5CE7);
  static const violetLight = Color(0xFFE8E4FD);
  static const violetDark = Color(0xFF5443D4);

  static const mint = Color(0xFF00D9A3);
  static const mintLight = Color(0xFFD7FBEF);
  static const mintDark = Color(0xFF00AC81);

  static const amber = Color(0xFFFFC94D);
  static const amberLight = Color(0xFFFFF3D6);
  static const amberDark = Color(0xFFE8A800);

  static const sky = Color(0xFF4FC3F7);
  static const skyLight = Color(0xFFDFF3FD);

  static const pink = Color(0xFFFF8FB1);
  static const pinkLight = Color(0xFFFFE4ED);

  // Antonym chip text + starred deck text from the prototype.
  static const antText = Color(0xFFC23E68);

  // Soft layered shadows (translated from CSS box-shadow vars).
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
