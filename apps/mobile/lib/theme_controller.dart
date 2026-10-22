import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SpiceThemePalette {
  nusantara,
  samudra,
}

enum MapStyle {
  vintageColor,
  vintageSepia,
  modern,
}

enum GraphicsQuality {
  low,
  medium,
  high,
  ultra,
}

/// Palet Warna Utama "Vintage Maritim / Peta Kuno / Papan Kayu"
class MaritimePalette {
  static const Color deepOceanBlue = Color(0xFF0A192F);
  static const Color abyssalBlue = Color(0xFF061026);
  static const Color shallowSeaBlue = Color(0xFF132C5C);
  static const Color darkWoodBrown = Color(0xFF3E2723);
  static const Color carvedMahogany = Color(0xFF281815);
  static const Color weatheredTeak = Color(0xFF4E342E);
  static const Color gold = Color(0xFFFFD700);
  static const Color antiqueBrass = Color(0xFFD4AF37);
  static const Color bronzeBorder = Color(0xFF9C7A3C);
  static const Color parchment = Color(0xFFF5DEB3);
  static const Color parchmentLight = Color(0xFFFFF5DC);
  static const Color parchmentMuted = Color(0xFFD7BA89);
  static const Color crimsonWax = Color(0xFF991B1B);
  static const Color emeraldJade = Color(0xFF15803D);

