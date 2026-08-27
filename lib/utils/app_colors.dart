import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors - JS Brand Red (more balanced usage)
  static const Color primary = Color(0xFFE51A1A);
  static const Color primaryLight = Color(0xFFF44336);
  static const Color primaryDark = Color(0xFFC62828);
  
  // Secondary Colors - Professional Whites and Grays
  static const Color secondary = Color(0xFFF8F9FA);
  static const Color secondaryLight = Color(0xFFFFFFFF);
  static const Color secondaryDark = Color(0xFFE9ECEF);
  
  // Accent Colors - Professional and Complementary
  static const Color accent = Color(0xFF2196F3);
  static const Color accentLight = Color(0xFF64B5F6);
  static const Color accentDark = Color(0xFF1976D2);
  
  // Background Colors - Clean Professional Theme
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  
  // Text Colors - Professional Dark Grays
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color textLight = Color(0xFFADB5BD);
  
  // Status Colors - Professional and Accessible
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE51A1A);
  static const Color info = Color(0xFF17A2B8);
  
  // Border Colors - Subtle Professional Borders
  static const Color border = Color(0xFFDEE2E6);
  static const Color borderLight = Color(0xFFF1F3F4);
  
  // Shadow Colors - Professional Subtle Shadows
  static const Color shadow = Color(0x1A000000);
  static const Color shadowLight = Color(0x0A000000);
  
  // Gradient Colors - Professional Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
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
  static const Color jsRed = Color(0xFFE51A1A);
  static const Color jsWhite = Color(0xFFFFFFFF);
  static const Color jsGray = Color(0xFFF8F9FA);
  
  // Professional Theme Colors
  static const Color professionalBackground = Color(0xFFFAFAFA);
  static const Color professionalSurface = Color(0xFFFFFFFF);
  static const Color professionalCard = Color(0xFFFFFFFF);
  static const Color professionalBorder = Color(0xFFE9ECEF);
} 