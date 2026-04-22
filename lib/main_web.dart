import 'package:flutter/material.dart';
import 'package:pathplanner/webui/pages/scouting_web_home_page.dart';

void main() {
  runApp(const PathPlannerScoutingWebApp());
}

class PathPlannerScoutingWebApp extends StatelessWidget {
  const PathPlannerScoutingWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    const canvas = Color(0xFF050505);
    const panel = Color(0xFF101010);
    const panelRaised = Color(0xFF171717);
    const accent = Color(0xFFD4A437);
    const secondary = Color(0xFFF4D37A);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: panel,
      surfaceContainer: panelRaised,
      surfaceContainerHighest: const Color(0xFF242424),
      primary: accent,
      secondary: secondary,
      tertiary: const Color(0xFFFFE6A6),
      outline: const Color(0xFF5A4820),
      onSurfaceVariant: const Color(0xFFB9AA83),
    );

    return MaterialApp(
      title: 'PathPlanner Scouting Web UI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: canvas,
        cardTheme: CardThemeData(
          color: panel,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: panelRaised,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          labelStyle: TextStyle(color: scheme.onSurface),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const ScoutingWebHomePage(),
    );
  }
}
