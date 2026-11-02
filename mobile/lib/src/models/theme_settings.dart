import 'package:flutter/material.dart';

enum AppThemePreset {
  light,
  dark,
  amoled,
  emerald,
  cyberpunk,
}

class AppThemeController extends ChangeNotifier {
  static final AppThemeController instance = AppThemeController._();
  AppThemeController._();

  AppThemePreset _preset = AppThemePreset.dark;
  AppThemePreset get preset => _preset;

  void setPreset(AppThemePreset newPreset) {
    _preset = newPreset;
    notifyListeners();
  }

  ThemeData get themeData {
    switch (_preset) {
      case AppThemePreset.light:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E6B5E),
            brightness: Brightness.light,
            surface: const Color(0xFFF8F9FA),
          ),
          scaffoldBackgroundColor: const Color(0xFFF3F4F6),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF3F4F6),
            foregroundColor: Color(0xFF1E293B),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 1,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

      case AppThemePreset.dark:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF38BDF8),
            brightness: Brightness.dark,
            surface: const Color(0xFF1E293B),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F172A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF1E293B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

      case AppThemePreset.amoled:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF60A5FA),
            surface: Color(0xFF121212),
          ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF121212),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF262626), width: 1),
            ),
          ),
        );

      case AppThemePreset.emerald:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10B981),
            brightness: Brightness.dark,
            surface: const Color(0xFF064E3B),
          ),
          scaffoldBackgroundColor: const Color(0xFF022C22),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF022C22),
            foregroundColor: Color(0xFFA7F3D0),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF064E3B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

      case AppThemePreset.cyberpunk:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF43F5E),
            secondary: Color(0xFF06B6D4),
            surface: Color(0xFF18182B),
          ),
          scaffoldBackgroundColor: const Color(0xFF0D0B18),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0D0B18),
            foregroundColor: Color(0xFFF43F5E),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF18182B),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF382956), width: 1),
            ),
          ),
        );
    }
  }
}