  static bool get _isFlutterTest {
    try {
      return const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// Font Judul Klasik & Megah (`Cinzel`)
  static TextStyle cinzel({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) {
    if (_isFlutterTest) {
      return (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'Cinzel',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        shadows: shadows,
      );
    }
    return GoogleFonts.cinzel(
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
    );
  }

  /// Font Judul Ornamen (`Cinzel Decorative`)
  static TextStyle cinzelDecorative({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) {
    if (_isFlutterTest) {
      return (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'CinzelDecorative',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        shadows: shadows,
      );
    }
    return GoogleFonts.cinzelDecorative(
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      shadows: shadows,
    );
  }

  /// Font Teks Isi Naskah Klasik (`Crimson Text`)
  static TextStyle crimsonText({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    if (_isFlutterTest) {
      return (textStyle ?? const TextStyle()).copyWith(
        fontFamily: 'CrimsonText',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return GoogleFonts.crimsonText(
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Dekorasi Papan Pengumuman Kayu Gelap dengan Border Emas & Drop Shadow
  static BoxDecoration woodPlankDecoration({
    Color? baseColor,
    Color? borderColor,
    double borderRadius = 12.0,
    double borderWidth = 1.2,
    bool isHighlighted = false,
  }) {
    final topWood = baseColor ?? darkWoodBrown;
    final bottomWood =
        baseColor != null ? baseColor : carvedMahogany;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          topWood,
          weatheredTeak,
          bottomWood,
        ],
        stops: const <double>[0.0, 0.45, 1.0],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ??
            (isHighlighted ? gold : const Color(0xAAFFD700)),
        width: isHighlighted ? 1.8 : borderWidth,
      ),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0xAA000000),
          blurRadius: 8,
          spreadRadius: 0.5,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x22FFD700),
          blurRadius: 2,
          offset: Offset(0, -1),
        ),
      ],
    );
  }

  /// Gaya Tombol Koin Emas / Logam Kuno 3D
  static ButtonStyle goldCoinButtonStyle({
    EdgeInsetsGeometry? padding,
    double borderRadius = 10.0,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: gold,
      foregroundColor: carvedMahogany,
      disabledBackgroundColor: const Color(0xFF5A4638),
      disabledForegroundColor: const Color(0xFF9E8C7A),
      shadowColor: const Color(0xEE000000),
      elevation: 6,
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      side: const BorderSide(
        color: Color(0xFFFFF3B0),
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      textStyle: cinzel(
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class ThemeController extends ChangeNotifier {
  static const String prefKeyThemeMode = 'jr_theme_mode';
  static const String prefKeyPalette = 'jr_theme_palette';
  static const String prefKeyMapStyle = 'map_style';
  static const String prefKeyGraphicsQuality = 'graphics_quality';

  ThemeMode _themeMode = ThemeMode.dark;
  SpiceThemePalette _palette = SpiceThemePalette.nusantara;
  MapStyle _mapStyle = MapStyle.vintageColor;
  GraphicsQuality _graphicsQuality = GraphicsQuality.high;

  ThemeMode get themeMode => _themeMode;
  SpiceThemePalette get palette => _palette;
  MapStyle get mapStyle => _mapStyle;
  GraphicsQuality get graphicsQuality => _graphicsQuality;

  set mapStyle(MapStyle style) {
    setMapStyle(style);
  }

  set graphicsQuality(GraphicsQuality quality) {
    setGraphicsQuality(quality);
  }

  Color get seedColor {
    switch (_palette) {
      case SpiceThemePalette.nusantara:
        return MaritimePalette.darkWoodBrown;
      case SpiceThemePalette.samudra:
        return MaritimePalette.deepOceanBlue;
    }
  }

  TextTheme _buildMaritimeTextTheme(Color primaryText, Color titleGold) {
    return TextTheme(
      displayLarge: MaritimePalette.cinzelDecorative(
        color: titleGold,
        fontSize: 30,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: MaritimePalette.cinzelDecorative(
        color: titleGold,
        fontSize: 26,
        fontWeight: FontWeight.bold,
      ),
      displaySmall: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      headlineLarge: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 19,
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
      titleMedium: MaritimePalette.cinzel(
        color: MaritimePalette.parchmentLight,
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      titleSmall: MaritimePalette.cinzel(
        color: primaryText,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: MaritimePalette.crimsonText(
        color: primaryText,
        fontSize: 16.5,
        height: 1.35,
      ),
      bodyMedium: MaritimePalette.crimsonText(
        color: primaryText,
        fontSize: 15,
        height: 1.35,
      ),
      bodySmall: MaritimePalette.crimsonText(
        color: MaritimePalette.parchmentMuted,
        fontSize: 13.5,
        height: 1.3,
      ),
      labelLarge: MaritimePalette.cinzel(
        color: titleGold,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
      labelMedium: MaritimePalette.crimsonText(
        color: primaryText,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: MaritimePalette.crimsonText(
        color: MaritimePalette.parchmentMuted,
        fontSize: 11.5,
      ),
    );
  }

  ThemeData _buildVintageMaritimeTheme({required Brightness brightness}) {
    final isSamudra = _palette == SpiceThemePalette.samudra;
    final scaffoldBg = isSamudra
        ? MaritimePalette.deepOceanBlue
        : const Color(0xFF0A192F);
    final surfaceWood = MaritimePalette.darkWoodBrown;
    final gold = MaritimePalette.gold;
    final parchment = MaritimePalette.parchment;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: gold,
      onPrimary: MaritimePalette.carvedMahogany,
      primaryContainer: MaritimePalette.weatheredTeak,
      onPrimaryContainer: parchment,
      secondary: MaritimePalette.antiqueBrass,
      onSecondary: MaritimePalette.carvedMahogany,
      secondaryContainer: MaritimePalette.darkWoodBrown,
      onSecondaryContainer: parchment,
      tertiary: const Color(0xFF38BDF8),
      onTertiary: MaritimePalette.abyssalBlue,
      error: const Color(0xFFF87171),
      onError: MaritimePalette.carvedMahogany,
      surface: surfaceWood,
      onSurface: parchment,
      onSurfaceVariant: MaritimePalette.parchmentMuted,
      outline: const Color(0xAAFFD700),
      outlineVariant: const Color(0x55FFD700),
      shadow: Colors.black,
    );

    final textTheme = _buildMaritimeTextTheme(parchment, gold);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      cardColor: surfaceWood,
      dividerColor: const Color(0x55FFD700),
      textTheme: textTheme,
      iconTheme: const IconThemeData(
        color: MaritimePalette.gold,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MaritimePalette.darkWoodBrown,
        foregroundColor: gold,
        elevation: 6,
        shadowColor: Colors.black87,
        centerTitle: false,
        iconTheme: const IconThemeData(color: MaritimePalette.gold),
        actionsIconTheme: const IconThemeData(color: MaritimePalette.gold),
        titleTextStyle: MaritimePalette.cinzel(
          color: gold,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          shadows: const <Shadow>[
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 2),
              blurRadius: 3,
            ),
          ],
        ),
        shape: const Border(
          bottom: BorderSide(
            color: MaritimePalette.gold,
            width: 1.5,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceWood,
        shadowColor: Colors.black87,
        elevation: 6,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(
            color: Color(0xAAFFD700),
            width: 1.2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: MaritimePalette.goldCoinButtonStyle(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: MaritimePalette.carvedMahogany,
          disabledBackgroundColor: const Color(0xFF5A4638),
          disabledForegroundColor: const Color(0xFF9E8C7A),
          shadowColor: Colors.black,
          elevation: 5,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          side: const BorderSide(color: Color(0xFFFFF3B0), width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: MaritimePalette.cinzel(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          backgroundColor: const Color(0x99281815),
          side: const BorderSide(color: MaritimePalette.gold, width: 1.3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: MaritimePalette.cinzel(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: MaritimePalette.cinzel(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xCC1E120E),
        labelStyle: MaritimePalette.crimsonText(
          color: MaritimePalette.parchmentMuted,
          fontSize: 14.5,
        ),
        hintStyle: MaritimePalette.crimsonText(
          color: const Color(0x99F5DEB3),
          fontSize: 14,
        ),
        helperStyle: MaritimePalette.crimsonText(
          color: MaritimePalette.parchmentMuted,
          fontSize: 12.5,
        ),
        prefixIconColor: gold,
        suffixIconColor: gold,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0x88FFD700),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: MaritimePalette.gold,
            width: 2.0,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0x88FFD700),
            width: 1.2,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MaritimePalette.carvedMahogany,
        selectedColor: const Color(0xFF6D4C41),
        disabledColor: const Color(0xFF1F1614),
        secondarySelectedColor: const Color(0xFF6D4C41),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: const BorderSide(color: Color(0x99FFD700), width: 1.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: MaritimePalette.crimsonText(
          color: parchment,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: MaritimePalette.cinzel(
          color: gold,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        checkmarkColor: gold,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: MaritimePalette.darkWoodBrown,
        selectedItemColor: gold,
        unselectedItemColor: MaritimePalette.parchmentMuted,
        selectedIconTheme: const IconThemeData(
          color: MaritimePalette.gold,
          size: 26,
        ),
        unselectedIconTheme: const IconThemeData(
          color: MaritimePalette.parchmentMuted,
          size: 22,
        ),
        selectedLabelStyle: MaritimePalette.cinzel(
          color: gold,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: MaritimePalette.crimsonText(
          color: MaritimePalette.parchmentMuted,
          fontSize: 11.5,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MaritimePalette.darkWoodBrown,
        indicatorColor: const Color(0x44FFD700),
        elevation: 10,
        shadowColor: Colors.black,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: MaritimePalette.gold, size: 25);
          }
          return const IconThemeData(
            color: MaritimePalette.parchmentMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MaritimePalette.cinzel(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            );
          }
          return MaritimePalette.crimsonText(
            color: MaritimePalette.parchmentMuted,
            fontSize: 11.5,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MaritimePalette.darkWoodBrown,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: MaritimePalette.gold, width: 1.5),
        ),
        titleTextStyle: MaritimePalette.cinzel(
          color: gold,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: MaritimePalette.crimsonText(
          color: parchment,
          fontSize: 15,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MaritimePalette.darkWoodBrown,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: MaritimePalette.darkWoodBrown,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: MaritimePalette.gold, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MaritimePalette.carvedMahogany,
        contentTextStyle: MaritimePalette.crimsonText(
          color: parchment,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: MaritimePalette.gold, width: 1.2),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MaritimePalette.gold,
        linearTrackColor: Color(0xFF1F120E),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: gold,
        textColor: parchment,
        titleTextStyle: MaritimePalette.cinzel(
          color: MaritimePalette.parchmentLight,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: MaritimePalette.crimsonText(
          color: MaritimePalette.parchment,
          fontSize: 13.5,
          height: 1.3,
        ),
      ),
    );
  }

  ThemeData get lightTheme =>
      _buildVintageMaritimeTheme(brightness: Brightness.light);

  ThemeData get darkTheme =>
      _buildVintageMaritimeTheme(brightness: Brightness.dark);

  static MapStyle _parseMapStyle(String? raw) {
    switch (raw) {
      case 'vintageSepia':
      case 'vintage_sepia':
        return MapStyle.vintageSepia;
      case 'modern':
        return MapStyle.modern;
      case 'vintageColor':
      case 'vintage_color':
      default:
        return MapStyle.vintageColor;
    }
  }

  static String _serializeMapStyle(MapStyle style) {
    switch (style) {
      case MapStyle.vintageColor:
        return 'vintageColor';
      case MapStyle.vintageSepia:
        return 'vintageSepia';
      case MapStyle.modern:
        return 'modern';
    }
  }

  static GraphicsQuality _parseGraphicsQuality(String? raw) {
    switch (raw) {
      case 'low':
        return GraphicsQuality.low;
      case 'medium':
        return GraphicsQuality.medium;
      case 'ultra':
        return GraphicsQuality.ultra;
      case 'high':
      default:
        return GraphicsQuality.high;
    }
  }

  static String _serializeGraphicsQuality(GraphicsQuality quality) {
    switch (quality) {
      case GraphicsQuality.low:
        return 'low';
      case GraphicsQuality.medium:
        return 'medium';
      case GraphicsQuality.high:
        return 'high';
      case GraphicsQuality.ultra:
        return 'ultra';
    }
  }

  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(prefKeyThemeMode);
      final palStr = prefs.getString(prefKeyPalette);
      final mapStyleStr = prefs.getString(prefKeyMapStyle);
      final graphicsStr = prefs.getString(prefKeyGraphicsQuality);

      if (modeStr == 'light') {
        _themeMode = ThemeMode.light;
      } else if (modeStr == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.dark;
      }

      if (palStr == 'samudra') {
        _palette = SpiceThemePalette.samudra;
      } else {
        _palette = SpiceThemePalette.nusantara;
      }

      _mapStyle = _parseMapStyle(mapStyleStr);
      _graphicsQuality = _parseGraphicsQuality(graphicsStr);
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

  Future<void> setMapStyle(MapStyle newStyle) async {
    _mapStyle = newStyle;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyMapStyle, _serializeMapStyle(newStyle));
    } catch (_) {
      // Abaikan kegagalan simpan di memori pengujian
    }
  }

  Future<void> setGraphicsQuality(GraphicsQuality newQuality) async {
    _graphicsQuality = newQuality;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefKeyGraphicsQuality,
        _serializeGraphicsQuality(newQuality),
      );
    } catch (_) {
      // Abaikan kegagalan simpan di memori pengujian
    }
  }
}