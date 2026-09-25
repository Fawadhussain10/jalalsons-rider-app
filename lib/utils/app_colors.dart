import 'package:flutter/material.dart';

class AppColors {
  // Brand — JS red
  static const Color primary = Color(0xFFE51A1A);
  static const Color primaryLight = Color(0xFFFF4B4B);
  static const Color primaryDark = Color(0xFFB31212);
  static const Color primarySoft = Color(0xFFFDECEC);

  // Premium neutrals ("ink" for hero headers, "canvas" for backgrounds)
  static const Color ink = Color(0xFF14161C);
  static const Color inkSoft = Color(0xFF23262F);
  static const Color canvas = Color(0xFFF4F5F8);
  static const Color gold = Color(0xFFF5B83D);

  // Secondary Colors - Professional Whites and Grays
  static const Color secondary = Color(0xFFF8F9FA);
  static const Color secondaryLight = Color(0xFFFFFFFF);
  static const Color secondaryDark = Color(0xFFE9ECEF);

  // Accent Colors
  static const Color accent = Color(0xFF2F6BFF);
  static const Color accentLight = Color(0xFF6E97FF);
  static const Color accentDark = Color(0xFF1F4FD1);

  // Background Colors
  static const Color background = canvas;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);

  // Text Colors
  static const Color textPrimary = Color(0xFF171A21);
  static const Color textSecondary = Color(0xFF69707D);
  static const Color textLight = Color(0xFFA6ABB5);

  // Status Colors
  static const Color success = Color(0xFF12A150);
  static const Color successSoft = Color(0xFFE6F6ED);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF4E2);
  static const Color error = Color(0xFFE51A1A);
  static const Color info = Color(0xFF2F6BFF);
  static const Color infoSoft = Color(0xFFE9F0FF);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color purpleSoft = Color(0xFFF0EBFF);

  // Borders & shadows
  static const Color border = Color(0xFFE6E8EE);
  static const Color borderLight = Color(0xFFF0F1F5);
  static const Color shadow = Color(0x14101828);
  static const Color shadowLight = Color(0x0A101828);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0F101828), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF3B3B), primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient inkGradient = LinearGradient(
    colors: [Color(0xFF1E2129), ink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // JS Brand Specific Colors
  static const Color jsRed = primary;
  static const Color jsWhite = Color(0xFFFFFFFF);
  static const Color jsGray = Color(0xFFF8F9FA);

  // Legacy names still used by some widgets
  static const Color professionalBackground = canvas;
  static const Color professionalSurface = Color(0xFFFFFFFF);
  static const Color professionalCard = Color(0xFFFFFFFF);
  static const Color professionalBorder = border;
}
