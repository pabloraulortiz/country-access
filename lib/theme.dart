import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colores de marca de Siscord (tomados del logo).
class Brand {
  static const navy = Color(0xFF0B1724);
  static const yellow = Color(0xFFFFBE00);
  static const pink = Color(0xFFE8317F);
  static const purple = Color(0xFF7B5EA7);
  static const bg = Color(0xFFF6F7FA);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Brand.navy, brightness: Brightness.light).copyWith(
    primary: Brand.navy,
    onPrimary: Colors.white,
    secondary: Brand.purple,
    onSecondary: Colors.white,
    tertiary: Brand.yellow,
    onTertiary: Brand.navy,
    secondaryContainer: const Color(0xFFFFE8A3),
    onSecondaryContainer: Brand.navy,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.yellow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.navy : Colors.black54),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Brand.navy : Colors.black54,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Brand.navy,
      unselectedLabelColor: Colors.black54,
      indicatorColor: Brand.yellow,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.yellow,
      foregroundColor: Brand.navy,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Brand.purple, width: 2)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.purple),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.navy : null,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.navy : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.yellow : null,
      ),
    ),
  );
}
