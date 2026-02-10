import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/home_page.dart';
import 'app_state.dart';

class IntelliNoteApp extends StatelessWidget {
  const IntelliNoteApp({super.key});

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color accentColor,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark
        ? const ColorScheme.dark().copyWith(
            primary: accentColor,
            onPrimary: Colors.white,
            secondary: accentColor,
            onSecondary: Colors.white,
            primaryContainer: Color(0xFF2A2D31),
            onPrimaryContainer: Color(0xFFE7EAF0),
            secondaryContainer: Color(0xFF2A2D31),
            onSecondaryContainer: Color(0xFFE7EAF0),
            surface: Color(0xFF1E1E1E),
            onSurface: Color(0xFFD4D4D4),
            surfaceContainerLowest: Color(0xFF161616),
            surfaceContainerLow: Color(0xFF1E1E1E),
            surfaceContainer: Color(0xFF252526),
            surfaceContainerHigh: Color(0xFF2D2D30),
            surfaceContainerHighest: Color(0xFF333337),
            outline: Color(0xFF3C3C3C),
            outlineVariant: Color(0xFF3A3A3A),
          )
        : ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.light,
          ).copyWith(
            surface: const Color(0xFFF8FAFC),
            onSurface: const Color(0xFF1E293B),
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['SimHei'],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          fontFamily: 'Consolas',
        ),
        iconTheme: IconThemeData(
          color: scheme.onSurface.withValues(alpha: 0.9),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.72 : 0.5),
            width: 1,
          ),
        ),
        color: isDark ? scheme.surfaceContainer : Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? scheme.surfaceContainer : Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return Colors.transparent;
          }),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.75)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? scheme.surfaceContainerLow : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.7),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.72),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.92),
          fontSize: 17,
        ),
        bodyMedium: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.78),
          fontSize: 15,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHigh : Colors.white,
        hintStyle: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.55),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.72),
        ),
        border: isDark
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
        enabledBorder: isDark
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
        focusedBorder: isDark
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: scheme.primary, width: 1.2),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, state, _) => MaterialApp(
          title: 'Intelli Note',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          theme: _buildTheme(
            brightness: Brightness.light,
            accentColor: state.themeAccent.color,
          ),
          darkTheme: _buildTheme(
            brightness: Brightness.dark,
            accentColor: state.themeAccent.color,
          ),
          home: const HomePage(),
        ),
      ),
    );
  }
}
