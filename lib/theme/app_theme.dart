import 'package:flutter/material.dart';
import '../services/app_settings.dart';

class AppTheme {
  // Colores de la paleta elegida por el usuario (Ajustes → Tema).
  // Se mantienen los nombres originales para no romper las vistas.
  static Color get primaryPink => AppSettings.instance.paleta.primario;
  static Color get darkPink => AppSettings.instance.paleta.acento;
  static Color get softPinkBg => AppSettings.instance.paleta.fondo;
  static Color get cardBorderPink => AppSettings.instance.paleta.borde;

  static const Color textDark = Color(0xFF4A2835); // Texto café-rosado elegante
  static const Color textMuted = Color(0xFF8C6D77); // Texto secundario

  // Colores para roles en tonos pastel
  static const Color adminBg = Color(0xFFFFD1DC); // Rosa fresa pastel
  static const Color adminText = Color(0xFFB71C1C);

  static const Color editorBg = Color(0xFFE8D7F1); // Lavanda pastel
  static const Color editorText = Color(0xFF6A1B9A);

  static const Color lectorBg = Color(0xFFD7EED6); // Menta pastel
  static const Color lectorText = Color(0xFF2E7D32);

  static const Color exito = Color(0xFF81C784);

  static ThemeData get pastelPinkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: softPinkBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryPink,
        primary: darkPink,
        secondary: primaryPink,
        surface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkPink),
        titleTextStyle: const TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: cardBorderPink.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cardBorderPink, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPink,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: cardBorderPink,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textDark),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? darkPink : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? cardBorderPink : null),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardBorderPink),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardBorderPink, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkPink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 2),
        ),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.6)),
      ),
    );
  }
}
