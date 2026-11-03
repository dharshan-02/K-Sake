import 'package:flutter/material.dart';

enum AppThemePreset { light, dark, amoled }

class AppThemeController extends ChangeNotifier {
  static final AppThemeController instance = AppThemeController._();
  AppThemeController._();

  AppThemePreset _preset = AppThemePreset.light;
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
            seedColor: const Color(0xFF5267C5),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
    }
  }
}
