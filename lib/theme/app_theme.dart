import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData mocha = ThemeData(
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.googleSansFlex().fontFamily,
    scaffoldBackgroundColor: mochaBase,
    colorScheme: ColorScheme.dark(
      primary: mochaMauve,
      onPrimary: mochaBase,
      secondary: mochaTeal,
      onSecondary: mochaBase,
      surface: mochaMantle,
      onSurface: mochaText,
      onSurfaceVariant: mochaSubtext0,
      outline: mochaSurface2,
      error: mochaRed,
      onError: mochaBase,
    ),
    cardTheme: CardThemeData(
      color: mochaSurface0,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    iconTheme: const IconThemeData(color: mochaText),
    textTheme: _googleSansTextTheme(),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static TextTheme _googleSansTextTheme() {
    return GoogleFonts.googleSansFlexTextTheme().copyWith(
      bodyLarge: const TextStyle(color: mochaText, fontSize: 16, height: 1.5),
      bodyMedium: const TextStyle(color: mochaText),
      bodySmall: const TextStyle(color: mochaSubtext0),
      labelLarge: const TextStyle(color: mochaText),
      labelMedium: const TextStyle(color: mochaText),
      labelSmall: const TextStyle(color: mochaSubtext0),
      headlineLarge: const TextStyle(
        fontWeight: FontWeight.bold,
        color: mochaText,
      ),
      headlineMedium: const TextStyle(
        fontWeight: FontWeight.bold,
        color: mochaText,
      ),
      titleLarge: const TextStyle(
        fontWeight: FontWeight.bold,
        color: mochaText,
      ),
      titleMedium: const TextStyle(
        fontWeight: FontWeight.w600,
        color: mochaText,
      ),
    );
  }
}

// Expose frequently used text colors as top-level constants
const Color mochaText = Color(0xFFCDD6F4);
const Color mochaSubtext0 = Color(0xFFA6ADC8);
const Color mochaSubtext1 = Color(0xFFBAC2DE);
const Color mochaOverlay0 = Color(0xFF6C7086);
const Color mochaSurface0 = Color(0xFF313244);
const Color mochaSurface1 = Color(0xFF45475A);
const Color mochaSurface2 = Color(0xFF585B70);
const Color mochaMantle = Color(0xFF181825);
const Color mochaBase = Color(0xFF1E1E2E);
const Color mochaMauve = Color(0xFFCBA6F7);
const Color mochaTeal = Color(0xFF94E2D5);
const Color mochaBlue = Color(0xFF89B4FA);
const Color mochaSky = Color(0xFF89DCEB);
const Color mochaRed = Color(0xFFF38BA8);
const Color mochaGreen = Color(0xFFA6E3A1);
const Color mochaPeach = Color(0xFFFAB387);
const Color mochaPink = Color(0xFFF5C2E7);