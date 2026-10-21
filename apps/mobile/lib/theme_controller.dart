import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SpiceThemePalette {
  nusantara,
  samudra,
}

class ThemeController extends ChangeNotifier {
  static const String prefKeyThemeMode = 'jr_theme_mode';
  static const String prefKeyPalette = 'jr_theme_palette';

  ThemeMode _themeMode = ThemeMode.system;
  SpiceThemePalette _palette = SpiceThemePalette.nusantara;

  ThemeMode get themeMode => _themeMode;
  SpiceThemePalette get palette => _palette;

  Color get seedColor {
    switch (_palette) {
      case SpiceThemePalette.nusantara:
        return const Color(0xFF8B4513); // Cokelat / Amber Rempah Nusantara
      case SpiceThemePalette.samudra:
        return const Color(0xFF0D47A1); // Biru Gelap Samudra Hindia-Pasifik
    }
  }

  ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }

  ThemeData get darkTheme {
    final darkSeed = _palette == SpiceThemePalette.nusantara
        ? const Color(0xFFD97706) // Amber Rempah Hangat di mode gelap
        : const Color(0xFF38BDF8); // Biru Samudra Bercahaya di mode gelap
    final scheme = ColorScheme.fromSeed(
      seedColor: darkSeed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }

  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(prefKeyThemeMode);
      final palStr = prefs.getString(prefKeyPalette);

      if (modeStr == 'light') {
        _themeMode = ThemeMode.light;
      } else if (modeStr == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }

      if (palStr == 'samudra') {
        _palette = SpiceThemePalette.samudra;
      } else {
        _palette = SpiceThemePalette.nusantara;
      }
      notifyListeners();
    } catch (_) {
      // Fallback aman bila berjalan di lingkungan tanpa native plugin
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system';
      await prefs.setString(prefKeyThemeMode, modeStr);
    } catch (_) {
      // Abaikan kegagalan simpan di memori pengujian
    }
  }

  Future<void> setPalette(SpiceThemePalette newPalette) async {
    _palette = newPalette;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefKeyPalette,
        newPalette == SpiceThemePalette.samudra ? 'samudra' : 'nusantara',
      );
    } catch (_) {
      // Abaikan kegagalan simpan di memori pengujian
    }
  }
}
